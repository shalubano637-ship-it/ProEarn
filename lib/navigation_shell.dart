
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:async';

import 'models.dart';
import 'service.dart';
import 'auth_screen.dart';

import 'social_feed.dart';
import 'user_profile_features.dart';
import 'theme/theme.dart';
import 'messaging/messages_list_page.dart';
import 'chests/chests_page.dart';
import 'chest_timer_service.dart';
import 'leaderboard_page.dart';
import 'bag_page.dart';
import 'rewards/signup_rewards_popup.dart';
import 'messaging/room_hub_page.dart';

    
 
    
           
          
class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;
  final Box settingsBox = Hive.box('app_settings');
  DateTime? lastNotificationViewedTime;
  StreamSubscription<List<Map<String, dynamic>>>? _banWatchSub;
  
  DateTime? _lastPressedTime;

  final List<Widget> _pages = const [
    ReelsPage(),
    LeaderboardPage(),
    MessagesListPage(),
    UploadPage(),
    RoomHubPage(embedded: true),
    BagPage(),
    SettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    _loadLastViewedTime(); // App start hote hi Hive se time read karein
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await SignupRewardsPopup.showIfEligible(context);
    });
    _watchForLiveBan(); // Admin panel se mid-session ban ho jaaye to turant sign out
  }

  void _watchForLiveBan() {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;

    _banWatchSub = Supabase.instance.client
        .from(kUsersCollection)
        .stream(primaryKey: ['uid'])
        .eq('uid', uid)
        .listen((rows) async {
      if (rows.isNotEmpty && rows.first['isBanned'] == true) {
        await _banWatchSub?.cancel();
        await Supabase.instance.client.auth.signOut();
        resetLocalUserState();
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginPage(bannedMessage: true)),
          (route) => false,
        );
      }
    });
  }

  void _loadLastViewedTime() {
    final savedTimeStr = settingsBox.get('last_notification_time');
    if (savedTimeStr != null) {
      setState(() {
        lastNotificationViewedTime = DateTime.parse(savedTimeStr);
      });
    }
  }

  void _saveLastViewedTime() {
    final now = DateTime.now();
    settingsBox.put('last_notification_time', now.toIso8601String()); // Hive write operation
    setState(() {
      lastNotificationViewedTime = now;
    });
  }

  @override
  void dispose() {
    _banWatchSub?.cancel();
    super.dispose();
  }

 
