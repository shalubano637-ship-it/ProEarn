# ProSN Full Supabase-to-Firebase Migration

Status: planning and repository discovery. No production cutover has been performed.

## Target architecture
- Firebase Authentication for email/password, verification, reset, Google sign-in, sessions, and linking.
- Cloud Firestore as the primary application database.
- Firebase Storage for suitable user media, after inventorying Cloudflare R2 and ImgBB dependencies.
- Cloud Functions (2nd gen) for trusted operations, moderation, notifications, payout requests, OTP, account deletion, rewards, and Play Billing verification.
- Deny-by-default Firestore Security Rules; admin status must come from trusted server-managed claims or protected records.
- Firebase Cloud Messaging retained, with token ownership moved to Firebase Auth.
- Evaluate Firebase App Check for supported endpoints and services.

## Current verified state
- Android application id: com.prosn.app. Firebase project: proearn-6acdd.
- Flutter currently includes Firebase Core and Firebase Messaging. The inspected pubspec does not include firebase_auth, cloud_firestore, firebase_storage, or cloud_functions.
- lib/main.dart initializes Supabase and calls the Supabase lifecycle RPC clear_my_conversations. Firebase is currently initialized for Android messaging after Supabase initialization.
- Authentication, profile, ban, FCM, billing, and lifecycle code still depend on Supabase.
- The live Supabase project has 12 active Edge Functions: imgbb-upload, notify, request-payout, verify-otp, send-otp, delete-account, delete-account-request, publish-app-update, voice-message, r2-upload, admin-moderate-report, and play-billing.
- The schema is relational and contains foreign keys. The only auth test account was previously deleted, and key user/billing tables were empty at that check. This does not prove every table or external media bucket is empty.
- Security Advisor previously reported 17 public tables with RLS enabled but no policies, a SECURITY DEFINER public_profiles view, 9 SECURITY DEFINER functions executable by anon, and 79 executable by authenticated. Review each access pattern; do not bulk-copy Supabase permissions into Firebase Rules.
- Existing billing ownership uses UUIDs and Supabase auth.uid(). Define an immutable Firebase UID strategy before implementation.

## Firestore data model proposal
Use Firebase Auth UID as document identity. Use deterministic document IDs and bounded subcollections; do not store unbounded follower, like, member, or message arrays.

Suggested collections, subject to full call-site inventory:
- users/{uid}: public profile fields only; keep private settings and sensitive metadata separate.
- userPrivate/{uid}: private account settings.
- posts/{postId}, with comments as a subcollection or a separately indexed collection.
- follows/{uid}/following/{targetUid}, plus a reverse follower index if required.
- blocks/{uid}/users/{blockedUid}.
- reports/{reportId} and moderationActions/{actionId}, with moderation writes restricted to trusted backend.
- conversations/{conversationId}/messages/{messageId}, plus messageRequests.
- rooms/{roomId}, roomEntries, and roomFavorites.
- wallets/{uid}, walletLedger/{entryId}, gifts, and rewards. All balance changes must be server-side transactions with an immutable ledger.
- referrals and referralRewards.
- billingPurchases/{purchaseTokenHash}, subscriptions/{uid}, and subscriptionClaims. Verify Play purchase tokens server-side before granting entitlements.
- appConfig for admin-managed configuration.
- notificationInbox/{uid}/items/{notificationId}; server-side FCM delivery.

Validate Firestore limits, query indexes, pagination, fanout costs, retention, and privacy per collection. Never duplicate sensitive profile data into public documents.

## Migration workstreams

### 1. Complete code inventory
Search Dart, native Android, SQL/migrations, Edge Functions, and CI/config for Supabase Auth/session APIs, PostgREST reads/writes, RPCs, realtime channels, storage buckets, triggers, views, policies, privileged functions, scheduled jobs, environment variables, and all media URL formats. Produce a call-site-to-Firebase mapping and acceptance test for every use.

### 2. Firebase project readiness
Confirm project access and configure Auth providers, Android SHA fingerprints, Firestore location, Storage bucket, Functions region/runtime, billing, App Check, service accounts, APIs, secrets, and separate dev/staging/prod environments. Secrets belong in Secret Manager or function secrets, never Git.

### 3. Authentication
Implement Firebase Auth signup, verification, login, Google sign-in, safe provider linking, password reset, session restoration, logout, and account deletion. Preserve existing validation and error states. Test before removing Supabase Auth.

