import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../service.dart';
import '../theme/theme.dart';
import '../profile/profile_page.dart';

class FollowListPage extends StatefulWidget {
  final String title;
  final List<String> users;

  const FollowListPage({super.key, required this.title, required this.users});

  @override
  State<FollowListPage> createState() => _FollowListPageState();
}

class _FollowListPageState extends State<FollowListPage> {
  late Future<List<Map<String, dynamic>>> _profilesFuture;

  @override
  void initState() {
    super.initState();
    _profilesFuture = _loadProfiles();
  }

  Future<List<Map<String, dynamic>>> _loadProfiles() async {
    final ids = widget.users.toSet().toList();
    if (ids.isEmpty) return [];
    final rows = await Supabase.instance.client
        .from('public_profiles')
        .select('uid,userName,profileUrl')
        .inFilter('uid', ids);
    final byId = {for (final row in rows) row['uid'] as String: Map<String, dynamic>.from(row)};
    // Keep the original follower/following order while avoiding one query per row.
    return ids.where(byId.containsKey).map((id) => byId[id]!).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentAuthUser = Supabase.instance.client.auth.currentUser;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold))),
      body: widget.users.isEmpty
          ? Center(child: Text("No ${widget.title} yet.", style: const TextStyle(color: AppColors.textTertiary, fontSize: 15)))
          : FutureBuilder<List<Map<String, dynamic>>>(
              future: _profilesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: TextButton(
                      onPressed: () => setState(() => _profilesFuture = _loadProfiles()),
                      child: const Text('Could not load users. Tap to retry.'),
                    ),
                  );
                }
                final profiles = snapshot.data ?? [];
                if (profiles.isEmpty) {
                  return Center(child: Text("No ${widget.title} yet."));
                }
                return ListView.builder(
                  itemCount: profiles.length,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemBuilder: (context, index) {
                    final targetData = profiles[index];
                    final targetUid = targetData['uid'] as String;
                    final username = targetData['userName'] ?? 'Unknown User';
                    final profileUrl = targetData['profileUrl'] ?? '';
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: theme.colorScheme.surfaceContainerHighest,
                        backgroundImage: profileUrl.isNotEmpty
                            ? CachedNetworkImageProvider(profileUrl, cacheManager: CustomImageCacheManager.instance)
                            : null,
                        child: profileUrl.isEmpty ? const Icon(Icons.person) : null,
                      ),
                      title: Text("@$username", style: const TextStyle(fontWeight: FontWeight.w500)),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () {
                        final isMe = currentAuthUser != null && targetUid == currentAuthUser.id;
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => ProfilePage(isOwnProfile: isMe, otherUser: isMe ? null : targetUid),
                        ));
                      },
                    );
                  },
                );
              },
            ),
    );
  }
}
