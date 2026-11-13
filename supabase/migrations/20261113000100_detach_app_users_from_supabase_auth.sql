-- Firebase Authentication migration: detach application UUIDs from Supabase Auth.
--
-- IMPORTANT:
-- This migration must only be applied together with the Firebase JWT trust setup,
-- UUID Firebase UID provisioning, and the updated account-deletion function.
-- Do not apply this migration independently while the app still uses Supabase Auth.
--
-- Keep UUID columns and RLS policies based on auth.uid(); Firebase users must be
-- provisioned with UUID UIDs and Supabase must validate Firebase JWTs as a third-party
-- auth provider. This removes only referential links to auth.users, not the UUID types.

BEGIN;

ALTER TABLE public.users
  DROP CONSTRAINT IF EXISTS users_uid_fkey;

ALTER TABLE public.play_purchase_events
  DROP CONSTRAINT IF EXISTS play_purchase_events_user_id_fkey;

ALTER TABLE public.play_subscriptions
  DROP CONSTRAINT IF EXISTS play_subscriptions_user_id_fkey;

ALTER TABLE public.play_subscription_daily_claims
  DROP CONSTRAINT IF EXISTS play_subscription_daily_claims_user_id_fkey;

COMMIT;
