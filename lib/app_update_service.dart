import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppUpdateInfo {
  final bool published;
  final String status;
  final int versionCode;
  final String versionName;
  final String apkUrl;
  final String title;
  final String message;
  final List<String> newFeatures;
  final List<String> fixes;
  final bool forceUpdate;

  const AppUpdateInfo({
    required this.published,
    required this.status,
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
    required this.title,
    required this.message,
    required this.newFeatures,
    required this.fixes,
    required this.forceUpdate,
  });

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) => AppUpdateInfo(
        published: json['published'] == true,
        status: json['status']?.toString() ?? (json['published'] == true ? 'published' : 'draft'),
        versionCode: (json['versionCode'] as num?)?.toInt() ?? 0,
        versionName: json['versionName']?.toString() ?? '',
        apkUrl: json['apkUrl']?.toString() ?? '',
        title: json['title']?.toString() ?? 'New Update Available',
        message: json['message']?.toString() ?? '',
        newFeatures: List<String>.from(json['newFeatures'] ?? const []),
        fixes: List<String>.from(json['fixes'] ?? const []),
        forceUpdate: json['forceUpdate'] == true,
      );
}

class AppUpdateService {
  static const _metadataUrl =
      'https://raw.githubusercontent.com/shalubano637-ship-it/ProEarn/main/update.json';
  static const _channel = MethodChannel('proearn/updater');

  static Future<AppUpdateInfo?> checkForUpdate() async {
    try {
      final response = await http
          .get(Uri.parse('$_metadataUrl?t=${DateTime.now().millisecondsSinceEpoch}'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;

      final info = AppUpdateInfo.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );

      final isAdmin = Supabase.instance.client.auth.currentUser?.email?.toLowerCase().trim() == 'shalubano637@gmail.com';

      // Testing updates are visible only to the admin account.
      if (info.status == 'testing') {
        if (!isAdmin) return null;
      } else if (!info.published) {
        return null;
      }
      if (info.versionCode <= 0 || info.apkUrl.isEmpty) return null;

      final package = await PackageInfo.fromPlatform();
      final currentCode = int.tryParse(package.buildNumber) ?? 0;
      return info.versionCode > currentCode ? info : null;
    } catch (_) {
      return null;
    }
  }

  static Future<File> downloadApk(
    AppUpdateInfo info, {
    void Function(int received, int total)? onProgress,
  }) async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/proearn-${info.versionName}.apk');

    final request = http.Request('GET', Uri.parse(info.apkUrl));
    final client = http.Client();
    final response = await client.send(request);
    if (response.statusCode != 200) {
      client.close();
      throw Exception('Download failed (${response.statusCode})');
    }

    final total = response.contentLength ?? 0;
    var received = 0;
    final sink = file.openWrite();
    try {
      await for (final chunk in response.stream) {
        received += chunk.length;
        sink.add(chunk);
        onProgress?.call(received, total);
      }
    } finally {
      await sink.close();
      client.close();
    }
    return file;
  }

  static Future<void> installApk(File apk) async {
    await _channel.invokeMethod('installApk', {'path': apk.path});
  }
}
