create or replace function public.create_due_chest_ready_notifications()
returns integer
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_count integer := 0;
  v_secret text;
  r record;
begin
  select decrypted_secret into v_secret
  from vault.decrypted_secrets
  where name = 'chest_cron_secret'
  limit 1;

  for r in
    select
      cp.uid,
      cp."unlockAt",
      cp."currentChestIndex",
      cp."readyNotificationSentAt",
      cp."pushSentAt",
      cp."isUnlocked"
    from public.chest_progress cp
    where cp."unlockAt" is not null
      and cp."unlockAt" <= now()
      and (
        cp."isUnlocked" = false
        or cp."readyNotificationSentAt" is null
        or cp."pushSentAt" is null
      )
    for update skip locked
  loop
    -- Persist readiness independently of notification deduplication. A stale
    -- dedup row must never prevent the server from unlocking the chest.
    update public.chest_progress
    set "isUnlocked" = true,
        "remainingSeconds" = 0,
        "readyNotificationSentAt" = coalesce("readyNotificationSentAt", now()),
        "updatedAt" = now()
    where uid = r.uid;

    if r."readyNotificationSentAt" is null then
      insert into public.notification_delivery_dedup
        ("senderId", "targetOwnerId", type, "eventKey", "createdAt")
      values
        (r.uid, r.uid, 'chest_ready',
         r."currentChestIndex"::text || ':' || r."unlockAt"::text, now())
      on conflict do nothing;

      insert into public.notifications
        ("targetOwnerId", type, title, body, "senderId", "senderName",
         "senderProfile", "senderProfileUrl", message, "targetPostId",
         "isRead", "timestamp")
      select
        r.uid, 'chest_ready', 'Chest Ready',
        'Your chest is ready to open! 🎁', r.uid::text, 'Pro Earn',
        '', '', 'Your chest is ready to open! 🎁', '', false, now()
      where not exists (
        select 1
        from public.notifications n
        where n."targetOwnerId" = r.uid
          and n.type = 'chest_ready'
          and n."timestamp" >= r."unlockAt"
      );
    end if;

    -- Server-to-server call: works even when the user's app is closed.
    -- The Edge Function validates this secret and sends the OneSignal push.
    if r."pushSentAt" is null and v_secret is not null and length(v_secret) >= 16 then
      perform net.http_post(
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
    end if;

    v_count := v_count + 1;
  end loop;

  if v_secret is null or length(v_secret) < 16 then
    raise warning 'Chest push secret missing; inbox notifications were processed but push calls were skipped.';
  end if;

  return v_count;
end;
$function$;

revoke all on function public.create_due_chest_ready_notifications() from public, anon, authenticated;
grant execute on function public.create_due_chest_ready_notifications() to service_role;
