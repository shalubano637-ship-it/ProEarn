

import 'dart:async';
import 'package:universal_io/universal_io.dart';

import 'package:flutter/material.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:share_plus/share_plus.dart';

import '../models.dart';
import '../service.dart';
import '../ad_unit_ids.dart';
import '../social_feed.dart';
import '../theme/theme.dart';
import '../social/follow_list_page.dart';
import '../widgets/error_retry_view.dart';
import '../messaging/chat_page.dart';
import '../messaging/chat_settings_page.dart';
import '../bag_page.dart';
import 'edit_profile_page.dart';
import 'analytics_page.dart';

class ProfilePage extends StatefulWidget {
  final bool isOwnProfile;
  final String? otherUser;

  const ProfilePage({super.key, this.isOwnProfile = true, this.otherUser});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}
class _ProfilePageState extends State<ProfilePage> {
  bool selectionMode = false;
  List<String> selectedPosts = [];
  
  BannerAd? _bannerAd;
  bool _isAdLoaded = false;

  Future<Map<String, dynamic>?>? _profileFuture;
  String? _loadedTargetUid;
  Stream<List<Map<String, dynamic>>>? _postsStream;

  @override
  void initState() {
    super.initState();
    _loadAds();
  }

  void _loadAds() {
    _bannerAd = BannerAd(
      adUnitId: AdUnitIds.banner,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          setState(() {
            _isAdLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('Top BannerAd failed: $error');
          ad.dispose();
        },
      ),
    )..load();

  }

  @override
  void dispose() {
    _bannerAd?.dispose();
        super.dispose();
  }

