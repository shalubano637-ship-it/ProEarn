

import 'dart:async';

import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';
import '../theme/theme.dart';

class ShareButton extends StatelessWidget {
  final String postId;
  final String postLink;

  const ShareButton({
    super.key, 
    required this.postId, 
    required this.postLink
  });

  Future<void> _incrementShareCount() async {
    await Supabase.instance.client.rpc('increment_share_count', params: {
      'p_post_id': postId,
    });
  }

  Future<void> _handleAppShare(BuildContext context) async {
    try {
      final ShareResult result = await Share.share(
        'Check out this amazing AI Generation on PRO EARN!\nPost Link: $postLink',
        subject: 'PRO EARN',
      );

      if (result.status == ShareResultStatus.success) {
        await _incrementShareCount();
      }
    } catch (e) {
      debugPrint("Error in app sharing: $e");
    }
  }

  Future<void> _handleDirectCopy(BuildContext context) async {
    try {
      await Clipboard.setData(ClipboardData(text: postLink));
      
      await _incrementShareCount();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Link copied to clipboard & Share counted!"),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint("Error in clipboard copy: $e");
    }
  }

  void _showShareOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.copy, color: AppColors.textPrimary),
                title: const Text('Copy Link', style: TextStyle(color: AppColors.textPrimary)),
                onTap: () {
                  Navigator.pop(context);
                  _handleDirectCopy(context); // Direct copy trigger
                },
              ),
              ListTile(
                leading: const Icon(Icons.apps, color: AppColors.textPrimary),
                title: const Text('Share to Other Apps', style: TextStyle(color: AppColors.textPrimary)),
                onTap: () {
                  Navigator.pop(context);
                  _handleAppShare(context); // Native Share sheet trigger
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client.from(kPostsCollection).stream(primaryKey: ['id']).eq('id', postId),
      builder: (context, snapshot) {
        int dynamicSharesCount = 0;

        if (snapshot.hasData && snapshot.data!.isNotEmpty) {
          var postData = snapshot.data!.first;
          dynamicSharesCount = (postData['sharesCount'] ?? 0) as int;
        }

        return Semantics(
          label: "Share, $dynamicSharesCount shares",
          button: true,
          child: GestureDetector(
          onTap: () => _showShareOptions(context), // Click par bottom sheet khulegi
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.share,
                size: 32,
                color: AppColors.textPrimary,
              ),
              const SizedBox(height: 4),
              Text(
                dynamicSharesCount.toString(),
                style: const TextStyle(
                  color: AppColors.textPrimary, 
                  fontSize: 12,
                  fontWeight: FontWeight.w500
                ),
              ),
            ],
          ),
          ),
        );
      },
    );
  }
}
