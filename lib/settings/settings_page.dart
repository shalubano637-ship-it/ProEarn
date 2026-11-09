import 'package:flutter/material.dart';

import 'push_notification_page.dart';
import 'security_page.dart';
import 'help_page.dart';
import 'privacy_page.dart';
import 'theme_settings_page.dart';
import '../models.dart';
import '../admin/admin_reports_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  Widget buildTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required Widget page,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => page));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        children: [
          buildTile(
            context: context,
            icon: Icons.person_outline,
            title: "Push Notification",
            page: const PushNotificationPage(),
          ),
          buildTile(
            context: context,
            icon: Icons.security,
            title: "Security",
            page: const SecurityPage(),
          ),
          buildTile(
            context: context,
            icon: Icons.lock_outline,
            title: "Privacy",
            page: const PrivacyPage(),
          ),
          buildTile(
            context: context,
            icon: Icons.help_outline,
            title: "Help",
            page: const HelpPage(),
          ),
          buildTile(
            context: context,
            icon: Icons.palette_outlined,
            title: "Themes",
            page: const ThemeSettingsPage(),
          ),
          if (isAdmin) ...[
            buildTile(
              context: context,
              icon: Icons.shield_outlined,
              title: "Admin Panel",
              page: const AdminReportsPage(),
            ),
          ],
        ],
      ),
    );
  }
}
