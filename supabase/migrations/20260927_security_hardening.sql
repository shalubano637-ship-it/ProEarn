-- Security hardening applied to production on 2026-09-27
-- Economy fields, chest timers, Get cooldowns, moderation ownership,
-- private-post state, account deletion throttling, legacy RPC removal,
-- and missing FK indexes.

CREATE OR REPLACE FUNCTION public.protect_users_sensitive_columns()
RETURNS trigger LANGUAGE plpgsql SET search_path=public AS $$
BEGIN
  IF current_setting('app.bypass_column_protection', true)='on' THEN RETURN NEW; END IF;
  IF NEW."mainCoins" IS DISTINCT FROM OLD."mainCoins"
     OR NEW.popularity IS DISTINCT FROM OLD.popularity
     OR NEW."totalGets" IS DISTINCT FROM OLD."totalGets"
     OR NEW.followers IS DISTINCT FROM OLD.followers
     OR NEW.following IS DISTINCT FROM OLD.following
     OR NEW."blockedUsers" IS DISTINCT FROM OLD."blockedUsers"
     OR NEW."hiddenPosts" IS DISTINCT FROM OLD."hiddenPosts"
     OR NEW."isEmailVerified" IS DISTINCT FROM OLD."isEmailVerified"
     OR NEW."isBanned" IS DISTINCT FROM OLD."isBanned"
     OR NEW."referralCode" IS DISTINCT FROM OLD."referralCode"
     OR NEW."referredBy" IS DISTINCT FROM OLD."referredBy"
     OR NEW."firstLoginRewardClaimedAt" IS DISTINCT FROM OLD."firstLoginRewardClaimedAt"
     OR NEW."signupRewardStartedAt" IS DISTINCT FROM OLD."signupRewardStartedAt"
     OR NEW."signupRewardEligible" IS DISTINCT FROM OLD."signupRewardEligible"
  THEN RAISE EXCEPTION 'Protected account fields can only be changed by server operations'; END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS protect_users_columns ON public.users;
CREATE TRIGGER protect_users_columns BEFORE UPDATE ON public.users
FOR EACH ROW EXECUTE FUNCTION public.protect_users_sensitive_columns();

ALTER TABLE public.chest_progress ADD COLUMN IF NOT EXISTS "unlockAt" timestamptz;
ALTER TABLE public.coin_chest_progress ADD COLUMN IF NOT EXISTS "unlockAt" timestamptz;
UPDATE public.chest_progress SET "unlockAt"=now()+make_interval(secs=>GREATEST("remainingSeconds",0)) WHERE "unlockAt" IS NULL;
UPDATE public.coin_chest_progress SET "unlockAt"=now()+make_interval(secs=>GREATEST("remainingSeconds",0)) WHERE "unlockAt" IS NULL;

CREATE OR REPLACE FUNCTION public.sync_chest_timer(p_remaining_seconds integer)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_me uuid:=auth.uid(); v_unlock timestamptz; v_remaining integer;
BEGIN
 IF v_me IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
 SELECT "unlockAt" INTO v_unlock FROM public.chest_progress WHERE uid=v_me FOR UPDATE;
 IF v_unlock IS NULL THEN
   v_unlock:=now()+make_interval(secs=>public.chest_duration_seconds(0));
   INSERT INTO public.chest_progress(uid,"remainingSeconds","unlockAt") VALUES(v_me,public.chest_duration_seconds(0),v_unlock)
   ON CONFLICT(uid) DO UPDATE SET "unlockAt"=COALESCE(public.chest_progress."unlockAt",EXCLUDED."unlockAt");
   RETURN;
 END IF;
 v_remaining:=GREATEST(0,CEIL(EXTRACT(EPOCH FROM(v_unlock-now())))::integer);
 UPDATE public.chest_progress SET "remainingSeconds"=v_remaining,"isUnlocked"=(v_remaining=0) OR "isUnlocked","updatedAt"=now() WHERE uid=v_me;
END $$;

