import 'package:universal_io/universal_io.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';
import '../service.dart';
import '../theme/theme.dart';

class HiddenPostsListScreen extends StatelessWidget {
  const HiddenPostsListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUser = Supabase.instance.client.auth.currentUser;
    final theme = Theme.of(context);

    if (currentUser == null) {
      return const Scaffold(body: Center(child: Text("Session expired.")));
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Hidden Posts")),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: Supabase.instance.client
            .from(kUsersCollection)
            .stream(primaryKey: ['uid'])
            .eq('uid', currentUser.id),
        builder: (context, userSnapshot) {
          if (userSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!userSnapshot.hasData || userSnapshot.data!.isEmpty) {
            return const Center(
              child: Text("Couldn’t load hidden posts. Check your connection and try again."),
            );
          }

          final hiddenPostIds = (userSnapshot.data!.first['hiddenPosts'] as List?)
                  ?.map((id) => id.toString())
                  .where((id) => id.isNotEmpty)
                  .toList() ??
              const <String>[];

          if (hiddenPostIds.isEmpty) {
            return const Center(
              child: Text(
                "You haven't hidden any posts.",
                style: TextStyle(color: AppColors.textTertiary, fontSize: 14),
              ),
            );
          }

          // One server-filtered stream replaces one Realtime subscription per hidden post.
          return StreamBuilder<List<Map<String, dynamic>>>(
            stream: Supabase.instance.client
                .from(kPostsCollection)
                .stream(primaryKey: ['id'])
                .inFilter('id', hiddenPostIds),
            builder: (context, postsSnapshot) {
              if (postsSnapshot.connectionState == ConnectionState.waiting &&
                  !postsSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (postsSnapshot.hasError) {
                return const Center(
                  child: Text("Couldn’t load hidden posts. Check your connection and try again."),
                );
              }

              final postsById = <String, Map<String, dynamic>>{
                for (final post in postsSnapshot.data ?? <Map<String, dynamic>>[])
                  post['id'].toString(): post,
              };
              // Preserve the user's hiddenPosts ordering and skip posts already deleted.
              final visiblePosts = hiddenPostIds
                  .map((id) => postsById[id])
                  .whereType<Map<String, dynamic>>()
                  .toList();

              if (visiblePosts.isEmpty) {
                return const Center(
                  child: Text(
                    "You haven't hidden any posts.",
                    style: TextStyle(color: AppColors.textTertiary, fontSize: 14),
                  ),
                );
              }

              return ListView.builder(
                itemCount: visiblePosts.length,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemBuilder: (context, index) {
                  final postData = visiblePosts[index];
                  final postId = postData['id'].toString();
                  final imageUrl = postData['imageUrl']?.toString() ?? '';
                  final caption = postData['caption']?.toString() ?? 'No Caption';

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    leading: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        borderRadius: AppRadius.smRadius,
                        color: theme.colorScheme.surfaceContainerHighest,
                      ),
                      child: ClipRRect(
                        borderRadius: AppRadius.smRadius,
                        child: imageUrl.startsWith('http')
                            ? GlobalCachedImage(
                                imageUrl: imageUrl,
                                fit: BoxFit.cover,
                                width: 50,
                                height: 50,
                              )
                            : Image.file(File(imageUrl), fit: BoxFit.cover),
                      ),
                    ),
                    title: Text(
                      caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                    ),
                    trailing: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: theme.colorScheme.primary),
                        shape: RoundedRectangleBorder(borderRadius: AppRadius.xlRadius),
                      ),
                      icon: const Icon(Icons.visibility, size: 16),
                      label: const Text(
                        "Unhide",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      onPressed: () async {
                        await Supabase.instance.client.rpc('unhide_post', params: {
                          'p_user_id': currentUser.id,
                          'p_post_id': postId,
                        });
                      },
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
