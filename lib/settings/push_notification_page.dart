// =============================================================================
// PRO EARN — Settings: PushNotificationPage
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
import 'dart:async';

// ---- Flutter framework ----
import 'package:flutter/material.dart';

// ---- Supabase ----
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';


// ---- App files (split out of the original single-file main.dart) ----
import '../models.dart';
import '../theme/theme.dart';

       class PushNotificationPage extends StatefulWidget {
  const PushNotificationPage({super.key});

  @override
  State<PushNotificationPage> createState() => _PushNotificationPageState();
}
// 1. WidgetsBindingObserver mixin add kiya lifecycle events listen karne ke liye
class _PushNotificationPageState extends State<PushNotificationPage> with WidgetsBindingObserver {
  final String _currentUid = Supabase.instance.client.auth.currentUser?.id ?? '';
  bool _isDevicePermissionGranted = false;

  @override
  void initState() {
    super.initState();
    // Observer ko register kiya
    WidgetsBinding.instance.addObserver(this);
    _checkCurrentDevicePermission();
  }

  @override
  void dispose() {
    // Observer ko remove kiya memory leaks se bachne ke liye
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // 2. Jab bhi app background se foreground (wapas screen par) aayegi, ye function chalega
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkCurrentDevicePermission();
    }
  }

  // Device level system permission check karne ka function
  Future<void> _checkCurrentDevicePermission() async {
    final granted = OneSignal.Notifications.permission;
    if (mounted) {
      setState(() {
        _isDevicePermissionGranted = granted;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUid.isEmpty) {
      return const Scaffold(
        body: Center(child: Text("Please login")),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: const Icon(Icons.notifications),
        title: const Text("Notification Settings"),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: Supabase.instance.client.from(kUsersCollection).stream(primaryKey: ['uid']).eq('uid', _currentUid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          bool dbPushEnabled = false;
          bool likes = true;
          bool comments = true;
          bool gets = true;
          bool follow = true;
          bool messages = true;

          if (snapshot.hasData && snapshot.data!.isNotEmpty) {
            var userData = snapshot.data!.first;
            dbPushEnabled = userData['pushNotificationsEnabled'] ?? false;
            likes = userData['notifyLikes'] ?? true;
            comments = userData['notifyComments'] ?? true;
            gets = userData['notifyGets'] ?? true;
            follow = userData['notifyFollow'] ?? true;
            messages = userData['notifyMessages'] ?? true;
          }

          // Ab FutureBuilder ki zaroorat nahi hai, real-time lifecycle variable use hoga
          bool finalPushState = dbPushEnabled && _isDevicePermissionGranted;

          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 10),
            children: [
              buildSwitch(
                "Push Notifications", 
                Icons.notifications_active,
                finalPushState, 
                (v) async => await togglePushNotificationStatus(v, _isDevicePermissionGranted),
              ),
              const Divider(),
              if (finalPushState) ...[
                buildSwitch(
                  "Likes", 
                  Icons.favorite,
                  likes, 
                  (v) async => await updateSinglePreference('notifyLikes', v),
                ),
                buildSwitch(
                  "Comments", 
                  Icons.comment,
                  comments, 
                  (v) async => await updateSinglePreference('notifyComments', v),
                ),
               
                buildSwitch(
                  "Follow", 
                  Icons.person_add,
                  follow, 
                  (v) async => await updateSinglePreference('notifyFollow', v),
                ),
                buildSwitch(
                  "Messages",
                  Icons.chat_bubble_outline,
                  messages,
                  (v) async => await updateSinglePreference('notifyMessages', v),
                ),
              ]
            ],
          );
        },
      ),
    );
  }

  Widget buildSwitch(String title, IconData icon, bool value, Function(bool) onChanged) {
    return SwitchListTile(
      secondary: Icon(icon, color: AppColors.info),
      value: value,
      title: Text(title),
      onChanged: onChanged,
    );
  }

  Future<void> togglePushNotificationStatus(bool isEnabled, bool isDeviceGranted) async {
    final client = Supabase.instance.client;

    if (isEnabled) {
      if (!isDeviceGranted) {
        final accepted = await OneSignal.Notifications.requestPermission(true);
        
        // Agar user ne system settings se block kiya hua hai, toh use refresh karke check karenge
        if (!accepted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Please Check your system notification settings!")),
            );
          }
          return;
        }
      }

      OneSignal.login(_currentUid);
      await client.from(kUsersCollection).update({
        'pushNotificationsEnabled': true,
        'notifyLikes': true,
        'notifyComments': true,
        'notifyGets': true,
        'notifyFollow': true,
        'notifyMessages': true,
      }).eq('uid', _currentUid);
    } else {
      await OneSignal.logout();
      await client.from(kUsersCollection).update({
        'pushNotificationsEnabled': false,
      }).eq('uid', _currentUid);
    }
    
    // Status update karne ke baad state refresh karein
    await _checkCurrentDevicePermission();
  }

  Future<void> updateSinglePreference(String fieldKey, bool value) async {
    await Supabase.instance.client.from(kUsersCollection).update({fieldKey: value}).eq('uid', _currentUid);
  }
}
