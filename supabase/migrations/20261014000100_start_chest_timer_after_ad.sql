-- Gift chest timers start only after the user completes the Start rewarded ad.
alter table public.chest_progress add column if not exists "readyNotificationSentAt" timestamptz;

create or replace function public.start_chest_timer()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_row public.chest_progress%rowtype; v_duration integer;
begin
  if v_uid is null then raise exception 'Not authenticated'; end if;
  select * into v_row from public.chest_progress where uid = v_uid for update;
  if found then
    if v_row."unlockAt" is not null or v_row."isUnlocked" then raise exception 'Chest timer already started or chest is ready'; end if;
    v_duration := public.chest_duration_seconds(v_row."currentChestIndex");
    update public.chest_progress set "remainingSeconds"=v_duration, "unlockAt"=now()+make_interval(secs=>v_duration), "isUnlocked"=false, "readyNotificationSentAt"=null, "updatedAt"=now() where uid=v_uid;
  else
    v_duration := public.chest_duration_seconds(0);
    insert into public.chest_progress(uid,"currentChestIndex","remainingSeconds","unlockAt","isUnlocked","updatedAt","readyNotificationSentAt")
    values(v_uid,0,v_duration,now()+make_interval(secs=>v_duration),false,now(),null);
  end if;
  return jsonb_build_object('started',true,'durationSeconds',v_duration);
end; $$;
revoke all on function public.start_chest_timer() from public, anon;
grant execute on function public.start_chest_timer() to authenticated, service_role;

create or replace function public.sync_chest_timer(p_remaining_seconds integer)
returns void language plpgsql security definer set search_path=public as $$
declare v_uid uuid:=auth.uid(); v_unlock timestamptz; v_remaining integer;
begin
  if v_uid is null then raise exception 'Not authenticated'; end if;
  select "unlockAt" into v_unlock from public.chest_progress where uid=v_uid for update;
  if not found or v_unlock is null then return; end if;
  v_remaining:=greatest(0,ceil(extract(epoch from (v_unlock-now())))::integer);
  update public.chest_progress set "remainingSeconds"=v_remaining,"isUnlocked"=(v_remaining=0) or "isUnlocked","updatedAt"=now() where uid=v_uid;
end; $$;
revoke all on function public.sync_chest_timer(integer) from public, anon;
grant execute on function public.sync_chest_timer(integer) to authenticated, service_role;

create or replace function public.claim_chest_reward(p_chest_index integer)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_me uuid:=auth.uid(); v_progress public.chest_progress%rowtype; v_next_index int; v_tier text; v_gift_id uuid; v_gift_name text; v_gift_url text;
begin
  if v_me is null then raise exception 'Not authenticated'; end if;
  select * into v_progress from public.chest_progress where uid=v_me for update;
  if not found then raise exception 'No chest progress found'; end if;
  if v_progress."currentChestIndex"<>p_chest_index then raise exception 'Chest index mismatch'; end if;
  if v_progress."unlockAt" is null or v_progress."unlockAt">now() then raise exception 'Chest is not unlocked yet'; end if;
  v_next_index:=(p_chest_index+1)%5;
  v_tier:=public.chest_gift_tier(p_chest_index);
  select id,name,"gifUrl" into v_gift_id,v_gift_name,v_gift_url from public.gifts where tier=v_tier and "isActive" order by random() limit 1;
  if v_gift_id is not null then
    insert into public.gift_inventory("ownerUid","giftId",count,source,"expiresAt") values(v_me,v_gift_id,1,'chest',now()+interval '7 days')
    on conflict ("ownerUid","giftId") where "expiresAt" is null do update set count=public.gift_inventory.count+1;
  end if;
  update public.chest_progress set "currentChestIndex"=v_next_index,"remainingSeconds"=public.chest_duration_seconds(v_next_index),"unlockAt"=null,"isUnlocked"=false,"readyNotificationSentAt"=null,"updatedAt"=now() where uid=v_me;
  return jsonb_build_object('giftId',v_gift_id,'giftName',v_gift_name,'gifUrl',v_gift_url);
end; $$;
revoke all on function public.claim_chest_reward(integer) from public, anon;
grant execute on function public.claim_chest_reward(integer) to authenticated, service_role;

create or replace function public.create_due_chest_ready_notifications()
returns integer language plpgsql security definer set search_path=public as $$
declare v_count integer:=0;
begin
  with due as (
    select cp.uid,cp."unlockAt",cp."currentChestIndex" from public.chest_progress cp
    where cp."unlockAt" is not null and cp."unlockAt"<=now() and cp."isUnlocked"=false and cp."readyNotificationSentAt" is null
    for update skip locked
  ), deduped as (
    insert into public.notification_delivery_dedup("senderId","targetOwnerId",type,"eventKey","createdAt")
    select d.uid,d.uid,'chest_ready',d."currentChestIndex"::text||':'||d."unlockAt"::text,now() from due d
    on conflict do nothing returning "targetOwnerId"
  ), inserted as (
    insert into public.notifications("targetOwnerId",type,title,body,"senderId","senderName","senderProfile","senderProfileUrl",message,"targetPostId","isRead","timestamp")
    select d.uid,'chest_ready','Chest Ready','Your chest is ready to open! 🎁',d.uid::text,'Pro Earn','','','Your chest is ready to open! 🎁','',false,now()
    from due d where exists(select 1 from deduped x where x."targetOwnerId"=d.uid) returning "targetOwnerId"
  )
  update public.chest_progress cp set "isUnlocked"=true,"remainingSeconds"=0,"readyNotificationSentAt"=now(),"updatedAt"=now()
  where cp.uid in(select "targetOwnerId" from inserted);
  get diagnostics v_count=row_count;
  return v_count;
end; $$;
revoke all on function public.create_due_chest_ready_notifications() from public, anon, authenticated;
grant execute on function public.create_due_chest_ready_notifications() to service_role;

do $$ begin
  if not exists(select 1 from cron.job where jobname='gift-chest-ready-notifications') then
    perform cron.schedule('gift-chest-ready-notifications','* * * * *','select public.create_due_chest_ready_notifications();');
  end if;
end; $$;
