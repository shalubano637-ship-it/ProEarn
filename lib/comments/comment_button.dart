// =============================================================================
// PRO EARN — Comments: CommentButton
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
import '../theme/theme.dart';


import 'comment_screen.dart';

// ================= FIXED COMMENT BUTTON ENGINE =================
class CommentButton extends StatelessWidget {
  final String postId;
  const CommentButton({super.key, required this.postId});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        IconButton(
          icon: const Icon(Icons.mode_comment_outlined, color: AppColors.textPrimary, size: 30),
          tooltip: "Comments",
          onPressed: () {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              backgroundColor: AppColors.background, // Reel card look context color
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              builder: (context) => FractionallySizedBox(
                heightFactor: 0.85,
                child: CommentScreen(postId: postId),
              ),
            );
          },
        ),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: Supabase.instance.client
              .from(kCommentsCollection)
              .stream(primaryKey: ['id'])
              .eq('postId', postId),
          builder: (context, snapshot) {
            int count = snapshot.hasData ? snapshot.data!.length : 0;
            return Text(
              "$count",
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
            );
          },
        ),
      ],
    );
  }
}
