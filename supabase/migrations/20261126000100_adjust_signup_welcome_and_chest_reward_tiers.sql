-- ProSN reward tier update:
-- Daily signup gifts are Low only.
-- First-login Welcome reward may be Low or Medium (50 coins remain unchanged).
-- Chest sequence: Chest 1-3 Low, Chest 4-5 Medium.

CREATE OR REPLACE FUNCTION public.chest_gift_tier(p_index integer)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public'
AS $function$
  SELECT CASE
    WHEN p_index BETWEEN 0 AND 2 THEN 'low'
    WHEN p_index BETWEEN 3 AND 4 THEN 'medium'
    ELSE NULL
  END;
$function$;

CREATE OR REPLACE FUNCTION public.claim_first_login_reward()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_me uuid := auth.uid();
  v_user public.users%rowtype;
  v_welcome_id uuid;
  v_welcome_name text;
  v_welcome_url text;
  v_medium_id uuid;
  v_medium_name text;
  v_medium_url text;
  v_referral_high_id uuid;
  v_referral_high_name text;
  v_referral_high_url text;
  v_inviter uuid;
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO v_user
  FROM public.users
  WHERE uid = v_me
  FOR UPDATE;

  IF v_user.uid IS NULL THEN
    RAISE EXCEPTION 'User profile not found';
  END IF;

  IF NOT coalesce(v_user."signupRewardEligible", false) THEN
    RETURN jsonb_build_object('alreadyClaimed', true, 'eligible', false);
  END IF;

  IF v_user."firstLoginRewardClaimedAt" IS NOT NULL THEN
    RETURN jsonb_build_object('alreadyClaimed', true);
  END IF;

  -- First-login Welcome gift is randomly selected from Low and Medium tiers only.
  SELECT id, name, "gifUrl"
    INTO v_welcome_id, v_welcome_name, v_welcome_url
  FROM public.gifts
  WHERE tier IN ('low', 'medium') AND "isActive"
  ORDER BY random()
  LIMIT 1;

  IF v_welcome_id IS NULL THEN
    RAISE EXCEPTION 'No low or medium welcome gifts available';
  END IF;

  INSERT INTO public.gift_inventory ("ownerUid","giftId",count,source)
  VALUES (v_me, v_welcome_id, 1, 'signup');

  -- Permit this trusted SECURITY DEFINER reward operation to update protected wallet/reward fields.
  PERFORM set_config('app.bypass_column_protection', 'on', true);

  UPDATE public.users
  SET "mainCoins" = coalesce("mainCoins",0) + 50,
      "firstLoginRewardClaimedAt" = now(),
      "signupRewardStartedAt" = coalesce("signupRewardStartedAt", now())
  WHERE uid = v_me;

  PERFORM set_config('app.bypass_column_protection', 'off', true);

  v_inviter := v_user."referredBy";

  -- Keep the existing referral reward rule unchanged:
  -- referred user receives a Medium gift and inviter receives a High gift.
  IF v_inviter IS NOT NULL
     AND v_inviter <> v_me
     AND NOT EXISTS (
       SELECT 1 FROM public.referral_rewards WHERE invitee_uid = v_me
     ) THEN

    SELECT id, name, "gifUrl"
      INTO v_medium_id, v_medium_name, v_medium_url
    FROM public.gifts
    WHERE tier = 'medium' AND "isActive"
    ORDER BY random()
    LIMIT 1;

    IF v_medium_id IS NULL THEN
      RAISE EXCEPTION 'No medium tier referral gifts available';
    END IF;

    SELECT id, name, "gifUrl"
      INTO v_referral_high_id, v_referral_high_name, v_referral_high_url
    FROM public.gifts
    WHERE tier = 'high' AND "isActive"
    ORDER BY random()
    LIMIT 1;

    IF v_referral_high_id IS NULL THEN
      RAISE EXCEPTION 'No high tier referral gifts available';
    END IF;

    INSERT INTO public.gift_inventory ("ownerUid","giftId",count,source)
    VALUES (v_me, v_medium_id, 1, 'referral');

    INSERT INTO public.gift_inventory ("ownerUid","giftId",count,source)
    VALUES (v_inviter, v_referral_high_id, 1, 'referral');

    INSERT INTO public.referral_rewards (invitee_uid, inviter_uid)
    VALUES (v_me, v_inviter);
  END IF;

  RETURN jsonb_build_object(
    'alreadyClaimed', false,
    'giftId', v_welcome_id,
    'giftName', v_welcome_name,
    'giftUrl', v_welcome_url,
    'coins', 50,
    'referralApplied', v_inviter IS NOT NULL
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_signup_reward_status()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_me uuid := auth.uid();
  v_user public.users%rowtype;
  v_cycle integer;
  v_next_day integer;
  v_last_claimed_at timestamptz;
  v_can_claim_today boolean := true;
  v_days jsonb := '[]'::jsonb;
  v_code text;
  i integer;
  v_tier text;
  v_claimed boolean;
BEGIN
  IF v_me IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT * INTO v_user FROM public.users WHERE uid = v_me;
  IF v_user.uid IS NULL THEN RAISE EXCEPTION 'User profile not found'; END IF;

  v_code := v_user."referralCode";
  IF v_code IS NULL OR v_code = '' THEN
    LOOP
      v_code := upper(substr(md5(random()::text || clock_timestamp()::text || gen_random_uuid()::text), 1, 6));
      EXIT WHEN NOT EXISTS (SELECT 1 FROM public.users WHERE "referralCode" = v_code);
    END LOOP;
    UPDATE public.users SET "referralCode" = v_code WHERE uid = v_me;
  END IF;

  IF NOT coalesce(v_user."signupRewardEligible", false) THEN
    RETURN jsonb_build_object('enabled', false, 'referralCode', v_code);
  END IF;

  IF v_user."firstLoginRewardClaimedAt" IS NULL THEN
    RETURN jsonb_build_object(
      'enabled', true, 'referralCode', v_code,
      'firstLoginClaimed', false, 'currentDay', 1,
      'cycleNumber', 1, 'canClaimToday', true, 'days', '[]'::jsonb
    );
  END IF;

  SELECT coalesce(max(r.cycle_number), 1)
    INTO v_cycle
  FROM public.signup_daily_rewards r
  WHERE r.uid = v_me;

  SELECT coalesce(min(n), 8)
    INTO v_next_day
  FROM generate_series(1, 7) AS n
  WHERE NOT EXISTS (
    SELECT 1 FROM public.signup_daily_rewards r
    WHERE r.uid = v_me AND r.cycle_number = v_cycle AND r.day_number = n
  );

  IF v_next_day = 8 THEN
    v_cycle := v_cycle + 1;
    v_next_day := 1;
  END IF;

  SELECT max(r.claimed_at)
    INTO v_last_claimed_at
  FROM public.signup_daily_rewards r
  WHERE r.uid = v_me;

  IF v_last_claimed_at IS NOT NULL
     AND (v_last_claimed_at AT TIME ZONE 'Asia/Kolkata')::date =
         (now() AT TIME ZONE 'Asia/Kolkata')::date THEN
    v_can_claim_today := false;
  END IF;

  FOR i IN 1..7 LOOP
    -- Preserve the tier shown for historical claims. Every new unclaimed
    -- daily signup reward is Low tier.
    SELECT coalesce(
      (SELECT r.tier
       FROM public.signup_daily_rewards r
       WHERE r.uid = v_me
         AND r.cycle_number = v_cycle
         AND r.day_number = i),
      'low'
    )
    INTO v_tier;

    SELECT EXISTS (
      SELECT 1 FROM public.signup_daily_rewards r
      WHERE r.uid = v_me
        AND r.cycle_number = v_cycle
        AND r.day_number = i
    )
    INTO v_claimed;

    v_days := v_days || jsonb_build_object(
      'day', i,
      'tier', v_tier,
      'claimed', v_claimed,
      'available', i = v_next_day AND v_can_claim_today
    );
  END LOOP;

  RETURN jsonb_build_object(
    'enabled', true,
    'referralCode', v_code,
    'firstLoginClaimed', v_user."firstLoginRewardClaimedAt" IS NOT NULL,
    'rewardStartDate', (v_user."signupRewardStartedAt" AT TIME ZONE 'Asia/Kolkata')::date,
    'cycleNumber', v_cycle,
    'currentDay', v_next_day,
    'canClaimToday', v_can_claim_today,
    'days', v_days
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.claim_signup_daily_reward(p_day_number integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_me uuid := auth.uid();
  v_user public.users%rowtype;
  v_cycle integer;
  v_next_day integer;
  v_last_claimed_at timestamptz;
  v_tier text := 'low';
  v_gift_id uuid;
  v_gift_name text;
  v_gift_url text;
BEGIN
  IF v_me IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT * INTO v_user FROM public.users WHERE uid = v_me FOR UPDATE;
  IF v_user.uid IS NULL THEN RAISE EXCEPTION 'User profile not found'; END IF;
  IF NOT coalesce(v_user."signupRewardEligible", false) THEN RAISE EXCEPTION 'REWARD_NOT_AVAILABLE'; END IF;
  IF v_user."firstLoginRewardClaimedAt" IS NULL THEN RAISE EXCEPTION 'FIRST_LOGIN_REWARD_REQUIRED'; END IF;

  SELECT max(r.claimed_at)
    INTO v_last_claimed_at
  FROM public.signup_daily_rewards r
  WHERE r.uid = v_me;

  IF v_last_claimed_at IS NOT NULL
     AND (v_last_claimed_at AT TIME ZONE 'Asia/Kolkata')::date =
         (now() AT TIME ZONE 'Asia/Kolkata')::date THEN
    RAISE EXCEPTION 'ALREADY_CLAIMED_TODAY';
  END IF;

  SELECT coalesce(max(r.cycle_number), 1)
    INTO v_cycle
  FROM public.signup_daily_rewards r
  WHERE r.uid = v_me;

  SELECT coalesce(min(n), 8)
    INTO v_next_day
  FROM generate_series(1, 7) AS n
  WHERE NOT EXISTS (
    SELECT 1 FROM public.signup_daily_rewards r
    WHERE r.uid = v_me AND r.cycle_number = v_cycle AND r.day_number = n
  );

  IF v_next_day = 8 THEN
    v_cycle := v_cycle + 1;
    v_next_day := 1;
  END IF;

  IF p_day_number <> v_next_day OR p_day_number < 1 OR p_day_number > 7 THEN
    RAISE EXCEPTION 'NEXT_REWARD_ONLY';
  END IF;

  -- All new daily signup claims are Low tier.
  v_tier := 'low';

  SELECT id, name, "gifUrl"
    INTO v_gift_id, v_gift_name, v_gift_url
  FROM public.gifts
  WHERE tier = v_tier AND "isActive"
  ORDER BY random()
  LIMIT 1;

  IF v_gift_id IS NULL THEN RAISE EXCEPTION 'No low tier gifts available'; END IF;

  INSERT INTO public.gift_inventory ("ownerUid", "giftId", count, source)
  VALUES (v_me, v_gift_id, 1, 'signup')
  ON CONFLICT ("ownerUid", "giftId") WHERE ("expiresAt" IS NULL)
  DO UPDATE SET count = public.gift_inventory.count + 1;

  INSERT INTO public.signup_daily_rewards (uid, cycle_number, day_number, tier)
  VALUES (v_me, v_cycle, p_day_number, v_tier);

  RETURN jsonb_build_object(
    'day', p_day_number, 'cycleNumber', v_cycle, 'tier', v_tier,
    'giftId', v_gift_id, 'giftName', v_gift_name, 'giftUrl', v_gift_url
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.claim_signup_daily_reward(integer) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.claim_signup_daily_reward(integer) TO authenticated;
