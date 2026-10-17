

import 'package:universal_io/universal_io.dart';
import 'dart:math';

import 'package:flutter/material.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';
import '../service.dart';
import '../user_profile_features.dart';
import '../theme/theme.dart';

import 'admob_reel_item.dart';
import '../posts/like_button.dart';
import '../comments/comment_button.dart';
import '../posts/get_prompt_button.dart';
import '../gifts/gift_button.dart';
import '../posts/share_button.dart';
import '../posts/more_options_button.dart';

                    class SingleReelScreen extends StatefulWidget {
  final int initialIndex;
  final List<Map<String, dynamic>> allDocs;

  const SingleReelScreen({
    super.key,
    required this.initialIndex,
    required this.allDocs,
  });

  @override
  State<SingleReelScreen> createState() => _SingleReelScreenState();
}
class _SingleReelScreenState extends State<SingleReelScreen> {
  late PageController _pageController;
  int _nextAdTarget = 5; 

  @override
  void initState() {
    super.initState();
    _resetAdTarget();
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  void _resetAdTarget() {
    final random = Random();
    _nextAdTarget = random.nextInt(6) + 5; 
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = Supabase.instance.client.auth.currentUser;

    if (currentUser == null) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Text(
            "Please log in",
            style: TextStyle(color: AppColors.textPrimary),
          ),
        ),
      );
    }

    int totalAds = widget.allDocs.length ~/ _nextAdTarget;
    int totalItemCount = widget.allDocs.length + totalAds;

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: AppColors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary, size: 28),
          tooltip: "Back",
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: PageView.builder(
        scrollDirection: Axis.vertical,
        controller: _pageController,
        itemCount: totalItemCount,
        itemBuilder: (context, index) {
          bool isAdIndex = (index > 0 && index % (_nextAdTarget + 1) == 0);

          if (isAdIndex) {
  return AdMobReelItem(
    onAdClosed: () {
      if (_pageController.hasClients) {
        _pageController.nextPage(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    },
  );
}

          int realIndex = index - (index ~/ (_nextAdTarget + 1));
          if (realIndex >= widget.allDocs.length) {
            realIndex = widget.allDocs.length - 1;
          }

          final postData = widget.allDocs[realIndex];

          final String postId = postData['id'].toString();
          final String postOwner = postData[kPostOwnerUidField] ?? '';
          final String imageUrl = postData['imageUrl'] ?? '';
          final String caption = postData['caption'] ?? 'No Caption';
          final String prompt = postData['prompt'] ?? '';
          final String postLink = postData['link'] ?? '';

          return Stack(
            fit: StackFit.expand,
            children: [
              Container(color: AppColors.background),
              SizedBox.expand(
                child: imageUrl.startsWith('http')
                    ? GlobalCachedImage(imageUrl: imageUrl, fit: BoxFit.cover)
                    : Image.file(File(imageUrl), fit: BoxFit.cover),
              ),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withAlpha(51),
                      AppColors.transparent,
                      Colors.black.withAlpha(127),
                    ],
                  ),
                ),
              ),
              Positioned(
                bottom: 90 + MediaQuery.of(context).padding.bottom, 
                left: 15,
                right: 90,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () {
                            if (postOwner == currentUser.id) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const ProfilePage(isOwnProfile: true)),
                              );
                            } else {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ProfilePage(isOwnProfile: false, otherUser: postOwner),
                                ),
                              );
                            }
                          },
                          child: FutureBuilder<Map<String, dynamic>?>(
                            future: Supabase.instance.client
                                .from('public_profiles')
                                .select()
                                .eq('uid', postOwner)
                                .maybeSingle(),
                            builder: (context, userSnapshot) {
                              String displayHandle = "Loading...";
                              if (userSnapshot.hasData && userSnapshot.data != null) {
                                displayHandle = userSnapshot.data!['userName'] ?? "User";
                              }
                              return Text(
                                "@$displayHandle",
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: AppColors.textPrimary,
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      caption,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 10,
                bottom: 80 + MediaQuery.of(context).padding.bottom,
                child: Column(
                  children: [
                    LikeButton(postId: postId),
                    const SizedBox(height: 20),
                    CommentButton(postId: postId),
                    const SizedBox(height: 20),
                    GetPromptButton(
                      postId: postId,
                      ownerId: postOwner,
                      prompt: prompt,
                      currentUserId: currentUser.id,
                    ),
                    const SizedBox(height: 20),
                    GiftButton(postId: postId),
                    const SizedBox(height: 20),
                    ShareButton(postId: postId, postLink: postLink),
                    const SizedBox(height: 20),
                    MoreOptionsButton(
                      targetPostId: postId,
                      targetOwnerId: postOwner,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
