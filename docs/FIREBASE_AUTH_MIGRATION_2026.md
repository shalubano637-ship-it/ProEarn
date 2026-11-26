# Firebase Authentication Migration (2026)

Status: migration work branch created; production authentication remains on Supabase.

## Scope approved
- Move email/password and Google authentication to Firebase Authentication.
- Keep Supabase Postgres, RLS, Storage, Realtime, Edge Functions, and billing. Existing test accounts are disposable and will not be imported or linked.
- Do not migrate to Firestore or Firebase Storage.
- Do not change `main`, deploy production services, or upload to Google Play during this work.

## Verified starting point
- Android application ID: `com.prosn.app`.
- Firebase project configured in the repository: `proearn-6acdd`.
- Supabase project: `mltvpfqfhbhgkejcjpmq`.
- `lib/main.dart` initializes Supabase and Firebase Core/Messaging.
- `lib/auth_screen.dart` still uses Supabase Auth for email/password, Google OAuth, password reset, auth-state changes, and email confirmation.
- The app uses UUID user IDs in Postgres and relies on `auth.uid()` in RLS.
- Existing Supabase Auth accounts and their test profiles are intentionally out of scope. They will not be imported, matched by email, or linked to Firebase identities.
- The `public.users.referredBy -> public.users.uid` self-reference remains part of the application model.
- The live database has already recorded the Firebase identity prerequisite migration. Existing test rows are not linked to new Firebase IDs.

## Critical identity design
A normal Firebase client signup creates a Firebase UID that is not guaranteed to be a UUID. The current Postgres schema and RLS rely on UUID identity, so simply adding `firebase_auth` and replacing the login buttons is unsafe.

The intended bridge is:
1. A trusted server-side Edge Function creates a Firebase user with a server-generated UUID as its UID.
2. The function assigns the Supabase-compatible `role: authenticated` custom claim before the client signs in.
3. Email/password signup signs in with the newly created credentials. Google sign-in uses a verified Google ID token and a server-issued Firebase custom token.
4. The Flutter Supabase client obtains the Firebase ID token through its supported access-token callback.
5. Supabase validates the Firebase project as a third-party auth provider. Verify `iss`, `aud`, `sub`, expiry, and the `role` claim.
6. RLS and all backend authorization continue to use the stable UUID. No client-supplied UID/email is trusted.

Email/password provisioning and Google account linking need separate, tested flows. A matching email alone must never silently merge two identities.

## Required implementation phases

### Phase A — inventory and compatibility
- Do not migrate or link legacy test accounts. Validate fresh Firebase signup and clean profile provisioning.
- Enumerate every use of `auth.uid()`, policies, RPCs, Edge Functions, Realtime, Storage, and billing ownership.
- Review account deletion, FCM ownership, ban checks, terms acceptance, referral attribution, and Play Billing ownership.
- Keep this migration on the feature branch until Firebase third-party JWT validation and integration tests pass.

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
- Email/Password and Google providers were confirmed enabled by the app owner.
- Legacy Supabase Auth test accounts are intentionally not migrated. New test accounts must be created through Firebase signup after the server-side functions and Supabase Third-Party Auth integration are configured.
- The Firebase identity prerequisite migration has already been recorded in the connected database. Existing test rows are not linked to Firebase IDs.
- The hosted Supabase Firebase Third-Party Auth integration must be enabled in the Dashboard for project `proearn-6acdd`; the repository config documents the provider but does not itself update hosted Dashboard settings.
- Firebase Admin service-account secrets and the Edge Functions must be deployed by an authorized project operator. Do not claim Firebase Auth is active until real token/RLS tests pass.

## Safety rule
Do not delete test users or profiles automatically in this code change. Legacy users are not migrated; optional test-data cleanup is a separate explicit operation. Do not change production RLS policies, deploy functions, or cut over `main` during preparation. Keep work isolated on `feature/firebase-auth-migration-2026`.
