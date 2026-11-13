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

1. Preserve UUID ownership. New Firebase UIDs must be server-generated UUIDs matching the app's `uid` values; do not use Firebase's default random UID for this schema.
2. Never trust a Firebase UID, email address, or UUID supplied by the mobile client as proof of identity.
3. Keep the Firebase UID itself UUID-shaped and equal to the stable app UUID, or comprehensively replace every `auth.uid()`/UUID ownership assumption with a verified mapping. The preferred option for this schema is a server-created Firebase user whose UID is a server-generated UUID.
4. Preserve existing profile, posts, follows, moderation state, admin mapping, and Play Billing ownership.
5. Keep account deletion working for Firebase-authenticated requests and ensure both identity records are handled correctly.
6. Ensure Firebase ID tokens include the Supabase `role: authenticated` claim and Supabase validates the configured Firebase project.
7. Keep RLS restrictive and test Data API, Storage, Realtime, and Edge Functions with real Firebase tokens.

## Implementation sequence

### Phase 1: identity bridge (server-side first)

- Use the Firebase UID itself as the stable app UUID. A separate mapping table is not part of the selected design unless implementation discovers a hard blocker.
- A trusted server endpoint must generate the UUID; the mobile client must never choose or submit the UID that becomes authoritative.
- Use Firebase Admin SDK to create the Firebase user with that server-generated UUID and assign the Supabase-compatible `role: authenticated` custom claim.
- Email/password signup: validate the request server-side, create the Firebase account with the server-generated UUID, then let the client sign in with Firebase credentials. Handle partial failure and duplicate email without creating orphaned identities.
- Google sign-in: verify the Google ID token server-side, including signature, expiry, issuer, and configured OAuth audience. Resolve an existing Firebase identity or create one with a server-generated UUID, then mint a Firebase custom token for that UID. Never trust a client-supplied email or UID.
- Decide and implement safe provider linking. A verified matching email alone must not silently merge accounts unless the server proves control of both provider identities under an explicit linking flow.
- Create the `public.users` profile only after Supabase accepts the Firebase ID token and RLS identity is established. Preserve username, terms acceptance, referral attribution, and existing validation rules.
- Add tests for duplicate email, unverified Google email, wrong OAuth audience, expired/replayed tokens, partial provisioning failure, and unauthorized UUID claims.

### Phase 2: Firebase client authentication

- Add and pin `firebase_auth` and the native Google Sign-In dependencies after selecting the supported plugin/API versions.
- Implement email/password signup, login, email verification, password reset, Google sign-in, auth-state restoration, and sign-out.
- Preserve terms acceptance, referral-code handling, username validation, ban checks, and existing error states.
- Configure Supabase Flutter's `accessToken` callback to return the current Firebase ID token only after the identity bridge and Firebase project trust are deployed.
- Force-refresh tokens after custom claims are assigned.

### Phase 3: dependent services

- Repository review confirms the client auth identity is consumed directly by profile loading, profile creation, FCM sync, ban checks, and lifecycle RPCs. These call sites must be switched together, not piecemeal.
- The live Supabase project currently has 12 active Edge Functions: `imgbb-upload`, `notify`, `request-payout`, `verify-otp`, `send-otp`, `delete-account`, `delete-account-request`, `publish-app-update`, `voice-message`, `r2-upload`, `admin-moderate-report`, and `play-billing`. Audit each function for bearer-token validation, `auth.uid()` assumptions, and service-role authorization before cutover.
- `notify` currently resolves callers with Supabase `auth.getUser()`, and `delete-account` does the same before deleting the Supabase Auth user. Both are known migration blockers; do not change their live deployments until Firebase token verification and deletion semantics are tested.
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


## Implementation decision after code inspection

The current `public.users.uid` and billing ownership columns are UUIDs, and existing application code uses the auth user ID directly in profile queries and writes. Supabase's `auth.uid()` also returns a UUID. A plain Firebase client signup (which creates a random Firebase UID) is therefore not a safe drop-in: it can fail UUID casts and break ownership checks. The implementation must provision UUID-shaped Firebase UIDs server-side before enabling Firebase tokens in the Supabase client. Do not add `firebase_auth` to the app or switch the Supabase `accessToken` callback until that provisioning path and Google custom-token flow are implemented and tested.


## Live Supabase security-advisor baseline (2026-11-13)

The hosted project's Security Advisor was queried before any auth cutover. It currently reports:

- 17 public tables with RLS enabled but no policies. These may be intentionally service-role-only, but each must be checked against actual client and Edge Function access before changing grants or adding policies.
- `public.public_profiles` is flagged as a SECURITY DEFINER view. Review whether it should use `security_invoker = true` and confirm its intended public profile visibility.
- 9 SECURITY DEFINER functions are executable by `anon`.
- 79 SECURITY DEFINER functions are executable by `authenticated`.

These advisor findings are not proof that every function is exploitable: SECURITY DEFINER can be intentional when its body validates caller identity and ownership. Do not mass-revoke or convert them. Before Firebase cutover, review function bodies and arguments for caller-controlled user IDs, enforce `auth.uid()` ownership checks, set a safe `search_path`, and narrow EXECUTE grants to the required roles. In particular, audit functions that accept a user UUID as an argument (for example follow, like, block, gift, reward, and scheduled chest operations).

**Migration gate:** do not switch client auth or apply production RLS/grant changes until the 17 table access patterns, the public_profiles view, and SECURITY DEFINER function authorization have been individually reviewed and regression-tested with Firebase JWTs and anonymous requests.
