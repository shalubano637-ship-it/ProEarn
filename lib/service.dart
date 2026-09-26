// =============================================================================
// PRO EARN — Backend/service helpers (Supabase, ImgBB via edge proxy, OneSignal)
// -----------------------------------------------------------------------------
// Split out of main.dart. Contains non-UI helper functions and service
// classes: account repair, push-notification toggling, sending in-app
// notifications, fetching posts, uploading images to ImgBB via a
// server-side edge function proxy, the shared image cache manager, and
// the monetization "get" transaction helper.
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'models.dart';
import 'theme/theme.dart';

// ================= AUTOMATIC ACCOUNT REPAIR PIPELINE =================
/// Creates a default Supabase user row for a signed-in auth user if one
/// doesn't already exist.
Future<void> ensureUserDocumentExists() async {
  final currentUser = Supabase.instance.client.auth.currentUser;
  if (currentUser == null) return;

  final client = Supabase.instance.client;

  try {
    final existing = await client
        .from(kUsersCollection)
        .select('uid')
        .eq('uid', currentUser.id)
        .maybeSingle();

    if (existing == null) {
      String defaultUsername = currentUser.email != null
          ? currentUser.email!.split('@')[0]
          : "user_${currentUser.id.substring(0, 5)}";

      await client.from(kUsersCollection).insert({
        'uid': currentUser.id,
        'userName': defaultUsername,
        'bio': 'No Bio Yet',
        'link': 'No Link',
        'profileUrl': '',
      });
      debugPrint("Supabase user row repaired successfully.");
    }
  } catch (e) {
    debugPrint("Error repairing missing user context: $e");
  }
}

// ================= PUSH SERVICE (OneSignal + Supabase) =================
/// Wraps OneSignal: toggling user's push-notification preferences in Supabase.
class PushService {
  static Future<void> togglePushNotificationStatus(bool isEnabled) async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) return;

    final client = Supabase.instance.client;

    if (isEnabled) {
      // Ask the OS for push permission and link this device to the user's
      // uid so OneSignal's `external_id` targeting (used server-side by
      // the `notify` edge function) keeps working exactly as before.
      final accepted = await OneSignal.Notifications.requestPermission(true);

      if (accepted) {
        await OneSignal.login(currentUser.id);
        await client.from(kUsersCollection).update({
          'pushNotificationsEnabled': true,
          'notifyLikes': true,
          'notifyComments': true,
          'notifyGets': true,
          'notifyFollow': true,
        }).eq('uid', currentUser.id);
        debugPrint("OneSignal device linked with default preferences enabled.");
      }
    } else {
      await OneSignal.logout();
      await client.from(kUsersCollection).update({
        'pushNotificationsEnabled': false,
      }).eq('uid', currentUser.id);
    }
  }

  static Future<void> updateSinglePreference(String fieldKey, bool value) async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) return;

    await Supabase.instance.client
        .from(kUsersCollection)
        .update({fieldKey: value})
        .eq('uid', currentUser.id);
  }
}

// ================= STARTUP DATA PERSISTENT FIX =================
Future<void> loadUserDataOnStartup() async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user != null) {
    currentUserId = user.id;
    currentUserEmail = user.email ?? "";

    try {
      final data = await Supabase.instance.client
          .from(kUsersCollection)
          .select()
          .eq('uid', user.id)
          .maybeSingle();
      if (data != null) {
        currentUserName = data['userName'] ?? user.email!.split("@")[0];
        currentUserBio = data['bio'] ?? "";
        currentUserProfile = data['profileUrl'] ?? "";
      }
    } catch (e) {
      debugPrint("Startup Profile context loading fail recovery pipeline trigger: $e");
    }
  }
}

// ================= BAN ENFORCEMENT =================
/// One-shot check: is the signed-in user currently banned (admin panel's
/// Ban User action sets `users.isBanned`)? If so, sign them out and clear
/// local state right here, so every call site just has to check the
/// returned bool and redirect to LoginPage instead of MainNavigationScreen.
///
/// Called at every place a session can hand off into the app (splash
/// auto-login, explicit login, post-signup email verification). For a
/// LIVE ban — admin bans someone while they're already inside the app —
/// see BannedUserWatcher in navigation_shell.dart instead, which reacts to
/// the same flag in real time via a Supabase stream.
Future<bool> isCurrentUserBanned() async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return false;

  try {
    final data = await Supabase.instance.client
        .from(kUsersCollection)
        .select('isBanned')
        .eq('uid', user.id)
        .maybeSingle();
    if (data != null && data['isBanned'] == true) {
      await Supabase.instance.client.auth.signOut();
      resetLocalUserState();
      return true;
    }
  } catch (e) {
    debugPrint("Ban check failed (treating as not banned): $e");
  }
  return false;
}

    // ================= NOTE =================