CREATE OR REPLACE FUNCTION public.sync_coin_chest_timer(p_remaining_seconds integer)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_uid text:=auth.uid()::text; v_unlock timestamptz; v_remaining integer;
BEGIN
 IF v_uid IS NULL OR v_uid='' THEN RAISE EXCEPTION 'Authentication required'; END IF;
 SELECT "unlockAt" INTO v_unlock FROM public.coin_chest_progress WHERE uid=v_uid FOR UPDATE;
 IF v_unlock IS NULL THEN
   v_unlock:=now()+interval '60 seconds';
   INSERT INTO public.coin_chest_progress(uid,"remainingSeconds","unlockAt") VALUES(v_uid,60,v_unlock)
   ON CONFLICT(uid) DO UPDATE SET "unlockAt"=COALESCE(public.coin_chest_progress."unlockAt",EXCLUDED."unlockAt");
   RETURN;
 END IF;
 v_remaining:=GREATEST(0,CEIL(EXTRACT(EPOCH FROM(v_unlock-now())))::integer);
 UPDATE public.coin_chest_progress SET "remainingSeconds"=v_remaining,"isUnlocked"=(v_remaining=0) OR "isUnlocked" WHERE uid=v_uid;
END $$;

REVOKE ALL ON FUNCTION public.reset_all_chest_progress() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.reset_coin_chest_progress() FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.redeem_get_prompt(
 p_post_id uuid,p_user_id uuid,p_owner_id uuid,p_next_multiplier integer,p_unlock_time timestamptz)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_me uuid:=auth.uid(); v_now timestamptz:=now(); v_current_multiplier integer;
 v_cooldown_until timestamptz; v_next_multiplier integer; v_next_unlock timestamptz; v_ist_today date:=public.ist_today();
BEGIN
 IF v_me IS NULL OR p_user_id<>v_me THEN RAISE EXCEPTION 'Not authorized'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.posts WHERE id=p_post_id AND "userName"=p_owner_id::text AND "moderationStatus"='approved') THEN RAISE EXCEPTION 'Post unavailable'; END IF;
 IF p_owner_id=v_me THEN RAISE EXCEPTION 'Cannot redeem your own post'; END IF;
 SELECT multiplier,"unlockTime" INTO v_current_multiplier,v_cooldown_until FROM public.cooldowns
 WHERE "postId"=p_post_id AND "userId"=v_me FOR UPDATE;
 IF v_cooldown_until IS NOT NULL AND v_cooldown_until>v_now THEN RAISE EXCEPTION 'Cooldown is active until %',v_cooldown_until; END IF;
 v_current_multiplier:=GREATEST(COALESCE(v_current_multiplier,1),1);
 v_next_multiplier:=LEAST(v_current_multiplier*2,64);
 v_next_unlock:=v_now+make_interval(mins=>v_current_multiplier);
 PERFORM set_config('app.bypass_column_protection','on',true);
 INSERT INTO public.cooldowns("postId","userId",multiplier,"unlockTime") VALUES(p_post_id,v_me,v_next_multiplier,v_next_unlock)
 ON CONFLICT("postId","userId") DO UPDATE SET multiplier=excluded.multiplier,"unlockTime"=excluded."unlockTime";
 UPDATE public.posts SET "getsCount"=COALESCE("getsCount",0)+1 WHERE id=p_post_id;
 UPDATE public.users SET "totalGets"=COALESCE("totalGets",0)+1 WHERE uid=p_owner_id;
 INSERT INTO public.daily_get_counts(uid,"istDate","getsCount") VALUES(p_owner_id,v_ist_today,1)
 ON CONFLICT(uid,"istDate") DO UPDATE SET "getsCount"=public.daily_get_counts."getsCount"+1;
 UPDATE public.users SET "mainCoins"=COALESCE("mainCoins",0)+1 WHERE uid=p_owner_id;
END $$;

