# Pro Earn — everything changed in this review, indexed

## SQL — all patches merged into one file

`supabase_schema_ALL_PATCHES.sql` — run once, top to bottom, in the
Supabase SQL Editor, after the original `supabase_schema.sql`. Contains
all 9 patches in the correct dependency order (numbered section headers
inside the file):

1. Revenue-share tables (rewarded_completions, payout_balances, revenue_settlements, creator_payout_accounts)
2. Security hardening (posts/users column GRANTs, admins table, atomic payout claim/refund)
3. Text moderation (blocklist trigger on posts/comments)
4. Pre-auth data-leak fix (email_is_registered / lookup_account_for_reset RPCs)
5. public_profiles view — final version (safe columns + followers/following)
6. Admin monetization-approval RPC fix (set_monetization_status)
7. Follow/unfollow rate limiting (follow_action_log)
8. Terms-acceptance tracking
9. Tighten users_select_all — the section that actually closes the original PII exposure; only correct once the app is deployed with all the public_profiles-based reads from this session

## Edge functions (supabase/functions/)

- `log-reward-completion/` — new. Logs rewarded-ad completions server-side, attributed to the real post owner
- `settle-revenue/` — new. Periodic job: pulls real AdMob rewarded-ad revenue, credits payout_balances
- `request-payout/` — rewritten. Pays from payout_balances via RazorpayX, atomic claim to prevent double-payout
- `delete-account/` — new. Deletes all user-owned data + the auth account (Play Store Account Deletion requirement)

Unmodified, not included here: `check-image-safety`, `imgbb-upload`, `notify`, `send-otp`, `verify-otp`.

## Dart source (lib/)

New files: `legal_text.dart`, `ad_unit_ids.dart`, `utils.dart`
Modified: `main.dart`, `auth_screen.dart`, `social_feed.dart`, `user_profile_features.dart`, `service.dart`, `models.dart`
Unmodified, not included here: `navigation_shell.dart`, `theme/*.dart`

## Tests (test/)

- `utils_test.dart` — new. First tests in the project.

## Config

- `pubspec.yaml` — package name lowercased, shared_preferences removed, sentry_flutter added, iOS icon gen disabled
- `android/app/build.gradle.kts` — proper release signingConfig template (key.properties-based)
- `android/app/src/main/AndroidManifest.xml` — removed ACCESS_FINE_LOCATION, usesCleartextTraffic

## Docs

- `REVENUE_SHARE_SETUP.md`, `SECURITY_SETUP.md`, `SENTRY_SETUP.md` — setup guides for the above
- `delete-account-request.html` — web deletion-request page (**still needs a real backend wired in** — currently browser-only confirmation, see TODO in the file)

## Also removed this session (not in this package, since there's nothing to deliver)

- `/ios` folder — app is Android-only now
- `currentUserPassword` global variable
- Dead `fetchPostsFromCloudFirestore()` function
