import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../ad_unit_ids.dart';

/// Loads a platform-rendered Google native ad using the Android factory.
class NativeAdCard extends StatefulWidget {
  const NativeAdCard({super.key, this.height = 280, this.onFailed});

  final double height;
  final VoidCallback? onFailed;

  @override
  State<NativeAdCard> createState() => _NativeAdCardState();
}

class _NativeAdCardState extends State<NativeAdCard> {
  NativeAd? _nativeAd;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  void _loadAd() {
    final ad = NativeAd(
      adUnitId: AdUnitIds.native,
      factoryId: 'proEarnNative',
      request: const AdRequest(),
      nativeAdOptions: NativeAdOptions(
        adChoicesPlacement: AdChoicesPlacement.topRightCorner,
        mediaAspectRatio: MediaAspectRatio.any,
      ),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('Native ad failed to load: $error');
          ad.dispose();
          if (mounted) {
            setState(() => _nativeAd = null);
            widget.onFailed?.call();
          }
        },
      ),
    );
    _nativeAd = ad;
    ad.load();
  }

  @override
  void dispose() {
    _nativeAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_nativeAd == null && !_loaded) return SizedBox(height: widget.height);
    if (!_loaded) return SizedBox(height: widget.height);
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: AdWidget(ad: _nativeAd!),
    );
  }
}
