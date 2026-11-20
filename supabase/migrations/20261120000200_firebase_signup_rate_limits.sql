-- Firebase Auth identity cutover prerequisites and durable signup throttling.
-- Verified application identity and billing tables were empty before applying.
alter table public.users drop constraint if exists users_uid_fkey;
alter table public.play_purchase_events drop constraint if exists play_purchase_events_user_id_fkey;
alter table public.play_subscriptions drop constraint if exists play_subscriptions_user_id_fkey;
alter table public.play_subscription_daily_claims drop constraint if exists play_subscription_daily_claims_user_id_fkey;

create table if not exists public.firebase_signup_rate_limits (
  bucket_key text primary key,
  window_started_at timestamptz not null,
  request_count integer not null check (request_count > 0)
);
alter table public.firebase_signup_rate_limits enable row level security;
revoke all on table public.firebase_signup_rate_limits from public, anon, authenticated;
grant all on table public.firebase_signup_rate_limits to service_role;

create or replace function public.consume_firebase_signup_rate_limit(p_email_key text, p_ip_key text)
returns boolean language plpgsql security definer set search_path = ''
as $$
declare
  v_email_count integer;
  v_ip_count integer;
  v_now timestamptz := pg_catalog.now();
begin
  if p_email_key is null or p_ip_key is null or length(p_email_key) < 32 or length(p_ip_key) < 32 then
    return false;
  end if;
  insert into public.firebase_signup_rate_limits as r (bucket_key, window_started_at, request_count)
  values (p_email_key, v_now, 1)
  on conflict (bucket_key) do update
    set window_started_at = case when r.window_started_at <= v_now - interval '1 hour' then v_now else r.window_started_at end,
        request_count = case when r.window_started_at <= v_now - interval '1 hour' then 1 else r.request_count + 1 end
  returning request_count into v_email_count;
  insert into public.firebase_signup_rate_limits as r (bucket_key, window_started_at, request_count)
  values (p_ip_key, v_now, 1)
  on conflict (bucket_key) do update
    set window_started_at = case when r.window_started_at <= v_now - interval '1 hour' then v_now else r.window_started_at end,
        request_count = case when r.window_started_at <= v_now - interval '1 hour' then 1 else r.request_count + 1 end
  returning request_count into v_ip_count;
  return v_email_count <= 5 and v_ip_count <= 20;
end;
$$;
revoke all on function public.consume_firebase_signup_rate_limit(text, text) from public, anon, authenticated;
grant execute on function public.consume_firebase_signup_rate_limit(text, text) to service_role;
