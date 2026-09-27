
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'service.dart';

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

abstract class ChestRepository {
  String? get currentUserId;

  Future<ChestProgress?> fetchProgress(String uid);

  Future<void> syncRemaining(int remainingSeconds);

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

  @visibleForTesting
  bool get notifiedThisUnlockForTest => _notifiedThisUnlock;

  @visibleForTesting
  bool get isTickingForTest => _localTicker?.isActive ?? false;

  Future<void> initialize() async {
    final uid = _repo.currentUserId;
    if (uid == null) return;

    try {
      final existing = await _repo.fetchProgress(uid);

      if (existing == null) {
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
    }
  }

  Future<void> _sendReadyNotificationOnce() async {
    if (_notifiedThisUnlock) return;
    _notifiedThisUnlock = true;
    final uid = _repo.currentUserId;
    if (uid == null) return;
    await _repo.sendChestReadyNotification(uid);
  }

  void pauseAndPersist() {
    if (!isUnlocked) {
      _localTicker?.cancel();
      _persistRemaining();
    }
  }

  Future<void> resumeFromForeground() async {
    await initialize();
  }

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

final coinChestTimerService = ChestTimerService(
  tableName: 'coin_chest_progress',
  syncRpcName: 'sync_coin_chest_timer',
);
