import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('FCM background message: ${message.messageId}');
}

class FcmService {
  static StreamSubscription<String>? _tokenSubscription;
  static StreamSubscription<AuthState>? _authSubscription;
  static StreamSubscription<RemoteMessage>? _messageSubscription;
  static bool _initialized = false;

  static void initialize() {
    if (_initialized) return;
    _initialized = true;

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Explicitly enable FCM auto-init so Firebase can create/refresh this
    // installation's registration token.
    unawaited(FirebaseMessaging.instance.setAutoInitEnabled(true));

    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.signedIn ||
          event.event == AuthChangeEvent.initialSession ||
          event.event == AuthChangeEvent.tokenRefreshed) {
        unawaited(syncForCurrentUser());
      }
    });

    _tokenSubscription = FirebaseMessaging.instance.onTokenRefresh.listen(
      (token) => unawaited(_saveToken(token)),
      onError: (error) => debugPrint('FCM token refresh error: $error'),
    );

    _messageSubscription = FirebaseMessaging.onMessage.listen((message) {
      debugPrint('FCM foreground message: ${message.messageId}');
    });
  }

  static Future<void> syncForCurrentUser() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final row = await Supabase.instance.client
          .from('users')
          .select('pushNotificationsEnabled')
          .eq('uid', user.id)
          .maybeSingle();

      if (row?['pushNotificationsEnabled'] == true) {
        await enableForCurrentUser();
      }
    } catch (error) {
      debugPrint('FCM startup sync failed: $error');
    }
  }

  static Future<bool> enableForCurrentUser() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      debugPrint('FCM registration skipped: no signed-in Supabase user.');
      return false;
    }

    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      final allowed =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
      debugPrint('FCM notification authorization: ${settings.authorizationStatus}');

      // Token registration is independent of notification display permission.
      // Generate and save the token even if Android notification permission is denied.
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) {
        debugPrint('FCM token generation failed: Firebase returned an empty token.');
        return false;
      }
      debugPrint('FCM token generated successfully (value intentionally hidden).');

      final saved = await _saveToken(token);
      if (!saved) return false;

      if (!allowed) {
        debugPrint('FCM token saved, but notification display permission is denied.');
        return false;
      }

      debugPrint('FCM registration and Supabase token save succeeded.');
      return true;
    } catch (error, stackTrace) {
      debugPrint('FCM registration failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }

  static Future<bool> _saveToken(String token) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || token.isEmpty) {
      debugPrint('FCM token save skipped: user is signed out or token is empty.');
      return false;
    }

    try {
      final saved = await Supabase.instance.client
          .from('users')
          .update({'fcmToken': token})
          .eq('uid', user.id)
          .select('uid')
          .maybeSingle();

      if (saved == null) {
        debugPrint('FCM token save failed: no matching users row (check uid/RLS).');
        return false;
      }

      debugPrint('FCM token saved successfully for current user.');
      return true;
    } catch (error, stackTrace) {
      debugPrint('FCM token save failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }

  static Future<void> disableForCurrentUser() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      await Supabase.instance.client
          .from('users')
          .update({'fcmToken': null})
          .eq('uid', user.id);
    } catch (error) {
      debugPrint('Could not clear FCM token from Supabase: $error');
    }
  }

  static Future<void> dispose() async {
    await _tokenSubscription?.cancel();
    await _authSubscription?.cancel();
    await _messageSubscription?.cancel();
    _tokenSubscription = null;
    _authSubscription = null;
    _messageSubscription = null;
    _initialized = false;
  }
}
