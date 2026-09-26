# Pro Earn — genuine ad-revenue-share setup

Replaces the old `₹0.03 per get` formula with a real, auditable model:
**40% of actual AdMob rewarded-ad revenue**, split among creators by their
share of rewarded-ad completions in each settlement period. Banner ad
revenue is never touched — that stays 100% platform's, by design (rewarded
ad unit IDs are the only ones counted).

## New pieces

| Piece | What it does |
|---|---|
| `rewarded_completions` table | One row per `onUserEarnedReward` event, server-attributed to the post's real owner |
| `settle-revenue` function | Scheduled job — pulls real revenue from AdMob Reporting API, credits `payout_balances` |
| `payout_balances` table | Each creator's real, settled balance — nothing derived from client-reported numbers |
| `log-reward-completion` function | Client calls this right after a reward fires; looks up the post owner server-side |
| `request-payout` (updated) | Now pays from `payout_balances` via real RazorpayX UPI transfer, not a formula guess |

## 1. Run the schema

```
supabase/functions and supabase_schema_revenue_share.sql — run this in the
SQL editor after the base supabase_schema.sql.
```

## 2. One-time AdMob OAuth setup (required — AdMob API can't use a plain service account)

1. In Google Cloud Console, create an OAuth 2.0 Client ID (type: Desktop app) for the project tied to your AdMob account.
2. Using the OAuth Playground (or any OAuth flow) with scope `https://www.googleapis.com/auth/admob.readonly`, sign in **as the AdMob account owner** once and get a refresh token.
3. Find your AdMob publisher ID (format `pub-XXXXXXXXXXXXXXXX`) in AdMob → Settings.

## 3. Deploy functions

```bash
supabase functions deploy log-reward-completion
supabase functions deploy settle-revenue
supabase functions deploy request-payout
```

## 4. Set secrets

```bash
supabase secrets set \
  ADMOB_CLIENT_ID=<oauth-client-id> \
  ADMOB_CLIENT_SECRET=<oauth-client-secret> \
  ADMOB_REFRESH_TOKEN=<refresh-token-from-step-2> \
  ADMOB_PUBLISHER_ID=pub-XXXXXXXXXXXXXXXX \
  REWARDED_AD_UNIT_IDS=ca-app-pub-xxxx/1111111111 \
  CRON_SECRET=<random-long-string> \
  RAZORPAY_KEY_ID=<razorpayx-key-id> \
  RAZORPAY_KEY_SECRET=<razorpayx-key-secret> \
  RAZORPAY_ACCOUNT_NUMBER=<razorpayx-business-account-number>
```

`REWARDED_AD_UNIT_IDS` can be a comma-separated list if you add more than
one rewarded placement later.

## 5. Schedule settle-revenue

Supabase → Edge Functions → your project → Cron, or an external cron
(GitHub Actions, cron-job.org) hitting the function URL weekly with header
`x-cron-secret: <CRON_SECRET>`. Body is optional — defaults to the trailing
7 days if you don't pass `periodStart`/`periodEnd`.

## 6. Client-side: add a real Rewarded ad + log the completion

The current app only has Banner and Interstitial ads — there's no Rewarded
ad unit yet, so this is the one piece that isn't purely server-side: you
need an actual rewarded placement for `settle-revenue` to have anything to
attribute. Add this to `lib/service.dart` alongside the existing ad code:

```dart
import 'package:google_mobile_ads/google_mobile_ads.dart';

RewardedAd? _rewardedAd;

void loadRewardedAd({required String adUnitId}) {
  RewardedAd.load(
    adUnitId: adUnitId, // your REAL rewarded ad unit ID — must match
                         // REWARDED_AD_UNIT_IDS on the server exactly
    request: const AdRequest(),
    rewardedAdLoadCallback: RewardedAdLoadCallback(
      onAdLoaded: (ad) => _rewardedAd = ad,
      onAdFailedToLoad: (error) => _rewardedAd = null,
    ),
  );
}

Future<void> showRewardedAd({
  required String postId,
  required String adUnitId,
}) async {
  if (_rewardedAd == null) return;
  _rewardedAd!.show(
    onUserEarnedReward: (ad, reward) async {
      // This is the ONLY place a completion gets logged — never log on
      // ad load, ad shown, or ad clicked, only on the actual earned-reward
      // callback, so the server-side count matches what AdMob itself paid for.
      await Supabase.instance.client.functions.invoke(
        'log-reward-completion',
        body: {'postId': postId, 'adUnitId': adUnitId},
      );
    },
  );
  _rewardedAd = null; // a used RewardedAd instance can't be shown again — reload before next use
}
```

Call `showRewardedAd` wherever the "watch an ad to support this creator /
unlock something" action lives in the feed — that UX decision is unchanged,
only the plumbing behind it is new.

## What this fixes vs. the old model

- Payout amount is now bounded by real AdMob revenue, not a client-visible
  fixed rate — nothing to reverse-engineer or farm for a guaranteed payout.
- Creator A vs creator B split by rewarded-ad completions, not raw "gets" —
  a creator with more likes but fewer ad views no longer out-earns one with
  fewer likes but more actual ad revenue behind them.
- `request-payout` now performs a real UPI transfer via RazorpayX instead of
  inserting a row nobody ever fulfills.
- Minimum withdrawal dropped from an unreachable $100 to $5 as a starting
  point — revisit this once you have a few real settlement periods of data
  on what a typical creator's share actually looks like; set it too low and
  RazorpayX per-payout fees eat the transfer, too high and it's the same
  "nobody ever cashes out" problem as before.
