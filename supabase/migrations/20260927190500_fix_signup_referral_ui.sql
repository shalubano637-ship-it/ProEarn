-- Fix signup popup eligibility flow and ensure every user has a referral code.
-- Existing users keep their existing signup eligibility; this migration does not
-- grant first-login rewards retroactively.

create or replace function public.get_signup_reward_status()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_me uuid := auth.uid();
  v_user public.users%rowtype;
  v_start date;
  v_today date := (now() at time zone 'Asia/Kolkata')::date;
  v_current_day int;
  v_days jsonb := '[]'::jsonb;
  v_code text;
  i int;
  v_tier text;
begin
  if v_me is null then
    raise exception 'Not authenticated';
  end if;

  select * into v_user
  from public.users
  where uid = v_me;

  if v_user.uid is null then
    raise exception 'User profile not found';
  end if;

  v_code := v_user."referralCode";

  if v_code is null or v_code = '' then
    loop
      v_code := upper(substr(md5(random()::text || clock_timestamp()::text || gen_random_uuid()::text), 1, 6));
      exit when not exists (
        select 1 from public.users where "referralCode" = v_code
      );
    end loop;

    update public.users
    set "referralCode" = v_code
    where uid = v_me;

    v_user."referralCode" := v_code;
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
    'enabled', true,
    'referralCode', v_user."referralCode",
    'firstLoginClaimed', v_user."firstLoginRewardClaimedAt" is not null,
    'rewardStartDate', v_start,
    'currentDay', v_current_day,
    'days', v_days
  );
end;
$function$;

revoke execute on function public.get_signup_reward_status() from public;
revoke execute on function public.get_signup_reward_status() from anon;
grant execute on function public.get_signup_reward_status() to authenticated;

update public.users
set "referralCode" = upper(substr(md5(random()::text || clock_timestamp()::text || gen_random_uuid()::text), 1, 6))
where "referralCode" is null;
