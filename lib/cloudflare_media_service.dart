import 'dart:convert';
import 'dart:typed_data';
import 'package:universal_io/universal_io.dart';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class CloudflareMediaService {
  static const gatewayUrl = String.fromEnvironment(
    'CLOUDFLARE_MEDIA_GATEWAY_URL',
    defaultValue: '',
  );

  static Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    if (gatewayUrl.isEmpty) {
      throw StateError('Cloudflare moderation gateway is not configured');
    }

    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null) throw StateError('Not authenticated');

    final response = await http.post(
      Uri.parse('$gatewayUrl$path'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );

    final decoded =
        response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final reason =
          decoded is Map ? decoded['reason'] ?? decoded['error'] : null;
      throw StateError(
        reason?.toString() ?? 'Cloudflare moderation request failed',
      );
    }

    return Map<String, dynamic>.from(decoded as Map);
  }

  /// Second moderation gate. This does NOT store the image.
  /// It only sends the bytes to Cloudflare for server-side safety analysis
  /// and returns a short-lived approval token for the ImgBB Edge Function.
  static Future<String> moderateImageBytes(
    Uint8List bytes, {
    String contentType = 'image/jpeg',
  }) async {
    if (bytes.isEmpty) throw StateError('Image is empty');
    if (bytes.length > 9 * 1024 * 1024) {
      throw StateError('Image is too large');
    }

    final result = await _post('/v1/moderate-image', {
      'contentType': contentType,
      'imageBase64': base64Encode(bytes),
    });

    if (result['safe'] != true) {
      throw StateError(
        result['reason']?.toString() ?? 'Cloudflare rejected the image',
      );
    }

    final approvalToken = result['approvalToken']?.toString();
    if (approvalToken == null || approvalToken.isEmpty) {
      throw StateError('Cloudflare did not return a moderation approval');
    }

    return approvalToken;
  }

  /// Backwards-compatible file API. It performs server-side moderation only;
  /// the actual storage upload is handled by the ImgBB Edge Function.
  static Future<String> moderateImage(File file) async {
    final bytes = await file.readAsBytes();
    return moderateImageBytes(
      bytes,
      contentType: _contentType(file.path),
    );
  }

  /// Kept with the existing call sites so chat/comments/profile/room uploads
  /// automatically use the new pipeline:
  /// device moderation -> Cloudflare moderation -> ImgBB storage.
  static Future<String> uploadImageBytes(
    Uint8List bytes, {
    String folder = 'posts',
    String contentType = 'image/jpeg',
    String? caption,
    String? prompt,
    String? link,
    void Function(int sent, int total)? onProgress,
  }) async {
    final approvalToken = await moderateImageBytes(
      bytes,
      contentType: contentType,
    );

    final response = await Supabase.instance.client.functions.invoke(
      'imgbb-upload',
      body: {
        'imageBase64': base64Encode(bytes),
        'folder': folder,
        'moderationApprovalToken': approvalToken,
        if (caption != null) 'caption': caption,
        if (prompt != null) 'prompt': prompt,
        if (link != null) 'link': link,
      },
    );

    final data = response.data;
    if (data is! Map) throw StateError('Invalid ImgBB response');

    final url = data['url']?.toString();
    if (url == null || url.isEmpty) {
      throw StateError('ImgBB did not return an image URL');
    }

    onProgress?.call(bytes.length, bytes.length);
    return url;
  }

  static Future<String> uploadImage(
    File file, {
    String folder = 'posts',
    void Function(int sent, int total)? onProgress,
  }) async {
    final bytes = await file.readAsBytes();
    return uploadImageBytes(
      bytes,
      folder: folder,
      contentType: _contentType(file.path),
      onProgress: onProgress,
    );
  }

  static String _contentType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }
}
