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
  static String? lastEnableError;
  static String? lastTokenSaveError;

  static void initialize() {
    if (_initialized) return;
    _initialized = true;
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
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

  // Silent startup sync: save the device token without showing a permission prompt.
  static Future<void> syncForCurrentUser() async {
    if (Supabase.instance.client.auth.currentUser == null) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) {
        debugPrint('FCM startup sync: Firebase returned an empty token.');
        return;
      }
      await _saveToken(token);
    } catch (error, stackTrace) {
      debugPrint('FCM startup sync failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  // Explicit login/settings action: request permission and persist preference.
  static Future<bool> enableForCurrentUser() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      debugPrint('FCM registration skipped: no signed-in Supabase user.');
      return false;
    }
    var stage = 'checking notification permission';
    lastEnableError = null;
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

      if (!allowed) {
        lastEnableError = 'Android notification permission status: ${settings.authorizationStatus}. Check app notification permission.';
        return false;
      }

      stage = 'generating Firebase token';
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) {
        lastEnableError = 'Firebase returned an empty FCM token.';
        debugPrint(lastEnableError);
        return false;
      }

      stage = 'saving FCM token to Supabase';
      if (!await _saveToken(token)) {
        lastEnableError = lastTokenSaveError ?? 'FCM token generated, but Supabase did not save it.';
        return false;
      }

      stage = 'saving notification preference';
      await Supabase.instance.client
          .from('users')
          .update({'pushNotificationsEnabled': allowed})
          .eq('uid', user.id);

      debugPrint('FCM registration and preference update succeeded.');
      return true;
    } catch (error, stackTrace) {
      lastEnableError = '$stage failed: $error';
      debugPrint('FCM registration failed at $stage: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }

  static Future<bool> _saveToken(String token) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || token.isEmpty) {
      lastTokenSaveError = 'No authenticated Supabase user or empty FCM token.';
      return false;
    }
    lastTokenSaveError = null;
    try {
      final saved = await Supabase.instance.client
          .from('users')
          .update({'fcmToken': token})
          .eq('uid', user.id)
          .select('uid')
          .maybeSingle();
      if (saved == null) {
        lastTokenSaveError = 'Supabase UPDATE matched 0 rows for the signed-in user. Check public.users.uid against auth.uid().';
        debugPrint('FCM token save failed: $lastTokenSaveError');
        return false;
      }
      debugPrint('FCM token saved successfully.');
      return true;
    } catch (error, stackTrace) {
      lastTokenSaveError = 'Supabase token UPDATE error: $error';
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
          .update({'pushNotificationsEnabled': false, 'fcmToken': null})
          .eq('uid', user.id);
    } catch (error) {
      debugPrint('Could not disable push notifications: $error');
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
