// =============================================================================
// PRO EARN — Feed: SearchPage
// -----------------------------------------------------------------------------
// Extracted from the original social_feed.dart during the feature-based
// file split (no UI or logic changes — only where this code physically
// lives). social_feed.dart is now a barrel file that re-exports this file.
// =============================================================================

// =============================================================================
// PRO EARN — AI-generated content social platform
// -----------------------------------------------------------------------------
// This file (social_feed.dart) is one of three files this app's UI/logic
// was split into (equal three-way split of the original single-file
// main.dart, no UI or logic changes — only where each class physically
// lives):
//   1. main.dart
//   2. social_feed.dart            (this file)
//   3. user_profile_features.dart
//
// social_feed.dart contains everything about browsing, creating, and
// interacting with posts/reels:
//   - Feed & Reels: ReelsPage, SearchPage, SingleReelScreen
//   - Upload & Media: UploadPage, GlobalImageAdjuster
//   - Post interactions: LikeButton, CommentButton, CommentScreen,
//     ShareButton, MoreOptionsButton, GetPromptButton (creator earnings)
//
// Persistence: Supabase (Postgres) is the source of truth for all
// user/post/social data.
// =============================================================================

// ---- Dart core ----
import 'dart:async';
import 'package:universal_io/universal_io.dart';
import 'dart:math';

// ---- Flutter framework ----
import 'package:flutter/material.dart';

// ---- Supabase ----
import 'package:supabase_flutter/supabase_flutter.dart';

// ---- Third-party packages ----
import 'package:google_mobile_ads/google_mobile_ads.dart';

// ---- App files (split out of the original single-file main.dart) ----
import '../models.dart';
import '../service.dart';
import '../user_profile_features.dart';
import '../theme/theme.dart';
import '../ad_unit_ids.dart';
import '../widgets/error_retry_view.dart';


import 'single_reel_screen.dart';

  class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}
