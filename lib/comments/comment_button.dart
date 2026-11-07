

import 'package:flutter/material.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';

import '../models.dart';
import '../theme/theme.dart';

import 'comment_screen.dart';

class CommentButton extends StatefulWidget {
  final String postId;
  const CommentButton({super.key, required this.postId});

  @override
  State<CommentButton> createState() => _CommentButtonState();
}

class _CommentButtonState extends State<CommentButton> {
  late final Stream<List<Map<String, dynamic>>> _commentsStream;

  @override
  void initState() {
    super.initState();
    _commentsStream = Supabase.instance.client.from(kCommentsCollection).stream(primaryKey: ['id']).eq('postId', widget.postId);
  }

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
                child: CommentScreen(postId: widget.postId),
              ),
            );
          },
        ),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: _commentsStream,
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
