import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../ad_free_access.dart';
import '../ad_unit_ids.dart';

/// A reserved, non-overlapping banner placement for secondary screens.
class AdBannerSlot extends StatefulWidget {
  const AdBannerSlot({super.key});

  @override
  State<AdBannerSlot> createState() => _AdBannerSlotState();
}

class _AdBannerSlotState extends State<AdBannerSlot> {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    AdFreeAccess.active.addListener(_onEntitlementChanged);
    if (!AdFreeAccess.isActive) _loadAd();
  }

  void _onEntitlementChanged() {
    if (AdFreeAccess.isActive) {
      _ad?.dispose();
      _ad = null;
      _loaded = false;
    } else if (_ad == null) {
      _loadAd();
    }
    if (mounted) setState(() {});
  }

  void _loadAd() {
    if (AdFreeAccess.isActive || _ad != null) return;
    _ad = BannerAd(
      adUnitId: AdUnitIds.banner,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted || AdFreeAccess.isActive) {
            ad.dispose();
            return;
          }
          setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('Banner placement failed: $error');
          ad.dispose();
          if (identical(_ad, ad)) _ad = null;
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    AdFreeAccess.active.removeListener(_onEntitlementChanged);
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (AdFreeAccess.isActive || !_loaded || _ad == null) {
      return const SizedBox.shrink();
    }
    return SafeArea(
      top: false,
      child: SizedBox(
        width: _ad!.size.width.toDouble(),
        height: _ad!.size.height.toDouble(),
        child: AdWidget(ad: _ad!),
      ),
    );
  }
}
