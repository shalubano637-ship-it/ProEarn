alter table public.users
  add column if not exists "referralCode" text,
  add column if not exists "referredBy" uuid references public.users(uid),
  add column if not exists "firstLoginRewardClaimedAt" timestamptz,
  add column if not exists "signupRewardStartedAt" timestamptz,
  add column if not exists "signupRewardEligible" boolean not null default true;

update public.users
set "signupRewardEligible" = false,
    "firstLoginRewardClaimedAt" = coalesce("firstLoginRewardClaimedAt", now())
where "createdAt" < now();

create unique index if not exists users_referral_code_unique
  on public.users ("referralCode")
  where "referralCode" is not null;

create table if not exists public.referral_rewards (
  invitee_uid uuid primary key references public.users(uid) on delete cascade,
  inviter_uid uuid not null references public.users(uid) on delete cascade,
  claimed_at timestamptz not null default now()
);

create table if not exists public.signup_daily_rewards (
  uid uuid not null references public.users(uid) on delete cascade,
  day_number smallint not null,
  tier text not null,
  claimed_at timestamptz not null default now(),
  primary key (uid, day_number),
  check (day_number between 1 and 7),
  check (tier in ('low','medium','high'))
);

alter table public.referral_rewards enable row level security;
alter table public.signup_daily_rewards enable row level security;

revoke all on public.referral_rewards from anon, authenticated;
revoke all on public.signup_daily_rewards from anon, authenticated;

create or replace function public.generate_referral_code()
returns text
language plpgsql
as $function$
declare
  v_code text;
begin
  loop
    v_code := upper(substr(md5(random()::text || clock_timestamp()::text || gen_random_uuid()::text), 1, 6));
    exit when not exists (
      select 1 from public.users where "referralCode" = v_code
    );
  end loop;
  return v_code;
end;
$function$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_referral_code text := upper(trim(coalesce(new.raw_user_meta_data->>'referralCode', '')));
  v_referrer uuid;
  v_code text;
begin
  select uid into v_referrer
  from public.users
  where "referralCode" = v_referral_code
  limit 1;

  if v_referrer = new.id then
    v_referrer := null;
  end if;

  v_code := public.generate_referral_code();

  insert into public.users (
    uid, "userName", email, "termsAcceptedAt", "termsVersion",
    "referralCode", "referredBy"
  )
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'userName', split_part(new.email, '@', 1)),
    coalesce(new.email, ''),
    (new.raw_user_meta_data->>'termsAcceptedAt')::timestamptz,
    new.raw_user_meta_data->>'termsVersion',
    v_code,
    v_referrer
  )
  on conflict (uid) do update
  set "referralCode" = coalesce(public.users."referralCode", excluded."referralCode"),
      "referredBy" = coalesce(public.users."referredBy", excluded."referredBy");

  return new;
end;
$function$;

create or replace function public.claim_first_login_reward()
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_me uuid := auth.uid();
  v_user public.users%rowtype;
  v_high_id uuid;
  v_high_name text;
  v_high_url text;
  v_medium_id uuid;
  v_medium_name text;
  v_medium_url text;
  v_inviter uuid;
begin
  if v_me is null then
    raise exception 'Not authenticated';
  end if;

  select * into v_user
  from public.users
  where uid = v_me
  for update;

  if v_user.uid is null then
    raise exception 'User profile not found';
  end if;

  if not coalesce(v_user."signupRewardEligible", false) then
    return jsonb_build_object('alreadyClaimed', true, 'eligible', false);
  end if;

  if v_user."firstLoginRewardClaimedAt" is not null then
    return jsonb_build_object('alreadyClaimed', true);
  end if;

  select id, name, "gifUrl"
    into v_high_id, v_high_name, v_high_url
  from public.gifts
  where tier = 'high' and "isActive"
  order by random()
  limit 1;

  if v_high_id is null then
    raise exception 'No high tier gifts available';
  end if;

  insert into public.gift_inventory ("ownerUid","giftId",count,source)
  values (v_me, v_high_id, 1, 'signup');

  update public.users
  set "mainCoins" = coalesce("mainCoins",0) + 50,
      "firstLoginRewardClaimedAt" = now(),
      "signupRewardStartedAt" = coalesce("signupRewardStartedAt", now())
  where uid = v_me;

  v_inviter := v_user."referredBy";

  if v_inviter is not null
     and v_inviter <> v_me
     and not exists (
       select 1 from public.referral_rewards where invitee_uid = v_me
     ) then

    select id, name, "gifUrl"
      into v_medium_id, v_medium_name, v_medium_url
    from public.gifts
    where tier = 'medium' and "isActive"
    order by random()
    limit 1;

    if v_medium_id is null then
      raise exception 'No medium tier gifts available';
    end if;

    insert into public.gift_inventory ("ownerUid","giftId",count,source)
    values (v_me, v_medium_id, 1, 'referral');

    insert into public.gift_inventory ("ownerUid","giftId",count,source)
    values (v_inviter, v_high_id, 1, 'referral');

    insert into public.referral_rewards (invitee_uid, inviter_uid)
    values (v_me, v_inviter);
  end if;

  return jsonb_build_object(
    'alreadyClaimed', false,
    'giftId', v_high_id,
    'giftName', v_high_name,
    'giftUrl', v_high_url,
    'coins', 50,
    'referralApplied', v_inviter is not null
  );
