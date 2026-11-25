-- Reset Gift Chest progress at midnight India time and clear the prior cycle's timer state.
CREATE OR REPLACE FUNCTION public.reset_all_chest_progress()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
BEGIN
  UPDATE public.chest_progress
  SET "currentChestIndex" = 0,
      "remainingSeconds" = public.chest_duration_seconds(0),
      "unlockAt" = NULL,
      "isUnlocked" = false,
      "readyNotificationSentAt" = NULL,
      "pushSentAt" = NULL,
      "updatedAt" = now();

  PERFORM public.sweep_expired_chest_gifts();
END;
$function$;

DO $schedule$
DECLARE
  v_job_id bigint;
BEGIN
  SELECT jobid INTO v_job_id
  FROM cron.job
  WHERE jobname = 'reset-chests-midnight-ist'
  LIMIT 1;

  IF v_job_id IS NOT NULL THEN
    PERFORM cron.unschedule(v_job_id);
  END IF;

  -- pg_cron uses GMT/UTC in this project. 18:30 UTC = 00:00 Asia/Kolkata.
  PERFORM cron.schedule(
    'reset-chests-midnight-ist',
    '30 18 * * *',
    'SELECT public.reset_all_chest_progress();'
  );
END;
$schedule$;
