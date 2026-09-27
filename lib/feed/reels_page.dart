

import 'dart:async';
import 'package:universal_io/universal_io.dart';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cached_network_image/cached_network_image.dart';

import '../models.dart';
import '../service.dart';
import '../user_profile_features.dart';
import '../theme/theme.dart';

import 'admob_reel_item.dart';
import '../posts/like_button.dart';
import '../comments/comment_button.dart';
import '../comments/comment_screen.dart';
import '../posts/get_prompt_button.dart';
import '../gifts/gift_button.dart';
import '../posts/share_button.dart';
import '../posts/more_options_button.dart';
import '../widgets/error_retry_view.dart';

 class ReelsPage extends StatefulWidget {
  const ReelsPage({super.key});

  @override
  State<ReelsPage> createState() => _ReelsPageState();
}
class _ReelsPageState extends State<ReelsPage> {
  late PageController _pageController;
  final Set<String> _prefetchedUrls = {};
  List<Map<String, dynamic>>? _shuffledDocs;
  String _lastStreamDocIds = "";

  Stream<List<Map<String, dynamic>>>? _userStream;
  Stream<List<Map<String, dynamic>>>? _postsStream;

  int _nextAdTarget = 5; 

  void _initStreams() {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser != null) {
      _userStream = Supabase.instance.client
          .from(kUsersCollection)
          .stream(primaryKey: ['uid'])
          .eq('uid', currentUser.id);

      _postsStream = Supabase.instance.client
          .from(kPostsCollection)
          .stream(primaryKey: ['id'])
          .order('timestamp', ascending: false);
    }
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    
    _resetAdTarget();

