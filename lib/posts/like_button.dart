// =============================================================================
// PRO EARN — Posts: LikeButton
// -----------------------------------------------------------------------------
// Extracted from the original social_feed.dart during the feature-based
// file split (no UI or logic changes — only where this code physically
// lives). social_feed.dart is now a barrel file that re-exports this file.
// =============================================================================

// =============================================================================
// PRO EARN — AI-generated content social platform
// -----------------------------------------------------------------------------
// This file (social_feed.dart) is one of three files this app's UI/logic
// was split into (equal three-way split of the original single-file
// main.dart, no UI or logic changes — only where each class physically
// lives):
//   1. main.dart
//   2. social_feed.dart            (this file)
//   3. user_profile_features.dart
//
// social_feed.dart contains everything about browsing, creating, and
// interacting with posts/reels:
//   - Feed & Reels: ReelsPage, SearchPage, SingleReelScreen
//   - Upload & Media: UploadPage, GlobalImageAdjuster
//   - Post interactions: LikeButton, CommentButton, CommentScreen,
//     ShareButton, MoreOptionsButton, GetPromptButton (creator earnings)
//
// Persistence: Supabase (Postgres) is the source of truth for all
// user/post/social data.
// =============================================================================


// ---- Flutter framework ----
import 'package:flutter/material.dart';

// ---- Supabase ----
import 'package:supabase_flutter/supabase_flutter.dart';


// ---- App files (split out of the original single-file main.dart) ----
import '../models.dart';
import '../service.dart';
import '../theme/theme.dart';



       class LikeButton extends StatelessWidget {
  final String postId;
  const LikeButton({super.key, required this.postId});

  void toggleLikeOperation(bool currentlyLiked, String currentUserId) async {
    final client = Supabase.instance.client;

    if (currentlyLiked) {
      // 1. Agar pehle se liked hai toh array se remove karo (UNLIKE)
      await client.rpc('toggle_post_like', params: {
        'p_post_id': postId,
        'p_user_id': currentUserId,
        'p_like': false,
      });
    } else {
      // 2. Agar liked nahi hai toh array me add karo (LIKE)
      await client.rpc('toggle_post_like', params: {
        'p_post_id': postId,
        'p_user_id': currentUserId,
        'p_like': true,
      });

      // ✅ FIX: Notification sirf Like karne par hi jayegi
      var postSnapshot = await client.from(kPostsCollection).select().eq('id', postId).maybeSingle();
      if (postSnapshot != null) {
        String targetOwner = postSnapshot[kPostOwnerUidField] ?? '';

        // Apni khud ki post ko like karne par notification na jaye uske liye check
        if (targetOwner.isNotEmpty && targetOwner != currentUserId) {
          sendNotification(
            targetOwnerId: targetOwner,
            type: 'like',
            message: 'liked your post.',
            targetPostId: postId,
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return const SizedBox.shrink();

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client.from(kPostsCollection).stream(primaryKey: ['id']).eq('id', postId),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Column(
            children: [
              Icon(Icons.favorite_border, size: 32, color: AppColors.textPrimary),
              SizedBox(height: 4),
              Text("0", style: TextStyle(color: AppColors.textPrimary, fontSize: 12)),
            ],
          );
        }

        var postData = snapshot.data!.first;
        List<dynamic> likedByList = postData['likedBy'] ?? [];
        
        int totalLikesCount = likedByList.length;
        bool isCurrentUserLiked = likedByList.contains(user.id);

        return Semantics(
          label: isCurrentUserLiked ? "Unlike, $totalLikesCount likes" : "Like, $totalLikesCount likes",
          button: true,
          toggled: isCurrentUserLiked,
          child: GestureDetector(
          onTap: () => toggleLikeOperation(isCurrentUserLiked, user.id),
          child: Column(
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return ScaleTransition(scale: animation, child: child);
                },
                child: Icon(
                  Icons.favorite,
                  key: ValueKey<bool>(isCurrentUserLiked),
                  size: 32,
                  color: isCurrentUserLiked ? AppColors.error : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                totalLikesCount.toString(),
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
              ),
            ],
          ),
          ),
        );
      },
    );
  }
}
