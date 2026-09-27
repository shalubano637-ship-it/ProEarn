
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:proearn/chest_timer_service.dart';

class MockChestRepository extends Mock implements ChestRepository {}

void main() {
  late MockChestRepository repo;
  const uid = 'user-123';

  setUp(() {
    repo = MockChestRepository();
    when(() => repo.currentUserId).thenReturn(uid);
    when(() => repo.syncRemaining(any())).thenAnswer((_) async {});
    when(() => repo.sendChestReadyNotification(any())).thenAnswer((_) async {});
  });

  group('timer start', () {
    test('brand-new user (no existing row) starts chest 1 at 60s and begins ticking', () {
      when(() => repo.fetchProgress(uid)).thenAnswer((_) async => null);

      fakeAsync((async) {
        final service = ChestTimerService(repository: repo);
        service.initialize();
        async.flushMicrotasks();

        expect(service.isLoaded, isTrue);
        expect(service.loadError, isNull);
        expect(service.currentChestIndex, 0);
        expect(service.remainingSeconds, 60);
        expect(service.isUnlocked, isFalse);
        expect(service.isTickingForTest, isTrue);
        verify(() => repo.syncRemaining(60)).called(1);
      });
    });

    test('existing not-yet-unlocked row resumes ticking from its saved remainingSeconds', () {
      when(() => repo.fetchProgress(uid)).thenAnswer(
        (_) async => const ChestProgress(currentChestIndex: 2, remainingSeconds: 37, isUnlocked: false),
      );

      fakeAsync((async) {
        final service = ChestTimerService(repository: repo);
        service.initialize();
        async.flushMicrotasks();

        expect(service.currentChestIndex, 2);
        expect(service.remainingSeconds, 37);
        expect(service.isTickingForTest, isTrue);
        verifyNever(() => repo.syncRemaining(60));
      });
    });

    test('ticking actually counts down one second per tick', () {
      when(() => repo.fetchProgress(uid)).thenAnswer((_) async => null);

      fakeAsync((async) {
        final service = ChestTimerService(repository: repo);
        service.initialize();
        async.flushMicrotasks();

        expect(service.remainingSeconds, 60);
        async.elapse(const Duration(seconds: 5));
        expect(service.remainingSeconds, 55);
      });
    });
  });

  group('pause/resume', () {
    test('pauseAndPersist stops the ticker and persists the exact remaining value', () {
      when(() => repo.fetchProgress(uid)).thenAnswer((_) async => null);

      fakeAsync((async) {
        final service = ChestTimerService(repository: repo);
        service.initialize();
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 10)); // 60 -> 50
        service.pauseAndPersist();
        async.flushMicrotasks();

        expect(service.isTickingForTest, isFalse);
        expect(service.remainingSeconds, 50);
        verify(() => repo.syncRemaining(50)).called(1);

        async.elapse(const Duration(seconds: 20));
        expect(service.remainingSeconds, 50);
      });
    });

    test('pauseAndPersist while already unlocked does not re-persist or double-cancel', () {
      when(() => repo.fetchProgress(uid)).thenAnswer(
        (_) async => const ChestProgress(currentChestIndex: 0, remainingSeconds: 0, isUnlocked: true),
      );

      fakeAsync((async) {
        final service = ChestTimerService(repository: repo);
        service.initialize();
        async.flushMicrotasks();

        service.pauseAndPersist();
        async.flushMicrotasks();

        verifyNever(() => repo.syncRemaining(any()));
      });
    });

    test('resumeFromForeground reloads from the repository and resumes ticking', () {
      when(() => repo.fetchProgress(uid)).thenAnswer(
        (_) async => const ChestProgress(currentChestIndex: 0, remainingSeconds: 42, isUnlocked: false),
      );

      fakeAsync((async) {
        final service = ChestTimerService(repository: repo);
        service.initialize();
        async.flushMicrotasks();

        service.pauseAndPersist();
        async.flushMicrotasks();
        expect(service.isTickingForTest, isFalse);

        when(() => repo.fetchProgress(uid)).thenAnswer(
          (_) async => const ChestProgress(currentChestIndex: 0, remainingSeconds: 30, isUnlocked: false),
        );

        service.resumeFromForeground();
        async.flushMicrotasks();

        expect(service.remainingSeconds, 30);
        expect(service.isTickingForTest, isTrue);
      });
    });
  });

  group('expiry', () {
    test('counting down to zero unlocks the chest, persists 0, and notifies once', () {
      when(() => repo.fetchProgress(uid)).thenAnswer(
        (_) async => const ChestProgress(currentChestIndex: 0, remainingSeconds: 3, isUnlocked: false),
      );

      fakeAsync((async) {
        final service = ChestTimerService(repository: repo);
        service.initialize();
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 3));
        async.flushMicrotasks();

        expect(service.isUnlocked, isTrue);
        expect(service.remainingSeconds, 0);
        expect(service.isTickingForTest, isFalse); // timer.cancel() on expiry
        verify(() => repo.syncRemaining(0)).called(1);
        verify(() => repo.sendChestReadyNotification(uid)).called(1);
      });
    });
  });

  group('already-expired chest', () {
    test('loading an already-unlocked row does not start a ticker or re-notify', () {
      when(() => repo.fetchProgress(uid)).thenAnswer(
        (_) async => const ChestProgress(currentChestIndex: 1, remainingSeconds: 0, isUnlocked: true),
      );

      fakeAsync((async) {
        final service = ChestTimerService(repository: repo);
        service.initialize();
        async.flushMicrotasks();

        expect(service.isUnlocked, isTrue);
        expect(service.isTickingForTest, isFalse);
        expect(service.notifiedThisUnlockForTest, isTrue); // marked, so no push fires later
        verifyNever(() => repo.sendChestReadyNotification(any()));
      });
    });
  });

  group('duplicate claim / duplicate unlock', () {
    test('reloading twice while still unlocked never sends a second notification', () {
      when(() => repo.fetchProgress(uid)).thenAnswer(
        (_) async => const ChestProgress(currentChestIndex: 0, remainingSeconds: 1, isUnlocked: false),
      );

      fakeAsync((async) {
        final service = ChestTimerService(repository: repo);
        service.initialize();
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 1)); // triggers unlock + 1 notification
        async.flushMicrotasks();
        verify(() => repo.sendChestReadyNotification(uid)).called(1);

        when(() => repo.fetchProgress(uid)).thenAnswer(
          (_) async => const ChestProgress(currentChestIndex: 0, remainingSeconds: 0, isUnlocked: true),
        );

        service.resumeFromForeground();
        async.flushMicrotasks();
        service.resumeFromForeground();
        async.flushMicrotasks();

        verify(() => repo.sendChestReadyNotification(uid)).called(1);
      });
    });

    test('advanceToNextChest resets the notify-guard for the NEW chest', () {
      when(() => repo.fetchProgress(uid)).thenAnswer(
        (_) async => const ChestProgress(currentChestIndex: 0, remainingSeconds: 1, isUnlocked: false),
      );

      fakeAsync((async) {
        final service = ChestTimerService(repository: repo);
        service.initialize();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        verify(() => repo.sendChestReadyNotification(uid)).called(1);

        when(() => repo.fetchProgress(uid)).thenAnswer(
          (_) async => const ChestProgress(currentChestIndex: 1, remainingSeconds: 1, isUnlocked: false),
        );
        service.advanceToNextChest();
        async.flushMicrotasks();
        expect(service.notifiedThisUnlockForTest, isFalse);

        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();

        verify(() => repo.sendChestReadyNotification(uid)).called(2);
      });
    });
  });

  group('notification trigger', () {
    test('does not attempt to notify if the user becomes unauthenticated mid-countdown', () {
      when(() => repo.fetchProgress(uid)).thenAnswer(
        (_) async => const ChestProgress(currentChestIndex: 0, remainingSeconds: 1, isUnlocked: false),
      );

      fakeAsync((async) {
        final service = ChestTimerService(repository: repo);
        service.initialize();
        async.flushMicrotasks();

        when(() => repo.currentUserId).thenReturn(null);

        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();

        expect(service.isUnlocked, isTrue); // local state still flips
        verifyNever(() => repo.sendChestReadyNotification(any()));
      });
    });
  });

  group('invalid state', () {
    test('initialize() is a no-op when nobody is signed in', () {
      when(() => repo.currentUserId).thenReturn(null);

      fakeAsync((async) {
        final service = ChestTimerService(repository: repo);
        service.initialize();
        async.flushMicrotasks();

        expect(service.isLoaded, isFalse);
        expect(service.isTickingForTest, isFalse);
        verifyNever(() => repo.fetchProgress(any()));
      });
    });

    test('a repository error surfaces as loadError instead of crashing or ticking', () {
      when(() => repo.fetchProgress(uid)).thenThrow(Exception('network down'));

      fakeAsync((async) {
        final service = ChestTimerService(repository: repo);
        service.initialize();
        async.flushMicrotasks();

        expect(service.isLoaded, isTrue);
        expect(service.loadError, isNotNull);
        expect(service.isTickingForTest, isFalse);
      });
    });

    test('dispose() cancels any active ticker', () {
      when(() => repo.fetchProgress(uid)).thenAnswer((_) async => null);

      fakeAsync((async) {
        final service = ChestTimerService(repository: repo);
        service.initialize();
        async.flushMicrotasks();
        expect(service.isTickingForTest, isTrue);

        service.dispose();
        expect(service.isTickingForTest, isFalse);
      });
    });
  });
}