    _initStreams();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ReelsAutoTrigger.targetPostId != null && ReelsAutoTrigger.targetPostId!.isNotEmpty) {
        String activePostId = ReelsAutoTrigger.targetPostId!;
        String activeCommentId = ReelsAutoTrigger.highlightCommentId ?? '';
        
        ReelsAutoTrigger.targetPostId = null;
        ReelsAutoTrigger.highlightCommentId = null;

        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: AppColors.background,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (context) => FractionallySizedBox(
            heightFactor: 0.85,
            child: CommentScreen(
              postId: activePostId, 
              highlightCommentId: activeCommentId,
            ),
          ),
        );
      }
    });
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

  void _prefetchImages(List<Map<String, dynamic>> docs) {
    for (final data in docs.take(3)) {
      final String imageUrl = data['imageUrl'] ?? '';
      
      if (imageUrl.isNotEmpty && imageUrl.startsWith('http') && !_prefetchedUrls.contains(imageUrl)) {
        _prefetchedUrls.add(imageUrl);
        precacheImage(
          CachedNetworkImageProvider(
            imageUrl, 
            cacheManager: CustomImageCacheManager.instance,
          ), 
          context,
        );
      }
    }
  }
    
  Future<void> _handleRefresh() async {
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted && _shuffledDocs != null) {
      _prefetchedUrls.clear();
      setState(() {
        _shuffledDocs!.shuffle();
        _resetAdTarget(); 
      });
    }
  }
    
  @override
  Widget build(BuildContext context) {
    final currentUser = Supabase.instance.client.auth.currentUser;
      
    if (currentUser == null || _userStream == null || _postsStream == null) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: Text("Please log in", style: TextStyle(color: AppColors.textPrimary))),
      );
    }

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _userStream, 
      builder: (context, userSnapshot) {
        List<dynamic> liveBlockedUsers = [];
        List<dynamic> liveHiddenPosts = [];
        if (userSnapshot.hasData && userSnapshot.data!.isNotEmpty) {
          var userData = userSnapshot.data!.first;
          liveBlockedUsers = userData['blockedUsers'] ?? [];
          liveHiddenPosts = userData['hiddenPosts'] ?? [];
        }

        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: _postsStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting && _shuffledDocs == null) {
              return const Center(child: CircularProgressIndicator(color: AppColors.accent));
            }
            if (snapshot.hasError) {
              return Scaffold(
                backgroundColor: AppColors.background,
                body: ErrorRetryView(
                  error: snapshot.error,
                  onRetry: () => setState(() { _initStreams(); }),
                ),
              );
            }
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const Scaffold(
                backgroundColor: AppColors.background,
                body: Center(
                  child: Text(
                    "No Posts Available",
                    style: TextStyle(color: AppColors.textTertiary, fontSize: 16),
                  ),
                ),
              );
            }

            final filteredDocs = snapshot.data!.where((data) {
              final String postOwnerUid = data[kPostOwnerUidField] ?? ''; 
              final String postId = data['id'].toString();
              
              bool isBlocked = liveBlockedUsers.contains(postOwnerUid);
              bool isHidden = liveHiddenPosts.contains(postId);
              bool isPrivatePost = data['isPrivatePost'] == true;

              return !isBlocked && !isHidden && !isPrivatePost;
            }).toList();
            String currentDocIds = filteredDocs.map((e) => e['id'].toString()).join(",");

            if (_shuffledDocs == null || _lastStreamDocIds != currentDocIds) {
              _shuffledDocs = List.from(filteredDocs);
              _lastStreamDocIds = currentDocIds;
              _resetAdTarget();
            }

            if (_shuffledDocs!.isEmpty) {
              return const Scaffold(
                backgroundColor: AppColors.background,
                body: Center(
                  child: Text(
                    "No Posts Available From Unblocked Creators",
                    style: TextStyle(color: AppColors.textTertiary, fontSize: 14),
                  ),
                ),
              );
            }

            _prefetchImages(_shuffledDocs!);
            
            return RefreshIndicator(
              onRefresh: _handleRefresh,
              color: AppColors.textPrimary,
              backgroundColor: AppColors.background,
              displacement: 40,
              child: PageView.builder(
                controller: _pageController,
                scrollDirection: Axis.vertical,
                itemCount: _shuffledDocs!.length + (_shuffledDocs!.length ~/ 5), 
                physics: const AlwaysScrollableScrollPhysics(), 
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
                  
                  if (realIndex >= _shuffledDocs!.length) {
                    realIndex = _shuffledDocs!.length - 1;
                  }

                  final postData = _shuffledDocs![realIndex];
                  
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
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.textPrimary),
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                if (postOwner != currentUser.id)
                                  StreamBuilder<List<Map<String, dynamic>>>(
                                    stream: Supabase.instance.client.from(kUsersCollection).stream(primaryKey: ['uid']).eq('uid', currentUser.id),
                                    builder: (context, userSub) {
                                      List<dynamic> myFollowing = [];
                                      if (userSub.hasData && userSub.data!.isNotEmpty) {
                                        var d = userSub.data!.first;
                                        myFollowing = d['following'] ?? [];
                                      }

                                      bool isFollowing = myFollowing.contains(postOwner);
                                      
                                      return GestureDetector(
                                        onTap: () async {
                                          try {
                                            if (isFollowing) {
                                              await Supabase.instance.client.rpc('toggle_follow', params: {
                                                'p_follower_id': currentUser.id,
                                                'p_target_id': postOwner,
                                                'p_follow': false,
                                              });
                                            } else {
                                              await Supabase.instance.client.rpc('toggle_follow', params: {
                                                'p_follower_id': currentUser.id,
                                                'p_target_id': postOwner,
                                                'p_follow': true,
                                              });

                                              sendNotification(
                                                targetOwnerId: postOwner,
                                                type: 'follow',
                                                message: 'started following you.',
                                              );
                                            }
                                          } catch (e) {
                                            debugPrint("toggle_follow failed: $e");
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text("Couldn't update follow status — please try again."), backgroundColor: AppColors.error),
                                              );
                                            }
                                          }
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                          decoration: BoxDecoration(color: AppColors.accent, borderRadius: AppRadius.xlRadius),
                                          child: Text(
                                            isFollowing ? "Unfollow" : "Follow", 
                                            style: const TextStyle(color: AppColors.textOnAccent, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(caption, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
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
          },
        );
      },
    );
  }
}
