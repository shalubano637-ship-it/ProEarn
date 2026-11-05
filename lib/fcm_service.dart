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
  static bool _initialized = false;

  static void initialize() {
    if (_initialized) return;
    _initialized = true;

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Re-register when a stored session is restored or a user signs in.
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.signedIn ||
          event.event == AuthChangeEvent.initialSession ||
          event.event == AuthChangeEvent.tokenRefreshed) {
        unawaited(syncForCurrentUser());
      }
    });

    _tokenSubscription = FirebaseMessaging.instance.onTokenRefresh.listen(
      (token) => _saveToken(token),
      onError: (error) => debugPrint('FCM token refresh error: $error'),
    );

    FirebaseMessaging.onMessage.listen((message) {
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
    if (user == null) return false;

    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      final allowed = settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
      if (!allowed) {
        debugPrint('FCM notification permission not granted.');
        return false;
      }

      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) {
        debugPrint('FCM did not return a registration token.');
        return false;
      }

      await _saveToken(token);
      return true;
    } catch (error, stackTrace) {
      debugPrint('FCM registration failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }

  static Future<void> _saveToken(String token) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || token.isEmpty) return;

    try {
      final saved = await Supabase.instance.client
          .from('users')
          .update({'fcmToken': token})
          .eq('uid', user.id)
          .select('uid')
          .maybeSingle();
      if (saved == null) {
        debugPrint('FCM token update matched no user row (uid/RLS check required).');
      } else {
        debugPrint('FCM token saved for current user.');
      }
    } catch (error) {
      debugPrint('Could not save FCM token to Supabase: $error');
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
    _tokenSubscription = null;
    _authSubscription = null;
    _initialized = false;
  }
}
