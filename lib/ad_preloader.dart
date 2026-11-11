
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'ad_unit_ids.dart';
import 'ad_free_access.dart';

class RewardedAdPreloader {
  RewardedAdPreloader._();

  static RewardedAd? _ad;
  static bool _isLoading = false;

  static bool get isReady => _ad != null;

  static void preload() {
    if (AdFreeAccess.isActive) return;
    if (_ad != null || _isLoading) return;
    _isLoading = true;
    RewardedAd.load(
      adUnitId: AdUnitIds.rewarded,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _ad = ad;
          _isLoading = false;
        },
        onAdFailedToLoad: (error) {
          debugPrint("RewardedAdPreloader: load failed — $error");
          _ad = null;
          _isLoading = false;
        },
      ),
    );
  }

  static RewardedAd? takeReadyAd() {
    if (AdFreeAccess.isActive) {
      _ad?.dispose();
      _ad = null;
      return null;
    }
    final ad = _ad;
    _ad = null;
    preload();
    return ad;
  }
}
