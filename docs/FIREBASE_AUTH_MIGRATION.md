# Firebase Authentication Migration

## Goal
Move ProSN sign-in to Firebase Authentication while retaining Supabase Postgres, RLS, Storage, Realtime, RPCs, Edge Functions, and billing data APIs.

Work only on `feature/firebase-auth-migration`. Do not merge to `main` until the migration is deployed and end-to-end verified.

## Confirmed project configuration
- Repository: `shalubano637-ship-it/ProEarn`
- Android application ID: `com.prosn.app`
- Firebase project ID (from the committed `google-services.json`): `proearn-6acdd`
- Supabase project: `mltvpfqfhbhgkejcjpmq`
- Firebase Email/Password and Google providers were reported enabled by the owner.
- The `com.prosn.app` Android OAuth client is present in `android/app/google-services.json`; its SHA-1 matches the certificate fingerprint supplied by the owner.
- SHA-256 must also be registered in Firebase Console > Project settings > Your apps > Android app.

## Live database cleanup
The owner explicitly confirmed all 8 Supabase Auth users were their own test accounts and asked for deletion.
- Deleted all 8 rows from `auth.users`.
- Verified `auth.users = 0` and `public.users = 0`.
- Verified dependent test data was cascaded away, including messages, notifications, gifts, conversations, rooms, and purchase/subscription rows.
- This was a live, irreversible deletion. There are currently no existing user accounts to migrate.

## Important current architecture
The Flutter client currently uses Supabase Auth throughout the app:
- `lib/auth_screen.dart`: email/password login and signup, Google OAuth, password reset, email verification, and session restoration.
- `lib/main.dart`: Supabase session initialization and startup/lifecycle checks.
- `lib/service.dart`: profile loading, user ID, ban checks, and account state.
- `lib/fcm_service.dart`: listens to Supabase Auth and stores FCM tokens under `public.users.uid`.
- `supabase/functions/delete-account/index.ts`: validates a Supabase Auth bearer token and deletes the Supabase Auth user.
- Numerous RLS policies and RPCs use `auth.uid()`.

The current profile and billing schema has foreign keys to `auth.users`:
- `public.users.uid -> auth.users.id`
- `play_purchase_events.user_id -> auth.users.id`
- `play_subscriptions.user_id -> auth.users.id`
- `play_subscription_daily_claims.user_id -> auth.users.id`

The profile UID columns are UUIDs. PostgreSQL's `auth.uid()` returns a UUID, so a normal Firebase-generated 28-character UID cannot be used as the app's database identity. Do not directly enable Firebase client signup or Google sign-in before resolving this.

## Required target identity design
Use a server-controlled UUID as the Firebase UID so Firebase JWT `sub` remains compatible with `auth.uid()` and the existing UUID profile references.

A trusted server-side provisioning layer must:
1. Create Firebase Auth users with a UUID UID using Firebase Admin SDK. The mobile app must never receive Admin credentials.
2. Set Firebase custom claim `role: authenticated` on every user so Supabase assigns the Postgres `authenticated` role.
3. Create the matching `public.users` profile row using a server-side Supabase service-role client. Preserve the same UUID in all app records.
4. For Google sign-in, verify the Google identity server-side and associate/link it to the server-created Firebase account. Never trust an email string supplied by the client alone.
5. Support account deletion through a trusted server flow that validates the Firebase token, removes app data/media, and deletes the Firebase user.

The database foreign keys to `auth.users` must be addressed deliberately. Since Firebase is the new identity provider, the likely end state is to remove only the four app-level foreign keys listed above after the server provisioning and deletion flows are implemented and tested. Do not change these constraints yet. Do not write to Supabase's protected `auth` schema directly.

## Supabase Firebase integration
Official Supabase documentation:
- Firebase integration: https://supabase.com/docs/guides/auth/third-party/firebase-auth
- Third-party Auth overview: https://supabase.com/docs/guides/auth/third-party/overview

Required project setup:
1. In Supabase Dashboard > Authentication > Third-Party Auth, add Firebase project `proearn-6acdd`.
2. Ensure the server provisioning flow adds `role: authenticated` to all Firebase ID tokens.
3. Initialize the Flutter Supabase client with the Firebase ID token as its `accessToken` callback. Do not use a global static Authorization header.
4. Verify a Firebase token reaches Supabase and that `auth.uid()` equals the UUID Firebase UID before enabling app traffic.

For a hosted Supabase project, the Firebase project integration validates the configured Firebase project. Continue to audit existing RLS policies and RPC authorization; the third-party integration does not replace app-level authorization.

## Client migration requirements
After the backend and database identity layer are ready:
- Add and pin `firebase_auth` and a supported Google Sign-In package; commit the lockfile.
- Initialize Firebase before constructing the Supabase client, on every supported platform.
- Configure Supabase Flutter `accessToken` to return `FirebaseAuth.instance.currentUser?.getIdToken()`.
- Replace Supabase Auth calls in splash/session restore, email/password signup/login, Google sign-in, password reset, email verification, and logout.
- Update FCM account observation and token save/unlink to use Firebase Auth UID.
- Update account deletion to use the Firebase-aware trusted endpoint.
- Preserve terms acceptance, ban checks, admin authorization, profile creation, referrals, notifications, billing, and all existing app flows.
- Remove the legacy Supabase OAuth callback only after Firebase Google sign-in works on the actual Android package.

## Verification gates
Do not call the migration complete or build a release APK until all pass:
- Firebase Email/Password signup and login produce UUID UIDs.
- Email verification and password reset work.
- Google sign-in securely links to a UUID Firebase account.
- Firebase JWT has `role: authenticated`, correct issuer/audience, and is accepted by Supabase.
- `auth.uid()` equals the Firebase UID and RLS blocks cross-user access.
- New profile creation, profile reads/updates, posts, follows, blocks, chats, gifts, coins, rooms, notifications, storage, Realtime, RPCs, Edge Functions, and admin checks work.
- FCM token save, refresh, unlink, and sign-out work.
- Account deletion removes all app data/media and the Firebase account.
- Play Billing purchase, subscription, restore, and claim flows still work.
- Cold start, app restart, token refresh, banned account, and sign-out tests pass.

## Current status
- Branch and migration plan exist.
- Android Firebase config is committed.
- Supabase test accounts have been deleted as requested.
- Firebase project ID confirmed: `proearn-6acdd`.
- No Flutter auth code has been switched yet.
- No production database constraints have been changed.
- The server-side UUID provisioning layer and Supabase third-party integration are still prerequisites. A client-only cutover would break identity/RLS and is intentionally not being made.