class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _debouncedQuery = '';

  // --- Banner Ad ke liye variables (Search bar ke upar wala) ---
  BannerAd? _bannerAd;
  bool _isBannerAdLoaded = false;

  // --- Grid Ad ke liye variables (Grid ke beech mein aane wale ads) ---
  int _nextAdTarget = 5; 
  BannerAd? _gridBannerAd;
  bool _isGridAdLoaded = false;

  @override
  void initState() {
    super.initState();
    _resetAdTarget(); 
    _loadBannerAd();  
    _loadGridBannerAd(); // Grid ke andar dikhane ke liye Ad load karein
    
    _searchController.addListener(() {
      _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 400), () {
        if (mounted) {
          setState(() {
            _debouncedQuery = _searchController.text.toLowerCase().trim();
          });
        }
      });
    });
  }

  // Search bar ke upar wala Banner Ad load karne ka function
  void _loadBannerAd() {
    final String adUnitId = AdUnitIds.banner;

    _bannerAd = BannerAd(
      adUnitId: adUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          setState(() {
            _isBannerAdLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          debugPrint('Banner ad failed to load: $error');
        },
      ),
    )..load();
  }

  // Grid ke bich me dikhane ke liye AdMob Banner Ad load karne ka function
  void _loadGridBannerAd() {
    final String adUnitId = AdUnitIds.banner;

    _gridBannerAd = BannerAd(
      adUnitId: adUnitId,
      size: AdSize.mediumRectangle, // Grid ke hisaab se medium rectangle ya banner chun sakte hain
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          setState(() {
            _isGridAdLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          debugPrint('Grid AdMob failed to load: $error');
        },
      ),
    )..load();
  }

  void _resetAdTarget() {
    final random = Random();
    _nextAdTarget = random.nextInt(6) + 5; 
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _bannerAd?.dispose(); 
    _gridBannerAd?.dispose(); // Grid ad ko bhi dispose karein
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = _debouncedQuery;

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          decoration: const InputDecoration(
            hintText: 'Search creators, captions or prompts...',
            border: InputBorder.none,
            prefixIcon: Icon(Icons.search),
          ),
        ),
      ),
      body: Column(
        children: [
          if (_isBannerAdLoaded && _bannerAd != null)
            Container(
              alignment: Alignment.center,
              width: _bannerAd!.size.width.toDouble(),
              height: _bannerAd!.size.height.toDouble(),
              child: AdWidget(ad: _bannerAd!),
            ),

          Expanded(
            child: query.isEmpty
                ? StreamBuilder<List<Map<String, dynamic>>>(
                    // Bounded to the 60 most recent posts — was an
                    // unfiltered stream of the entire table, which meant the
                    // full dataset (and every future insert/update/delete
                    // anywhere in the app) was pushed to every client
                    // viewing the discovery grid. This still updates live
                    // within that recent-60 window; full infinite-scroll
                    // pagination beyond that would need a separate
                    // non-realtime paged query, not attempted here.
                    stream: Supabase.instance.client
                        .from(kPostsCollection)
                        .stream(primaryKey: ['id'])
                        .order('timestamp', ascending: false)
                        .limit(60),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                      final rawDocs = snapshot.data!;

                      int totalAds = rawDocs.length ~/ _nextAdTarget;
                      int totalItemCount = rawDocs.length + totalAds;

                      return GridView.builder(
                        padding: const EdgeInsets.all(2),
                        itemCount: totalItemCount,
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3, crossAxisSpacing: 2, mainAxisSpacing: 2),
                        itemBuilder: (context, index) {
                          bool isAdIndex = (index > 0 && index % (_nextAdTarget + 1) == 0);

                          if (isAdIndex) {
                            // --- YAHAN DUMMY AD KI JAGAH ADMOB TEST AD LAGA DIYA GAYA HAI ---
                            return Container(
                              color: AppColors.surfaceElevated,
                              child: Center(
                                child: _isGridAdLoaded && _gridBannerAd != null
                                    ? AdWidget(ad: _gridBannerAd!)
                                    : const Text(
                                        "Ad",
                                        style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.bold, fontSize: 12),
                                      ),
                              ),
                            );
                          }

                          int realIndex = index - (index ~/ (_nextAdTarget + 1));
                          if (realIndex >= rawDocs.length) {
                            realIndex = rawDocs.length - 1;
                          }

                          final pData = rawDocs[realIndex];
                          final img = pData['imageUrl'] ?? '';
                          
                          return GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => SingleReelScreen(
                                    initialIndex: realIndex,
                                    allDocs: rawDocs,
                                  ),
                                ),
                              );
                            },
                            child: Container(
                              color: AppColors.surfaceElevated,
                              child: img.startsWith('http')
                                  ? GlobalCachedImage(imageUrl: img, fit: BoxFit.cover)
                                  : Image.file(File(img), fit: BoxFit.cover),
                            ),
                          );
                        },
                      );
                    },
                  )
                : ListView(
                    children: [
                      FutureBuilder<List<Map<String, dynamic>>>(
                        key: ValueKey('users_$query'),
                        future: Supabase.instance.client
                            .from('public_profiles')
                            .select()
                            .ilike('userName', '%$query%')
                            .limit(30),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const SizedBox.shrink();
                          }

                          final userDocs = snapshot.data ?? [];

                          if (userDocs.isEmpty) return const SizedBox.shrink();

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.all(10.0),
                                child: Text("Users", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textTertiary)),
                              ),
                              ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: userDocs.length,
                                itemBuilder: (context, index) {
                                  final uData = userDocs[index];
                                  final String uName = uData['userName'] ?? 'No Name';
                                  final String pPic = uData['profileUrl'] ?? '';
                                  final String uId = uData['uid'].toString();

                                  return ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                                      child: ClipOval(
                                        child: GlobalCachedImage(
                                          imageUrl: pPic,
                                          width: 40,
                                          height: 40,
                                          errorWidget: const Icon(Icons.person),
                                        ),
                                      ),
                                    ),
                                    title: Text(uName),
                                    onTap: () {
                                      final currentAuthUser = Supabase.instance.client.auth.currentUser;
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => ProfilePage(
                                            isOwnProfile: currentAuthUser != null && uId == currentAuthUser.id,
                                            otherUser: uId,
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                              const Divider(),
                            ],
                          );
                        },
                      ),

                      const Padding(
                        padding: EdgeInsets.all(10.0),
                        child: Text("Posts", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textTertiary)),
                      ),
                      FutureBuilder<List<Map<String, dynamic>>>(
                        key: ValueKey(query),
                        future: Supabase.instance.client
                            .from(kPostsCollection)
                            .select()
                            .or('caption.ilike.%$query%,prompt.ilike.%$query%')
                            .order('timestamp', ascending: false)
                            .limit(60),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          if (snapshot.hasError) {
                            return ErrorRetryView(
                              error: snapshot.error,
                              onRetry: () => setState(() {}),
                            );
                          }

                          final filtered = snapshot.data ?? [];

                          if (filtered.isEmpty) {
                            return const Center(child: Padding(
                              padding: EdgeInsets.all(20.0),
                              child: Text("No posts found matching search query.", style: TextStyle(color: AppColors.textTertiary)),
                            ));
                          }

                          int totalAds = filtered.length ~/ _nextAdTarget;
                          int totalItemCount = filtered.length + totalAds;

                          return GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(2),
                            itemCount: totalItemCount,
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3, crossAxisSpacing: 2, mainAxisSpacing: 2),
                            itemBuilder: (context, index) {
                              bool isAdIndex = (index > 0 && index % (_nextAdTarget + 1) == 0);

                              if (isAdIndex) {
                                // --- FILTERED GRID AD UI ---
                                return Container(
                                  color: AppColors.surfaceElevated,
                                  child: Center(
                                    child: _isGridAdLoaded && _gridBannerAd != null
                                        ? AdWidget(ad: _gridBannerAd!)
                                        : const Text(
                                            "Ad",
                                            style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.bold, fontSize: 12),
                                          ),
                                  ),
                                );
                              }

                              int realIndex = index - (index ~/ (_nextAdTarget + 1));
                              if (realIndex >= filtered.length) {
                                realIndex = filtered.length - 1;
                              }

                              final pData = filtered[realIndex];
                              final img = pData['imageUrl'] ?? '';
                              
                              return GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => SingleReelScreen(
                                        initialIndex: realIndex,
                                        allDocs: filtered,
                                      ),
                                    ),
                                  );
                                },
                                child: Container(
                                  color: AppColors.surfaceElevated,
                                  child: img.startsWith('http')
                                      ? GlobalCachedImage(imageUrl: img, fit: BoxFit.cover)
                                      : Image.file(File(img), fit: BoxFit.cover),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
