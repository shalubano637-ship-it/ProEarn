// =============================================================================
// PRO EARN — Notifications: NotificationPage
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
import 'package:google_mobile_ads/google_mobile_ads.dart';

// ---- App files (split out of the original single-file main.dart) ----
import '../models.dart';
import '../service.dart';
import '../ad_unit_ids.dart';
import '../utils.dart';
import '../navigation_shell.dart';
import '../theme/theme.dart';
import '../profile/profile_page.dart';
import '../widgets/error_retry_view.dart';

 // ================= SAFE & ISOLATED NOTIFICATION PAGE (CRASH PROOF + ADMOB BANNER) =================
class NotificationPage extends StatefulWidget {
  const NotificationPage({super.key});

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}
class _NotificationPageState extends State<NotificationPage> with WidgetsBindingObserver {
  BannerAd? _bannerAd;
  bool _isAdLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadBannerAd();
    Supabase.instance.client.rpc('set_presence', params: {'p_screen': 'notifications'})
        .catchError((e) => debugPrint('set_presence failed: $e'));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      Supabase.instance.client.rpc('set_presence', params: {'p_screen': 'other'})
          .catchError((e) => debugPrint('set_presence failed: $e'));
    } else if (state == AppLifecycleState.resumed) {
      Supabase.instance.client.rpc('set_presence', params: {'p_screen': 'notifications'})
          .catchError((e) => debugPrint('set_presence failed: $e'));
    }
  }

  // AdMob Banner Ad Load karne ka function
  void _loadBannerAd() {
    _bannerAd = BannerAd(
      adUnitId: AdUnitIds.banner,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          setState(() {
            _isAdLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('BannerAd failed to load: $error');
          ad.dispose();
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bannerAd?.dispose();
    Supabase.instance.client.rpc('set_presence', params: {'p_screen': 'other'})
        .catchError((e) => debugPrint('set_presence failed: $e'));
    super.dispose();
  }

  // Helper method: Date ko group name me convert karne ke liye
  String _getGroupLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final aDate = DateTime(date.year, date.month, date.day);

    if (aDate == today) {
      return "Today";
    } else if (aDate == yesterday) {
      return "Yesterday";
    } else {
      return "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}";
    }
  }

  // Helper method: Formatted Time nikalne ke liye
  String _formatTime(DateTime date) => formatClockTime(date);

  @override
  Widget build(BuildContext context) {
    final currentUser = Supabase.instance.client.auth.currentUser;
    final theme = Theme.of(context);

    if (currentUser == null) {
      return const Scaffold(
        body: Center(child: Text("Please login to view notifications.")),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Notifications", style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          // ================= NEW: ADMOB BANNER AD AT THE TOP =================
          if (_isAdLoaded && _bannerAd != null)
            Container(
              alignment: Alignment.center,
              width: _bannerAd!.size.width.toDouble(),
              height: _bannerAd!.size.height.toDouble(),
              child: AdWidget(ad: _bannerAd!),
            ),

          // ================= AREA 2: NORMAL NOTIFICATIONS LIST =================
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: Supabase.instance.client
                  .from(kNotificationsCollection)
                  .stream(primaryKey: ['id'])
                  .eq('targetOwnerId', currentUser.id)
                  .order('timestamp', ascending: false),
              builder: (context, notificationSnapshot) {
                if (notificationSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (notificationSnapshot.hasError) {
                  return ErrorRetryView(
                    error: notificationSnapshot.error,
                    onRetry: () => setState(() {}),
                  );
                }

                final notificationDocs = notificationSnapshot.data ?? [];

                if (notificationDocs.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.notifications_none, size: 60, color: AppColors.textTertiary),
                        SizedBox(height: 10),
                        Text("No notifications yet.", style: TextStyle(color: AppColors.textTertiary)),
                      ],
                    ),
                  );
                }

                // Normal notifications grouping logic
                final Map<String, List<Map<String, dynamic>>> groupedNotifications = {};
                for (var data in notificationDocs) {
                  try {
                    final timestamp = data['timestamp'];
                    if (timestamp == null) continue; // Skip docs without valid timestamp

                    final DateTime date = DateTime.parse(timestamp.toString());
                    final String label = _getGroupLabel(date);

                    if (groupedNotifications[label] == null) {
                      groupedNotifications[label] = [];
                    }
                    groupedNotifications[label]!.add(data);
                  } catch (e) {
                    // Malformed/unparseable timestamp on one notification
                    // row shouldn't take down the whole list — just skip
                    // that row, but log it so a bad row doesn't go
                    // completely unnoticed.
                    debugPrint("Notification grouping: skipped a row with a bad timestamp: $e");
                  }
                }

                return ListView(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  children: groupedNotifications.entries.map((entry) {
                    final String dateHeader = entry.key;
                    final List<Map<String, dynamic>> docsInGroup = entry.value;

                    // 1. Agar group me koi doc nahi hai, to pure header ko skip karein
                    if (docsInGroup.isEmpty) {
                      return const SizedBox.shrink();
                    }

                    // 2. Filter out valid items
                    final validWidgets = docsInGroup.map<Widget?>((data) {
                      try {
                        final String type = data['type'] ?? '';
                        final String targetPostId = data['targetPostId'] ?? '';
                        final String senderId = data['senderId'] ?? '';
                        final String notificationCommentId = data['commentId'] ?? data['id'].toString();

                        final timestamp = data['timestamp'];
                        final String timeText = timestamp != null ? _formatTime(DateTime.parse(timestamp.toString())) : '';

                        String rawMessage = data['message'] ?? '';
                        if (rawMessage.trim().isEmpty) {
                          if (type == 'like') rawMessage = 'liked your post.';
                          if (type == 'comment') rawMessage = 'commented on your post.';
                          if (type == 'follow') rawMessage = 'started following you.';
                        }

                        IconData leadingIcon = Icons.notifications;
                        if (type == 'like') leadingIcon = Icons.favorite;
                        if (type == 'comment') leadingIcon = Icons.comment;
                        if (type == 'follow') leadingIcon = Icons.person_add;

                        final String dbSenderName = data['senderName'] ?? 'Someone';
                        final String dbSenderProfile = data['senderProfileUrl'] ?? '';

                        return FutureBuilder<Map<String, dynamic>?>(
                          future: Supabase.instance.client
                              .from('public_profiles')
                              .select()
                              .eq('uid', senderId)
                              .maybeSingle(),
                          builder: (context, senderSnapshot) {
                            String realTimeProfileUrl = dbSenderProfile;
                            String realTimeName = dbSenderName;

                            if (senderSnapshot.hasData && senderSnapshot.data != null) {
                              final senderData = senderSnapshot.data!;
                              realTimeProfileUrl = senderData['profileUrl'] ?? dbSenderProfile;
                              realTimeName = senderData['userName'] ?? dbSenderName;
                            }

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 1),
                              leading: CircleAvatar(
                                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                                child: ClipOval(
                                  child: GlobalCachedImage(
                                    imageUrl: realTimeProfileUrl,
                                    width: 40,
                                    height: 40,
                                    errorWidget: Icon(leadingIcon, color: theme.colorScheme.primary),
                                  ),
                                ),
                              ),
                              title: RichText(
                                text: TextSpan(
                                  style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 14),
                                  children: [
                                    TextSpan(text: realTimeName, style: const TextStyle(fontWeight: FontWeight.bold)),
                                    TextSpan(text: ' $rawMessage'),
                                  ],
                                ),
                              ),
                              subtitle: Text(
                                timeText,
                                style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant.withOpacity(0.6)),
                              ),
                              onTap: () {
                                if (type == 'comment' && targetPostId.trim().isNotEmpty) {
                                  ReelsAutoTrigger.targetPostId = targetPostId.trim();
                                  ReelsAutoTrigger.highlightCommentId = notificationCommentId;
                                  Navigator.pushAndRemoveUntil(
                                    context,
                                    MaterialPageRoute(builder: (_) => const MainNavigationScreen()),
                                    (route) => false,
                                  );
                                } else if ((type == 'follow' || type == 'like') && senderId.isNotEmpty) {
                                  bool isMe = senderId == currentUser.id;
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ProfilePage(isOwnProfile: isMe, otherUser: isMe ? null : senderId),
                                    ),
                                  );
                                }
                              },
                            );
                          },
                        );
                      } catch (_) {
                        return null;
                      }
                    }).whereType<Widget>().toList();

                    // Agar sare documents invalid nikle to empty widget return karein
                    if (validWidgets.isEmpty) {
                      return const SizedBox.shrink();
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 16.0, top: 14.0, bottom: 6.0),
                          child: Text(
                            dateHeader,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                              fontSize: 13,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        ...validWidgets,
                      ],
                    );
                  }).toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