@override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentUser = Supabase.instance.client.auth.currentUser;

    return PopScope(
      canPop: false, // Disables standard automatic page pop/app termination routing
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        if (_selectedIndex != 0) {
          setState(() {
            _selectedIndex = 0;
          });
          return;
        }
        
        final now = DateTime.now();
        final backButtonHasNotBeenPressedRecently = 
            _lastPressedTime == null || now.difference(_lastPressedTime!) > const Duration(seconds: 3);

        if (backButtonHasNotBeenPressedRecently) {
          _lastPressedTime = now;

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Tap again to exit",
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              duration: Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).clearSnackBars();
          await SystemNavigator.pop(); // Standard clean platform exit line
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            "PRO EARN",
            style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
          leadingWidth: 120,
          leading: Row(
            children: [
              Semantics(
                label: "Open your profile",
                button: true,
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ProfilePage(isOwnProfile: true)),
                    );
                  },
                  child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: currentUser == null
                      ? const CircleAvatar(radius: 18, child: Icon(Icons.person_outline))
                      : StreamBuilder<List<Map<String, dynamic>>>(
                          stream: Supabase.instance.client
                              .from(kUsersCollection)
                              .stream(primaryKey: ['uid'])
                              .eq('uid', currentUser.id),
                          builder: (context, snapshot) {
                            String profileUrl = "";
                            if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                              var data = snapshot.data!.first;
                              profileUrl = data['profileUrl'] ?? "";
                            }
                            return CircleAvatar(
                              radius: 18,
                              backgroundColor: theme.colorScheme.surfaceContainerHighest,
                              child: ClipOval(
                                child: GlobalCachedImage(
                                  imageUrl: profileUrl,
                                  width: 36,
                                  height: 36,
                                  fit: BoxFit.cover,
                                  errorWidget: Icon(
                                    Icons.person_outline, 
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                              ),
                            ); // Khatam CircleAvatar
                          }, // Khatam builder function
                        ), // Khatam StreamBuilder
                ), // Khatam Padding
                ), // Khatam GestureDetector
              ), // Khatam Semantics
              if (currentUser != null) const _CoinBalanceIndicator(),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.search),            IconButton(
              icon: const Icon(Icons.card_giftcard_outlined),
              tooltip: "Rewards",
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ChestsPage()),
                );
              },
            ),

              tooltip: "Search",
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SearchPage()),
                );
              },
            ),
            currentUser == null
                ? IconButton(
                    icon: const Icon(Icons.notifications_none),
                    tooltip: "Notifications",
                    onPressed: () {},
                  )
                : StreamBuilder<List<Map<String, dynamic>>>(
                    stream: Supabase.instance.client
                        .from(kNotificationsCollection)
                        .stream(primaryKey: ['id'])
                        .eq('targetOwnerId', currentUser.id)
                        .order('timestamp', ascending: false),
                    builder: (context, snapshot) {
                      bool showRedDot = false;

                      if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                        if (lastNotificationViewedTime == null) {
                          showRedDot = true;
                        } else {
                          var firstDoc = snapshot.data!.first;
                          final rawTime = firstDoc['timestamp'];
                          
                          if (rawTime != null) {
                            DateTime latestNotificationDate = DateTime.parse(rawTime.toString());
                            if (latestNotificationDate.isAfter(lastNotificationViewedTime!)) {
                              showRedDot = true;
                            }
                          }
                        }
                      }
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.notifications_none),
                            tooltip: showRedDot ? "Notifications (new)" : "Notifications",
                            onPressed: () {
                              _saveLastViewedTime();
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const NotificationPage()),
                              );
                            },
                          ),
                          if (showRedDot)
                            Positioned(
                              right: 12,
                              top: 12,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: AppColors.error,
                                  shape: BoxShape.circle,
                                ),
                                constraints: const BoxConstraints(
                                  minWidth: 8,
                                  minHeight: 8,
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
          ],
        ),
        body: _pages[_selectedIndex],
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (index) {
            setState(() {
              _selectedIndex = index;
            });
          },
          type: BottomNavigationBarType.fixed,
          items: [
            const BottomNavigationBarItem(icon: Icon(Icons.video_library_outlined), label: "Reels"),
            const BottomNavigationBarItem(icon: Icon(Icons.leaderboard_outlined), label: "Rank"),
            const BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_outline), label: "Messages"),
            const BottomNavigationBarItem(icon: Icon(Icons.add_box_outlined), label: "Upload"),
            BottomNavigationBarItem(
              icon: const Icon(Icons.forum_outlined),
              label: "Rooms",
            ),
            const BottomNavigationBarItem(icon: Icon(Icons.shopping_bag_outlined), label: "Bag"),
            const BottomNavigationBarItem(icon: Icon(Icons.settings), label: "Settings"),
          ],
        ),
      ),
    );
  }
}

class _CoinBalanceIndicator extends StatefulWidget {
  const _CoinBalanceIndicator();

  @override
  State<_CoinBalanceIndicator> createState() => _CoinBalanceIndicatorState();
}

class _CoinBalanceIndicatorState extends State<_CoinBalanceIndicator> {
  late final String _uid;
  late final Stream<List<Map<String, dynamic>>> _userStream;

  @override
  void initState() {
    super.initState();
    _uid = Supabase.instance.client.auth.currentUser?.id ?? '';
    _userStream = Supabase.instance.client
        .from(kUsersCollection)
        .stream(primaryKey: ['uid'])
        .eq('uid', _uid);
  }

  @override
  Widget build(BuildContext context) {
    if (_uid.isEmpty) return const SizedBox.shrink();

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _userStream,
      builder: (context, userSnapshot) {
        final double mainCoins = (userSnapshot.data != null && userSnapshot.data!.isNotEmpty)
            ? ((userSnapshot.data!.first['mainCoins'] ?? 0) as num).toDouble()
            : 0.0;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("🪙", style: TextStyle(fontSize: 13)),
              const SizedBox(width: 3),
              Text(
                mainCoins.toStringAsFixed(2),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
            ],
          ),
        );
      },
    );
  }
}
