// =============================================================================
// PRO EARN — Global chest timer service
// -----------------------------------------------------------------------------
// Previously the countdown only ran while ChestsPage itself was mounted —
// navigating to any other page effectively paused it (dispose() cancelled
// the local Timer). This moves the ticking Timer to a single app-lifetime
// singleton, started once at app init (or right after login) and kept
// alive independent of navigation — ChestsPage just displays whatever
// state this service currently holds.
//
// Still only ticks in the foreground: the SAME pause/resume + server-sync
// logic as before applies, just triggered from a global lifecycle
// observer (see main.dart's _AppLifecycleObserver) instead of a
// per-page one, so background/close still freezes progress exactly where
// it was regardless of which screen was open when it happened.
//
// When a chest unlocks, this also fires a push notification (via the
// existing sendNotification() → notify edge function pipeline, type
// 'chest_ready') so the user finds out even if they're on a completely
// different screen when it happens.
//
// Testability: all Supabase access is behind ChestRepository — a tiny
// 4-method interface with exactly what this service needs (fetch/sync
// progress, current uid, send the ready notification). Production code
// is unchanged (`ChestTimerService()` below still talks to the real
// Supabase client via _SupabaseChestRepository, same RPCs/table/columns
// as before). Tests inject a FakeChestRepository instead — see
// test/chest_timer_service_test.dart — so timer logic can be verified
// with zero network calls and a controllable clock (fake_async).
// =============================================================================

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'service.dart';

/// A single chest_progress row, as read from/written to Supabase.
class ChestProgress {
  final int currentChestIndex;
  final int remainingSeconds;
  final bool isUnlocked;

  const ChestProgress({
    required this.currentChestIndex,
    required this.remainingSeconds,
    required this.isUnlocked,
  });
}

/// Everything ChestTimerService needs from the outside world. The real
/// implementation (_SupabaseChestRepository, used by default) is a thin
/// wrapper around the exact same Supabase calls the service used to make
/// directly. Tests supply a fake implementation instead.
abstract class ChestRepository {
  /// The signed-in user's uid, or null if nobody's logged in.
  String? get currentUserId;

  /// Loads this user's current chest_progress row, or null if they've
  /// never had one (brand-new user).
  Future<ChestProgress?> fetchProgress(String uid);

  /// Upserts remainingSeconds for the current chest (`sync_chest_timer`
  /// RPC). Also used to create the very first chest_progress row, with
  /// remainingSeconds = 60.
  Future<void> syncRemaining(int remainingSeconds);

  /// Fires the 'chest_ready' push notification for [uid].
  Future<void> sendChestReadyNotification(String uid);
}

class _SupabaseChestRepository implements ChestRepository {
  final SupabaseClient _client;
  final String tableName;
  final String syncRpcName;
  _SupabaseChestRepository(this._client, {required this.tableName, required this.syncRpcName});

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Future<ChestProgress?> fetchProgress(String uid) async {
    final existing = await _client
        .from(tableName)
        .select()
        .eq('uid', uid)
        .maybeSingle();

    if (existing == null) return null;
    return ChestProgress(
      currentChestIndex: existing['currentChestIndex'] as int,
      remainingSeconds: existing['remainingSeconds'] as int,
      isUnlocked: existing['isUnlocked'] as bool,
    );
  }

  @override
  Future<void> syncRemaining(int remainingSeconds) async {
    await _client.rpc(syncRpcName, params: {'p_remaining_seconds': remainingSeconds});
  }

  @override
  Future<void> sendChestReadyNotification(String uid) async {
    // chest_ready is a system notification, not "from" another user —
    // targetOwnerId == the sender's own id, which the notify edge
    // function specifically allows only for this type.
    await sendNotification(
      targetOwnerId: uid,
      type: 'chest_ready',
      message: 'Your chest is ready to open! 🎁',
    );
  }
}

class ChestTimerService extends ChangeNotifier {
  ChestTimerService({
    ChestRepository? repository,
    String tableName = 'chest_progress',
    String syncRpcName = 'sync_chest_timer',
  }) : _repo = repository ?? _SupabaseChestRepository(Supabase.instance.client, tableName: tableName, syncRpcName: syncRpcName);

  final ChestRepository _repo;

