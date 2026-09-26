// =============================================================================
// PRO EARN — Settings: SettingsPage (menu)
// -----------------------------------------------------------------------------
// Extracted from the original user_profile_features.dart during the
// feature-based file split (no UI or logic changes — only where this code
// physically lives). user_profile_features.dart is now a barrel file that
// re-exports this file.
// =============================================================================

// =============================================================================
// PRO EARN — AI-generated content social platform
// -----------------------------------------------------------------------------
// This file (user_profile_features.dart) is one of three files this app's
// UI/logic was split into (equal three-way split of the original
// single-file main.dart, no UI or logic changes — only where each class
// physically lives):
//   1. main.dart
//   2. social_feed.dart
//   3. user_profile_features.dart  (this file)
//
// user_profile_features.dart contains everything about the user's own
// account, profile, and account-management screens:
//   - Profile & social graph: ProfilePage, FollowListPage,
//     BlockedUsersListScreen, EditProfilePage, ImageCropPage
//   - Notifications: NotificationPage, PushNotificationPage
//   - Settings & Security: SettingsPage, SecurityPage, HelpPage
//   - Analytics: AnalyticsPage
//
// Persistence: Supabase (Postgres) is the source of truth for all
// user/post/social data.
// =============================================================================


// ---- Flutter framework ----
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---- App files (split out of the original single-file main.dart) ----
import 'push_notification_page.dart';
import 'security_page.dart';
import 'help_page.dart';
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
    // Admin Panel entry only renders for kAdminEmail — this is just a UI
    // convenience, though; real enforcement is the server-side RLS in
    // supabase/migrations/2026_admin_reports_panel.sql.
    final currentEmail = Supabase.instance.client.auth.currentUser?.email?.toLowerCase().trim();
    final isAdmin = currentEmail == kAdminEmail.toLowerCase();

    return Scaffold(
      body: ListView(
        children: [
          buildTile(context: context, icon: Icons.person_outline, title: "Push Notification", page: const PushNotificationPage()),
          buildTile(context: context, icon: Icons.security, title: "Security", page: const SecurityPage()),
          buildTile(context: context, icon: Icons.help_outline, title: "Help", page: const HelpPage()),
          if (isAdmin)
            buildTile(context: context, icon: Icons.shield_outlined, title: "Admin Panel", page: const AdminReportsPage()),
        ],
      ),
    );
  }
}
