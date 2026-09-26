// =============================================================================
// PRO EARN — Feed: AdMobReelItem (native ad card in the reel feed)
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

// ---- Flutter framework ----
import 'package:flutter/material.dart';

// ---- Third-party packages ----
import 'package:google_mobile_ads/google_mobile_ads.dart';

// ---- App files (split out of the original single-file main.dart) ----
import '../theme/theme.dart';
import '../ad_unit_ids.dart';



class AdMobReelItem extends StatefulWidget {
  final VoidCallback onAdClosed; // रील बदलने के लिए कॉलबैक

  const AdMobReelItem({super.key, required this.onAdClosed});

  @override
  State<AdMobReelItem> createState() => _AdMobReelItemState();
}
class _AdMobReelItemState extends State<AdMobReelItem> {
  InterstitialAd? _interstitialAd;
  bool _isAdLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadInterstitialAd();
  }

  void _loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: AdUnitIds.interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          setState(() {
            _interstitialAd = ad;
            _isAdLoaded = true;
          });
          _showAdIfReady();
        },
        onAdFailedToLoad: (error) {
          debugPrint('Interstitial Ad failed to load: $error');
          // अगर ऐड लोड होने में फेल हो जाए, तो भी अगली रील पर मूव कर जाएं
          widget.onAdClosed();
        },
      ),
    );
  }

  void _showAdIfReady() {
    if (_interstitialAd == null) return;

    _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        // जैसे ही यूजर कट बटन दबाएगा, यह कॉलबैक अगली रील पर ले जाएगा
        widget.onAdClosed();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        widget.onAdClosed();
      },
    );

    _interstitialAd!.show();
    _interstitialAd = null;
  }

  @override
  void dispose() {
    _interstitialAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: AppColors.warning),
                SizedBox(height: 16),
                Text(
                  "Loading Sponsored Reel...",
                  style: TextStyle(color: AppColors.textTertiary, fontSize: 14),
                ),
              ],
            ),
          ),
          Positioned(
            top: 50,
            left: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.overlay,
                borderRadius: AppRadius.smRadius,
              ),
              child: const Text(
                "Sponsored Ad",
                style: TextStyle(color: AppColors.textPrimary, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
