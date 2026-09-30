import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:universal_io/universal_io.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'cloudflare_media_service.dart';
import 'models.dart';
import 'theme/theme.dart';

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

class PushService {
  static Future<void> togglePushNotificationStatus(bool isEnabled) async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) return;

    final client = Supabase.instance.client;

    if (isEnabled) {
      final accepted = await OneSignal.Notifications.requestPermission(true);

      if (accepted) {
        await OneSignal.login(currentUser.id);
        await client.from(kUsersCollection).update({
          'pushNotificationsEnabled': true,
          'notifyLikes': true,
          'notifyComments': true,
          'notifyGets': true,
          'notifyFollow': true,
          'notifyMessages': true,
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

Future<String?> uploadImageBytesToMediaGateway(
  Uint8List bytes, {
  String folder = 'posts',
  bool clientModerated = false,
}) async {
  try {
    return await CloudflareMediaService.uploadImageBytes(
      bytes,
      folder: folder,
    );
  } catch (e) {
    debugPrint("Cloudflare moderation + ImgBB upload failed: $e");
    return null;
  }
}

Future<String?> uploadImageToMediaGateway(
  File imageFile, {
  String folder = 'posts',
  void Function(int sent, int total)? onProgress,
}) async {
  try {
    return await CloudflareMediaService.uploadImage(
      imageFile,
      folder: folder,
      onProgress: onProgress,
    );
  } catch (e) {
    debugPrint("Cloudflare moderation + ImgBB upload failed: $e");
    return null;
  }
}

Future<Map<String, dynamic>> createPostThroughCloudflareBytes({
  required Uint8List bytes,
  required String contentType,
  required String caption,
  required String prompt,
  required String link,
  void Function(int sent, int total)? onProgress,
}) async {
  final url = await CloudflareMediaService.uploadImageBytes(
    bytes,
    folder: 'posts',
    contentType: contentType,
    caption: caption,
    prompt: prompt,
    link: link,
    onProgress: onProgress,
  );
  if (url.isEmpty) throw StateError('ImgBB did not return a post image URL');
  return {'url': url};
}

Future<Map<String, dynamic>> createPostThroughCloudflare({
  required File imageFile,
  required String caption,
  required String prompt,
  required String link,
  void Function(int sent, int total)? onProgress,
}) async {
  final url = await CloudflareMediaService.uploadImage(
    imageFile,
    folder: 'posts',
    caption: caption,
    prompt: prompt,
    link: link,
    onProgress: onProgress,
  );
  if (url.isEmpty) throw StateError('ImgBB did not return a post image URL');
  return {'url': url};
}

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

class GlobalCachedImage extends StatelessWidget {
  final String imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget? errorWidget;
  final FilterQuality filterQuality;

  const GlobalCachedImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit
        .cover,
    this.width,
    this.height,
    this.errorWidget,
    this.filterQuality = FilterQuality.high,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty || !imageUrl.startsWith('http')) {
      return Container(
        width: width,
        height: height,
        color: AppColors.surfaceElevated,
        child: errorWidget ?? const Icon(Icons.person, color: AppColors.textTertiary),
      );
    }

    // CachedNetworkImage has limited web caching support. On web, use the
    // browser's native image pipeline so a refresh does not depend on the
    // custom CacheManager implementation.
    if (kIsWeb) {
      return Image.network(
        imageUrl,
        width: width,
        height: height,
        fit: fit,
        filterQuality: filterQuality,
        gaplessPlayback: true,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            width: width,
            height: height,
            color: AppColors.surfaceElevated,
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          );
        },
        errorBuilder: (context, url, error) => Container(
          width: width,
          height: height,
          color: AppColors.surfaceElevated,
          child: this.errorWidget ??
              const Icon(Icons.broken_image, color: AppColors.textTertiary),
        ),
      );
    }

    return CachedNetworkImage(
      imageUrl: imageUrl,
      width: width,
      height: height,
      fit: fit,
      filterQuality: filterQuality,
      cacheManager: CustomImageCacheManager.instance,
      useOldImageOnUrlChange: true,
      placeholder: (context, url) => Container(
        width: width,
        height: height,
        color: AppColors.surfaceElevated,
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.textTertiary,
            ),
          ),
        ),
      ),
      errorWidget: (context, url, error) => Container(
        width: width,
        height: height,
        color: AppColors.surfaceElevated,
        child: this.errorWidget ??
            const Icon(Icons.broken_image, color: AppColors.textTertiary),
      ),
    );
  }
}
