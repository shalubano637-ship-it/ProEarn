import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../service.dart';
import '../theme/theme.dart';

/// Reuses the feed's shared posts stream; no per-reel realtime subscription.
class LikeButton extends StatefulWidget {
  final String postId;
  final String ownerId;
  final bool initiallyLiked;
  final int initialLikeCount;
  const LikeButton({super.key, required this.postId, required this.ownerId, required this.initiallyLiked, required this.initialLikeCount});
  @override
  State<LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends State<LikeButton> {
  bool? _optimisticLiked;
  int? _optimisticCount;
  bool _requestInProgress = false;

  @override
  void didUpdateWidget(covariant LikeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_optimisticLiked != null && widget.initiallyLiked == _optimisticLiked && widget.initialLikeCount == _optimisticCount) {
      _optimisticLiked = null;
      _optimisticCount = null;
    }
  }

  Future<void> _toggle(String userId, bool liked, int count) async {
    if (_requestInProgress) return;
    final nextLiked = !liked;
    final nextCount = (count + (nextLiked ? 1 : -1)).clamp(0, 1 << 30);
    setState(() { _requestInProgress = true; _optimisticLiked = nextLiked; _optimisticCount = nextCount; });
    try {
      await Supabase.instance.client.rpc('toggle_post_like', params: {'p_post_id': widget.postId, 'p_user_id': userId, 'p_like': nextLiked});
      if (nextLiked && widget.ownerId.isNotEmpty && widget.ownerId != userId) {
        sendNotification(targetOwnerId: widget.ownerId, type: 'like', message: 'liked your post.', targetPostId: widget.postId).catchError((error) { debugPrint('Like notification failed: $error'); });
      }
    } catch (error, stackTrace) {
      debugPrint('Like toggle failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() { _optimisticLiked = null; _optimisticCount = null; });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't update like. Please try again."), backgroundColor: AppColors.error));
      }
    } finally { if (mounted) setState(() => _requestInProgress = false); }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return const SizedBox.shrink();
    final liked = _optimisticLiked ?? widget.initiallyLiked;
    final count = _optimisticCount ?? widget.initialLikeCount;
    return Semantics(
      label: liked ? 'Unlike, $count likes' : 'Like, $count likes', button: true, toggled: liked,
      child: GestureDetector(
        onTap: _requestInProgress ? null : () => _toggle(user.id, liked, count),
        child: Column(children: [
          AnimatedSwitcher(duration: const Duration(milliseconds: 160), transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
            child: Icon(liked ? Icons.favorite : Icons.favorite_border, key: ValueKey<bool>(liked), size: 32, color: liked ? AppColors.error : AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text(count.toString(), style: const TextStyle(color: AppColors.textPrimary, fontSize: 12)),
        ]),
      ),
    );
  }
}