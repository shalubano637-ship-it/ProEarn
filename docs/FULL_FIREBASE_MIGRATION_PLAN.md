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
