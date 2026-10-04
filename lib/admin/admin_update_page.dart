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
  bool _working = false;

  Future<void> _submit(String action) async {
    final email =
        Supabase.instance.client.auth.currentUser?.email?.toLowerCase().trim();
    if (email != kAdminEmail.toLowerCase()) {
      _snack('Not authorized.', error: true);
      return;
    }

    setState(() => _working = true);
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'publish-app-update',
        body: {'action': action},
      );

      if (!mounted) return;
      if (response.status >= 200 && response.status < 300) {
        final data = response.data;
        final update =
            data is Map && data['update'] is Map ? data['update'] as Map : null;
        final version = update?['versionName']?.toString();
        final build = update?['versionCode']?.toString();

        _snack(
          action == 'test'
              ? 'Test build ${version ?? ''} (build ${build ?? ''}) start ho gaya. Sirf Admin ko dikhega.'
              : 'Update public ho gaya. Ab users ko update dikhega.',
        );
      } else {
        final data = response.data;
        _snack(
          data is Map && data['error'] != null
              ? data['error'].toString()
              : 'Operation failed.',
          error: true,
        );
      }
    } catch (e) {
      if (mounted) _snack('Operation failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _snack(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? AppColors.error : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final email =
        Supabase.instance.client.auth.currentUser?.email?.toLowerCase().trim();
    if (email != kAdminEmail.toLowerCase()) {
      return const Scaffold(body: Center(child: Text('Not authorized.')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Admin — App Updates')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Test → Verify → Publish',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Ab version name, version code ya changelog manually enter karne ki zarurat nahi hai. '
            'Test Update automatically next version/build banayega, update.json set karega aur GitHub Actions se APK build karega.',
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _working ? null : () => _submit('test'),
            icon: const Icon(Icons.science_outlined),
            label: const Text('Test Update'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _working ? null : () => _submit('publish'),
            icon: const Icon(Icons.public),
            label: const Text('Publish to Everyone'),
          ),
          const SizedBox(height: 18),
          if (_working) const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 12),
          const Text(
            'Flow: Test Update → APK build → Admin install/test → sab sahi ho to Publish to Everyone.',
            style: TextStyle(fontSize: 13),
          ),
        ],
      ),
    );
  }
}
