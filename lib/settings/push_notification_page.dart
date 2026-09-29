

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

import '../models.dart';
import '../theme/theme.dart';

       class PushNotificationPage extends StatefulWidget {
  const PushNotificationPage({super.key});

  @override
  State<PushNotificationPage> createState() => _PushNotificationPageState();
}
class _PushNotificationPageState extends State<PushNotificationPage> with WidgetsBindingObserver {
  final String _currentUid = Supabase.instance.client.auth.currentUser?.id ?? '';
  bool _isDevicePermissionGranted = false;
  bool? _pushEnabled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkCurrentDevicePermission();
    _loadPushPreference();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkCurrentDevicePermission();
    }
  }

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

          finalPushState = _pushEnabled ?? dbPushEnabled;

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

  bool finalPushState = false;

  Future<void> _loadPushPreference() async {
    try {
      final row = await Supabase.instance.client
          .from(kUsersCollection)
          .select('pushNotificationsEnabled')
          .eq('uid', _currentUid)
          .maybeSingle();
      if (mounted) setState(() => _pushEnabled = row?['pushNotificationsEnabled'] == true);
    } catch (_) {}
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
    final previous = _pushEnabled ?? false;
    if (mounted) setState(() => _pushEnabled = isEnabled);

    if (isEnabled) {
      if (!isDeviceGranted) {
        final accepted = await OneSignal.Notifications.requestPermission(true);
        
        if (!accepted && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Push is enabled in the app, but system/browser permission is still off.")),
          );
        }
      }

      await OneSignal.login(_currentUid);
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
    
    await _checkCurrentDevicePermission();
    await _loadPushPreference();
  }

  Future<void> updateSinglePreference(String fieldKey, bool value) async {
    await Supabase.instance.client.from(kUsersCollection).update({fieldKey: value}).eq('uid', _currentUid);
  }
}
