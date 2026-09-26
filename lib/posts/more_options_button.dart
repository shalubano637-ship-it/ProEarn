// =============================================================================
// PRO EARN — Posts: MoreOptionsButton
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



class MoreOptionsButton extends StatelessWidget {
  final String targetPostId;
  final String targetOwnerId; // Jis user ki post hai uski UID

  const MoreOptionsButton({
    super.key,
    required this.targetPostId,
    required this.targetOwnerId,
  });

  void _openModerationSheet(BuildContext context) {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) return;

    // Safety Check: Khud ko report, block ya hide karne se rokein
    if (currentUser.id == targetOwnerId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You cannot moderate your own posts.")),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        // State variables setup inside modal popup area
        bool isReportOn = false;
        bool isBlockOn = false;
        bool isHidePostOn = false; // State variable for single post hiding
        String? selectedReason;
        
        final List<String> reportReasons = [
          "Spam or Misleading",
          "Hate Speech or Violence",
          "Harassment or Bullying",
          "Nudity or Sexual Content",
          "Intellectual Property Violation"
        ];

        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;
            final systemPadding = MediaQuery.of(context).padding.bottom;
            
            // Validation indicator: Teeno me se koi bhi EK feature active ho toh button chalna chahiye
            final bool isAnyActionSelected = isReportOn || isBlockOn || isHidePostOn;

            return Padding(
              padding: EdgeInsets.only(
                top: 16,
                left: 20,
                right: 20,
                bottom: bottomInset > 0 ? bottomInset + 24 : systemPadding + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Pop-up main layout handle indicator
                  Center(
                    child: Container(
                      width: 40,
                      height: 5,
                      decoration: BoxDecoration(
                        color: AppColors.textTertiary,
                        borderRadius: AppRadius.smRadius,
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),
                  const Text(
                    "Content Moderation Options",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Text(
                    "please select rules first.",
                    style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
                  ),
                  const SizedBox(height: 20),

                  // 1. REPORT TOGGLE CONTAINER
                  SwitchListTile(
                    title: const Text("Report Content", style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text("Submit a review policy report for this post."),
                    value: isReportOn,
                    activeColor: AppColors.error,
                    onChanged: (bool val) {
                      setModalState(() {
                        isReportOn = val;
                        if (isReportOn) {
                          // Rule: Report karne par safety ke liye Block automatic system activate
                          isBlockOn = true;
                        }
                      });
                    },
                  ),

                  // Dynamic expanding Dropdown for Report Reasons
                  if (isReportOn)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: DropdownButtonFormField<String>(
                        value: selectedReason,
                        hint: const Text("Please select the reason for the report."),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                          border: OutlineInputBorder(borderRadius: AppRadius.smRadius, borderSide: BorderSide.none),
                        ),
                        items: reportReasons.map((String reason) {
                          return DropdownMenuItem<String>(
                            value: reason,
                            child: Text(reason, style: const TextStyle(fontSize: 14)),
                          );
                        }).toList(),
                        onChanged: (String? newReason) {
                          setModalState(() {
                            selectedReason = newReason;
                          });
                        },
                      ),
                    ),

                  const Divider(height: 10),

                  // 2. BLOCK TOGGLE CONTAINER (Poore user ko block karne ke liye)
                  SwitchListTile(
                    title: const Text("Block User", style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text("Remove all posts from this creator."),
                    value: isBlockOn,
                    activeColor: AppColors.warning,
                    onChanged: (bool val) {
                      if (isReportOn && !val) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("The 'Block Mandatory' segment is a compulsory part of the report.")),
                        );
                        return;
                      }
                      setModalState(() {
                        isBlockOn = val;
                      });
                    },
                  ),

                  const Divider(height: 10),

                  // 3. HIDE THIS POST ONLY TOGGLE (Independent Single Post Action)
                  SwitchListTile(
                    title: const Text("Hide This Post", style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text("Hide this post"),
                    value: isHidePostOn,
                    activeColor: AppColors.info,
                    onChanged: (bool val) {
                      setModalState(() {
                        isHidePostOn = val;
                      });
                    },
                  ),

                  const SizedBox(height: 25),

                  // CONFIRM ACTION EXECUTION BUTTON
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        // FIX: Agar teeno me se kuch bhi active hai, toh Red/Active color dikhega, warna Grey
                        backgroundColor: isAnyActionSelected ? AppColors.error : AppColors.textTertiary,
                        foregroundColor: AppColors.textPrimary,
                        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdRadius),
                      ),
                      // FIX: Kisi ek switch ke on hote hi onPressed callback function mill jayega (un-null ho jayega)
                      onPressed: !isAnyActionSelected ? null : () async {
                        // Validation logic for report reason
                        if (isReportOn && selectedReason == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Please select a reason!")),
                          );
                          return;
                        }

                        Navigator.pop(context); // Bottom sheet close flow
                        
                        final client = Supabase.instance.client;

                        // Action 1: Report submission logic
                        if (isReportOn) {
                          await client.from(kReportsCollection).insert({
                            'reportedBy': currentUser.id,
                            'reportedUserId': targetOwnerId,
                            'targetPostId': targetPostId,
                            'reason': selectedReason,
                            'source': 'post',
                          });
                        }

                        // Action 2 & 3: Block user / Hide post (atomic RPC — see supabase_schema.sql)
                        if (isBlockOn || isHidePostOn) {
                          await client.rpc('block_user_and_hide_post', params: {
                            'p_blocker_id': currentUser.id,
                            'p_target_owner_id': isBlockOn ? targetOwnerId : '',
                            'p_target_post_id': isHidePostOn ? targetPostId : '',
                          });
                        }

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Action success!")),
                          );
                        }
                      },
                      child: const Text("CONFIRM MODERATION", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.more_vert, color: AppColors.textPrimary, size: 28),
      tooltip: "More options",
      onPressed: () => _openModerationSheet(context),
    );
  }
}
