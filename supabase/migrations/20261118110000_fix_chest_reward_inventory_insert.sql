-- Fix chest reward insertion: expiring chest gifts do not match the
-- permanent inventory partial unique index, so they must be inserted as
-- separate rows without an ON CONFLICT clause.

create or replace function public.claim_chest_reward(p_chest_index integer)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_progress public.chest_progress%rowtype;
  v_next_index int;
  v_tier text;
  v_gift_id uuid;
  v_gift_name text;
  v_gift_url text;
begin
  if v_me is null then raise exception 'Not authenticated'; end if;

  select * into v_progress
  from public.chest_progress
  where uid = v_me
  for update;

  if not found then raise exception 'No chest progress found'; end if;
  if v_progress."currentChestIndex" <> p_chest_index then
    raise exception 'Chest index mismatch';
  end if;
  if v_progress."unlockAt" is null or v_progress."unlockAt" > now() then
    raise exception 'Chest is not unlocked yet';
  end if;

  v_next_index := (p_chest_index + 1) % 5;
  v_tier := public.chest_gift_tier(p_chest_index);

  select id, name, "gifUrl"
  into v_gift_id, v_gift_name, v_gift_url
  from public.gifts
  where tier = v_tier and "isActive"
  order by random()
  limit 1;

  if v_gift_id is not null then
    insert into public.gift_inventory("ownerUid", "giftId", count, source, "expiresAt")
    values (v_me, v_gift_id, 1, 'chest', now() + interval '7 days');
  end if;

  update public.chest_progress
  set "currentChestIndex" = v_next_index,
      "remainingSeconds" = public.chest_duration_seconds(v_next_index),
      "unlockAt" = null,
      "isUnlocked" = false,
      "readyNotificationSentAt" = null,
      "pushSentAt" = null,
      "updatedAt" = now()
  where uid = v_me;

  return jsonb_build_object('giftId', v_gift_id, 'giftName', v_gift_name, 'gifUrl', v_gift_url);
end;
$$;

revoke all on function public.claim_chest_reward(integer) from public, anon;
grant execute on function public.claim_chest_reward(integer) to authenticated, service_role;
