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

  static Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    if (gatewayUrl.isEmpty) throw StateError('Cloudflare media gateway is not configured');
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null) throw StateError('Not authenticated');
    final response = await http.post(
      Uri.parse('$gatewayUrl$path'),
      headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    final decoded = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final reason = decoded is Map ? decoded['reason'] ?? decoded['error'] : null;
      throw StateError(reason?.toString() ?? 'Cloudflare media request failed');
    }
    return Map<String, dynamic>.from(decoded as Map);
  }

  static Future<String> moderateImage(File file) async {
    final bytes = await file.readAsBytes();
    final result = await _post('/v1/moderate-image', {
      'contentType': _contentType(file.path),
      'imageBase64': base64Encode(bytes),
    });
    if (result['safe'] != true) {
      throw StateError(result['reason']?.toString() ?? 'Server moderation rejected the image');
    }
    final approvalToken = result['approvalToken']?.toString();
    if (approvalToken == null || approvalToken.isEmpty) {
      throw StateError('Cloudflare did not return a moderation approval');
    }
    return approvalToken;
  }

  static Future<String> uploadImageBytes(
    Uint8List bytes, {
    String folder = 'posts',
    String contentType = 'image/jpeg',
    void Function(int sent, int total)? onProgress,
  }) async {
    if (bytes.isEmpty) throw StateError('Image is empty');
    if (bytes.length > 9 * 1024 * 1024) throw StateError('Image is too large');

    final intent = await _post('/v1/upload-intent', {
      'contentType': contentType,
      'folder': folder,
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

    final finalized = await _post('/v1/finalize-media', {
      'objectKey': objectKey,
      'contentType': contentType,
      'size': bytes.length,
      'folder': folder,
    });
    final url = finalized['url']?.toString();
    if (url == null || url.isEmpty) throw StateError('Server moderation did not approve media');
    return url;
  }

  static Future<String> uploadImage(
    File file, {
    String folder = 'posts',
    void Function(int sent, int total)? onProgress,
  }) async {
    final bytes = await file.readAsBytes();
    final contentType = _contentType(file.path);
    final intent = await _post('/v1/upload-intent', {
      'contentType': contentType,
      'folder': folder,
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

    final finalized = await _post('/v1/finalize-media', {
      'objectKey': objectKey,
      'contentType': contentType,
      'size': bytes.length,
      'folder': folder,
    });
    final url = finalized['url']?.toString();
    if (url == null || url.isEmpty) throw StateError('Server moderation did not approve media');
    return url;
  }

  static String _contentType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }
}
