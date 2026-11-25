-- Reset the complete Gift Chest cycle at 00:00 India Standard Time.
-- Supabase pg_cron runs in GMT/UTC; 18:30 UTC is 00:00 IST.
--
-- Also clear the previous cycle's unlock and notification markers. If unlockAt
-- remains set, the app can interpret the expired timestamp as an unlocked chest
-- after the daily reset.

create or replace function public.reset_all_chest_progress()
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  update public.chest_progress
  set "currentChestIndex" = 0,
      "remainingSeconds" = public.chest_duration_seconds(0),
      "unlockAt" = null,
      "isUnlocked" = false,
      "readyNotificationSentAt" = null,
      "pushSentAt" = null,
      "updatedAt" = now();

  -- Retain the existing expiry cleanup; unexpired gift inventory is untouched.
  perform public.sweep_expired_chest_gifts();
end;
$function$;

do $block$
declare
  v_job_id bigint;
begin
  select jobid
    into v_job_id
  from cron.job
  where jobname = 'reset-chests-midnight-ist';

  if v_job_id is null then
    raise exception 'Required cron job reset-chests-midnight-ist was not found.';
  end if;

  perform cron.alter_job(
    job_id := v_job_id,
    schedule := '30 18 * * *',
    command := 'select public.reset_all_chest_progress();',
    active := true
  );
end;
$block$;
