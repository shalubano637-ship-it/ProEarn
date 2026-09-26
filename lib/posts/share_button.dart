// =============================================================================
// PRO EARN — Posts: ShareButton
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

// ---- Dart core ----
import 'dart:async';

// ---- Flutter framework ----
import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ---- Supabase ----
import 'package:supabase_flutter/supabase_flutter.dart';


// ---- App files (split out of the original single-file main.dart) ----
import '../models.dart';
import '../theme/theme.dart';



// ================= SHARE BUTTON =================
class ShareButton extends StatelessWidget {
  final String postId;
  final String postLink;

  const ShareButton({
    super.key, 
    required this.postId, 
    required this.postLink
  });

  // Database increment operation ko common function banaya
  Future<void> _incrementShareCount() async {
    await Supabase.instance.client.rpc('increment_share_count', params: {
      'p_post_id': postId,
    });
  }

  // 1. External Apps ke liye Primary Share Handler
  Future<void> _handleAppShare(BuildContext context) async {
    try {
      final ShareResult result = await Share.share(
        'Check out this amazing AI Generation on PRO EARN!\nPost Link: $postLink',
        subject: 'PRO EARN',
      );

      // Agar kisi app (WhatsApp, Insta) par bheja gaya
      if (result.status == ShareResultStatus.success) {
        await _incrementShareCount();
      }
    } catch (e) {
      debugPrint("Error in app sharing: $e");
    }
  }

  // 2. Clipboard Copy ke liye Direct Fallback Handler (💯% Reliable for Copy)
  Future<void> _handleDirectCopy(BuildContext context) async {
    try {
      await Clipboard.setData(ClipboardData(text: postLink));
      
      // Clipboard par copy hote hi counter 100% badhega
      await _incrementShareCount();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Link copied to clipboard & Share counted!"),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint("Error in clipboard copy: $e");
    }
  }

  // 3. User ko options dikhane ke liye Bottom Sheet (Jaise bade apps me hota hai)
  void _showShareOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.copy, color: AppColors.textPrimary),
                title: const Text('Copy Link', style: TextStyle(color: AppColors.textPrimary)),
                onTap: () {
                  Navigator.pop(context);
                  _handleDirectCopy(context); // Direct copy trigger
                },
              ),
              ListTile(
                leading: const Icon(Icons.apps, color: AppColors.textPrimary),
                title: const Text('Share to Other Apps', style: TextStyle(color: AppColors.textPrimary)),
                onTap: () {
                  Navigator.pop(context);
                  _handleAppShare(context); // Native Share sheet trigger
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client.from(kPostsCollection).stream(primaryKey: ['id']).eq('id', postId),
      builder: (context, snapshot) {
        int dynamicSharesCount = 0;

        if (snapshot.hasData && snapshot.data!.isNotEmpty) {
          var postData = snapshot.data!.first;
          dynamicSharesCount = (postData['sharesCount'] ?? 0) as int;
        }

        return Semantics(
          label: "Share, $dynamicSharesCount shares",
          button: true,
          child: GestureDetector(
          onTap: () => _showShareOptions(context), // Click par bottom sheet khulegi
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.share,
                size: 32,
                color: AppColors.textPrimary,
              ),
              const SizedBox(height: 4),
              Text(
                dynamicSharesCount.toString(),
                style: const TextStyle(
                  color: AppColors.textPrimary, 
                  fontSize: 12,
                  fontWeight: FontWeight.w500
                ),
              ),
            ],
          ),
          ),
        );
      },
    );
  }
}
