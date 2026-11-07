import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../theme/theme.dart';
import '../ad_unit_ids.dart';

/// In-feed sponsored placement. Full-screen interstitials must not interrupt
/// the vertical reels swipe flow.
class AdMobReelItem extends StatefulWidget {
  final VoidCallback onAdClosed;

  const AdMobReelItem({super.key, required this.onAdClosed});

  @override
  State<AdMobReelItem> createState() => _AdMobReelItemState();
}

class _AdMobReelItemState extends State<AdMobReelItem> {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _ad = BannerAd(
      adUnitId: AdUnitIds.banner,
      size: AdSize.mediumRectangle,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('In-feed ad failed to load: $error');
          ad.dispose();
          if (mounted) widget.onAdClosed();
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.overlay,
              borderRadius: AppRadius.smRadius,
            ),
            child: const Text(
              'Sponsored',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 12),
            ),
          ),
          if (_loaded && _ad != null)
            SizedBox(
              width: _ad!.size.width.toDouble(),
              height: _ad!.size.height.toDouble(),
              child: AdWidget(ad: _ad!),
            )
          else
            const SizedBox(
              width: 300,
              height: 250,
              child: Center(
                child: CircularProgressIndicator(color: AppColors.warning),
              ),
            ),
          const SizedBox(height: 12),
          const Text(
            'Swipe up to continue',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
