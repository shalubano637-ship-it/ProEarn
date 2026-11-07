

import 'package:flutter/material.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';
import '../service.dart';
import '../theme/theme.dart';

       class LikeButton extends StatefulWidget {
  final String postId;
  const LikeButton({super.key, required this.postId});

  @override
  State<LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends State<LikeButton> {
  late Stream<List<Map<String, dynamic>>> _postStream;
  bool _likeRequestInProgress = false;

  @override
  void initState() {
    super.initState();
    _createPostStream();
  }

  void _createPostStream() {
    _postStream = Supabase.instance.client
        .from(kPostsCollection)
        .stream(primaryKey: ['id'])
        .eq('id', widget.postId);
  }

  @override
  void didUpdateWidget(covariant LikeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.postId != widget.postId) {
      _createPostStream();
    }
  }

  Future<void> toggleLikeOperation(bool currentlyLiked, String currentUserId) async {
    if (_likeRequestInProgress) return;
    setState(() => _likeRequestInProgress = true);
    final client = Supabase.instance.client;
    try {

    if (currentlyLiked) {
      await client.rpc('toggle_post_like', params: {
        'p_post_id': widget.postId,
        'p_user_id': currentUserId,
        'p_like': false,
      });
    } else {
      await client.rpc('toggle_post_like', params: {
        'p_post_id': widget.postId,
        'p_user_id': currentUserId,
        'p_like': true,
      });

      var postSnapshot = await client.from(kPostsCollection).select().eq('id', widget.postId).maybeSingle();
      if (postSnapshot != null) {
        String targetOwner = postSnapshot[kPostOwnerUidField] ?? '';

        if (targetOwner.isNotEmpty && targetOwner != currentUserId) {
          sendNotification(
            targetOwnerId: targetOwner,
            type: 'like',
            message: 'liked your post.',
            targetPostId: widget.postId,
          ).catchError((error) {
            debugPrint('Like notification failed: $error');
          });
        }
      }
    }
    } catch (error, stackTrace) {
      debugPrint('Like toggle failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't update like. Please try again."),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _likeRequestInProgress = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return const SizedBox.shrink();

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _postStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Column(
            children: [
              Icon(Icons.favorite_border, size: 32, color: AppColors.textPrimary),
              SizedBox(height: 4),
              Text("0", style: TextStyle(color: AppColors.textPrimary, fontSize: 12)),
            ],
          );
        }

        var postData = snapshot.data!.first;
        List<dynamic> likedByList = postData['likedBy'] ?? [];
        
        int totalLikesCount = likedByList.length;
        bool isCurrentUserLiked = likedByList.contains(user.id);

        return Semantics(
          label: isCurrentUserLiked ? "Unlike, $totalLikesCount likes" : "Like, $totalLikesCount likes",
          button: true,
          toggled: isCurrentUserLiked,
          child: GestureDetector(
          onTap: _likeRequestInProgress
              ? null
              : () => toggleLikeOperation(isCurrentUserLiked, user.id),
          child: Column(
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return ScaleTransition(scale: animation, child: child);
                },
                child: Icon(
                  Icons.favorite,
                  key: ValueKey<bool>(isCurrentUserLiked),
                  size: 32,
                  color: isCurrentUserLiked ? AppColors.error : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                totalLikesCount.toString(),
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
              ),
            ],
          ),
          ),
        );
      },
    );
  }
}
