-- Schedule each chest timer as a one-shot pg_cron job rather than polling every minute.
-- Cron has minute precision, so delivery may be up to about one minute after unlockAt.

create or replace function public.process_scheduled_chest_timer(p_kind text, p_uid text)
returns void
language plpgsql
security definer
set search_path = public, extensions, cron, vault
as $$
declare
  v_secret text;
  v_job_name text := 'chest-timer-' || p_kind || '-' || substr(md5(p_uid), 1, 16);
  v_unlock_at timestamptz;
  v_index integer;
  v_push_sent_at timestamptz;
  v_uid text;
begin
  if p_kind not in ('gift', 'coin') then
    raise exception 'Invalid chest kind';
  end if;

  select decrypted_secret into v_secret
  from vault.decrypted_secrets
  where name = 'chest_cron_secret'
  limit 1;

  if p_kind = 'gift' then
    select cp."unlockAt", cp."currentChestIndex", cp."pushSentAt", cp.uid::text
      into v_unlock_at, v_index, v_push_sent_at, v_uid
    from public.chest_progress cp
    where cp.uid::text = p_uid
    for update;

    if v_uid is not null and v_unlock_at is not null and v_unlock_at <= now() then
      update public.chest_progress
      set "isUnlocked" = true, "remainingSeconds" = 0,
          "readyNotificationSentAt" = coalesce("readyNotificationSentAt", now()),
          "updatedAt" = now()
      where uid::text = p_uid;
    else
      v_uid := null;
    end if;
  else
    select cp."unlockAt", cp."currentChestIndex", cp."pushSentAt", cp.uid
      into v_unlock_at, v_index, v_push_sent_at, v_uid
    from public.coin_chest_progress cp
    where cp.uid = p_uid
    for update;

    if v_uid is not null and v_unlock_at is not null and v_unlock_at <= now() then
      update public.coin_chest_progress
      set "isUnlocked" = true, "remainingSeconds" = 0
      where uid = p_uid;
    else
      v_uid := null;
    end if;
  end if;

  if v_uid is not null and v_push_sent_at is null
     and v_secret is not null and length(v_secret) >= 16 then
    perform net.http_post(
      url := 'https://mltvpfqfhbhgkejcjpmq.supabase.co/functions/v1/notify',
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-cron-secret', v_secret),
      body := jsonb_build_object('type', 'chest_ready', 'targetOwnerId', v_uid)
    );
  end if;

  -- Remove this one-shot job even if the timer was cancelled or already handled.
  perform cron.unschedule(v_job_name);
end;
$$;

create or replace function public.schedule_chest_timer_job()
returns trigger
language plpgsql
security definer
set search_path = public, extensions, cron
as $$
declare
  v_kind text;
  v_uid text;
  v_job_name text;
  v_unlock_at timestamptz;
  v_schedule text;
begin
  v_kind := case when tg_table_name = 'chest_progress' then 'gift' else 'coin' end;
  v_uid := new.uid::text;
  v_unlock_at := new."unlockAt";
  v_job_name := 'chest-timer-' || v_kind || '-' || substr(md5(v_uid), 1, 16);

  -- Replace a prior schedule when a timer is restarted or extended.
  perform cron.unschedule(jobid)
  from cron.job
  where jobname = v_job_name;

  if v_unlock_at is null or new."isUnlocked" is true then
    return new;
  end if;

  -- pg_cron evaluates schedules in the database cron timezone (normally UTC).
  -- Schedule at the unlock minute, never before the stored deadline.
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
    format('select public.process_scheduled_chest_timer(%L, %L);', v_kind, v_uid)
  );
  return new;
end;
$$;

drop trigger if exists schedule_gift_chest_timer_job on public.chest_progress;
create trigger schedule_gift_chest_timer_job
after insert or update of "unlockAt", "isUnlocked"
on public.chest_progress
for each row execute function public.schedule_chest_timer_job();

drop trigger if exists schedule_coin_chest_timer_job on public.coin_chest_progress;
create trigger schedule_coin_chest_timer_job
after insert or update of "unlockAt", "isUnlocked"
on public.coin_chest_progress
for each row execute function public.schedule_chest_timer_job();

-- Schedule timers that were already running when this migration is applied.
do $$
declare r record;
begin
  for r in select uid::text as uid from public.chest_progress
           where "unlockAt" is not null and "isUnlocked" is false and "unlockAt" > now()
  loop
    perform cron.unschedule(jobid)
    from cron.job
    where jobname = 'chest-timer-gift-' || substr(md5(r.uid), 1, 16);
    perform cron.schedule(
      'chest-timer-gift-' || substr(md5(r.uid), 1, 16),
      extract(minute from date_trunc('minute', (select "unlockAt" from public.chest_progress where uid::text = r.uid)))::int::text || ' ' ||
      extract(hour from date_trunc('minute', (select "unlockAt" from public.chest_progress where uid::text = r.uid)))::int::text || ' ' ||
      extract(day from date_trunc('minute', (select "unlockAt" from public.chest_progress where uid::text = r.uid)))::int::text || ' ' ||
      extract(month from date_trunc('minute', (select "unlockAt" from public.chest_progress where uid::text = r.uid)))::int::text || ' *',
      format('select public.process_scheduled_chest_timer(%L, %L);', 'gift', r.uid)
    );
  end loop;

  for r in select uid from public.coin_chest_progress
           where "unlockAt" is not null and "isUnlocked" is false and "unlockAt" > now()
  loop
    perform cron.unschedule(jobid)
    from cron.job
    where jobname = 'chest-timer-coin-' || substr(md5(r.uid), 1, 16);
    perform cron.schedule(
      'chest-timer-coin-' || substr(md5(r.uid), 1, 16),
      extract(minute from date_trunc('minute', (select "unlockAt" from public.coin_chest_progress where uid = r.uid)))::int::text || ' ' ||
      extract(hour from date_trunc('minute', (select "unlockAt" from public.coin_chest_progress where uid = r.uid)))::int::text || ' ' ||
      extract(day from date_trunc('minute', (select "unlockAt" from public.coin_chest_progress where uid = r.uid)))::int::text || ' ' ||
      extract(month from date_trunc('minute', (select "unlockAt" from public.coin_chest_progress where uid = r.uid)))::int::text || ' *',
      format('select public.process_scheduled_chest_timer(%L, %L);', 'coin', r.uid)
    );
  end loop;
end $$;

-- Disable the global minute poll only after per-timer schedules are installed.
select cron.unschedule(jobid) from cron.job where jobname = 'gift-chest-ready-notifications';
