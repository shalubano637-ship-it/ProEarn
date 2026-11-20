-- Firebase Auth becomes the identity provider while Supabase remains the data API.
-- Apply only after the Firebase provisioning function is deployed and tested.
-- Firebase UUID UIDs replace auth.uid() identity; app tables must no longer FK to auth.users.
alter table public.users drop constraint if exists users_uid_fkey;
alter table public.play_purchase_events drop constraint if exists play_purchase_events_user_id_fkey;
alter table public.play_subscriptions drop constraint if exists play_subscriptions_user_id_fkey;
alter table public.play_subscription_daily_claims drop constraint if exists play_subscription_daily_claims_user_id_fkey;
