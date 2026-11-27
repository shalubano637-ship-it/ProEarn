# Firebase UUID Provisioning Bridge

This branch contains server-side provisioning for fresh Firebase Auth accounts. Legacy Supabase Auth test accounts are deliberately not imported or linked.

## Function: firebase-auth-provision
- Uses the Firebase Admin service-account JSON from Supabase Edge Function secret `FIREBASE_SERVICE_ACCOUNT_JSON`.
- Creates Firebase Auth users with a server-generated UUID UID.
- Sets the Firebase custom claim `role: authenticated`.
- Creates the matching `public.users.uid` profile row with username, email, terms acceptance, and referral linkage.
- Rolls back the Firebase Auth account if profile creation fails.
- Never sends Admin credentials to the Flutter client.

## Database prerequisite
The migration `20261120142953_firebase_uuid_identity_and_signup_rate_limits.sql` drops the app foreign keys from app identity tables to `auth.users` and adds durable signup throttling. It is already recorded as applied in the connected Supabase project. Do not re-apply it or assume this operation migrated existing user accounts.

## Not yet switched
Flutter still uses Supabase Auth. Google sign-in, password reset, email verification, account deletion, FCM auth observation, and Supabase access-token callback are not yet migrated. Do not merge or release this branch yet.

## Required verification
1. Deploy the function to a staging project or after an approved maintenance window.
2. Apply the migration to a non-production database first.
3. Sign up a test account and verify Firebase UID is UUID-shaped.
4. Decode the Firebase ID token and confirm `role=authenticated`, issuer and audience.
5. Initialize Supabase with the Firebase ID token callback and verify `auth.uid() = Firebase UID` for a newly created account.
6. Verify RLS isolation, fresh profile insert, terms fields, referral handling, email verification and rollback behavior.
