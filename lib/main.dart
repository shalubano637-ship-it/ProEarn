
import 'dart:async';
import 'package:flutter/foundation.dart' show kDebugMode, defaultTargetPlatform, TargetPlatform;
import 'package:firebase_core/firebase_core.dart';
import 'fcm_service.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:sentry_flutter/sentry_flutter.dart';


import 'package:hive_flutter/hive_flutter.dart';

import 'auth_screen.dart';
import 'service.dart';
import 'theme/theme.dart';
import 'theme/theme_controller.dart';
import 'chest_timer_service.dart';
import 'ad_preloader.dart';
import 'ad_free_access.dart';
import 'play_billing_service.dart';

final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

   Future<void> main() async {

  WidgetsFlutterBinding.ensureInitialized();

  await SentryFlutter.init((options) {
    options.dsn = const String.fromEnvironment('SENTRY_DSN');
    options.tracesSampleRate = 0.2;
    options.debug = kDebugMode;
  });

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

  runZonedGuarded(
    () async {

      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);

      try {
        await Hive.initFlutter();
        await Hive.openBox('app_settings');
      } catch (e, st) {
        debugPrint("Hive Init Error: $e");
        Sentry.captureException(e, stackTrace: st);
      }

      try {
        await appThemeController.load();
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

      // Start Firebase Messaging after Supabase is ready for auth restoration.
      try {
        if (defaultTargetPlatform == TargetPlatform.android) {
          await Firebase.initializeApp();
          FcmService.initialize();
        }
      } catch (e, st) {
        debugPrint('Firebase Init Error: $e');
        Sentry.captureException(e, stackTrace: st);
      }

      WidgetsBinding.instance.addObserver(_AppLifecycleObserver());
      runApp(const AiSocialApp());

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

  chestTimerService.initialize();
  unawaited(loadUserDataOnStartup());
  try {
    await AdFreeAccess.initialize();
    unawaited(PlayBillingService.instance.initialize());
  } catch (e, st) {
    debugPrint('Billing entitlement initialization failed: $e');
    Sentry.captureException(e, stackTrace: st);
  }
  try {
    await MobileAds.instance.initialize();
    RewardedAdPreloader.preload();
  } catch (e, st) {
    debugPrint('Google Mobile Ads initialization failed: $e');
    Sentry.captureException(e, stackTrace: st);
  }
}
class AiSocialApp extends StatelessWidget {
  const AiSocialApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appThemeController,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        scaffoldMessengerKey: scaffoldMessengerKey,
        navigatorKey: navigatorKey,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: appThemeController.mode,
        home: const SplashPage(),
      ),
    );
  }
}

class _AppLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      chestTimerService.pauseAndPersist();
      if (Supabase.instance.client.auth.currentUser != null) {
        Supabase.instance.client.rpc('clear_my_conversations').catchError((e) {
          debugPrint('clear_my_conversations failed: $e');
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      chestTimerService.resumeFromForeground();
      unawaited(AdFreeAccess.initialize());
      unawaited(PlayBillingService.instance.refreshSubscription());
    }
  }
}

