alter table public.ad_gift_claims
  add column if not exists "nextUnlockAt" timestamptz;

create or replace function public.get_ad_gift_chest_status()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_caller uuid := auth.uid();
  v_today text := to_char(now() at time zone 'Asia/Kolkata', 'YYYY-MM-DD');
  v_count int;
  v_next_unlock timestamptz;
  v_now timestamptz := now();
begin
  if v_caller is null then
    raise exception 'Not authenticated';
  end if;

  select count, "nextUnlockAt"
    into v_count, v_next_unlock
  from public.ad_gift_claims
  where uid = v_caller
    and "istDate" = v_today
  for update;

  if not found then
    v_count := 0;
    v_next_unlock := v_now + interval '1 minute';

    insert into public.ad_gift_claims (uid, "istDate", count, "nextUnlockAt")
    values (v_caller, v_today, 0, v_next_unlock);
  elsif v_count < 3 and v_next_unlock is null then
    v_next_unlock := v_now + case v_count
      when 0 then interval '1 minute'
      when 1 then interval '3 minutes'
      when 2 then interval '5 minutes'
      else interval '0 minutes'
    end;

    update public.ad_gift_claims
    set "nextUnlockAt" = v_next_unlock
    where uid = v_caller
      and "istDate" = v_today;
  end if;

  return jsonb_build_object(
    'claimedToday', v_count,
    'dailyCap', 3,
    'nextUnlockAt', v_next_unlock
  );
end;
$function$;

create or replace function public.claim_random_gift_from_ad()
returns table("giftId" uuid, "giftName" text)
language plpgsql
security definer
set search_path to 'public'
as $function$
#variable_conflict use_column
declare
  v_caller uuid := auth.uid();
  v_today text := to_char(now() at time zone 'Asia/Kolkata', 'YYYY-MM-DD');
  v_daily_cap constant int := 3;
  v_claimed_today int;
  v_next_unlock timestamptz;
  v_new_count int;
  v_gift record;
begin
  if v_caller is null then
    raise exception 'Not authenticated';
  end if;

  select count, "nextUnlockAt"
    into v_claimed_today, v_next_unlock
  from public.ad_gift_claims
  where uid = v_caller
    and "istDate" = v_today
  for update;

  if not found then
    insert into public.ad_gift_claims (uid, "istDate", count, "nextUnlockAt")
    values (v_caller, v_today, 0, now() + interval '1 minute')
    returning count, "nextUnlockAt"
      into v_claimed_today, v_next_unlock;
  end if;

  v_claimed_today := coalesce(v_claimed_today, 0);

  if v_claimed_today >= v_daily_cap then
    raise exception 'DAILY_LIMIT_REACHED';
  end if;

  if v_next_unlock is null then
    v_next_unlock := now() + case v_claimed_today
      when 0 then interval '1 minute'
      when 1 then interval '3 minutes'
      when 2 then interval '5 minutes'
      else interval '0 minutes'
    end;

    update public.ad_gift_claims
    set "nextUnlockAt" = v_next_unlock
    where uid = v_caller
      and "istDate" = v_today;

    raise exception 'CHEST_LOCKED';
  end if;

  if now() < v_next_unlock then
    raise exception 'CHEST_LOCKED';
  end if;

  select g.id, g.name
    into v_gift
  from public.gifts g
  where g."isActive"
    and g."priceCoins" <= (
      select percentile_cont(0.3)
      within group (order by "priceCoins")
      from public.gifts
      where "isActive"
    )
  order by random()
  limit 1;

  if v_gift.id is null then
    raise exception 'No gifts available';
  end if;

  insert into public.gift_inventory (
    "ownerUid",
    "giftId",
    count,
    source
  )
  values (
    v_caller,
    v_gift.id,
    1,
    'ad'
  )
  on conflict ("ownerUid", "giftId")
  where "expiresAt" is null
  do update
  set count = public.gift_inventory.count + 1;

  v_new_count := v_claimed_today + 1;

  update public.ad_gift_claims
  set count = v_new_count,
      "nextUnlockAt" = case v_new_count
        when 1 then now() + interval '3 minutes'
        when 2 then now() + interval '5 minutes'
        else null
      end
  where uid = v_caller
    and "istDate" = v_today;

  return query
  select v_gift.id, v_gift.name;
end;
$function$;
