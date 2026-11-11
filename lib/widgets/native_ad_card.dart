import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../ad_free_access.dart';
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
    AdFreeAccess.active.addListener(_onEntitlementChanged);
    if (!AdFreeAccess.isActive) _loadAd();
  }

  void _onEntitlementChanged() {
    if (AdFreeAccess.isActive) {
      _nativeAd?.dispose();
      _nativeAd = null;
      _loaded = false;
    } else if (_nativeAd == null) {
      _loadAd();
    }
    if (mounted) setState(() {});
  }

  void _loadAd() {
    if (AdFreeAccess.isActive || _nativeAd != null) return;
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
          if (!mounted || AdFreeAccess.isActive) {
            ad.dispose();
            return;
          }
          setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('Native ad failed to load: $error');
          ad.dispose();
          if (identical(_nativeAd, ad)) _nativeAd = null;
          if (mounted && !AdFreeAccess.isActive) {
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
    AdFreeAccess.active.removeListener(_onEntitlementChanged);
    _nativeAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (AdFreeAccess.isActive) return const SizedBox.shrink();
    if (_nativeAd == null || !_loaded) return SizedBox(height: widget.height);
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: AdWidget(ad: _nativeAd!),
    );
  }
}
