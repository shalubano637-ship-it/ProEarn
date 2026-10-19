-- Welcome rewards: one claim per India calendar day, then repeat the 7-day cycle.
-- Existing claims are preserved as cycle 1.

ALTER TABLE public.signup_daily_rewards
  ADD COLUMN IF NOT EXISTS cycle_number integer NOT NULL DEFAULT 1;

ALTER TABLE public.signup_daily_rewards
  DROP CONSTRAINT IF EXISTS signup_daily_rewards_pkey;

ALTER TABLE public.signup_daily_rewards
  ADD CONSTRAINT signup_daily_rewards_pkey
  PRIMARY KEY (uid, cycle_number, day_number);

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
    v_tier := CASE WHEN i <= 2 THEN 'low' WHEN i <= 4 THEN 'medium' ELSE 'high' END;
    v_days := v_days || jsonb_build_object(
      'day', i,
      'tier', v_tier,
      'claimed', EXISTS (
        SELECT 1 FROM public.signup_daily_rewards r
        WHERE r.uid = v_me AND r.cycle_number = v_cycle AND r.day_number = i
      ),
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
  v_tier text;
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

  v_tier := CASE WHEN p_day_number <= 2 THEN 'low' WHEN p_day_number <= 4 THEN 'medium' ELSE 'high' END;

  SELECT id, name, "gifUrl"
    INTO v_gift_id, v_gift_name, v_gift_url
  FROM public.gifts
  WHERE tier = v_tier AND "isActive"
  ORDER BY random()
  LIMIT 1;

  IF v_gift_id IS NULL THEN RAISE EXCEPTION 'No gifts available for tier'; END IF;

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