CREATE OR REPLACE FUNCTION public.protect_posts_sensitive_columns()
RETURNS trigger LANGUAGE plpgsql SET search_path=public AS $$
BEGIN
 IF current_setting('app.bypass_column_protection',true)='on' THEN RETURN NEW; END IF;
 IF NEW."getsCount" IS DISTINCT FROM OLD."getsCount"
 OR NEW."likedBy" IS DISTINCT FROM OLD."likedBy"
 OR NEW.multiplier IS DISTINCT FROM OLD.multiplier
 OR NEW."unlockTime" IS DISTINCT FROM OLD."unlockTime"
 OR NEW."moderationStatus" IS DISTINCT FROM OLD."moderationStatus"
 OR NEW."moderationCheckedAt" IS DISTINCT FROM OLD."moderationCheckedAt"
 OR NEW."moderationReason" IS DISTINCT FROM OLD."moderationReason"
 OR NEW."mediaObjectKey" IS DISTINCT FROM OLD."mediaObjectKey"
 OR NEW."isPrivatePost" IS DISTINCT FROM OLD."isPrivatePost"
 THEN RAISE EXCEPTION 'Protected post fields can only be changed by server operations'; END IF;
 RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS protect_posts_columns ON public.posts;
CREATE TRIGGER protect_posts_columns BEFORE UPDATE ON public.posts FOR EACH ROW EXECUTE FUNCTION public.protect_posts_sensitive_columns();

DROP VIEW IF EXISTS public.public_profiles;
CREATE VIEW public.public_profiles AS
SELECT uid,"userName",bio,link,"profileUrl","fullName","createdAt","isPrivateAccount","whoCanMessage"
FROM public.users;

DROP FUNCTION IF EXISTS public.email_is_registered(text);
DROP FUNCTION IF EXISTS public.lookup_account_for_reset(text);

ALTER TABLE public.account_deletion_requests ADD COLUMN IF NOT EXISTS request_key text;
CREATE INDEX IF NOT EXISTS account_deletion_requests_created_at_idx ON public.account_deletion_requests(created_at);
CREATE OR REPLACE FUNCTION public.submit_account_deletion_request(p_email text,p_reason text DEFAULT NULL,p_request_key text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_key text:=COALESCE(NULLIF(trim(p_request_key),''),lower(trim(p_email)));
BEGIN
 IF length(v_key)<3 OR length(v_key)>320 THEN RAISE EXCEPTION 'Invalid request key'; END IF;
 PERFORM pg_advisory_xact_lock(hashtext(v_key));
 IF EXISTS(SELECT 1 FROM public.account_deletion_requests WHERE request_key=v_key AND created_at>now()-interval '24 hours')
 THEN RAISE EXCEPTION 'Please wait before submitting another deletion request'; END IF;
 INSERT INTO public.account_deletion_requests(email,reason,status,request_key)
 VALUES(lower(trim(p_email)),left(COALESCE(p_reason,''),1000),'pending',v_key);
END $$;
REVOKE ALL ON public.account_deletion_requests FROM anon,authenticated;
REVOKE ALL ON FUNCTION public.submit_account_deletion_request(text,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.submit_account_deletion_request(text,text,text) TO service_role;

CREATE INDEX IF NOT EXISTS message_requests_recipient_id_idx ON public.message_requests("recipientId");
CREATE INDEX IF NOT EXISTS message_requests_sender_id_idx ON public.message_requests("senderId");
CREATE INDEX IF NOT EXISTS referral_rewards_inviter_uid_idx ON public.referral_rewards(inviter_uid);
CREATE INDEX IF NOT EXISTS users_referred_by_idx ON public.users("referredBy");

REVOKE EXECUTE ON FUNCTION public.claim_first_login_reward() FROM anon;
REVOKE EXECUTE ON FUNCTION public.claim_signup_daily_reward(integer) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_ad_gift_chest_status() FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_leaderboard_by_gets(integer) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_leaderboard_by_gets_for_day(date,integer) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_leaderboard_by_likes(integer) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_leaderboard_by_likes_for_day(date,integer) FROM anon;
REVOKE EXECUTE ON FUNCTION public.delete_message_for_everyone(text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.delete_message_for_everyone(uuid) FROM anon;
ALTER FUNCTION public.generate_referral_code() SET search_path=public;
