import 'package:flutter/material.dart';

import 'app_update_service.dart';
import 'theme/theme.dart';

class AppUpdatePage extends StatefulWidget {
  final AppUpdateInfo? updateInfo;
  const AppUpdatePage({super.key, this.updateInfo});

  @override
  State<AppUpdatePage> createState() => _AppUpdatePageState();
}

class _AppUpdatePageState extends State<AppUpdatePage> {
  AppUpdateInfo? _info;
  bool _checking = true;
  bool _downloading = false;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _info = widget.updateInfo;
    if (_info != null) {
      _checking = false;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    final info = await AppUpdateService.checkForUpdate();
    if (!mounted) return;
    setState(() {
      _info = info;
      _checking = false;
    });
  }

  Future<void> _downloadAndInstall() async {
    final info = _info;
    if (info == null || _downloading) return;

    setState(() {
      _downloading = true;
      _progress = 0;
    });

    try {
      final apk = await AppUpdateService.downloadApk(
        info,
        onProgress: (received, total) {
          if (!mounted || total <= 0) return;
          setState(() => _progress = received / total);
        },
      );
      if (!mounted) return;
      await AppUpdateService.installApk(apk);
    } catch (e) {
      if (!mounted) return;
      setState(() => _downloading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update failed: $e'), backgroundColor: AppColors.error),
      );
    }
  }

  Widget _bulletSection(String title, List<String> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Icon(Icons.circle, size: 6),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(item, style: const TextStyle(height: 1.35))),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;

    return Scaffold(
      appBar: AppBar(title: const Text('App Update')),
      body: _checking
          ? const Center(child: CircularProgressIndicator())
          : info == null
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('You are using the latest version.', textAlign: TextAlign.center),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.system_update_alt, size: 34),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            info.title,
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('Version ${info.versionName}'),
                    if (info.message.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(info.message, style: const TextStyle(height: 1.45)),
                    ],
                    const SizedBox(height: 22),
                    _bulletSection('New Features', info.newFeatures),
                    _bulletSection('Fixes & Improvements', info.fixes),
                    const SizedBox(height: 16),
                    if (_downloading) ...[
                      LinearProgressIndicator(value: _progress > 0 ? _progress : null),
                      const SizedBox(height: 8),
                      Text(
                        _progress > 0
                            ? 'Downloading ${(100 * _progress).toStringAsFixed(0)}%'
                            : 'Preparing download…',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                    ],
                    SizedBox(
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: _downloading ? null : _downloadAndInstall,
                        icon: const Icon(Icons.download),
                        label: Text(_downloading ? 'Downloading…' : 'Download Update'),
                      ),
                    ),
                  ],
                ),
    );
  }
}
