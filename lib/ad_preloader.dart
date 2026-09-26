// =============================================================================
// PRO EARN — Rewarded ad preloader
// -----------------------------------------------------------------------------
// Every "watch an ad" button used to call RewardedAd.load() only at the
// moment the user opened that specific sheet/button, so there was always
// a load delay right when they wanted to watch — sometimes a few seconds,
// sometimes it just wasn't ready yet. This keeps ONE ad preloaded in the
// background at all times (started at app launch — see main.dart — and
// re-started immediately every time the current one is consumed), so by
// the time someone taps "watch ad" it's normally already sitting there
// ready to show.
//
// Used by: chat_gift_sheet.dart, get_prompt_button.dart, chests_page.dart.
// =============================================================================

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'ad_unit_ids.dart';

class RewardedAdPreloader {
  RewardedAdPreloader._();

  static RewardedAd? _ad;
  static bool _isLoading = false;

  static bool get isReady => _ad != null;

  /// Safe to call as often as you like (app start, resuming a screen,
  /// after consuming the current ad) — it's a no-op if a load is already
  /// in flight or an ad is already sitting ready.
  static void preload() {
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

  /// Hands over the currently-preloaded ad (if any) for the caller to
  /// `.show()`, and immediately kicks off loading the next one so
  /// there's minimal downtime before the button is usable again.
  static RewardedAd? takeReadyAd() {
    final ad = _ad;
    _ad = null;
    preload();
    return ad;
  }
}
