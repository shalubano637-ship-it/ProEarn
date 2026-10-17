

import 'package:flutter/material.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cached_network_image/cached_network_image.dart';

import '../service.dart';
import '../theme/theme.dart';
import '../profile/profile_page.dart';

class FollowListPage extends StatelessWidget {
  final String title;
  final List<String> users; // Isme ab creators ki UIDs pass hongi

  const FollowListPage({super.key, required this.title, required this.users});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentAuthUser = Supabase.instance.client.auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: users.isEmpty
          ? Center(
              child: Text(
                "No $title yet.",
                style: const TextStyle(color: AppColors.textTertiary, fontSize: 15),
              ),
            )
          : ListView.builder(
              itemCount: users.length,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemBuilder: (context, index) {
                String targetUid = users[index];

                return FutureBuilder<Map<String, dynamic>?>(
                  future: Supabase.instance.client
                      .from('public_profiles')
                      .select()
                      .eq('uid', targetUid)
                      .maybeSingle(),
                  builder: (context, userSnapshot) {
                    if (!userSnapshot.hasData || userSnapshot.data == null) {
                      return const SizedBox.shrink(); // Agar user delete ho gaya ho to skip karein
                    }

                    var targetData = userSnapshot.data!;
                    String username = targetData['userName'] ?? "Unknown User";
                    String profileUrl = targetData['profileUrl'] ?? "";

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: theme.colorScheme.surfaceContainerHighest,
                        backgroundImage: profileUrl.isNotEmpty ? CachedNetworkImageProvider(profileUrl, cacheManager: CustomImageCacheManager.instance) : null,
                        child: profileUrl.isEmpty ? const Icon(Icons.person) : null,
                      ),
                      title: Text(
                        "@$username",
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () {
                        bool isMe = currentAuthUser != null && targetUid == currentAuthUser.id;
                        
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ProfilePage(
                              isOwnProfile: isMe,
                              otherUser: isMe ? null : targetUid,
                            ),
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
