import 'package:proearn/firebase_user_compat.dart';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';
import '../service.dart';
import '../theme/theme.dart';

class BlockedUsersListScreen extends StatefulWidget {
  const BlockedUsersListScreen({super.key});

  @override
  State<BlockedUsersListScreen> createState() => _BlockedUsersListScreenState();
}

class _BlockedUsersListScreenState extends State<BlockedUsersListScreen> {
  Stream<List<Map<String, dynamic>>>? _userStream;
  String _loadedIdsKey = '';
  Future<List<Map<String, dynamic>>>? _profilesFuture;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _userStream = Supabase.instance.client
          .from(kUsersCollection)
          .stream(primaryKey: ['uid'])
          .eq('uid', uid);
    }
  }

  Future<List<Map<String, dynamic>>> _loadProfiles(List<String> uids) async {
    if (uids.isEmpty) return [];
    final rows = await Supabase.instance.client
        .from('public_profiles')
        .select('uid,userName,profileUrl')
        .inFilter('uid', uids);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> _unblock(String uid) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
    try {
      await Supabase.instance.client.rpc('unblock_user', params: {
        'p_user_id': currentUser.uid,
        'p_blocked_id': uid,
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't unblock this user. Please try again."),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final theme = Theme.of(context);

    if (currentUser == null || _userStream == null) {
      return const Scaffold(body: Center(child: Text("Session expired.")));
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Blocked Users")),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _userStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text("Couldn't load blocked users. Check your connection and try again."));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text("You haven't blocked anyone."));
          }

          final rawIds = (snapshot.data!.first['blockedUsers'] as List?) ?? [];
          final blockedUids = rawIds.map((value) => value.toString()).toSet().toList();
          if (blockedUids.isEmpty) {
            return const Center(
              child: Text(
                "You haven't blocked anyone.",
                style: TextStyle(color: AppColors.textTertiary, fontSize: 14),
              ),
            );
          }

          final idsKey = blockedUids.join('|');
          if (idsKey != _loadedIdsKey) {
            _loadedIdsKey = idsKey;
            _profilesFuture = _loadProfiles(blockedUids);
          }

          return FutureBuilder<List<Map<String, dynamic>>>(
            future: _profilesFuture,
            builder: (context, profilesSnapshot) {
              if (profilesSnapshot.connectionState == ConnectionState.waiting && !profilesSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (profilesSnapshot.hasError) {
                return const Center(child: Text("Couldn't load blocked user profiles. Please try again."));
              }

              final profiles = {
                for (final profile in (profilesSnapshot.data ?? []))
                  profile['uid'].toString(): profile,
              };
              final visibleUids = blockedUids.where(profiles.containsKey).toList();
              if (visibleUids.isEmpty) {
                return const Center(
                  child: Text(
                    "You haven't blocked anyone.",
                    style: TextStyle(color: AppColors.textTertiary, fontSize: 14),
                  ),
                );
              }

              return ListView.builder(
                itemCount: visibleUids.length,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemBuilder: (context, index) {
                  final blockedUid = visibleUids[index];
                  final targetData = profiles[blockedUid]!;
                  final username = targetData['userName'] ?? "Unknown User";
                  final profileUrl = targetData['profileUrl'] ?? "";

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                      child: ClipOval(
                        child: GlobalCachedImage(
                          imageUrl: profileUrl,
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                          errorWidget: const Icon(Icons.person),
                        ),
                      ),
                    ),
                    title: Text(username, style: const TextStyle(fontWeight: FontWeight.w500)),
                    trailing: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: theme.colorScheme.outline),
                        shape: RoundedRectangleBorder(borderRadius: AppRadius.xlRadius),
                      ),
                      onPressed: () => _unblock(blockedUid),
                      child: const Text("Unblock", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
