

import 'package:flutter/material.dart';

import 'package:google_mobile_ads/google_mobile_ads.dart';

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
