
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

}

class _SupabaseChestRepository implements ChestRepository {
  final SupabaseClient _client;
  final String tableName;
  final String syncRpcName;
  _SupabaseChestRepository(this._client, {required this.tableName, required this.syncRpcName});

  @override
  String? get currentUserId => FirebaseAuth.instance.currentUser?.uid;

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

  Future<void> startTimer() async {
    if (tableName != 'chest_progress') throw StateError('Only gift chest timers can be started here');
    await _client.rpc('start_chest_timer');
  }


}

DateTime _nextIstMidnightUtc(DateTime nowUtc) {
  final istNow = nowUtc.toUtc().add(const Duration(hours: 5, minutes: 30));
  final nextMidnightAsUtc = DateTime.utc(istNow.year, istNow.month, istNow.day + 1);
  return nextMidnightAsUtc.subtract(const Duration(hours: 5, minutes: 30));
}

class ChestTimerService extends ChangeNotifier {
  ChestTimerService({
    ChestRepository? repository,
    String tableName = 'chest_progress',
    String syncRpcName = 'sync_chest_timer',
  }) : _repo = repository ?? _SupabaseChestRepository(Supabase.instance.client, tableName: tableName, syncRpcName: syncRpcName);

  final ChestRepository _repo;

  Timer? _localTicker;
  Timer? _dailyRefreshTimer;
  Future<void>? _initialization;

  int currentChestIndex = 0;
  int remainingSeconds = 60;
  bool isUnlocked = false;
  bool isStarted = false;
  bool isLoaded = false;
  String? loadError;
  DateTime? _unlockAt;

  @visibleForTesting
  bool get isTickingForTest => _localTicker?.isActive ?? false;

  Future<void> initialize() {
    // Navigation and the Rewards page can request initialization at nearly
    // the same time. Share one in-flight read instead of hitting Supabase twice.
    final inFlight = _initialization;
    if (inFlight != null) return inFlight;

    final future = _initializeInternal();
    _initialization = future;
    return future.whenComplete(() {
      if (identical(_initialization, future)) _initialization = null;
    });
  }

  Future<void> _initializeInternal() async {
    final uid = _repo.currentUserId;
    if (uid == null) return;

    // A daily server reset also needs to refresh in-memory state when the app
    // remains open across midnight. Server cron remains authoritative if the
    // app is suspended or closed.
    _localTicker?.cancel();
    _scheduleDailyIstRefresh();

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
          final remainingDuration = _unlockAt!.difference(DateTime.now());
          // Round up partial seconds so a fresh timer does not lose a second.
          final serverRemaining = (remainingDuration.inMilliseconds / Duration.millisecondsPerSecond).ceil();
          remainingSeconds = math.max(0, serverRemaining);
          isUnlocked = existing.isUnlocked || remainingSeconds <= 0;
        } else {
          remainingSeconds = existing.remainingSeconds;
          isUnlocked = existing.isUnlocked;
        }
      }

      isLoaded = true;
      loadError = null;
      notifyListeners();

      if (!isUnlocked && isStarted) {
        _startTicking();
      }
    } catch (e) {
      debugPrint("chest_progress load failed: $e");
      loadError = "Couldn't load your chests — please try again.";
      isLoaded = true;
      notifyListeners();
    }
  }

  void _scheduleDailyIstRefresh() {
    _dailyRefreshTimer?.cancel();
    final nowUtc = DateTime.now().toUtc();
    final nextResetUtc = _nextIstMidnightUtc(nowUtc);
    final delay = nextResetUtc.difference(nowUtc);
    _dailyRefreshTimer = Timer(delay, () {
      _dailyRefreshTimer = null;
      if (_repo.currentUserId != null) {
        initialize();
      }
    });
  }

  @visibleForTesting
  DateTime nextIstMidnightUtcForTest(DateTime nowUtc) => _nextIstMidnightUtc(nowUtc);

  Future<void> startTimer() async {
    if (isStarted || isUnlocked) return;
    await _repo.startTimer();
    await initialize();
  }

  void _startTicking() {
    _localTicker?.cancel();
    if (!isStarted || isUnlocked) return;
    _localTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (remainingSeconds > 0) {
        remainingSeconds -= 1;
      }

      if (remainingSeconds <= 0) {
        remainingSeconds = 0;
        timer.cancel();
        isUnlocked = true;
        notifyListeners();
        _persistRemaining();
        return;
      }

      notifyListeners();
    });
  }

  Future<void> _persistRemaining() async {
    try {
      await _repo.syncRemaining(remainingSeconds);
    } catch (_) {
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
    notifyListeners();
    await initialize();
  }

  @override
  void dispose() {
    _localTicker?.cancel();
    _dailyRefreshTimer?.cancel();
    super.dispose();
  }
}

final chestTimerService = ChestTimerService();

