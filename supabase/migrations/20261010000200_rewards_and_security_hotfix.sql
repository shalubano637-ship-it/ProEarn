-- Security and rewards hotfixes applied to production on 2026-10-10.
-- Public profile reads remain available; client writes are blocked.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLE public.public_profiles FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.public_profiles TO anon, authenticated;

-- Post creation must use the trusted server-side moderation/upload path.
REVOKE INSERT ON TABLE public.posts FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.delete_message_for_everyone(p_message_id text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_caller text := auth.uid()::text; v_sender text;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501'; END IF;
  SELECT "senderId"::text INTO v_sender FROM public.messages WHERE id::text = p_message_id;
  IF v_sender IS NULL THEN RAISE EXCEPTION 'Message not found'; END IF;
  IF v_sender IS DISTINCT FROM v_caller THEN RAISE EXCEPTION 'Only the sender can remove this message for everyone' USING ERRCODE = '42501'; END IF;
  UPDATE public.messages SET "deletedForEveryone" = TRUE, text = NULL, "imageUrl" = NULL WHERE id::text = p_message_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.delete_message_for_everyone(p_message_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_caller uuid := auth.uid(); v_sender uuid;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501'; END IF;
  SELECT "senderId" INTO v_sender FROM public.messages WHERE id = p_message_id;
  IF v_sender IS NULL THEN RAISE EXCEPTION 'Message not found'; END IF;
  IF v_sender IS DISTINCT FROM v_caller THEN RAISE EXCEPTION 'Only the sender can remove this message for everyone' USING ERRCODE = '42501'; END IF;
  UPDATE public.messages SET "deletedForEveryone" = TRUE, text = NULL, "imageUrl" = NULL WHERE id = p_message_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.delete_message_for_everyone(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.delete_message_for_everyone(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_message_for_everyone(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_message_for_everyone(uuid) TO authenticated;

CREATE TABLE IF NOT EXISTS public.notification_delivery_dedup (
  "senderId" uuid NOT NULL,
  "targetOwnerId" uuid NOT NULL,
  type text NOT NULL,
  "eventKey" text NOT NULL,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY ("senderId", "targetOwnerId", type, "eventKey")
);
REVOKE ALL ON TABLE public.notification_delivery_dedup FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT ON TABLE public.notification_delivery_dedup TO service_role;

-- Eligible new users must be able to open the signup popup before its first-login
-- reward initializes signupRewardStartedAt.
CREATE OR REPLACE FUNCTION public.get_signup_reward_status()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_me uuid := auth.uid();
  v_user public.users%rowtype;
  v_start date;
  v_today date := (now() at time zone 'Asia/Kolkata')::date;
  v_current_day int;
  v_days jsonb := '[]'::jsonb;
  v_code text;
  i int;
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
    v_user."referralCode" := v_code;
  END IF;
  IF NOT coalesce(v_user."signupRewardEligible", false) THEN
    RETURN jsonb_build_object('enabled', false, 'referralCode', v_user."referralCode");
  END IF;
  v_start := (coalesce(v_user."signupRewardStartedAt", v_user."firstLoginRewardClaimedAt") at time zone 'Asia/Kolkata')::date;
  IF v_start IS NULL THEN
    RETURN jsonb_build_object('enabled', true, 'referralCode', v_user."referralCode", 'firstLoginClaimed', false, 'days', '[]'::jsonb);
  END IF;
  v_current_day := greatest(1, least(7, (v_today - v_start) + 1));
  FOR i IN 1..7 LOOP
    v_tier := CASE WHEN i <= 2 THEN 'low' WHEN i <= 4 THEN 'medium' ELSE 'high' END;
    v_days := v_days || jsonb_build_object(
      'day', i, 'tier', v_tier,
      'claimed', EXISTS (SELECT 1 FROM public.signup_daily_rewards WHERE uid = v_me AND day_number = i),
      'available', i = v_current_day
    );
  END LOOP;
  RETURN jsonb_build_object(
    'enabled', true, 'referralCode', v_user."referralCode",
    'firstLoginClaimed', v_user."firstLoginRewardClaimedAt" IS NOT NULL,
    'rewardStartDate', v_start, 'currentDay', v_current_day, 'days', v_days
  );
END;
$function$;