  Timer? _localTicker;

  int currentChestIndex = 0;
  int remainingSeconds = 60;
  bool isUnlocked = false;
  bool isLoaded = false;
  String? loadError;

  bool _notifiedThisUnlock = false; // avoid duplicate chest_ready pushes if unlock fires more than once before being claimed

  /// Exposed read-only for tests; production code never calls this.
  @visibleForTesting
  bool get notifiedThisUnlockForTest => _notifiedThisUnlock;

  /// Exposed so tests can assert the ticker was actually cancelled
  /// (e.g. after pauseAndPersist / dispose) without reaching into a
  /// private field via reflection.
  @visibleForTesting
  bool get isTickingForTest => _localTicker?.isActive ?? false;

  /// Call at app startup (if already logged in) and right after a
  /// successful login (if not). Safe to call multiple times — reloads
  /// fresh state from the server each time, which is also what powers
  /// resume-from-background.
  Future<void> initialize() async {
    final uid = _repo.currentUserId;
    if (uid == null) return;

    try {
      final existing = await _repo.fetchProgress(uid);

      if (existing == null) {
        // First time ever — start chest 1's timer immediately.
        await _repo.syncRemaining(60);
        currentChestIndex = 0;
        remainingSeconds = 60;
        isUnlocked = false;
      } else {
        currentChestIndex = existing.currentChestIndex;
        remainingSeconds = existing.remainingSeconds;
        isUnlocked = existing.isUnlocked;
      }

      isLoaded = true;
      loadError = null;
      _notifiedThisUnlock = isUnlocked; // don't re-notify for an unlock that already happened before this load
      notifyListeners();

      if (!isUnlocked) {
        _startTicking();
      }
    } catch (e) {
      debugPrint("chest_progress load failed: $e");
      loadError = "Couldn't load your chests — please try again.";
      isLoaded = true;
      notifyListeners();
    }
  }

  void _startTicking() {
    _localTicker?.cancel();
    _localTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (remainingSeconds <= 0) {
        timer.cancel();
        isUnlocked = true;
        notifyListeners();
        _persistRemaining();
        _sendReadyNotificationOnce();
        return;
      }
      remainingSeconds -= 1;
      notifyListeners();
    });
  }

  Future<void> _persistRemaining() async {
    try {
      await _repo.syncRemaining(remainingSeconds);
    } catch (_) {
      // Non-fatal — worst case a few seconds since the last successful
      // sync are lost if the app is killed right now.
    }
  }

  Future<void> _sendReadyNotificationOnce() async {
    if (_notifiedThisUnlock) return;
    _notifiedThisUnlock = true;
    final uid = _repo.currentUserId;
    if (uid == null) return;
    await _repo.sendChestReadyNotification(uid);
  }

  /// Called by the global lifecycle observer when the app leaves the
  /// foreground — stop ticking right here and persist exactly where it
  /// stopped, so background time never counts toward the countdown.
  void pauseAndPersist() {
    if (!isUnlocked) {
      _localTicker?.cancel();
      _persistRemaining();
    }
  }

  /// Called by the global lifecycle observer when the app returns to the
  /// foreground — reload from the server (in case another device/session
  /// changed it) and resume ticking.
  Future<void> resumeFromForeground() async {
    await initialize();
  }

  /// After the rewarded ad completes and claim_chest_reward succeeds,
  /// call this with the fresh next-chest state to resume ticking for the
  /// next chest immediately, without a full server round-trip.
  void advanceToNextChest() {
    _notifiedThisUnlock = false;
    initialize(); // simplest correct way to pick up the new index/duration
  }

  @override
  void dispose() {
    _localTicker?.cancel();
    super.dispose();
  }
}

final chestTimerService = ChestTimerService();

// Second, fully independent set of 5 chests — same mechanics (countdown →
// watch a rewarded ad → claim), but rewards coins instead of a gift. Own
// table (coin_chest_progress) and own sync RPC (sync_coin_chest_timer) —
// see supabase/migrations/2026_coin_chests.sql — so it never touches or
// interferes with the original gift chestTimerService above.
final coinChestTimerService = ChestTimerService(
  tableName: 'coin_chest_progress',
  syncRpcName: 'sync_coin_chest_timer',
);
