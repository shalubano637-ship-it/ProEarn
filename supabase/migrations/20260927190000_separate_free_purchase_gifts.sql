CREATE OR REPLACE FUNCTION public.send_gift(
  p_gift_id uuid,
  p_post_id uuid,
  p_quantity integer
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_me uuid := auth.uid();
  v_recipient uuid;
  v_remaining int := p_quantity;
  v_row record;
  v_popularity_value numeric(10,2);
  v_total_popularity numeric(14,2);
  v_deduct int;
  v_ist_today date := public.ist_today();
  v_self_gift boolean;
begin
  if v_me is null then raise exception 'Not authenticated'; end if;
  if p_quantity is null or p_quantity <= 0 then raise exception 'Quantity must be positive'; end if;

  select "userName" into v_recipient from public.posts where id = p_post_id;
  if v_recipient is null then raise exception 'Post not found'; end if;

  v_self_gift := v_recipient = v_me;

  select "popularityValue" into v_popularity_value
  from public.gifts
  where id = p_gift_id and "isActive";
  if v_popularity_value is null then raise exception 'Gift not found or not available'; end if;

  if v_self_gift then
    if public.available_gift_count(v_me, p_gift_id) < p_quantity then
      raise exception 'Not enough of this gift in your bag';
    end if;
  else
    if not exists (
      select 1 from public.gift_inventory
      where "ownerUid" = v_me and "giftId" = p_gift_id
        and source = 'purchased' and count > 0
        and public.expires_at_check("expiresAt")
    ) then
      raise exception 'Free gifts can only be used on your own post. Purchase this gift to send it to others.';
    end if;

    if (
      select coalesce(sum(count), 0) from public.gift_inventory
      where "ownerUid" = v_me and "giftId" = p_gift_id
        and source = 'purchased'
        and public.expires_at_check("expiresAt")
    ) < p_quantity then
      raise exception 'Not enough purchased gifts to send';
    end if;
  end if;

  for v_row in
    select id, count from public.gift_inventory
    where "ownerUid" = v_me and "giftId" = p_gift_id
      and public.expires_at_check("expiresAt")
      and (v_self_gift or source = 'purchased')
    order by "expiresAt" asc nulls last
    for update
  loop
    exit when v_remaining <= 0;
    v_deduct := least(v_remaining, v_row.count);
    update public.gift_inventory set count = count - v_deduct where id = v_row.id;
    v_remaining := v_remaining - v_deduct;
  end loop;

  if v_remaining > 0 then raise exception 'Not enough of this gift in your bag'; end if;

  insert into public.gift_received_log
    ("recipientUid", "giftId", "fromUid", "postId", quantity)
  values
    (v_recipient, p_gift_id, v_me, p_post_id, p_quantity);

  v_total_popularity := v_popularity_value * p_quantity;
  perform set_config('app.bypass_column_protection', 'on', true);

  update public.users
  set popularity = popularity + v_total_popularity
  where uid = v_recipient;

  insert into public.daily_popularity_counts (uid, "istDate", popularity)
  values (v_recipient, v_ist_today, v_total_popularity)
  on conflict (uid, "istDate")
  do update set popularity = public.daily_popularity_counts.popularity + v_total_popularity;
end;
$function$;

CREATE OR REPLACE FUNCTION public.send_gift_to_user(
  p_gift_id uuid,
  p_target_uid uuid,
  p_quantity integer
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_caller uuid := auth.uid();
  v_owned int;
  v_popularity_value numeric(10,2);
  v_total_popularity numeric(14,2);
  v_ist_today date := public.ist_today();
begin
  if v_caller is null then raise exception 'Not authenticated'; end if;
  if p_target_uid is null then raise exception 'Target user is required'; end if;
  if p_quantity is null or p_quantity < 1 then raise exception 'Quantity must be at least 1'; end if;

  select "popularityValue" into v_popularity_value
  from public.gifts where id = p_gift_id and "isActive";
  if v_popularity_value is null then raise exception 'Gift not found or not available'; end if;

  select coalesce(sum(count), 0) into v_owned
  from public.gift_inventory
  where "ownerUid" = v_caller and "giftId" = p_gift_id
    and source = 'purchased'
    and ("expiresAt" is null or "expiresAt" > now());

  if v_owned < p_quantity then
    raise exception 'Only purchased gifts can be sent to another user';
  end if;

  update public.gift_inventory gi
  set count = gi.count - p_quantity
  where gi."ownerUid" = v_caller and gi."giftId" = p_gift_id
    and gi.source = 'purchased'
    and (gi."expiresAt" is null or gi."expiresAt" > now())
    and gi.count >= p_quantity;

  if not found then raise exception 'Not enough purchased gifts in your bag'; end if;

  insert into public.gift_inventory ("ownerUid", "giftId", count, source, "expiresAt")
  values (p_target_uid, p_gift_id, p_quantity, 'chat', null)
  on conflict ("ownerUid", "giftId") where "expiresAt" is null
  do update set count = public.gift_inventory.count + p_quantity;

  v_total_popularity := v_popularity_value * p_quantity;
  perform set_config('app.bypass_column_protection', 'on', true);

  update public.users set popularity = popularity + v_total_popularity
  where uid = p_target_uid;

  insert into public.daily_popularity_counts (uid, "istDate", popularity)
  values (p_target_uid, v_ist_today, v_total_popularity)
  on conflict (uid, "istDate")
  do update set popularity = public.daily_popularity_counts.popularity + v_total_popularity;
end;
$function$;