end;
$function$;

create or replace function public.get_signup_reward_status()
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_me uuid := auth.uid();
  v_user public.users%rowtype;
  v_start date;
  v_today date := (now() at time zone 'Asia/Kolkata')::date;
  v_current_day int;
  v_days jsonb := '[]'::jsonb;
  i int;
  v_tier text;
begin
  if v_me is null then
    raise exception 'Not authenticated';
  end if;

  select * into v_user from public.users where uid = v_me;

  if v_user.uid is null then
    raise exception 'User profile not found';
  end if;

  if not coalesce(v_user."signupRewardEligible", false) or v_user."signupRewardStartedAt" is null then
    return jsonb_build_object(
      'enabled', false,
      'referralCode', v_user."referralCode"
    );
  end if;

  v_start := (v_user."signupRewardStartedAt" at time zone 'Asia/Kolkata')::date;
  v_current_day := greatest(1, least(7, (v_today - v_start) + 1));

  for i in 1..7 loop
    v_tier := case
      when i <= 2 then 'low'
      when i <= 4 then 'medium'
      else 'high'
    end;

    v_days := v_days || jsonb_build_object(
      'day', i,
      'tier', v_tier,
      'claimed', exists (
        select 1 from public.signup_daily_rewards
        where uid = v_me and day_number = i
      ),
      'available', i = v_current_day
    );
  end loop;

  return jsonb_build_object(
    'referralCode', v_user."referralCode",
    'firstLoginClaimed', v_user."firstLoginRewardClaimedAt" is not null,
    'rewardStartDate', v_start,
    'currentDay', v_current_day,
    'days', v_days
  );
end;
$function$;

create or replace function public.claim_signup_daily_reward(p_day_number integer)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_me uuid := auth.uid();
  v_user public.users%rowtype;
  v_start date;
  v_today date := (now() at time zone 'Asia/Kolkata')::date;
  v_current_day int;
  v_tier text;
  v_gift_id uuid;
  v_gift_name text;
  v_gift_url text;
begin
  if v_me is null then
    raise exception 'Not authenticated';
  end if;

  select * into v_user from public.users where uid = v_me for update;

  if not coalesce(v_user."signupRewardEligible", false) then
    raise exception 'REWARD_NOT_AVAILABLE';
  end if;

  if v_user."firstLoginRewardClaimedAt" is null then
    raise exception 'FIRST_LOGIN_REWARD_REQUIRED';
  end if;

  v_start := (v_user."signupRewardStartedAt" at time zone 'Asia/Kolkata')::date;
  v_current_day := (v_today - v_start) + 1;

  if p_day_number <> v_current_day or p_day_number < 1 or p_day_number > 7 then
    raise exception 'DAY_NOT_AVAILABLE';
  end if;

  if exists (
    select 1 from public.signup_daily_rewards
    where uid = v_me and day_number = p_day_number
  ) then
    raise exception 'DAY_ALREADY_CLAIMED';
  end if;

  v_tier := case
    when p_day_number <= 2 then 'low'
    when p_day_number <= 4 then 'medium'
    else 'high'
  end;

  select id, name, "gifUrl"
    into v_gift_id, v_gift_name, v_gift_url
  from public.gifts
  where tier = v_tier and "isActive"
  order by random()
  limit 1;

  if v_gift_id is null then
    raise exception 'No gifts available for tier';
  end if;

  insert into public.gift_inventory ("ownerUid","giftId",count,source)
  values (v_me, v_gift_id, 1, 'signup');

  insert into public.signup_daily_rewards (uid, day_number, tier)
  values (v_me, p_day_number, v_tier);

  return jsonb_build_object(
    'day', p_day_number,
    'tier', v_tier,
    'giftId', v_gift_id,
    'giftName', v_gift_name,
    'giftUrl', v_gift_url
  );
end;
$function$;
