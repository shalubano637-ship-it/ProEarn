import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';
import '../theme/theme.dart';

class AdminUpdatePage extends StatefulWidget {
  const AdminUpdatePage({super.key});

  @override
  State<AdminUpdatePage> createState() => _AdminUpdatePageState();
}

class _AdminUpdatePageState extends State<AdminUpdatePage> {
  final _versionName = TextEditingController();
  final _versionCode = TextEditingController();
  final _title = TextEditingController(text: 'New Update Available');
  final _message = TextEditingController();
  final _features = TextEditingController();
  final _fixes = TextEditingController();
  bool _forceUpdate = false;
  bool _publishing = false;

  @override
  void dispose() {
    _versionName.dispose();
    _versionCode.dispose();
    _title.dispose();
    _message.dispose();
    _features.dispose();
    _fixes.dispose();
    super.dispose();
  }

  List<String> _lines(String value) => value
      .split(RegExp(r'\r?\n'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  Future<void> _publish() async {
    final email = Supabase.instance.client.auth.currentUser?.email?.toLowerCase().trim();
    if (email != kAdminEmail.toLowerCase()) {
      _snack('Not authorized.', error: true);
      return;
    }

    final code = int.tryParse(_versionCode.text.trim());
    if (code == null || code <= 0 || _versionName.text.trim().isEmpty) {
      _snack('Version name aur valid version code enter karo.', error: true);
      return;
    }

    setState(() => _publishing = true);
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'publish-app-update',
        body: {
          'versionCode': code,
          'versionName': _versionName.text.trim(),
          'title': _title.text.trim(),
          'message': _message.text.trim(),
          'newFeatures': _lines(_features.text),
          'fixes': _lines(_fixes.text),
          'forceUpdate': _forceUpdate,
        },
      );

      if (!mounted) return;
      if (response.status >= 200 && response.status < 300) {
        _snack('Update publish ho gaya. GitHub Actions APK build karega.');
      } else {
        final data = response.data;
        _snack(data is Map && data['error'] != null ? data['error'].toString() : 'Publish failed.', error: true);
      }
    } catch (e) {
      if (mounted) _snack('Publish failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  void _snack(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: error ? AppColors.error : null),
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = Supabase.instance.client.auth.currentUser?.email?.toLowerCase().trim();
    if (email != kAdminEmail.toLowerCase()) {
      return const Scaffold(body: Center(child: Text('Not authorized.')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Admin — Publish Update')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Publish a new app version',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text('Publishing commits update.json. GitHub Actions then builds and releases the APK.'),
          const SizedBox(height: 20),
          TextField(controller: _versionName, decoration: const InputDecoration(labelText: 'Version name', hintText: '1.0.2')),
          const SizedBox(height: 12),
          TextField(
            controller: _versionCode,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Version code', hintText: '3'),
          ),
          const SizedBox(height: 12),
          TextField(controller: _title, decoration: const InputDecoration(labelText: 'Update title')),
          const SizedBox(height: 12),
          TextField(controller: _message, maxLines: 3, decoration: const InputDecoration(labelText: 'Message')),
          const SizedBox(height: 12),
          TextField(
            controller: _features,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'New features', hintText: 'One item per line'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _fixes,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'Fixes & improvements', hintText: 'One item per line'),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Force update'),
            subtitle: const Text('Users cannot dismiss the update popup.'),
            value: _forceUpdate,
            onChanged: _publishing ? null : (v) => setState(() => _forceUpdate = v),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _publishing ? null : _publish,
              icon: _publishing
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.publish),
              label: Text(_publishing ? 'Publishing…' : 'Publish Update'),
            ),
          ),
        ],
      ),
    );
  }
}
