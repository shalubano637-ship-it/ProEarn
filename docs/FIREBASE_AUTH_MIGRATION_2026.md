# Firebase Authentication Migration (2026)

Status: migration work branch created; production authentication remains on Supabase.

## Scope approved
- Move email/password and Google authentication to Firebase Authentication.
- Keep Supabase Postgres, RLS, Storage, Realtime, Edge Functions, billing, and existing app data.
- Do not migrate to Firestore or Firebase Storage.
- Do not change `main`, deploy production services, or upload to Google Play during this work.

## Verified starting point
- Android application ID: `com.prosn.app`.
- Firebase project configured in the repository: `proearn-6acdd`.
- Supabase project: `mltvpfqfhbhgkejcjpmq`.
- `lib/main.dart` initializes Supabase and Firebase Core/Messaging.
- `lib/auth_screen.dart` still uses Supabase Auth for email/password, Google OAuth, password reset, auth-state changes, and email confirmation.
- The current app uses the authenticated user ID directly as a UUID in Postgres and relies on `auth.uid()` in RLS.
- Existing Supabase Auth user count was reported as zero in the earlier migration discovery, but this must be rechecked immediately before cutover.
- Current live database inspection found the `public.users.referredBy -> public.users.uid` self-reference; it did not find the previously expected foreign keys from the user/billing tables to `auth.users`. This difference must be reconciled against all schema migrations and RLS policies before cutover.

## Critical identity design
A normal Firebase client signup creates a Firebase UID that is not guaranteed to be a UUID. The current Postgres schema and RLS rely on UUID identity, so simply adding `firebase_auth` and replacing the login buttons is unsafe.

The intended bridge is:
1. A trusted Firebase callable function creates a Firebase user with a server-generated UUID as its UID.
2. The function assigns the Supabase-compatible `role: authenticated` custom claim.
3. It returns a Firebase custom token. The client signs in with that token.
4. The Flutter Supabase client obtains the Firebase ID token through its supported access-token callback.
5. Supabase validates the Firebase project as a third-party auth provider. Verify `iss`, `aud`, `sub`, expiry, and the `role` claim.
6. RLS and all backend authorization continue to use the stable UUID. No client-supplied UID/email is trusted.

Email/password provisioning and Google account linking need separate, tested flows. A matching email alone must never silently merge two identities.

## Required implementation phases

### Phase A — inventory and compatibility
- Recheck live `auth.users` count and all application user/billing rows.
- Enumerate every use of Supabase Auth, `auth.uid()`, auth triggers, policies, RPCs, Edge Functions, Realtime, and Storage.
- Review account deletion, FCM ownership, ban checks, terms acceptance, referral attribution, and Play Billing ownership.
- Preserve the current Supabase auth path until the Firebase bridge is ready.

### Phase B — trusted identity bridge
- Implement Firebase callable provisioning with server-generated UUID UIDs.
- Implement password signup/login and verified Google sign-in/account linking without trusting client identity claims.
- Assign and refresh the `role: authenticated` custom claim.
- Add emulator/unit tests for duplicate email, invalid/expired Google tokens, wrong OAuth audience, partial failures, retries, and account-link conflicts.

### Phase C — Supabase third-party JWT
- Configure Firebase as a third-party auth provider in the Supabase project.
- Configure the Flutter Supabase client to use the current Firebase ID token.
- Validate PostgREST, Storage, Realtime, RPC, and Edge Function JWT handling with Firebase tokens.
- Confirm that every relevant policy sees the expected UUID from `auth.uid()`.

### Phase D — app integration
- Replace Supabase Auth calls in the login/signup, verification, reset-password, splash/session restore, and sign-out flows.
- Preserve terms acceptance, referral code, username validation, moderation/ban checks, FCM token linking, and account deletion.
- Update every Edge Function that calls Supabase `auth.getUser()` or assumes a Supabase Auth user.
- Keep Supabase database and all existing data in place.

### Phase E — test and cutover
- Run static analysis, unit tests, Firebase emulator tests, and a debug APK build.
- Test two-account RLS isolation, profile creation, Google login, email verification, password reset, FCM, subscriptions/purchases, and complete account deletion.
- Test rollback to the current Supabase Auth build.
- Only after all gates pass, make Firebase Auth the default in a test APK. Keep Play Store upload disabled unless explicitly requested.

## Current blocker / required console access
Repository tools can edit code, but they do not provide Firebase Console access to enable Authentication providers, deploy Cloud Functions, or configure Supabase third-party Firebase JWT trust. Those steps must be performed through authorized project access or manually in the consoles. Do not claim Firebase Auth is active until these are verified.

## Safety rule
Do not delete Supabase Auth users, remove Supabase Auth dependencies, change production RLS policies, deploy functions, or cut over `main` as part of the initial migration PR. Keep all work isolated on `feature/firebase-auth-migration-2026`.
