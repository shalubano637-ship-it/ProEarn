// =============================================================================
// PRO EARN — Social: FollowListPage (followers/following list)
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

// ---- Supabase ----
import 'package:supabase_flutter/supabase_flutter.dart';

// ---- Third-party packages ----
import 'package:cached_network_image/cached_network_image.dart';

// ---- App files (split out of the original single-file main.dart) ----
import '../service.dart';
import '../theme/theme.dart';
import '../profile/profile_page.dart';

         // ================= FIXED FOLLOW LIST PAGE (REAL-TIME FIRESTORE SYNC) =================
class FollowListPage extends StatelessWidget {
  final String title;
  final List<String> users; // Isme ab creators ki UIDs pass hongi

  const FollowListPage({super.key, required this.title, required this.users});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentAuthUser = Supabase.instance.client.auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: users.isEmpty
          ? Center(
              child: Text(
                "No $title yet.",
                style: const TextStyle(color: AppColors.textTertiary, fontSize: 15),
              ),
            )
          : ListView.builder(
              itemCount: users.length,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemBuilder: (context, index) {
                String targetUid = users[index];

                // Har ek ID ka real-time data Supabase se fetch karenge
                return FutureBuilder<Map<String, dynamic>?>(
                  future: Supabase.instance.client
                      .from('public_profiles')
                      .select()
                      .eq('uid', targetUid)
                      .maybeSingle(),
                  builder: (context, userSnapshot) {
                    if (!userSnapshot.hasData || userSnapshot.data == null) {
                      return const SizedBox.shrink(); // Agar user delete ho gaya ho to skip karein
                    }

                    var targetData = userSnapshot.data!;
                    String username = targetData['userName'] ?? "Unknown User";
                    String profileUrl = targetData['profileUrl'] ?? "";

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: theme.colorScheme.surfaceContainerHighest,
                        backgroundImage: profileUrl.isNotEmpty ? CachedNetworkImageProvider(profileUrl, cacheManager: CustomImageCacheManager.instance) : null,
                        child: profileUrl.isEmpty ? const Icon(Icons.person) : null,
                      ),
                      title: Text(
                        "@$username",
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () {
                        // FIX: Agar clicked ID meri hai toh isOwnProfile true hoga, warna false aur specific target open hoga
                        bool isMe = currentAuthUser != null && targetUid == currentAuthUser.id;
                        
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ProfilePage(
                              isOwnProfile: isMe,
                              otherUser: isMe ? null : targetUid,
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
    );
  }
}
