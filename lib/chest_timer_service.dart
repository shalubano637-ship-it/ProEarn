
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
        await _repo.syncRemaining(60);
        currentChestIndex = 0;
        remainingSeconds = 60;
        isUnlocked = false;
      } else {
        currentChestIndex = existing.currentChestIndex;
        _unlockAt = existing.unlockAt;
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
      _notifiedThisUnlock = isUnlocked && _unlockAt == null;
      notifyListeners();

      if (isUnlocked && _unlockAt != null) {
        await _sendReadyNotificationOnce(checkDatabase: true);
      } else if (!isUnlocked) {
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

  Future<void> _sendReadyNotificationOnce({bool checkDatabase = false}) async {
    if (_notifiedThisUnlock) return;
    final uid = _repo.currentUserId;
    if (uid == null) return;

    if (checkDatabase && _unlockAt != null) {
      try {
        final alreadySent = await _repo.hasChestReadyNotificationSince(uid, _unlockAt!);
        if (alreadySent) {
          _notifiedThisUnlock = true;
          return;
        }
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