  Future<void> deleteSelectedPosts() async {
    final postIdsToDelete = List<String>.from(selectedPosts);
    try {
      await Supabase.instance.client
          .from(kPostsCollection)
          .delete()
          .inFilter('id', postIdsToDelete);

      if (!mounted) return;
      setState(() {
        selectionMode = false;
      });
      selectedPosts.clear();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Selected posts deleted successfully!")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't delete post — please try again.")),
      );
    }
  }

  Future<Map<String, dynamic>?> _loadProfileData(String uid) async {
    final profile = await Supabase.instance.client.from('public_profiles').select().eq('uid', uid).maybeSingle();
    if (profile == null) return null;
    if (widget.isOwnProfile) {
      final own = await Supabase.instance.client.from('users').select('followers,following').eq('uid', uid).maybeSingle();
      return {...profile, 'followers': own?['followers'] ?? const [], 'following': own?['following'] ?? const []};
    }
    return profile;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentUser = Supabase.instance.client.auth.currentUser;
    
    final String targetUid = widget.isOwnProfile
        ? (currentUser?.id ?? '')
        : (widget.otherUser ?? '');

    if (_profileFuture == null || _loadedTargetUid != targetUid) {
      _loadedTargetUid = targetUid;
      _profileFuture = _loadProfileData(targetUid);
      _postsStream = Supabase.instance.client
          .from(kPostsCollection)
          .stream(primaryKey: ['id'])
          .eq(kPostOwnerUidField, targetUid);
    }

    return Scaffold(
      appBar: AppBar(
        title: FutureBuilder<Map<String, dynamic>?>(
          future: _profileFuture,
          builder: (context, snapshot) {
            String appBarTitle = "Profile";
            if (snapshot.hasData && snapshot.data != null) {
              appBarTitle = snapshot.data!['userName'] ?? "User";
            }
            return Text(
              appBarTitle,
              style: const TextStyle(fontWeight: FontWeight.bold),
            );
          },
        ),
        actions: [
          if (selectionMode && widget.isOwnProfile) ...[
            IconButton(
              icon: const Icon(Icons.delete, color: AppColors.error),
              tooltip: "Delete selected posts",
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text("Delete Posts"),
                    content: Text("Are you sure you want to delete ${selectedPosts.length} selected post(s)?"),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          deleteSelectedPosts();
                        },
                        child: const Text("Delete", style: TextStyle(color: AppColors.error)),
                      ),
                    ],
                  ),
                );
              },
            ),
            IconButton(
              tooltip: "Cancel selection",
              onPressed: () {
                setState(() {
                  selectionMode = false;
                  selectedPosts.clear();
                });
              },
              icon: const Icon(Icons.close),
            ),
          ],
          if (!selectionMode) ...[
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: "Share profile",
              onPressed: () async {
                final profile = await Supabase.instance.client
                    .from('public_profiles')
                    .select('userName')
                    .eq('uid', targetUid)
                    .maybeSingle();
                final name = profile?['userName'] ?? 'this user';
                Share.share('Check out @$name profile on PRO EARN! App Link: app://profile/$targetUid');
              },
            ),
            if (!widget.isOwnProfile)
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: "Chat settings",
                onPressed: () async {
                  final profile = await Supabase.instance.client
                      .from('public_profiles')
                      .select('userName')
                      .eq('uid', targetUid)
                      .maybeSingle();
                  final name = profile?['userName'] ?? 'User';
                  if (context.mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ChatSettingsPage(otherUid: targetUid, otherUserName: name)),
                    );
                  }
                },
              ),
          ],
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _profileFuture,
        builder: (context, userSnapshot) {
          String displayUsername = "Loading...";
          String displayBio = "Creative AI Artist";
          String profileUrl = "";
          
          List<String> userFollowersList = [];
          List<String> userFollowingList = [];
          bool isPrivateAccount = false;

          if (userSnapshot.hasData && userSnapshot.data != null) {
            final uData = userSnapshot.data!;
            displayUsername = uData['userName'] ?? "User";
            displayBio = uData['bio'] ?? "No Bio Yet";
            profileUrl = uData['profileUrl'] ?? "";
            isPrivateAccount = uData['isPrivateAccount'] == true;

            if (uData['followers'] != null) {
              userFollowersList = List<String>.from(uData['followers']);
            }
            if (uData['following'] != null) {
              userFollowingList = List<String>.from(uData['following']);
            }

            if (widget.isOwnProfile) {
              currentUserName = displayUsername;
              currentUserBio = displayBio;
              currentUserProfile = profileUrl;
            }
          }

          final bool viewerIsFollowing = currentUser != null && userFollowersList.contains(currentUser.id);
          final bool canSeePrivateProfile = widget.isOwnProfile || !isPrivateAccount || viewerIsFollowing;

          return SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '@$displayUsername',
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Text(displayBio),
                            const SizedBox(height: 15),
                            Row(
                              children: [
                                if (canSeePrivateProfile) ...[
                                  GestureDetector(
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => FollowListPage(title: "Followers", users: userFollowersList),
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        Text(userFollowersList.length.toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
                                        const Text("Followers"),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 30),
                                  GestureDetector(
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => FollowListPage(title: "Following", users: userFollowingList),
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        Text(userFollowingList.length.toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
                                        const Text("Following"),
                                      ],
                                    ),
                                  ),
                                ],
                                if (!canSeePrivateProfile)
                                  const Text(
                                    'Private account',
                                    style: TextStyle(color: AppColors.textTertiary),
                                  ),
                              ],
                            )
                          ],
                        ),
                      ),
                      Column(
                        children: [
                          CircleAvatar(
                            radius: 45,
                            backgroundColor: theme.colorScheme.surfaceContainerHighest,
                            backgroundImage: profileUrl.isNotEmpty ? CachedNetworkImageProvider(profileUrl, cacheManager: CustomImageCacheManager.instance) : null,
                            child: profileUrl.isEmpty ? const Icon(Icons.person, size: 45) : null,
                          ),
                        ],
                      )
                    ],
                  ),
                ),
                const SizedBox(height: 25),
                
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      if (widget.isOwnProfile)
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: theme.colorScheme.primary, foregroundColor: theme.colorScheme.onPrimary),
                            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EditProfilePage())),
                            child: const Text("Edit Profile"),
                          ),
                        ),
                      if (!widget.isOwnProfile)
                        Expanded(
                          child: currentUser == null
                              ? const SizedBox.shrink()
                              : Builder(
                                  builder: (context) {
                                    bool isFollowing = userFollowersList.contains(currentUser.id);

                                    return ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: isFollowing 
                                            ? theme.colorScheme.surfaceContainerHighest 
                                            : theme.colorScheme.primary, 
                                        foregroundColor: isFollowing 
                                            ? theme.colorScheme.onSurface 
                                            : theme.colorScheme.onPrimary,
                                      ),
                                      onPressed: () async {
                                        try {
                                          if (isFollowing) {
                                            await Supabase.instance.client.rpc('toggle_follow', params: {
                                              'p_follower_id': currentUser.id,
                                              'p_target_id': targetUid,
                                              'p_follow': false,
                                            });
                                          } else {
                                            await Supabase.instance.client.rpc('toggle_follow', params: {
                                              'p_follower_id': currentUser.id,
                                              'p_target_id': targetUid,
                                              'p_follow': true,
                                            });

                                            sendNotification(
                                              targetOwnerId: targetUid,
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
                                      child: Text(isFollowing ? "Unfollow" : "Follow"),
                                    );
                                  },
                                ),
                        ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: theme.colorScheme.surfaceContainerHighest, foregroundColor: theme.colorScheme.onSurface),
                          onPressed: () {
                            if (widget.isOwnProfile) {
                              Navigator.push(context, MaterialPageRoute(builder: (_) => const AnalyticsPage()));
                            } else {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => ChatPage(otherUid: targetUid, otherUserName: displayUsername)),
                              );
                            }
                          },
                          child: Text(widget.isOwnProfile ? "Analytics" : "Message"),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        icon: const Icon(Icons.shopping_bag_outlined),
                        tooltip: widget.isOwnProfile ? "Your Bag" : "$displayUsername's received gifts",
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => widget.isOwnProfile
                                  ? const BagPage()
                                  : BagPage(viewUid: targetUid, initialTabIndex: 1),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 15),

                if (!canSeePrivateProfile)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(24, 35, 24, 50),
                    child: Text(
                      'Follow this account to see their posts and follower/following lists.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textTertiary),
                    ),
                  ),

                if (canSeePrivateProfile && _isAdLoaded && _bannerAd != null)
                  Container(
                    alignment: Alignment.center,
                    width: _bannerAd!.size.width.toDouble(),
                    height: _bannerAd!.size.height.toDouble(),
                    margin: const EdgeInsets.only(bottom: 10),
                    child: AdWidget(ad: _bannerAd!),
                  ),

                if (canSeePrivateProfile)
                  StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _postsStream,
                  builder: (context, postSnapshot) {
                    if (postSnapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(padding: EdgeInsets.all(20.0), child: Center(child: CircularProgressIndicator()));
                    }
                    if (postSnapshot.hasError) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 30),
                        child: ErrorRetryView(
                          error: postSnapshot.error,
                          onRetry: () => setState(() {}),
                        ),
                      );
                    }
                    if (!postSnapshot.hasData || postSnapshot.data!.isEmpty) {
                      return const Padding(padding: EdgeInsets.only(top: 50), child: Center(child: Text("No Posts Yet", style: TextStyle(color: AppColors.textTertiary))));
                    }
                    
                    final userPostDocs = postSnapshot.data!;

                    final totalItemCount = userPostDocs.length;

                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: totalItemCount,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 2,
                        mainAxisSpacing: 2,
                      ),
                      itemBuilder: (context, index) {
                        final postIndex = index;

                        final pData = userPostDocs[postIndex];
                        final String currentPostId = pData['id'].toString();
                        final String imgUrl = pData['imageUrl'] ?? '';
                        final selected = selectedPosts.contains(currentPostId);

                        return GestureDetector(
                          onTap: () {
                            if (selectionMode) {
                              setState(() {
                                if (selected) {
                                  selectedPosts.remove(currentPostId);
                                  if (selectedPosts.isEmpty) selectionMode = false;
                                } else {
                                  selectedPosts.add(currentPostId);
                                }
                              });
                            } else {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => SingleReelScreen(initialIndex: postIndex, allDocs: userPostDocs),
                                ),
                              );
                            }
                          },
                          onLongPress: () {
                            if (!widget.isOwnProfile) return;
                            setState(() {
                              selectionMode = true;
                              if (selected) {
                                selectedPosts.remove(currentPostId);
                                if (selectedPosts.isEmpty) selectionMode = false;
                              } else {
                                selectedPosts.add(currentPostId);
                              }
                            });
                          },
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: imgUrl.startsWith('http') 
                                    ? GlobalCachedImage(imageUrl: imgUrl, fit: BoxFit.cover) 
                                    : Image.file(File(imgUrl), fit: BoxFit.cover),
                              ),
                              if (selected)
                                Positioned.fill(
                                  child: Container(
                                    color: AppColors.overlay,
                                    child: const Center(child: Icon(Icons.check_circle, color: Colors.white, size: 35)),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                )
              ],
            ),
          );
        },
      ),
    );
  }
}