### 4. Database and rules
Implement Firestore repositories, indexes, and deny-by-default rules. Add emulator tests for anonymous, owner, other-user, blocked-user, and admin access. Implement wallet, reward, referral, and billing mutations as trusted server-side transactions. Clients must not grant themselves admin privileges or modify balances.

### 5. Backend functions
Port all 12 active Edge Functions by behavior, not name alone. Verify caller identity and authorization inside every function. Use idempotency keys for payments, rewards, and notification workflows. Keep payouts and Play Billing verification server-side. Add OTP rate limiting and safe deletion semantics.

### 6. Storage and media
Inventory Supabase Storage, R2, ImgBB, and remote media references. Choose a retention or migration policy for each. Copy objects with integrity checks and preserve or redirect URLs where feasible. Enforce content type, size, ownership, and moderation constraints.

### 7. Data migration
Take a verified Supabase database backup and enumerate all rows and storage objects. Export relational data, transform to Firestore documents, preserve IDs/timestamps/relationships, validate counts and checksums, and test import in a non-production Firebase project first. Do not infer that all data is empty from auth table counts.

### 8. Cutover and rollback
Use staging first. Freeze writes for final export, import, verify counts, deploy rules/functions, build a test APK, and run acceptance tests. Keep Supabase intact and read-only during a rollback window. Disable Supabase only after explicit sign-off and a successful Firebase-only release.

## Required acceptance tests
- Signup, verification, login, Google sign-in, account linking, password reset, session restore, logout.
- Profile edit, avatar upload, post/reel upload, feed pagination.
- Follow/unfollow, block/unblock, follower/following visibility, report and admin moderation.
- Comments, likes, notifications, messaging, voice messages, rooms and membership.
- Wallet, coin purchases, gifts, rewards, referrals, weekly/monthly passes, restore purchases, duplicate/replayed purchase tokens.
- Payout authorization and audit trail.
- FCM registration, token refresh, preferences.
- Account deletion across Firestore, Storage, Auth, and external media.
- Security Rules tests prove users cannot access another user's private data or grant themselves admin/coins.
- Offline/retry behavior, pagination, performance, crash-free startup, rollback.

## Safety gates
- Do not delete, pause, or modify Supabase during development.
- Do not deploy untested rules/functions to production.
- Do not remove Supabase dependencies or change app startup until Firebase replacements compile and pass tests.
- Do not claim migration or APK completion until a Firebase-only build is installed and all acceptance tests pass.
- Do not upload to Google Play; requested deliverable is a test APK only.
- Firebase Console configuration and deployment require authorized project access. If unavailable through connected tools, provide exact manual setup steps rather than claiming those changes were made.


## Initial file-by-file dependency inventory (verified from branch source)

This is a concrete first pass, not yet a complete repository-wide inventory. Search indexing did not return code matches, so additional Dart files, Android sources, SQL migrations, and function source folders still need enumeration before implementation.

| File | Current Supabase dependency | Firebase replacement required |
|---|---|---|
| `pubspec.yaml` | `supabase_flutter` present; Firebase Core/Messaging only | Add and pin Auth, Firestore, Storage, Functions packages only when their adapters are ready; retain Supabase temporarily |
| `lib/main.dart` | Initializes Supabase; lifecycle calls `clear_my_conversations` RPC; app startup assumes Supabase initialization | Initialize Firebase before Firebase-backed services; replace lifecycle RPC with tested Cloud Function/Firestore operation; remove Supabase startup only at cutover |
| `lib/auth_screen.dart` | Supabase email/password, OAuth Google, password reset, auth-state stream, email-confirmation fields, user table terms lookup/update | Firebase Auth email/password, verification, Google credential flow, reset, auth-state stream; Firestore terms acceptance; test provider linking |
| `lib/fcm_service.dart` | Reads Supabase current user/auth stream and writes FCM token/preferences to `users` | Firebase Auth UID and Firestore token/preferences; token cleanup on sign-out/account switch |
| `lib/service.dart` | User creation/profile/ban reads and writes; `notify` Edge Function; Supabase-backed notification helper | Firestore repositories and authenticated callable/HTTPS Functions; server-enforced ban and notification authorization |
| `lib/play_billing_service.dart` | Supabase auth stream/current user; `play-billing` Edge Function; `claim_ad_free_daily_coins` RPC | Firebase Auth; callable Functions for offer eligibility, purchase verification, subscription refresh and daily claims; idempotent ledger |
| `lib/ad_free_access.dart` | Supabase user-row query and realtime stream for entitlement | Firestore entitlement document/stream; server-controlled expiry and no client-granted entitlement |
| `lib/chest_timer_service.dart` | Supabase auth, `chest_progress` reads, timer RPCs, `notify` Edge Function and notifications query | Firestore chest state and trusted Functions for start/sync/notification dedupe |
| `lib/cloudflare_media_service.dart` | Supabase access token authorizes Cloudflare gateway; `r2-upload` Edge Function uploads to R2 | Firebase ID token validation at gateway/Function; preserve R2 unless media-retention decision explicitly migrates it |
| `lib/models.dart` | Shared relational table-name constants and global user state; not itself a network client | Replace table constants with typed Firestore collection/repository definitions as call sites are migrated |
| `android/app/google-services.json` | No Supabase dependency; Firebase config includes project `proearn-6acdd` and package `com.prosn.app` | Verify Firebase Console Android app, OAuth clients, SHA-1/SHA-256 and downloaded config match release signing; never infer that config alone enables Auth/Firestore |

