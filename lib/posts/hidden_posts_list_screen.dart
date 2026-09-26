// =============================================================================
// PRO EARN — Posts: HiddenPostsListScreen
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

// ---- Dart core ----
import 'package:universal_io/universal_io.dart';

// ---- Flutter framework ----
import 'package:flutter/material.dart';

// ---- Supabase ----
import 'package:supabase_flutter/supabase_flutter.dart';


// ---- App files (split out of the original single-file main.dart) ----
import '../models.dart';
import '../service.dart';
import '../theme/theme.dart';

  // ================= HIDDEN POSTS LIST SCREEN WITH UNHIDE FUNCTIONALITY =================
class HiddenPostsListScreen extends StatelessWidget {
  const HiddenPostsListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUser = Supabase.instance.client.auth.currentUser;
    final theme = Theme.of(context);

    if (currentUser == null) {
      return const Scaffold(body: Center(child: Text("Session expired.")));
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Hidden Posts")),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: Supabase.instance.client
            .from(kUsersCollection)
            .stream(primaryKey: ['uid'])
            .eq('uid', currentUser.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text("Data fetch failed."));
          }

          var userData = snapshot.data!.first;
          List<dynamic> hiddenPostIds = userData['hiddenPosts'] ?? [];

          if (hiddenPostIds.isEmpty) {
            return const Center(
              child: Text(
                "You haven't hidden any posts.",
                style: TextStyle(color: AppColors.textTertiary, fontSize: 14),
              ),
            );
          }

          return ListView.builder(
            itemCount: hiddenPostIds.length,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemBuilder: (context, index) {
              String postId = hiddenPostIds[index];

              return StreamBuilder<List<Map<String, dynamic>>>(
                stream: Supabase.instance.client
                    .from(kPostsCollection)
                    .stream(primaryKey: ['id'])
                    .eq('id', postId),
                builder: (context, postSnapshot) {
                  if (!postSnapshot.hasData || postSnapshot.data!.isEmpty) {
                    return const SizedBox.shrink(); // Agar post delete ho gayi ho
                  }

                  var postData = postSnapshot.data!.first;
                  String imageUrl = postData['imageUrl'] ?? '';
                  String caption = postData['caption'] ?? 'No Caption';

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    leading: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        borderRadius: AppRadius.smRadius,
                        color: theme.colorScheme.surfaceContainerHighest,
                      ),
                      child: ClipRRect(
                        borderRadius: AppRadius.smRadius,
                        child: imageUrl.startsWith('http')
                            ? GlobalCachedImage(
                                imageUrl: imageUrl,
                                fit: BoxFit.cover,
                                width: 50,
                                height: 50,
                              )
                            : Image.file(File(imageUrl), fit: BoxFit.cover),
                      ),
                    ),
                    title: Text(
                      caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                    ),
                    trailing: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: theme.colorScheme.primary),
                        shape: RoundedRectangleBorder(borderRadius: AppRadius.xlRadius),
                      ),
                      icon: const Icon(Icons.visibility, size: 16),
                      label: const Text("Unhide", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      onPressed: () async {
                        // User row se hiddenPosts field me se Post ID remove karein
                        await Supabase.instance.client.rpc('unhide_post', params: {
                          'p_user_id': currentUser.id,
                          'p_post_id': postId,
                        });

                        
                      },
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
