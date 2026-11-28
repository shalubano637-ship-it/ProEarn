import 'package:universal_io/universal_io.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';
import '../service.dart';
import '../theme/theme.dart';

class HiddenPostsListScreen extends StatefulWidget {
  const HiddenPostsListScreen({super.key});

  @override
  State<HiddenPostsListScreen> createState() => _HiddenPostsListScreenState();
}

class _HiddenPostsListScreenState extends State<HiddenPostsListScreen> {
  Stream<List<Map<String, dynamic>>>? _userStream;
  String _loadedIdsKey = '';
  Future<List<Map<String, dynamic>>>? _postsFuture;

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

  Future<List<Map<String, dynamic>>> _loadPosts(List<String> postIds) async {
    if (postIds.isEmpty) return [];
    final rows = await Supabase.instance.client
        .from(kPostsCollection)
        .select('id,imageUrl,caption')
        .inFilter('id', postIds);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> _unhide(String postId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await Supabase.instance.client.rpc('unhide_post', params: {
        'p_user_id': uid,
        'p_post_id': postId,
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't unhide this post. Please try again."),
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
      appBar: AppBar(title: const Text("Hidden Posts")),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _userStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text("Couldn't load hidden posts. Check your connection and try again."));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text("You haven't hidden any posts."));
          }

          final rawIds = (snapshot.data!.first['hiddenPosts'] as List?) ?? [];
          final hiddenPostIds = rawIds.map((value) => value.toString()).toSet().toList();
          if (hiddenPostIds.isEmpty) {
            return const Center(
              child: Text(
                "You haven't hidden any posts.",
                style: TextStyle(color: AppColors.textTertiary, fontSize: 14),
              ),
            );
          }

          final idsKey = hiddenPostIds.join('|');
          if (idsKey != _loadedIdsKey) {
            _loadedIdsKey = idsKey;
            _postsFuture = _loadPosts(hiddenPostIds);
          }

          return FutureBuilder<List<Map<String, dynamic>>>(
            future: _postsFuture,
            builder: (context, postsSnapshot) {
              if (postsSnapshot.connectionState == ConnectionState.waiting && !postsSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (postsSnapshot.hasError) {
                return const Center(child: Text("Couldn't load hidden posts. Please try again."));
              }

              final postsById = {
                for (final post in (postsSnapshot.data ?? []))
                  post['id'].toString(): post,
              };
              final visiblePostIds = hiddenPostIds.where(postsById.containsKey).toList();
              if (visiblePostIds.isEmpty) {
                return const Center(
                  child: Text(
                    "You haven't hidden any posts.",
                    style: TextStyle(color: AppColors.textTertiary, fontSize: 14),
                  ),
                );
              }

              return ListView.builder(
                itemCount: visiblePostIds.length,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemBuilder: (context, index) {
                  final postId = visiblePostIds[index];
                  final postData = postsById[postId]!;
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
                            ? GlobalCachedImage(imageUrl: imageUrl, fit: BoxFit.cover, width: 50, height: 50)
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
                      onPressed: () => _unhide(postId),
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
