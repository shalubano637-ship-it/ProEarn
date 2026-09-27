

import 'package:flutter/material.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';
import '../theme/theme.dart';

import 'comment_screen.dart';

class CommentButton extends StatelessWidget {
  final String postId;
  const CommentButton({super.key, required this.postId});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        IconButton(
          icon: const Icon(Icons.mode_comment_outlined, color: AppColors.textPrimary, size: 30),
          tooltip: "Comments",
          onPressed: () {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              backgroundColor: AppColors.background, // Reel card look context color
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              builder: (context) => FractionallySizedBox(
                heightFactor: 0.85,
                child: CommentScreen(postId: postId),
              ),
            );
          },
        ),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: Supabase.instance.client
              .from(kCommentsCollection)
              .stream(primaryKey: ['id'])
              .eq('postId', postId),
          builder: (context, snapshot) {
            int count = snapshot.hasData ? snapshot.data!.length : 0;
            return Text(
              "$count",
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
            );
          },
        ),
      ],
    );
  }
}
