

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
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text("Data fetch failed."));
          }

          var userData = snapshot.data!.first;
          List<dynamic> hiddenPostIds = userData['hiddenPosts'] ?? [];

          if (hiddenPostIds.isEmpty) {
            return const Center(
              child: Text(
                "You haven't hidden any posts.",
                style: TextStyle(color: AppColors.textTertiary, fontSize: 14),
              ),
            );
          }

          return ListView.builder(
            itemCount: hiddenPostIds.length,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemBuilder: (context, index) {
              String postId = hiddenPostIds[index];

              return StreamBuilder<List<Map<String, dynamic>>>(
                stream: Supabase.instance.client
                    .from(kPostsCollection)
                    .stream(primaryKey: ['id'])
                    .eq('id', postId),
                builder: (context, postSnapshot) {
                  if (!postSnapshot.hasData || postSnapshot.data!.isEmpty) {
                    return const SizedBox.shrink(); // Agar post delete ho gayi ho
                  }

                  var postData = postSnapshot.data!.first;
                  String imageUrl = postData['imageUrl'] ?? '';
                  String caption = postData['caption'] ?? 'No Caption';

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
                      label: const Text("Unhide", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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