### Immediate implementation constraints
1. Billing cannot be ported as a simple table rename. Purchase token verification, replay protection, account ownership, first-purchase offer eligibility, subscription expiry, and coin ledger writes must be server-side and idempotent.
2. Cloudflare R2 is an active media path. Moving to Firebase Storage is a separate data migration; first replace the gateway's Supabase-token verification without changing stored media URLs.
3. Terms acceptance and ban checks are part of the auth gate. Do not remove those checks during Firebase Auth replacement.
4. Chest timers and notification deduplication have existing behavior and tests. Preserve their repository abstraction and add Firebase repository tests before swapping implementations.
5. The current Firebase config contains the correct `com.prosn.app` client entry, but this does not prove that Firestore, Storage, Functions, or Firebase Auth are provisioned or deployed.

## Next source files to inspect
- Remaining `lib/**` files for PostgREST, auth, realtime, RPC, and Edge Function call sites.
- `supabase/functions/**` and `supabase/migrations/**` for request contracts, schema, triggers, RLS, and scheduled work.
- Android manifest/Gradle and CI workflows for package, signing, build and Firebase configuration.


## Auth-flow deep inspection (2026-11-13)

The first UI cutover is blocked until profile provisioning and authorization are implemented. The inspected source confirms:

- `lib/auth_screen.dart` currently signs up with Supabase Auth metadata: `userName`, `termsAcceptedAt`, `termsVersion`, and uppercase `referralCode`. A Supabase database trigger is expected to create the `public.users` row.
- Email verification is polled by repeatedly calling Supabase `signInWithPassword`; resend uses Supabase `auth.resend(type: signup)`. Firebase must instead use the signed-in Firebase user, `sendEmailVerification()`, `reload()`, and Firebase verification state. Do not keep a password in a long-lived verification page as the new flow.
- Password reset currently uses Supabase `resetPasswordForEmail`; Google login currently uses Supabase OAuth redirect and an auth-state listener.
- `SplashPage` requires current terms acceptance and checks the ban flag before opening the app. The terms document is read from `users/{uid}`-equivalent data and updated on acceptance.
- `service.dart` repairs a missing user row, loads profile fields, and checks `isBanned` through Supabase. Its current ban-check error handling fails open; the Firebase implementation must not silently treat an unavailable authorization check as an allowed account.
- FCM currently depends on Supabase auth and the Supabase users row, so it cannot be considered migrated merely by switching Firebase Auth.

### Blocking Firebase prerequisites

- No `firebase.json` or `firestore.rules` was found at the repository root on this branch.
- No Firestore package or Firestore profile repository is present yet.
- Therefore there is no verified Firebase-side replacement for the Supabase user-creation trigger, profile document, terms acceptance, referral handling, or ban enforcement.
- Do not enable Firebase signup/login UI until Firestore is provisioned, deny-by-default rules and trusted profile/ban provisioning are deployed, and emulator tests cover owner/other-user/admin access.
- The current Firebase Auth adapter is isolated scaffolding only. It does not switch any app screen or alter Supabase behavior.


## Firebase profile adapter scaffold (2026-11-13)