// The client-side OneSignal REST-key push helper that used to live here
// has been removed. Pushes now happen entirely inside the `notify`
// Supabase Edge Function (see sendNotification below), which holds the
// OneSignal REST API key server-side only.


   // ================= NOTIFICATION SENDER (server-side via edge function) =================
// This used to check preferences, insert the notification row, and call
// OneSignal all from the client — which meant the OneSignal REST key had
// to live in the app, and any client could insert a notification
// addressed to any other user. Both are now handled inside the `notify`
// edge function; this wrapper keeps the exact same call signature so
// every call site elsewhere in the app is unchanged.
Future<void> sendNotification({
  required String targetOwnerId,
  required String type,
  required String message,
  String targetPostId = '',
}) async {
  final currentUser = Supabase.instance.client.auth.currentUser;
  if (currentUser == null) return;
  if (currentUser.id == targetOwnerId && type != 'chest_ready') return;

  try {
    await Supabase.instance.client.functions.invoke(
      'notify',
      body: {
        'targetOwnerId': targetOwnerId,
        'type': type,
        'message': message,
        'targetPostId': targetPostId,
      },
    );
  } catch (e) {
    debugPrint("Notification send error: $e");
  }
}


      
      

    

// ================= IMGBB UPLOADER (server-side proxy, secure) =================
// R2 setup abhi pending hai, isliye ImgBB wapas use ho raha hai — lekin
// is baar API key client ke andar nahi hai. App image ko base64 me
// `imgbb-upload` edge function ko bhejta hai; woh function (jahan key
// server-side secret ke roop me stored hai) actual ImgBB upload karta
// hai aur URL wapas bhejta hai. Decompile karke bhi key nahi milegi.

/// Uploads [imageFile] to ImgBB via the server-side proxy and returns its
/// public URL, or null on failure. [folder] is kept for call-site
/// compatibility (progress-bar callers etc.) but isn't used by ImgBB.
Future<String?> uploadImageToImgBB(
  File imageFile, {
  String folder = 'posts',
  void Function(int sent, int total)? onProgress,
}) async {
  try {
    final bytes = await imageFile.readAsBytes();
    onProgress?.call(0, bytes.length);

    final base64Image = base64Encode(bytes);

    final response = await Supabase.instance.client.functions.invoke(
      'imgbb-upload',
      body: {'imageBase64': base64Image},
    );

    onProgress?.call(bytes.length, bytes.length);

    final data = response.data;
    if (response.status != 200 || data is! Map || data['url'] is! String) {
      debugPrint("ImgBB upload failed: ${response.status} ${response.data}");
      return null;
    }

    return data['url'] as String;
  } catch (e) {
    debugPrint("Error uploading to ImgBB: $e");
    return null;
  }
}

// ================= IMAGE CACHE MANAGER =================
class CustomImageCacheManager {
  static const key = 'customCacheKey';
  static CacheManager instance = CacheManager(
    Config(
      key,
      stalePeriod: const Duration(days: 7),
      maxNrOfCacheObjects: 300,
    ),
  );
}

// ================= GLOBAL CACHED IMAGE WIDGET =================
// Moved here from main.dart so pages that need it (bag_page.dart,
// messaging/, chests/) don't have to import main.dart directly, which
// would create a circular import (main.dart → navigation_shell.dart →
// those pages → main.dart). service.dart has no dependency back on any
// screen file, so it's a safe shared home for this.
class GlobalCachedImage extends StatelessWidget {
  final String imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget? errorWidget;

  const GlobalCachedImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit
        .cover, // Enforces Aspect-Ratio Cover globally to stop shrinking/stretching
    this.width,
    this.height,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    // Fallback if URL is corrupted or local file path is sent
    if (imageUrl.isEmpty || !imageUrl.startsWith('http')) {
      return Container(
        width: width,
        height: height,
        color: AppColors.surfaceElevated,
        child: errorWidget ?? const Icon(Icons.person, color: AppColors.textTertiary),
      );
    }

    return CachedNetworkImage(
      imageUrl: imageUrl,
      width: width,
      height: height,
      fit: fit, // proportional fitting mechanism
      filterQuality: FilterQuality.high,
      cacheManager: CustomImageCacheManager.instance,
      placeholder: (context, url) => Container(
        width: width,
        height: height,
        color: AppColors.surfaceElevated,
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.textTertiary),
          ),
        ),
      ),
      errorWidget: (context, url, error) => Container(
        width: width,
        height: height,
        color: AppColors.surfaceElevated,
        child:
            errorWidget ?? const Icon(Icons.broken_image, color: AppColors.textTertiary),
      ),
    );
  }
}
