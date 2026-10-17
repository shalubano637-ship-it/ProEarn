# Crash reporting (Sentry) — setup

`main.dart` now initializes Sentry via `SentryFlutter.init`, wired into the
existing `runZonedGuarded` error zone plus the three startup try/catch
blocks (Hive/Supabase/OneSignal init) and the outer async-error catch.
Before this, every one of those failure paths only ever reached
`debugPrint` — invisible once the app is in a real user's hands.

## 1. Create a Sentry project

Sentry.io (or self-hosted) → New Project → platform: Flutter. Copy the DSN
it gives you (looks like `https://xxxx@xxxx.ingest.sentry.io/xxxx`).

## 2. Never hardcode the DSN in source

Pass it at build time instead:

```bash
flutter build apk --release --dart-define=SENTRY_DSN=https://xxxx@xxxx.ingest.sentry.io/xxxx
flutter run --dart-define=SENTRY_DSN=https://xxxx@xxxx.ingest.sentry.io/xxxx
```

With no `SENTRY_DSN` provided (e.g. plain `flutter run` during local dev),
`SentryFlutter.init` no-ops rather than throwing — so it's safe to leave
enabled in every build config, including CI, without needing a separate
"is this prod" branch.

## 3. What gets reported automatically vs. what was wired manually

- **Automatic**: uncaught Flutter framework errors (`FlutterError.onError`,
  hooked internally by `SentryFlutter.init`) — widget build/layout/paint
  exceptions.
- **Manual (added in this pass)**: the outer `runZonedGuarded` catch (async
  errors outside the Flutter framework's own error hooks), and the
  Hive/Supabase/OneSignal startup `catch` blocks — these previously
  swallowed real startup failures into a debug-only log line.

`ErrorWidget.builder` (the red "App UI Error" screen) is unrelated to
Sentry — that just controls what's *shown on screen* when a widget build
fails; it doesn't report anywhere on its own. Both can and should stay.

## 4. Confirm it's working

Add a temporary test button anywhere reachable, run a real (non-debug)
build with the DSN set, tap it, and check the Sentry dashboard for the
event within a minute or two:

```dart
ElevatedButton(
  onPressed: () => throw Exception('Sentry test error'),
  child: const Text('Test Sentry'),
),
```

Remove the test button once you've confirmed an event arrives.

## Not covered by this pass

- `tracesSampleRate` is set to `0.2` (20% of transactions) as a reasonable
  starting point for performance monitoring — tune this once you have a
  sense of your actual traffic/Sentry-plan quota.
- Android/iOS **native** crash reporting (crashes in engine code, not Dart)
  is included automatically by `sentry_flutter`'s bundled native SDKs — no
  extra setup needed for that specifically.
