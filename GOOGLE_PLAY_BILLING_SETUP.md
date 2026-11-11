# Google Play Billing setup for ProSN

The app uses Google Play Billing for all coin packs and Ad-Free subscriptions. Product prices shown in the app are read from Google Play; the values below are the intended India pricing and must be configured in Play Console.

## Product catalogue

Create these as **one-time in-app products** (consumable):

| Product ID | Coins credited | Intended India price |
|---|---:|---:|
| `coins_100` | 100 | ₹9 |
| `coins_275` | 275 | ₹19 |
| `coins_700` | 700 | ₹39 |
| `coins_1700` | 1,700 | ₹79 |
| `coins_3800` | 3,800 | ₹149 |
| `coins_9200` | 9,200 | ₹299 |

Create these as **auto-renewing subscriptions**:

| Product ID | Base plan billing period | Intended India price |
|---|---|---:|
| `ad_free_weekly` | 1 week | ₹99 |
| `ad_free_monthly` | 1 month | ₹299 |

Use these exact product IDs. Configure the subscription base plans as auto-renewing. Activate all products and make them available in India. Google Play may require a published app bundle and tester accounts before products can be queried.

## Google Play Developer API credentials

1. In Google Play Console, open **Setup → API access** and link the Google Cloud project.
2. Create a Google Cloud service account and generate a JSON key.
3. Grant that service account access to this Play Console app with permissions to view app information and manage orders/subscriptions.
4. In Supabase Dashboard → Project Settings → Edge Functions → Secrets, add:
   - `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`: the complete service-account JSON file contents (keep it secret; never commit it).
   - `GOOGLE_PLAY_PACKAGE_NAME`: `com.prosn.app`.
5. The Supabase platform provides `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` to Edge Functions. Never put the service-role key or Google service-account JSON in the Flutter app.

The deployed `play-billing` Edge Function authenticates the signed-in user, verifies each purchase with Google Play Developer API, records the purchase token once, credits coins server-side, and consumes coin-pack purchases. Subscription entitlements are updated only after server verification.

## Testing

Do not test purchases from a sideloaded APK. Use a Play Store-installed internal test build signed with the same Play app signing identity.

1. Upload an AAB to an internal testing track.
2. Add tester Google accounts to the track and license testing.
3. Install the app from the Play Store opt-in link (not by sideloading).
4. Test each coin pack, both subscriptions, cancellation/expiry, restore, and duplicate purchase callbacks.
5. Confirm coin balances and subscription expiry in Supabase before production rollout.

## Important behavior

- Coin packs are consumable and are granted only once per unique Google purchase token.
- Weekly/monthly passes are auto-renewing Google Play subscriptions.
- Active passes suppress banner, native, and in-feed reel ads.
- An active pass can claim 150 coins once per India calendar day.
- The app refreshes a saved subscription with Google Play on startup and when the Coin Vault is opened.
- A Google Play Real-time Developer Notifications (RTDN) Pub/Sub endpoint is not configured yet. Startup/restore refresh keeps app entitlement current when the app is used; RTDN should be added before relying on immediate off-app cancellation/refund updates.
