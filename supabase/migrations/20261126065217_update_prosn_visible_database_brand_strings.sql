CREATE OR REPLACE FUNCTION public.check_text_moderation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_combined_text text;
  v_term text;
BEGIN
  IF TG_TABLE_NAME = 'posts' THEN
    v_combined_text := lower(coalesce(NEW.caption, '') || ' ' || coalesce(NEW.prompt, ''));
  ELSIF TG_TABLE_NAME = 'comments' THEN
    v_combined_text := lower(coalesce(NEW."commentText", ''));
  ELSE
    RETURN NEW;
  END IF;

  FOR v_term IN SELECT term FROM public.moderation_blocklist LOOP
    IF v_combined_text LIKE '%' || v_term || '%' THEN
      RAISE EXCEPTION 'Content rejected: contains a term not allowed on ProSN.'
        USING ERRCODE = 'P0001';
    END IF;
  END LOOP;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_due_chest_ready_notifications()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_count integer := 0;
  v_secret text;
  r record;
BEGIN
  SELECT decrypted_secret INTO v_secret
  FROM vault.decrypted_secrets
  WHERE name = 'chest_cron_secret'
  LIMIT 1;

  FOR r IN
    SELECT
      cp.uid,
      cp."unlockAt",
      cp."currentChestIndex",
      cp."readyNotificationSentAt",
      cp."pushSentAt",
      cp."isUnlocked"
    FROM public.chest_progress cp
    WHERE cp."unlockAt" IS NOT NULL
      AND cp."unlockAt" <= now()
      AND (
        cp."isUnlocked" = false
        OR cp."readyNotificationSentAt" IS NULL
        OR cp."pushSentAt" IS NULL
      )
    FOR UPDATE SKIP LOCKED
  LOOP
    -- Persist readiness independently of notification deduplication.
    UPDATE public.chest_progress
    SET "isUnlocked" = true,
        "remainingSeconds" = 0,
        "readyNotificationSentAt" = coalesce("readyNotificationSentAt", now()),
        "updatedAt" = now()
    WHERE uid = r.uid;

    IF r."readyNotificationSentAt" IS NULL THEN
      INSERT INTO public.notification_delivery_dedup
        ("senderId", "targetOwnerId", type, "eventKey", "createdAt")
      VALUES
        (r.uid, r.uid, 'chest_ready',
         r."currentChestIndex"::text || ':' || r."unlockAt"::text, now())
      ON CONFLICT DO NOTHING;

      INSERT INTO public.notifications
        ("targetOwnerId", type, title, body, "senderId", "senderName",
         "senderProfile", "senderProfileUrl", message, "targetPostId",
         "isRead", "timestamp")
      SELECT
        r.uid, 'chest_ready', 'Chest Ready',
        'Your chest is ready to open! 🎁', r.uid::text, 'ProSN',
        '', '', 'Your chest is ready to open! 🎁', '', false, now()
      WHERE NOT EXISTS (
        SELECT 1
        FROM public.notifications n
        WHERE n."targetOwnerId" = r.uid
          AND n.type = 'chest_ready'
          AND n."timestamp" >= r."unlockAt"
      );
    END IF;

    -- Server-to-server call: works even when the user's app is closed.
    -- The Edge Function validates this secret and sends the Firebase Cloud Messaging (FCM) push.
    IF r."pushSentAt" IS NULL AND v_secret IS NOT NULL AND length(v_secret) >= 16 THEN
      PERFORM net.http_post(
        url := 'https://mltvpfqfhbhgkejcjpmq.supabase.co/functions/v1/notify',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'x-cron-secret', v_secret
        ),
        body := jsonb_build_object(
          'type', 'chest_ready',
          'targetOwnerId', r.uid::text
        )
      );
    END IF;

    v_count := v_count + 1;
  END LOOP;

  IF v_secret IS NULL OR length(v_secret) < 16 THEN
    RAISE WARNING 'Chest push secret missing; inbox notifications were processed but push calls were skipped.';
  END IF;

  RETURN v_count;
END;
$function$;