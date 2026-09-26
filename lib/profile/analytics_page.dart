// =============================================================================
// PRO EARN — Profile: AnalyticsPage (creator earnings analytics)
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
import 'dart:io';

// ---- Flutter framework ----
import 'package:flutter/material.dart';

// ---- Supabase ----
import 'package:supabase_flutter/supabase_flutter.dart';

// ---- App files (split out of the original single-file main.dart) ----
import '../models.dart';
import '../service.dart';
import '../theme/theme.dart';

  // ================= FIXED CUSTOM ANALYTICS PAGE =================
class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}
class _AnalyticsPageState extends State<AnalyticsPage> {
  String _selectedFilter = 'Newly Post'; // Default dropdown selection state

  @override
  Widget build(BuildContext context) {
    final currentUser = Supabase.instance.client.auth.currentUser;
    final theme = Theme.of(context);

    if (currentUser == null) {
      return const Scaffold(
        body: Center(child: Text("Please login first.")),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("My Analytics Tracker"),
        actions: [
          // Dropdown Filter menu choice selection configuration bar
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: DropdownButton<String>(
              value: _selectedFilter,
              dropdownColor: theme.colorScheme.surface,
              underline: const SizedBox(),
              icon: Icon(Icons.filter_list, color: theme.colorScheme.onSurface),
              items: <String>['Newly Post', 'Popular Post'].map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                );
              }).toList(),
              onChanged: (newValue) {
                if (newValue != null) {
                  setState(() {
                    _selectedFilter = newValue;
                  });
                }
              },
            ),
          ),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        // Direct Query: User ko sirf khud ke posts filter karke newly data live show karega
        stream: Supabase.instance.client
            .from(kPostsCollection)
            .stream(primaryKey: ['id'])
            .eq(kPostOwnerUidField, currentUser.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Text(
                "No active post is available in data analytics.",
                style: TextStyle(color: AppColors.textTertiary, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            );
          }

          // Fetch original rows array
          List<Map<String, dynamic>> myDocs = List.from(snapshot.data!);

          // Shorting logic handler routing core block matrix
          if (_selectedFilter == 'Newly Post') {
            // Default Sorting: Latest timestamp fields elements structural parsing
            myDocs.sort((a, b) {
              var tA = a['timestamp'] != null ? DateTime.parse(a['timestamp'].toString()) : null;
              var tB = b['timestamp'] != null ? DateTime.parse(b['timestamp'].toString()) : null;
              if (tA == null) return 1;
              if (tB == null) return -1;
              return tB.compareTo(tA); // Descending order element sort execution
            });
          } else if (_selectedFilter == 'Popular Post') {
            // Popular sorting node: Higher array list size logic length elements
            myDocs.sort((a, b) {
              List<dynamic> likesA = a['likedBy'] ?? [];
              List<dynamic> likesB = b['likedBy'] ?? [];
              return likesB.length.compareTo(likesA.length); // Dynamic popular element rank
            });
          }

          return ListView.builder(
            itemCount: myDocs.length,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            itemBuilder: (context, index) {
              final data = myDocs[index];
              final String postId = data['id'].toString();
              final String imageUrl = data['imageUrl'] ?? '';
              final String caption = data['caption'] ?? 'No Caption';
              
              List<dynamic> likesList = data['likedBy'] ?? [];
              int currentLikesCount = likesList.length;

              return Card(
                margin: const EdgeInsets.only(bottom: 15),
                shape: RoundedRectangleBorder(borderRadius: AppRadius.mdRadius),
                clipBehavior: Clip.antiAlias,
                elevation: 2,
                child: ListTile(
                  contentPadding: const EdgeInsets.all(10),
                  leading: Container(
                    width: 85,
                    height: 85,
                    decoration: BoxDecoration(
                      borderRadius: AppRadius.smRadius,
                      color: AppColors.surfaceElevated,
                    ),
                    child: ClipRRect(
                      borderRadius: AppRadius.smRadius,
                      child: imageUrl.startsWith('http')
                          ? GlobalCachedImage(imageUrl: imageUrl, fit: BoxFit.cover)
                          : Image.file(File(imageUrl), fit: BoxFit.cover),
                    ),
                  ),
                  title: Text(
                    caption,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Row(
                      children: [
                        Icon(Icons.favorite, size: 16, color: AppColors.error.withOpacity(0.8)),
                        const SizedBox(width: 4),
                        Text("$currentLikesCount Likes", style: const TextStyle(fontSize: 12)),
                        const SizedBox(width: 15),
                        const Icon(Icons.bar_chart, size: 16, color: AppColors.info),
                        const SizedBox(width: 4),
                        const Text("Metrics Live", style: TextStyle(fontSize: 12, color: AppColors.info)),
                      ],
                    ),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    _showDetailedAnalyticsBottomSheet(context, postId, data);
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  // Live score tracker detailed configuration node layer layout matrix logic panel block
  void _showDetailedAnalyticsBottomSheet(BuildContext context, String postId, Map<String, dynamic> postData) {
    final theme = Theme.of(context);
    final String imageUrl = postData['imageUrl'] ?? '';
    final String caption = postData['caption'] ?? 'No Caption';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: Supabase.instance.client.from(kPostsCollection).stream(primaryKey: ['id']).eq('id', postId),
          builder: (context, postSnapshot) {
            int liveLikes = 0;
            int liveShares = 0;
            int liveGets = 0; // <-- 1. Gets ke liye variable banaya

            if (postSnapshot.hasData && postSnapshot.data!.isNotEmpty) {
              var liveData = postSnapshot.data!.first;
              List<dynamic> likedBy = liveData['likedBy'] ?? [];
              liveLikes = likedBy.length;
              liveShares = liveData['sharesCount'] ?? 0;
              
              // <-- 2. Database se getsCount ya gets list length uthane ka logic
              if (liveData['getsCount'] != null) {
                liveGets = (liveData['getsCount'] as num).toInt();
              } else if (liveData['gets'] != null && liveData['gets'] is List) {
                liveGets = (liveData['gets'] as List).length;
              }
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).padding.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 45,
                      height: 5,
                      decoration: BoxDecoration(color: AppColors.textTertiary, borderRadius: AppRadius.smRadius),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text("Post Engagement Report", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          borderRadius: AppRadius.mdRadius,
                          border: Border.all(color: theme.colorScheme.primary.withOpacity(0.2)),
                        ),
                        child: ClipRRect(
                          borderRadius: AppRadius.mdRadius,
                          child: imageUrl.startsWith('http')
                              ? GlobalCachedImage(imageUrl: imageUrl, fit: BoxFit.cover)
                              : Image.file(File(imageUrl), fit: BoxFit.cover),
                        ),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Text(
                          caption,
                          style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 25),
                  const Text("Live Statistics Analytics:", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textTertiary)),
                  const SizedBox(height: 12),

                  // Grid Matrix/Row layout me card distribution
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildScoreAnalyticsCard(Icons.favorite, "Likes", "$liveLikes", AppColors.error),
                      
                      // Comments table stream node
                      StreamBuilder<List<Map<String, dynamic>>>(
                        stream: Supabase.instance.client.from(kCommentsCollection).stream(primaryKey: ['id']).eq('postId', postId),
                        builder: (context, commentSnapshot) {
                          int totalComments = commentSnapshot.hasData ? commentSnapshot.data!.length : 0;
                          return _buildScoreAnalyticsCard(Icons.comment, "Comments", "$totalComments", AppColors.info);
                        },
                      ),
                      
                      _buildScoreAnalyticsCard(Icons.share, "Shares", "$liveShares", AppColors.success),
                      
                      // <-- 3. Naya Gets Card yahan add kiya hai
                      _buildScoreAnalyticsCard(Icons.ads_click, "Gets", "$liveGets", AppColors.warning),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildScoreAnalyticsCard(IconData icon, String label, String counterValue, Color elementColor) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4), // 4 cards fit karne ke liye thoda margin adjust kiya
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: AppRadius.mdRadius,
        ),
        child: Column(
          children: [
            Icon(icon, color: elementColor, size: 24), // Size thodi kam ki taaki 4 cards comfortable aa sakein
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textTertiary, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(counterValue, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
