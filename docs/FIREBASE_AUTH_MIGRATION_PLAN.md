# ProSN Firebase Authentication Migration Plan

Status: discovery complete; implementation and production cutover are NOT complete. The only Supabase Auth account was the owner's test account and has been deleted; verification confirmed zero rows in `auth.users`, `public.users`, and the three Play Billing ownership tables. There are no existing app users to migrate or claim.

## Current repository state

- Firebase Core and Firebase Messaging are present for push notifications.
- `firebase_auth` is not currently a dependency.
- Email/password signup, login, password reset, email confirmation, Google OAuth, session restoration, and sign-out still use Supabase Auth.
- Profile IDs are UUIDs and the database currently references `auth.users` from `public.users` and Play Billing ownership tables.
- Application authorization and row-level security depend on `auth.uid()`.
- The account-deletion Edge Function currently validates a Supabase Auth bearer token and deletes the matching Supabase Auth user.

## Non-negotiable compatibility requirements

1. Preserve each existing user's UUID identity. Do not replace it with a random Firebase UID.
2. Never trust a Firebase UID, email address, or UUID supplied by the mobile client as proof of identity.
3. Resolve Firebase identity to the stable app UUID only through a server-verified mapping.
4. Preserve existing profile, posts, follows, moderation state, admin mapping, and Play Billing ownership.
5. Keep account deletion working for Firebase-authenticated requests and ensure both identity records are handled correctly.
6. Ensure Firebase ID tokens include the Supabase `role: authenticated` claim and Supabase validates the configured Firebase project.
7. Keep RLS restrictive and test Data API, Storage, Realtime, and Edge Functions with real Firebase tokens.

## Implementation sequence

### Phase 1: identity bridge (server-side first)

- Design a private mapping table between Firebase UID and existing UUID app identity.
- Verify Firebase ID tokens server-side using the Firebase Admin SDK.
- No legacy account-claiming flow is needed because the only existing Auth account was the owner's test account and has been deleted. New account provisioning still needs server-side identity verification; email equality alone must not silently merge identities.
- Decide how Google sign-in links to an existing email/password account and how duplicate identities are rejected.
- Add server-side profile provisioning that creates the UUID app profile only after verified identity mapping.
- Add tests for replay, mismatched email, duplicate provider identity, and unauthorized UUID claims.

### Phase 2: Firebase client authentication

- Add and pin `firebase_auth` and the native Google Sign-In dependencies after selecting the supported plugin/API versions.
- Implement email/password signup, login, email verification, password reset, Google sign-in, auth-state restoration, and sign-out.
- Preserve terms acceptance, referral-code handling, username validation, ban checks, and existing error states.
- Configure Supabase Flutter's `accessToken` callback to return the current Firebase ID token only after the identity bridge and Firebase project trust are deployed.
- Force-refresh tokens after custom claims are assigned.

### Phase 3: dependent services

- Update profile loading and creation to use the server-resolved stable UUID.
- Update FCM token sync and auth-state listeners.
- Update every Edge Function that currently assumes a Supabase Auth user.
- Update account deletion to verify Firebase tokens, resolve the stable UUID, remove app data, and revoke/delete the Firebase identity safely.
- Audit admin authorization; never derive admin status from client metadata.

### Phase 4: database cutover

- Inventory every foreign key to `auth.users`, every use of `auth.uid()`, auth triggers, views, policies, RPCs, and billing references.
- Test the Firebase JWT issuer, audience, subject, and `role` claim against the hosted Supabase integration.
- Only remove `auth.users` foreign keys after all identity, deletion, and rollback tests pass.
- Keep UUID column types and RLS ownership semantics stable.
- Apply schema changes only through a reviewed migration after staging verification.

### Phase 5: acceptance tests

- New email/password account; email verification; sign out/in; password reset.
- Existing-account migration without duplicate profile or lost billing history.
- Google sign-in for new and existing accounts; account-link conflict cases.
- Banned user, terms acceptance, referral attribution, admin permissions.
- RLS isolation between two users; Storage and Realtime authorization.
- FCM token registration, refresh, disable, and sign-out unlink.
- Purchase/subscription ownership and restore.
- Full account deletion including media and Firebase identity.
- Rollback to the previous app/auth path.

## Current cutover decision

Do not merge a schema change or ship an APK claiming Firebase Auth is active yet. The current app still uses Supabase Auth. The earlier draft that detached foreign keys was removed because it would be unsafe without the identity bridge and full application changes.
