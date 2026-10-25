-- Keep timer-based push scheduling exclusively for Gift Chest.

drop trigger if exists schedule_coin_chest_timer_job on public.coin_chest_progress;
drop trigger if exists schedule_gift_chest_timer_job on public.chest_progress;

do $$
declare r record;
begin
  for r in select jobid from cron.job where jobname like 'chest-timer-coin-%'
  loop
    perform cron.unschedule(r.jobid);
  end loop;
end $$;

drop function if exists public.schedule_chest_timer_job();

create or replace function public.process_scheduled_gift_chest_timer(p_uid text)
returns void
language plpgsql
security definer
set search_path = public, extensions, cron, vault
as $$
declare
  v_secret text;
  v_job_name text := 'chest-timer-gift-' || substr(md5(p_uid), 1, 16);
  v_unlock_at timestamptz;
  v_push_sent_at timestamptz;
  v_uid text;
begin
  select decrypted_secret into v_secret
  from vault.decrypted_secrets
  where name = 'chest_cron_secret'
  limit 1;

  select cp."unlockAt", cp."pushSentAt", cp.uid::text
    into v_unlock_at, v_push_sent_at, v_uid
  from public.chest_progress cp
  where cp.uid::text = p_uid
  for update;

  if v_uid is not null and v_unlock_at is not null and v_unlock_at <= now() then
    update public.chest_progress
    set "isUnlocked" = true,
        "remainingSeconds" = 0,
        "readyNotificationSentAt" = coalesce("readyNotificationSentAt", now()),
        "updatedAt" = now()
    where uid::text = p_uid;

    if v_push_sent_at is null and v_secret is not null and length(v_secret) >= 16 then
      perform net.http_post(
        url := 'https://mltvpfqfhbhgkejcjpmq.supabase.co/functions/v1/notify',
        headers := jsonb_build_object('Content-Type', 'application/json', 'x-cron-secret', v_secret),
        body := jsonb_build_object('type', 'chest_ready', 'targetOwnerId', v_uid)
      );
    end if;
  end if;

  perform cron.unschedule(v_job_name);
end;
$$;

create or replace function public.schedule_gift_chest_timer_job()
returns trigger
language plpgsql
security definer
set search_path = public, extensions, cron
as $$
declare
  v_uid text := new.uid::text;
  v_job_name text := 'chest-timer-gift-' || substr(md5(new.uid::text), 1, 16);
  v_unlock_at timestamptz := new."unlockAt";
  v_schedule text;
begin
  perform cron.unschedule(jobid)
  from cron.job
  where jobname = v_job_name;

  if v_unlock_at is null or new."isUnlocked" is true then
    return new;
  end if;

  v_unlock_at := date_trunc('minute', v_unlock_at);
  if v_unlock_at <= date_trunc('minute', now()) then
    v_unlock_at := date_trunc('minute', now()) + interval '1 minute';
  end if;

  v_schedule := extract(minute from v_unlock_at)::int::text || ' ' ||
                extract(hour from v_unlock_at)::int::text || ' ' ||
                extract(day from v_unlock_at)::int::text || ' ' ||
                extract(month from v_unlock_at)::int::text || ' *';

  perform cron.schedule(
    v_job_name,
    v_schedule,
    format('select public.process_scheduled_gift_chest_timer(%L);', v_uid)
  );
  return new;
end;
$$;

create trigger schedule_gift_chest_timer_job
after insert or update of "unlockAt", "isUnlocked"
on public.chest_progress
for each row execute function public.schedule_gift_chest_timer_job();

-- Recreate schedules for Gift Chest timers that are already running.
do $$
declare r record;
declare v_unlock_at timestamptz;
declare v_schedule text;
begin
  for r in
    select uid::text as uid, "unlockAt" as unlock_at
    from public.chest_progress
    where "unlockAt" is not null and "isUnlocked" is false and "unlockAt" > now()
  loop
    perform cron.unschedule(jobid)
    from cron.job
    where jobname = 'chest-timer-gift-' || substr(md5(r.uid), 1, 16);

    v_unlock_at := date_trunc('minute', r.unlock_at);
    if v_unlock_at <= date_trunc('minute', now()) then
      v_unlock_at := date_trunc('minute', now()) + interval '1 minute';
    end if;
    v_schedule := extract(minute from v_unlock_at)::int::text || ' ' ||
                  extract(hour from v_unlock_at)::int::text || ' ' ||
                  extract(day from v_unlock_at)::int::text || ' ' ||
                  extract(month from v_unlock_at)::int::text || ' *';

    perform cron.schedule(
      'chest-timer-gift-' || substr(md5(r.uid), 1, 16),
      v_schedule,
      format('select public.process_scheduled_gift_chest_timer(%L);', r.uid)
    );
  end loop;
end $$;
