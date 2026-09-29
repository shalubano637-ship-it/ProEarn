import 'dart:async';
import 'dart:convert';
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

Future<String?> uploadImageToMediaGateway(
  File imageFile, {
  String folder = 'posts',
  void Function(int sent, int total)? onProgress,
}) async {
  try {
    final bytes = await imageFile.readAsBytes();
    final base64Image = base64Encode(bytes);
    onProgress?.call(0, bytes.length);

    final response = await Supabase.instance.client.functions.invoke(
      'imgbb-upload',
      body: {
        'imageBase64': base64Image,
        'folder': folder,
      },
    );

    final data = response.data;
    if (data is! Map) {
      throw StateError('Invalid ImgBB response');
    }

    final url = data['url']?.toString();
    if (url == null || url.isEmpty) {
      throw StateError('ImgBB did not return an image URL');
    }

    onProgress?.call(bytes.length, bytes.length);
    return url;
  } catch (e) {
    debugPrint("ImgBB image upload failed: $e");
    return null;
  }
}

Future<Map<String, dynamic>> createPostThroughCloudflare({
  required File imageFile,
  required String caption,
  required String prompt,
  required String link,
  void Function(int sent, int total)? onProgress,
}) async {
  final bytes = await imageFile.readAsBytes();
  final contentType = imageFile.path.toLowerCase().endsWith('.png')
      ? 'image/png'
      : imageFile.path.toLowerCase().endsWith('.webp')
          ? 'image/webp'
          : 'image/jpeg';

  if (CloudflareMediaService.gatewayUrl.isEmpty) {
    throw StateError('Cloudflare media gateway is not configured');
  }

  final intent = await _cloudflarePost('/v1/upload-intent', {
    'contentType': contentType,
    'folder': 'posts',
  });
  final uploadUrl = intent['uploadUrl']?.toString();
  final objectKey = intent['objectKey']?.toString();
  if (uploadUrl == null || objectKey == null) throw StateError('Invalid upload intent');

  final request = http.Request('PUT', Uri.parse(uploadUrl));
  request.headers['Content-Type'] = contentType;
  request.bodyBytes = bytes;
  onProgress?.call(0, bytes.length);
  final response = await request.send();
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw StateError('R2 upload failed: ${response.statusCode}');
  }
  onProgress?.call(bytes.length, bytes.length);

  return _cloudflarePost('/v1/finalize-post', {
    'objectKey': objectKey,
    'contentType': contentType,
    'size': bytes.length,
    'caption': caption,
    'prompt': prompt,
    'link': link,
  });
}

Future<Map<String, dynamic>> _cloudflarePost(String path, Map<String, dynamic> body) async {
  final token = Supabase.instance.client.auth.currentSession?.accessToken;
  if (token == null) throw StateError('Not authenticated');
  final response = await http.post(
    Uri.parse('${CloudflareMediaService.gatewayUrl}$path'),
    headers: {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    },
    body: jsonEncode(body),
  );
  final decoded = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);
  if (response.statusCode < 200 || response.statusCode >= 300) {
    final reason = decoded is Map ? decoded['reason'] ?? decoded['error'] : null;
    throw StateError(reason?.toString() ?? 'Cloudflare request failed');
  }
  return Map<String, dynamic>.from(decoded as Map);
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

  const GlobalCachedImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit
        .cover,
    this.width,
    this.height,
    this.errorWidget,
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
        filterQuality: FilterQuality.medium,
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
      filterQuality: FilterQuality.medium,
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