Added on the migration branch:
- `cloud_firestore: ^5.6.12` dependency.
- `lib/firebase_profile_service.dart` with isolated profile ensure/load, current-terms read/write, and ban lookup methods.
- `firebase.json`, `firestore.rules`, and `firestore.indexes.json` so Firestore rules/index configuration has an explicit deployment manifest.
- Firestore rules currently deny every client read/write. This is intentional fail-closed scaffolding, not production-ready rules.

Important limitations:
- The new profile adapter is not called by app screens or startup. Supabase remains the active auth/database path.
- Profile creation currently uses a client transaction and is blocked by the deny-all rules until a reviewed provisioning design is implemented. It must not be treated as a trusted replacement for the Supabase signup trigger.
- `pendingReferralCode` is only an untrusted submitted value; a trusted backend must validate and apply referral attribution.
- Ban reads must fail closed at the app gate; a missing profile or Firestore error must never be interpreted as an unbanned account.
- Email is currently included in the private profile draft. Before enabling access, split public and private profile fields and write rules that prevent other users from reading private fields.
- No Firebase CLI deployment, Firestore database provisioning, emulator tests, Flutter dependency resolution, analyzer, APK build, or live Firebase Auth test has been performed in this step.

### Next safe implementation gate
Create a trusted Firebase provisioning function for new Auth users (profile creation, validated referral attribution, immutable moderation fields), add emulator-backed Security Rules tests, and only then connect the Firebase Auth UI. Do not deploy the deny-all rules to a live project if it would disrupt an already-used Firestore database; confirm the target Firebase project/database state first.


## Trusted Firebase profile provisioning scaffold (2026-11-13)

Added:
- `functions/` Node 20 TypeScript Firebase Functions package and build scripts.
- Callable `provisionMyProfile` in `functions/src/index.ts`.
- The callable requires Firebase Auth, derives UID/email from verified auth context, validates username/referral-code format, checks the submitted Terms version against server-owned `appConfig/legal`, and creates public `users/{uid}` and private `userPrivate/{uid}` records in one Admin SDK transaction.
- Server sets `isBanned: false`; the client cannot set that field through this endpoint. No coins, rewards, or referral credit are granted.
- Flutter adapter now calls the callable for profile provisioning. Direct client profile creation was removed.
- Added `cloud_functions` Flutter dependency and Firebase Functions codebase to `firebase.json`.

Deployment prerequisites:
1. Provision Firestore in the intended Firebase project.
2. Create `appConfig/legal` with the exact current `termsVersion` before signup is enabled.
3. Deploy the Functions code and deny-by-default Firestore rules from a trusted CI/developer environment.
4. Add emulator tests for unauthenticated calls, invalid username, missing/old Terms version, malformed referral code, idempotent retries, and attempts to write protected moderation fields.
5. Implement trusted profile/ban/terms read endpoints and a trusted terms re-acceptance endpoint before routing app gates to Firebase.

Limitations:
- No Firebase deployment or live test was performed. This environment has GitHub repository access but no Firebase project deployment credential/CLI execution path.
- Firestore rules remain deny-all. The new callable uses Admin SDK and can provision records despite those client rules, but app-side profile reads/ban checks remain unavailable until secure read rules or callables are added.
- The app UI and startup are still on Supabase. Do not switch signup/login yet.
- Terms acceptance is a client attestation; the callable verifies it matches the server-configured current version, but legal consent UI must remain explicit and auditable.


## Trusted account-state endpoints and rules tests (2026-11-13)

Added:
- `getMyAccountState`: authenticated callable returning only the caller's ban flag and current Terms acceptance state; private email/legal metadata are not returned.
- `acceptCurrentTerms`: authenticated callable that records explicit re-acceptance against the server-configured Terms version.
- Flutter profile adapter now uses callable endpoints for account-state and Terms operations. Ban-check errors propagate, so callers must fail closed.
- Firestore rules emulator tests assert that unauthenticated and authenticated clients cannot read/write `users` or `userPrivate`, cannot set moderation/admin fields, and that Admin SDK seeding is possible while client rules remain closed.
- Added rules-unit-testing dependencies and test script under `functions/package.json`.

Important:
- The rules tests have been authored but not executed in this environment; Firebase Emulator Suite and npm install/build are not available here.
- The rules remain deny-all intentionally. This is a safe pre-deployment posture, not the final app access policy.
- These endpoints are scaffolding only until the Firebase project is provisioned, the current Terms version is configured, Functions are deployed, and emulator/live tests pass.
- Do not wire the app's startup/login gates to these callables until these prerequisites and migration/rollback tests are complete.
