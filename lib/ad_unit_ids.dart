// =============================================================================
// PRO EARN — AdMob ad unit IDs (single source of truth)
// -----------------------------------------------------------------------------
// Android-only (this app no longer targets iOS — see removed /ios folder).
//
// Previously these were hardcoded as raw string literals in 11 different
// places across social_feed.dart and user_profile_features.dart — same
// value copy-pasted repeatedly, with no single place to swap test IDs for
// production ones before release.
//
// *** ALL VALUES BELOW ARE GOOGLE'S PUBLIC TEST AD UNIT IDS ***
// They must be replaced with your real production ad unit IDs (AdMob
// dashboard → Apps → Ad units) before this app is uploaded to Play Store —
// shipping test IDs to production means either no real ads serve, or an
// AdMob policy strike if mixed incorrectly with a real App ID.
//
// REWARDED is the ad unit counted by the server-side revenue-share
// settlement (see REWARDED_AD_UNIT_IDS in settle-revenue). If you change
// this, update that secret too, on both sides, or settlement will
// attribute zero revenue to real rewarded views.
// =============================================================================

class AdUnitIds {
  AdUnitIds._();

  static const String banner = 'ca-app-pub-3940256099942544/6300978111';
  static const String interstitial = 'ca-app-pub-3940256099942544/1033173712';
  static const String rewarded = 'ca-app-pub-3940256099942544/5224354917';
}

