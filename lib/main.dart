// ---- Dart core ----
import 'dart:async';
import 'package:flutter/foundation.dart' show kDebugMode;

// ---- Flutter framework ----
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ---- Supabase ----
import 'package:supabase_flutter/supabase_flutter.dart';

// ---- Crash reporting ----
import 'package:sentry_flutter/sentry_flutter.dart';

// ---- Third-party packages ----
import 'package:onesignal_flutter/onesignal_flutter.dart';

import 'package:hive_flutter/hive_flutter.dart';

// ---- App files (split out of the original single-file main.dart) ----
import 'auth_screen.dart';
import 'service.dart';
import 'theme/theme.dart';
import 'moderation/moderation_config.dart';
import 'chest_timer_service.dart';
import 'ad_preloader.dart';
import 'messaging/chat_page.dart';
import 'chests/chests_page.dart';
import 'user_profile_features.dart';


final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();


   Future<void> main() async {
  // 1. App initialization se pehle binding jaruri hai
  WidgetsFlutterBinding.ensureInitialized();

  // 1b. Crash reporting — DSN is injected at build time, never hardcoded:
  //   flutter build apk --dart-define=SENTRY_DSN=https://xxx@xxx.ingest.sentry.io/xxx
  // With no DSN provided (e.g. local `flutter run` during dev), Sentry
  // no-ops rather than throwing, so this is safe to leave in for all builds.
  await SentryFlutter.init((options) {
    options.dsn = const String.fromEnvironment('SENTRY_DSN');
    options.tracesSampleRate = 0.2;
    options.debug = kDebugMode;
  });

  // 2. Custom Screen Error Handler (App crash nahi hone dega)
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.red.shade50,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 60),
                  const SizedBox(height: 16),
                  const Text(
                    'App UI Error',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: SingleChildScrollView(
                      child: Text(
                        details.exceptionAsString(),
                        style: const TextStyle(fontSize: 12, color: Colors.black87),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  };

  // 3. Main App Execution inside Safe Zone
  runZonedGuarded(
    () async {
      // System orientations
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);

      // Safe Hive Initialization
      try {
        await Hive.initFlutter();
        await Hive.openBox('app_settings');
      } catch (e, st) {
        debugPrint("Hive Init Error: $e");
        Sentry.captureException(e, stackTrace: st);
      }

      // Safe Supabase Initialization
      // URL/key are overridable via --dart-define so a staging Supabase
      // project can be pointed at during development/testing, e.g.:
      //   flutter run --dart-define=SUPABASE_URL=https://staging-project.supabase.co \
      //                --dart-define=SUPABASE_ANON_KEY=sb_publishable_xxx
      // Defaults to the production project below when not overridden, so
      // this is a safe no-op change for existing build/run commands.
      try {
        await Supabase.initialize(
          url: const String.fromEnvironment(
            'SUPABASE_URL',
            defaultValue: 'https://mltvpfqfhbhgkejcjpmq.supabase.co',
          ),
          anonKey: const String.fromEnvironment(
            'SUPABASE_ANON_KEY',
            defaultValue: 'sb_publishable_3c2SHzm3Y8u_pjbmpWNSXw_5Rwkn5b_',
          ),
        );
      } catch (e, st) {
        debugPrint("Supabase Init Error: $e");
        Sentry.captureException(e, stackTrace: st);
      }

      // Launch the UI as soon as the essential Supabase setup is ready.
      // Non-critical services are initialized after the first frame so a
      // cold start is not blocked by push, moderation model, profile fetch,
      // or rewarded-ad preloading.
      WidgetsBinding.instance.addObserver(_AppLifecycleObserver());
      runApp(const AiSocialApp());

      // These services are intentionally deferred. They remain available,
      // but no longer delay the first screen from appearing.
      unawaited(_initializeDeferredServices());
    },
    (error, stackTrace) {
      debugPrint('CRITICAL ASYNC ERROR: $error');
      debugPrint('STACKTRACE: $stackTrace');
      Sentry.captureException(error, stackTrace: stackTrace);
    },
  );
}
         




Future<void> _initializeDeferredServices() async {
  // Safe OneSignal Initialization
  try {
    OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
    OneSignal.initialize("d82b1c8e-4add-4022-9f3d-8af0bcdf7915");
    OneSignal.Notifications.addClickListener((event) {
      final data = event.notification.additionalData;
      if (data == null) return;
      final type = data['type'] as String?;
      final nav = navigatorKey.currentState;
      if (nav == null) return;
      if (type == 'message') {
        final senderId = data['senderId'] as String?;
        final senderName = data['senderName'] as String? ?? 'User';
        if (senderId != null) {
          nav.push(MaterialPageRoute(
            builder: (_) => ChatPage(otherUid: senderId, otherUserName: senderName),
          ));
        }
      } else if (type == 'chest_ready') {
        nav.push(MaterialPageRoute(builder: (_) => const ChestsPage()));
      } else if (type == 'like' || type == 'follow' || type == 'comment' || type == 'get') {
        nav.push(MaterialPageRoute(builder: (_) => const NotificationPage()));
      }
    });
  } catch (e, st) {
    debugPrint("OneSignal Init Error: $e");
    Sentry.captureException(e, stackTrace: st);
  }

  // Heavy native moderation model: warm it after the UI is visible.
  try {
    await moderationPipeline.initialize();
  } catch (e, st) {
    debugPrint("Moderation Pipeline Init Error: $e");
    Sentry.captureException(e, stackTrace: st);
  }

  chestTimerService.initialize();
  coinChestTimerService.initialize();
  unawaited(loadUserDataOnStartup());
  RewardedAdPreloader.preload();
}
class AiSocialApp extends StatelessWidget {
  const AiSocialApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: scaffoldMessengerKey,
      navigatorKey: navigatorKey,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: const SplashPage(),
    );
  }
}

// Clears the signed-in user's own view of unsaved conversations whenever
// the app leaves the foreground — see clear_my_conversations() for what
// this actually does server-side (per-user cutoff, never touches the
// other participant's view or the underlying message rows).
//
// HONEST LIMITATION: Flutter's AppLifecycleState can reliably distinguish
// "foreground" from "not foreground" (paused/inactive/detached), but it
// CANNOT reliably distinguish "briefly backgrounded" from "swiped away
// from recents and about to be killed" — by the time Android actually
// terminates the process, no Dart code can run to react to it. `paused`
// (backgrounding) is the most robust signal actually available, so that's
// what's used here — in practice this means the chat clears as soon as
// the app leaves the foreground at all, not only on a full close.
// Clears the signed-in user's own view of unsaved conversations, and
// pauses/resumes the global chest timer, whenever the app leaves or
// returns to the foreground.
//
// HONEST LIMITATION: Flutter's AppLifecycleState can reliably distinguish
// "foreground" from "not foreground" (paused/inactive/detached), but it
// CANNOT reliably distinguish "briefly backgrounded" from "swiped away
// from recents and about to be killed" — by the time Android actually
// terminates the process, no Dart code can run to react to it. `paused`
// (backgrounding) is the most robust signal actually available, so that's
// what's used here — in practice this means both the chat-clearing and
// the chest-timer pause happen as soon as the app leaves the foreground
// at all, not only on a full close.
class _AppLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      chestTimerService.pauseAndPersist();
      coinChestTimerService.pauseAndPersist();
      if (Supabase.instance.client.auth.currentUser != null) {
        Supabase.instance.client.rpc('clear_my_conversations').catchError((e) {
          debugPrint('clear_my_conversations failed: $e');
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      chestTimerService.resumeFromForeground();
      coinChestTimerService.resumeFromForeground();
    }
  }
}

