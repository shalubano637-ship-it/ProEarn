# Firebase UUID Provisioning Bridge

This branch contains the first server-side provisioning layer for the Firebase Auth migration.

## Function: firebase-auth-provision
- Uses the Firebase Admin service-account JSON from Supabase Edge Function secret `FIREBASE_SERVICE_ACCOUNT_JSON`.
- Creates Firebase Auth users with a server-generated UUID UID.
- Sets the Firebase custom claim `role: authenticated`.
- Creates the matching `public.users.uid` profile row with username, email, terms acceptance, and referral linkage.
- Rolls back the Firebase Auth account if profile creation fails.
- Never sends Admin credentials to the Flutter client.

## Database prerequisite
The migration `20261120000100_firebase_auth_identity.sql` drops only the four app foreign keys from app tables to `auth.users`. It is a branch migration and has NOT been applied to the live database. It must be applied only after reviewing and testing the provisioning function.

## Not yet switched
Flutter still uses Supabase Auth. Google sign-in, password reset, email verification, account deletion, FCM auth observation, and Supabase access-token callback are not yet migrated. Do not merge or release this branch yet.

## Required verification
1. Deploy the function to a staging project or after an approved maintenance window.
2. Apply the migration to a non-production database first.
3. Sign up a test account and verify Firebase UID is UUID-shaped.
4. Decode the Firebase ID token and confirm `role=authenticated`, issuer and audience.
5. Initialize Supabase with the Firebase ID token callback and verify `auth.uid() = Firebase UID`.
6. Verify RLS isolation, profile insert, terms fields, referral handling, email verification and rollback behavior.
