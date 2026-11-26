
import 'dart:async';
import 'package:flutter/foundation.dart' show kDebugMode, defaultTargetPlatform, TargetPlatform;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_supabase_token_bridge.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'dart:ui' show PlatformDispatcher;
import 'fcm_service.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:sentry_flutter/sentry_flutter.dart';


import 'package:hive_flutter/hive_flutter.dart';

import 'auth_screen.dart';
import 'models.dart';
import 'service.dart';
import 'theme/theme.dart';
import 'theme/theme_controller.dart';
import 'chest_timer_service.dart';
import 'ad_preloader.dart';
import 'ad_free_access.dart';
import 'play_billing_service.dart';
import 'utils/friendly_error.dart';

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
                        diagnosticErrorMessage(details.exception),
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

      // Firebase Core must be ready before Supabase Auth is bridged to Firebase.
      // Supabase uses Firebase ID tokens as its third-party user JWT. Initialize
      // Firebase before Supabase so authenticated requests use the correct token.
      try {
        if (defaultTargetPlatform == TargetPlatform.android) {
          await Firebase.initializeApp();
          FlutterError.onError = (details) {
            FirebaseCrashlytics.instance.recordFlutterFatalError(details);
            Sentry.captureException(details.exception, stackTrace: details.stack);
          };
          PlatformDispatcher.instance.onError = (error, stackTrace) {
            FirebaseCrashlytics.instance.recordError(error, stackTrace, fatal: true);
            Sentry.captureException(error, stackTrace: stackTrace);
            return true;
          };
        }
      } catch (e, st) {
        debugPrint(diagnosticErrorMessage(e));
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
          accessToken: FirebaseSupabaseTokenBridge().getAccessToken,
        );
        if (defaultTargetPlatform == TargetPlatform.android &&
            Firebase.apps.isNotEmpty) {
          FcmService.initialize();
        }
      } catch (e, st) {
        debugPrint(diagnosticErrorMessage(e));
        Sentry.captureException(e, stackTrace: st);
      }

      WidgetsBinding.instance.addObserver(_AppLifecycleObserver());
      runApp(const AiSocialApp());

      unawaited(_initializeDeferredServices());
    },
    (error, stackTrace) {
      debugPrint('CRITICAL ASYNC ERROR: ${diagnosticErrorMessage(error)}');
      debugPrint('STACKTRACE: $stackTrace');
      Sentry.captureException(error, stackTrace: stackTrace);
      if (Firebase.apps.isNotEmpty) {
        unawaited(FirebaseCrashlytics.instance.recordError(error, stackTrace, fatal: true));
      }
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
        // Handle stale/unknown deep links safely instead of letting Flutter
        // fail while resolving a route after login or notification taps.
        onUnknownRoute: (settings) {
          debugPrint('Unknown route requested: ${settings.name}');
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => const SplashPage(),
          );
        },
      ),
    );
  }
}

class _AppLifecycleObserver extends WidgetsBindingObserver {
  static const Duration _sessionValidationInterval = Duration(seconds: 45);
  static const Set<String> _invalidSessionCodes = {
    'user-not-found',
    'user-disabled',
    'user-token-expired',
    'invalid-user-token',
  };

  Timer? _sessionValidationTimer;
  bool _sessionValidationInProgress = false;
  bool _handlingRemoteAccountDeletion = false;

  _AppLifecycleObserver() {
    _sessionValidationTimer = Timer.periodic(
      _sessionValidationInterval,
      (_) {
        if (_sessionValidationTimer?.isActive == true &&
            WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
          unawaited(_validateRemoteFirebaseAccount());
        }
      },
    );
  }

  Future<void> _validateRemoteFirebaseAccount() async {
    if (_sessionValidationInProgress || _handlingRemoteAccountDeletion) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _sessionValidationInProgress = true;
    try {
      // reload() calls Firebase's account lookup endpoint. If the account was
      // deleted from the website or disabled by an administrator, Firebase
      // rejects this cached client session with a definitive Auth error.
      await user.reload();
      final refreshedUser = FirebaseAuth.instance.currentUser;
      if (refreshedUser == null) {
        await _logoutAfterRemoteAccountDeletion();
        return;
      }

      // Force a token refresh as a second server-side check so a deleted
      // account cannot keep using a previously cached ID token.
      await refreshedUser.getIdToken(true);
    } on FirebaseAuthException catch (authError) {
      if (_invalidSessionCodes.contains(authError.code)) {
        debugPrint('Remote Firebase account is no longer valid (' + authError.code + '); signing out.');
        await _logoutAfterRemoteAccountDeletion();
      } else {
        // Transient network/rate-limit failures must never sign out a valid user.
        debugPrint('Firebase session revalidation deferred (' + authError.code + ').');
      }
    } catch (error, stackTrace) {
      debugPrint('Firebase session revalidation failed transiently: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _sessionValidationInProgress = false;
    }
  }

  Future<void> _logoutAfterRemoteAccountDeletion() async {
    if (_handlingRemoteAccountDeletion) return;
    _handlingRemoteAccountDeletion = true;

    try {
      // FCM unlink is best-effort. The public profile may already be deleted.
      await FcmService.signOutAndUnlink();
    } catch (error) {
      debugPrint('Remote-deletion cleanup failed; forcing local Firebase sign-out: $error');
      try {
        await FirebaseAuth.instance.signOut();
      } catch (signOutError) {
        debugPrint('Firebase local sign-out failed: $signOutError');
      }
    }

    resetLocalUserState();
    final navigator = navigatorKey.currentState;
    if (navigator != null) {
      navigator.pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => const LoginPage(sessionExpiredMessage: true),
        ),
        (route) => false,
      );
    }
    scaffoldMessengerKey.currentState?.showSnackBar(
      const SnackBar(
        content: Text('Your ProSN account is no longer available. Please sign in again.'),
      ),
    );
    _handlingRemoteAccountDeletion = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      chestTimerService.pauseAndPersist();
      if (FirebaseAuth.instance.currentUser != null) {
        Supabase.instance.client.rpc('clear_my_conversations').catchError((e) {
          debugPrint('clear_my_conversations failed: $e');
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      // Check immediately on return from background, then continue periodic
      // checks while the app remains in the foreground.
      unawaited(_validateRemoteFirebaseAccount());
      chestTimerService.resumeFromForeground();
      unawaited(AdFreeAccess.initialize());
      unawaited(PlayBillingService.instance.refreshSubscription().then((_) {
        RewardedAdPreloader.preload();
      }));
    }
  }
}

