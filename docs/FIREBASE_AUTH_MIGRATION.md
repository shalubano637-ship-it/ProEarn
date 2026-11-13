# Firebase Authentication Migration Plan

## Decision
- Authentication provider: Firebase Authentication.
- Application data: keep Supabase Postgres, Storage/media gateway, Edge Functions, RPCs, and billing.
- Existing accounts and application data must remain available.
- Work branch: `feature/firebase-auth-migration`; do not merge into `main` until end-to-end verification passes.

## Repository findings
- `pubspec.yaml` includes `firebase_core` and `firebase_messaging`, but not `firebase_auth` or a Google sign-in package.
- `lib/main.dart` initializes Supabase and initializes Firebase only on Android. Startup, lifecycle, and deferred services currently assume Supabase Auth.
- `lib/auth_screen.dart` uses Supabase Auth for password login, signup, Google OAuth, password reset, email verification, session restoration, and sign-out.
- `lib/fcm_service.dart` observes Supabase Auth events and stores FCM tokens in `public.users` keyed by the current Supabase user UUID.
- `public.users.uid` is a UUID referenced by many application tables and RPCs. The signup trigger creates that row from `auth.users.id`.
- `android/app/google-services.json` contains a Firebase Android client for `com.prosn.app`, but the OAuth client list is empty. Google provider setup is not verified.
- Android manifest still contains the old Supabase OAuth callback intent filter. It must be replaced only after Firebase Google sign-in and redirect handling are configured and tested.

## Non-negotiable identity constraint
Changing to Firebase Auth without preserving the existing Supabase UUID as the effective Supabase JWT subject will break RLS and application references. The current app assumes `auth.uid() = public.users.uid`; many RPCs use `auth.uid()` to identify the user. Creating new Firebase UIDs and merely copying profile rows is not a safe migration.

The safe target is:
1. Keep each existing user's current Supabase UUID as the Firebase Auth UID.
2. Configure Supabase Third-Party Auth for the Firebase project so Supabase accepts Firebase-issued JWTs.
3. Add a trusted server-side migration/identity bridge. Never place Firebase Admin credentials or Supabase service-role keys in the Flutter app.
4. For existing email/password users, verify their current Supabase credentials during a controlled one-time migration, then provision the Firebase account with the same UID using Firebase Admin. Passwords cannot be bulk-copied from this Flutter repository. If an existing password cannot be safely verified and provisioned, require a secure account-recovery flow rather than silently creating a second identity.
5. For Google users, securely link/provision the Firebase identity to the same existing UID after validating the existing account. Avoid creating duplicate users based on unverified email alone.
6. Keep all profile, posts, followers, messages, coins, purchases, moderation, and admin data in Supabase under the unchanged UID.

## Required setup before client cutover
- Enable Email/Password and Google providers in Firebase Authentication.
- Configure the Firebase Android app's SHA-1 and SHA-256 fingerprints and complete Google OAuth client setup; download the updated `google-services.json` for package `com.prosn.app`.
- Provide/enable a trusted migration endpoint or Cloud Function using Firebase Admin SDK. It must validate the legacy Supabase session and credentials, enforce rate limits, preserve the existing UID, and never return admin secrets.
- Configure Supabase Third-Party Auth for the Firebase project and verify that RLS sees the Firebase UID as `auth.uid()`.
- Review all RLS policies, database triggers, Edge Functions, account deletion, and admin authorization under Firebase-issued tokens before enabling the new client.
- Decide the supported platforms. The repository currently has no `GoogleService-Info.plist` in its tracked iOS files; Firebase initialization is Android-only in `main.dart`.

## Cutover sequence
1. Implement Firebase Auth behind an isolated auth service on this branch; keep Supabase data APIs unchanged.
2. Implement one-time existing-account migration and UID preservation on the trusted server.
3. Update splash/session restore, email/password signup and login, Google sign-in, verification, password reset, logout, FCM account observation, and lifecycle handling.
4. Keep the existing Supabase account session only for the migration bridge; remove legacy Supabase Auth only after migration coverage is verified.
5. Test old accounts, new accounts, Google accounts, duplicate-email cases, password reset, email verification, banned accounts, terms acceptance, FCM token save/unlink, account deletion, RLS/RPCs, admin controls, purchases, and sign-out/restart.
6. Build and run Android tests on the branch. Merge only after all critical checks pass.

## Current status
Branch created. No authentication code has been changed yet. A client-only switch is intentionally blocked until the trusted UID-preserving migration bridge and Firebase/Supabase provider configuration are available. This prevents locking existing users out or breaking Supabase RLS.
