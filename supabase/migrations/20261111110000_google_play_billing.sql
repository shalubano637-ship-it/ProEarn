-- Google Play Billing: verified purchase ledger, subscription entitlement and daily coin claims.
create table if not exists public.play_purchase_events (
  purchase_token text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  product_id text not null,
  purchase_type text not null check (purchase_type in ('coin_pack','subscription')),
  order_id text,
  coins_granted integer not null default 0 check (coins_granted >= 0),
  purchased_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create index if not exists play_purchase_events_user_created_idx
  on public.play_purchase_events(user_id, created_at desc);
alter table public.play_purchase_events enable row level security;
revoke all on public.play_purchase_events from anon, authenticated;

create table if not exists public.play_subscriptions (
  purchase_token text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  product_id text not null check (product_id in ('ad_free_weekly','ad_free_monthly')),
  order_id text,
  status text not null default 'active',
  expires_at timestamptz not null,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create index if not exists play_subscriptions_user_expiry_idx
  on public.play_subscriptions(user_id, expires_at desc);
alter table public.play_subscriptions enable row level security;
revoke all on public.play_subscriptions from anon, authenticated;

create table if not exists public.play_subscription_daily_claims (
  user_id uuid not null references auth.users(id) on delete cascade,
  claim_date date not null,
  purchase_token text not null references public.play_subscriptions(purchase_token) on delete cascade,
  coins integer not null default 150 check (coins = 150),
  created_at timestamptz not null default now(),
  primary key(user_id, claim_date)
);
alter table public.play_subscription_daily_claims enable row level security;
revoke all on public.play_subscription_daily_claims from anon, authenticated;

alter table public.users
  add column if not exists "isAdFree" boolean not null default false,
  add column if not exists "adFreeUntil" timestamptz;

create or replace function public.record_verified_play_purchase(
  p_user_id uuid,
  p_product_id text,
  p_purchase_token text,
  p_order_id text,
  p_expires_at timestamptz default null
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_coins integer := 0;
  v_type text;
  v_inserted integer := 0;
  v_existing public.play_purchase_events%rowtype;
begin
  if p_user_id is null or p_purchase_token is null or length(p_purchase_token) < 20 then
    raise exception 'Invalid purchase';
  end if;

  v_coins := case p_product_id
    when 'coins_100' then 100
    when 'coins_275' then 275
    when 'coins_700' then 700
    when 'coins_1700' then 1700
    when 'coins_3800' then 3800
    when 'coins_9200' then 9200
    else 0
  end;

  if v_coins > 0 then
    v_type := 'coin_pack';
  elsif p_product_id in ('ad_free_weekly','ad_free_monthly') then
    v_type := 'subscription';
    if p_expires_at is null or p_expires_at <= now() then
      raise exception 'Subscription is not active';
    end if;
  else
    raise exception 'Unknown Play product';
  end if;

  insert into public.play_purchase_events(
    purchase_token,user_id,product_id,purchase_type,order_id,coins_granted
  ) values (
    p_purchase_token,p_user_id,p_product_id,v_type,p_order_id,v_coins
  ) on conflict (purchase_token) do nothing;
  get diagnostics v_inserted = row_count;

  if v_inserted = 0 then
    select * into v_existing from public.play_purchase_events
    where purchase_token = p_purchase_token;
    if v_existing.user_id <> p_user_id or v_existing.product_id <> p_product_id then
      raise exception 'Purchase token is already linked to another account or product';
    end if;
  end if;

  if v_type = 'coin_pack' then
    if v_inserted = 1 then
      perform set_config('app.bypass_column_protection', 'on', true);
      update public.users
        set "mainCoins" = coalesce("mainCoins",0) + v_coins
      where uid = p_user_id;
      if not found then raise exception 'User profile not found'; end if;
    end if;
    return jsonb_build_object('success',true,'duplicate',v_inserted = 0,'coinsGranted',case when v_inserted = 1 then v_coins else 0 end);
  end if;

  insert into public.play_subscriptions(
    purchase_token,user_id,product_id,order_id,status,expires_at,updated_at
  ) values (
    p_purchase_token,p_user_id,p_product_id,p_order_id,'active',p_expires_at,now()
  )
  on conflict (purchase_token) do update
    set order_id = excluded.order_id,
        status = 'active',
        expires_at = greatest(public.play_subscriptions.expires_at, excluded.expires_at),
        updated_at = now()
    where public.play_subscriptions.user_id = excluded.user_id
      and public.play_subscriptions.product_id = excluded.product_id;

  if not exists (
    select 1 from public.play_subscriptions
    where purchase_token = p_purchase_token and user_id = p_user_id
      and product_id = p_product_id
  ) then
    raise exception 'Subscription token conflict';
  end if;

  perform set_config('app.bypass_column_protection', 'on', true);
  update public.users
  set "isAdFree" = true,
      "adFreeUntil" = greatest(coalesce("adFreeUntil",p_expires_at),p_expires_at)
  where uid = p_user_id;

  return jsonb_build_object('success',true,'duplicate',v_inserted = 0,'adFreeUntil',p_expires_at);
end;
$$;
revoke all on function public.record_verified_play_purchase(uuid,text,text,text,timestamptz) from public, anon, authenticated;
grant execute on function public.record_verified_play_purchase(uuid,text,text,text,timestamptz) to service_role;

create or replace function public.claim_ad_free_daily_coins()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := auth.uid();
  v_sub public.play_subscriptions%rowtype;
  v_today date := (now() at time zone 'Asia/Kolkata')::date;
  v_inserted integer := 0;
begin
  if v_me is null then raise exception 'Not authenticated'; end if;

  select * into v_sub
  from public.play_subscriptions
  where user_id = v_me and status = 'active' and expires_at > now()
  order by expires_at desc
  limit 1;

  if not found then
    perform set_config('app.bypass_column_protection', 'on', true);
    update public.users set "isAdFree" = false, "adFreeUntil" = null where uid = v_me;
    return jsonb_build_object('success',false,'reason','no_active_subscription');
  end if;

  insert into public.play_subscription_daily_claims(user_id,claim_date,purchase_token,coins)
  values(v_me,v_today,v_sub.purchase_token,150)
  on conflict(user_id,claim_date) do nothing;
  get diagnostics v_inserted = row_count;

  perform set_config('app.bypass_column_protection', 'on', true);
  update public.users
    set "isAdFree" = true,
        "adFreeUntil" = v_sub.expires_at,
        "mainCoins" = coalesce("mainCoins",0) + case when v_inserted = 1 then 150 else 0 end
  where uid = v_me;

  return jsonb_build_object(
    'success',true,
    'coinsGranted',case when v_inserted = 1 then 150 else 0 end,
    'alreadyClaimed',v_inserted = 0,
    'expiresAt',v_sub.expires_at
  );
end;
$$;
revoke all on function public.claim_ad_free_daily_coins() from public, anon;
grant execute on function public.claim_ad_free_daily_coins() to authenticated;

create or replace function public.protect_user_monetization_columns()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_setting('app.bypass_column_protection', true) = 'on' then
    return new;
  end if;
  if new."isAdFree" is distinct from old."isAdFree"
     or new."adFreeUntil" is distinct from old."adFreeUntil" then
    raise exception 'Monetization entitlements can only be changed by verified server operations';
  end if;
  return new;
end;
$$;
drop trigger if exists protect_user_monetization_columns on public.users;
create trigger protect_user_monetization_columns
before update on public.users
for each row execute function public.protect_user_monetization_columns();
revoke all on function public.protect_user_monetization_columns() from public, anon, authenticated;
