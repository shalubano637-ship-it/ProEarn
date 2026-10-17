

import 'package:flutter/material.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../models.dart';
import '../service.dart';
import '../ad_unit_ids.dart';
import '../utils.dart';
import '../navigation_shell.dart';
import '../theme/theme.dart';
import '../profile/profile_page.dart';
import '../widgets/error_retry_view.dart';

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
          if (_isAdLoaded && _bannerAd != null)
            Container(
              alignment: Alignment.center,
              width: _bannerAd!.size.width.toDouble(),
              height: _bannerAd!.size.height.toDouble(),
              child: AdWidget(ad: _bannerAd!),
            ),

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
                    debugPrint("Notification grouping: skipped a row with a bad timestamp: $e");
                  }
                }

                return ListView(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  children: groupedNotifications.entries.map((entry) {
                    final String dateHeader = entry.key;
                    final List<Map<String, dynamic>> docsInGroup = entry.value;

                    if (docsInGroup.isEmpty) {
                      return const SizedBox.shrink();
                    }

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
                          if (type == 'chest_ready') rawMessage = 'Your chest is ready to open! 🎁';
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
