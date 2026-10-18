
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'service.dart';

class ChestProgress {
  final int currentChestIndex;
  final int remainingSeconds;
  final bool isUnlocked;
  final DateTime? unlockAt;

  const ChestProgress({
    required this.currentChestIndex,
    required this.remainingSeconds,
    required this.isUnlocked,
    this.unlockAt,
  });
}

abstract class ChestRepository {
  String? get currentUserId;

  Future<ChestProgress?> fetchProgress(String uid);

  Future<void> syncRemaining(int remainingSeconds);
  Future<void> startTimer();

  Future<void> sendChestReadyNotification(String uid);
  Future<bool> hasChestReadyNotificationSince(String uid, DateTime unlockAt);
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
      unlockAt: existing['unlockAt'] == null ? null : DateTime.tryParse(existing['unlockAt'].toString()),
    );
  }

  @override
  Future<void> syncRemaining(int remainingSeconds) async {
    await _client.rpc(syncRpcName, params: {'p_remaining_seconds': remainingSeconds});
  }

  @override
  Future<void> startTimer() async {
    if (tableName != 'chest_progress') throw StateError('Only gift chest timers can be started here');
    await _client.rpc('start_chest_timer');
  }

  @override
  Future<void> sendChestReadyNotification(String uid) async {
    // Do not use the shared sendNotification helper here: it catches errors
    // internally, which made the timer mark a failed notification as sent.
    final response = await _client.functions.invoke(
      'notify',
      body: {
        'targetOwnerId': uid,
        'type': 'chest_ready',
        'message': 'Your chest is ready to open! 🎁',
      },
    );
    if (response.status < 200 || response.status >= 300) {
      throw StateError('Chest notification failed with HTTP ${response.status}');
    }
    final data = response.data;
    if (data is Map && data['success'] == false) {
      throw StateError('Chest notification was not accepted');
    }
  }

  @override
  Future<bool> hasChestReadyNotificationSince(String uid, DateTime unlockAt) async {
    final row = await _client
        .from('notifications')
        .select('id')
        .eq('targetOwnerId', uid)
        .eq('type', 'chest_ready')
        .gte('timestamp', unlockAt.toUtc().toIso8601String())
        .limit(1)
        .maybeSingle();
    return row != null;
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
  bool isStarted = false;
  bool isLoaded = false;
  String? loadError;
  DateTime? _unlockAt;

  bool _notifiedThisUnlock = false; // avoid duplicate chest_ready notifications for the same unlock

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
        currentChestIndex = 0;
        remainingSeconds = 0;
        isUnlocked = false;
        isStarted = false;
        _unlockAt = null;
      } else {
        currentChestIndex = existing.currentChestIndex;
        _unlockAt = existing.unlockAt;
        isStarted = existing.unlockAt != null || existing.isUnlocked;
        if (_unlockAt != null) {
          final serverRemaining = _unlockAt!.difference(DateTime.now()).inSeconds;
          remainingSeconds = math.max(0, serverRemaining);
          isUnlocked = existing.isUnlocked || remainingSeconds <= 0;
        } else {
          remainingSeconds = existing.remainingSeconds;
          isUnlocked = existing.isUnlocked;
        }
      }

      isLoaded = true;
      loadError = null;
      _notifiedThisUnlock = false;
      notifyListeners();

      if (isUnlocked && _unlockAt != null) {
        await _sendReadyNotificationOnce(checkDatabase: true);
      } else if (!isUnlocked && isStarted) {
        _startTicking();
      }
    } catch (e) {
      debugPrint("chest_progress load failed: $e");
      loadError = "Couldn't load your chests — please try again.";
      isLoaded = true;
      notifyListeners();
    }
  }

  Future<void> startTimer() async {
    if (isStarted || isUnlocked) return;
    await _repo.startTimer();
    await initialize();
  }

  void _startTicking() {
    _localTicker?.cancel();
    if (!isStarted || isUnlocked) return;
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

  Future<void> _sendReadyNotificationOnce({bool checkDatabase = false}) async {
    if (_notifiedThisUnlock) return;
    final uid = _repo.currentUserId;
    if (uid == null) return;

    if (checkDatabase && _unlockAt != null) {
      try {
        // Inbox notification rows do not confirm OneSignal push delivery.
        // Keep trying the push endpoint; server-side delivery is deduplicated.
      } catch (e) {
        debugPrint('chest ready notification lookup failed: $e');
      }
    }

    try {
      await _repo.sendChestReadyNotification(uid);
      _notifiedThisUnlock = true;
    } catch (e) {
      debugPrint('chest ready notification send failed: $e');
    }
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

  Future<void> advanceToNextChest() async {
    _localTicker?.cancel();
    isUnlocked = false;
    isStarted = false;
    _unlockAt = null;
    remainingSeconds = 0;
    _notifiedThisUnlock = false;
    notifyListeners();
    await initialize();
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
