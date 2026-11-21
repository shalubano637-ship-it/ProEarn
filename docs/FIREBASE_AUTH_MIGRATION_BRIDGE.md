# Firebase Authentication Migration Bridge

## Status
Preparation only. This branch does not switch production authentication and does not modify the live Supabase project.

## Required identity invariant
The application stores user identity as UUID values in `public.users.uid` and relies on Supabase RLS policies using `auth.uid()`. A normal Firebase client signup generates a Firebase UID that is not guaranteed to be a UUID. Passing that token to Supabase without provisioning a matching UUID will break profile access and RLS-protected queries.

## Required architecture
1. A trusted server-side provisioning endpoint creates Firebase Auth users with a server-assigned UUID as the Firebase UID. Never expose Firebase service-account credentials in the Flutter app.
2. The server sets the Firebase custom claim `role=authenticated` and verifies the resulting Firebase ID token.
3. Flutter signs in with Firebase Auth and supplies the Firebase ID token to Supabase through the Supabase client's `accessToken` callback.
4. The Firebase UID, token `sub`, and existing `public.users.uid` must be the same UUID.
5. Database access is tested against representative RLS-protected tables before enabling the new auth path.
6. Account deletion must verify the Firebase token, clean up the user's app data, and delete the Firebase Auth identity. It must not trust a client-supplied UID.

## Cutover blockers
- Confirm the Firebase Admin SDK can run safely in the chosen server environment and can create a user with an explicit UUID UID.
- Implement and test provisioning, email/password signup/login, Google credential linking, token refresh, logout, and duplicate-email handling.
- Update all auth-dependent Flutter code, including splash/session restoration, FCM token ownership, profile services, settings, billing entitlements, and account deletion.
- Verify Supabase third-party Firebase auth accepts the token and RLS resolves `auth.uid()` to the expected UUID.
- Verify email verification and password reset flows.
- Run Flutter analyzer, unit/widget tests, and a real-device integration test.

## Safety rules
- Do not change `main`, deploy Edge Functions, modify Supabase Auth settings, alter RLS policies, or delete user/database records as part of preparation.
- Do not report the migration as complete until real Firebase signup/login and database RLS tests pass.
- Keep the existing Supabase Auth path available until the migration is explicitly approved for cutover.
