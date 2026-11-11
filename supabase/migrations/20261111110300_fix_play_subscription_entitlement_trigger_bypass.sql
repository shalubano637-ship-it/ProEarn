create or replace function public.record_verified_play_purchase(
  p_user_id uuid,
  p_product_id text,
  p_purchase_token text,
  p_order_id text,
  p_expires_at timestamptz default null
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_coins integer := 0;
  v_type text;
  v_inserted integer := 0;
  v_existing public.play_purchase_events%rowtype;
begin
  if p_user_id is null or p_purchase_token is null or length(p_purchase_token) < 20 then
    raise exception 'Invalid purchase';
  end if;
  v_coins := case p_product_id
    when 'coins_100' then 100 when 'coins_275' then 275
    when 'coins_700' then 700 when 'coins_1700' then 1700
    when 'coins_3800' then 3800 when 'coins_9200' then 9200 else 0
  end;
  if v_coins > 0 then
    v_type := 'coin_pack';
  elsif p_product_id in ('ad_free_weekly','ad_free_monthly') then
    v_type := 'subscription';
    if p_expires_at is null or p_expires_at <= now() then
      raise exception 'Subscription is not active';
    end if;
  else
    raise exception 'Unknown Play product';
  end if;
  insert into public.play_purchase_events(
    purchase_token,user_id,product_id,purchase_type,order_id,coins_granted
  ) values (p_purchase_token,p_user_id,p_product_id,v_type,p_order_id,v_coins)
  on conflict (purchase_token) do nothing;
  get diagnostics v_inserted = row_count;
  if v_inserted = 0 then
    select * into v_existing from public.play_purchase_events where purchase_token = p_purchase_token;
    if v_existing.user_id <> p_user_id or v_existing.product_id <> p_product_id then
      raise exception 'Purchase token is already linked to another account or product';
    end if;
  end if;
  if v_type = 'coin_pack' then
    if v_inserted = 1 then
      perform set_config('app.bypass_column_protection', 'on', true);
      update public.users set "mainCoins" = coalesce("mainCoins",0) + v_coins where uid = p_user_id;
      if not found then raise exception 'User profile not found'; end if;
    end if;
    return jsonb_build_object('success',true,'duplicate',v_inserted = 0,
      'coinsGranted',case when v_inserted = 1 then v_coins else 0 end);
  end if;
  insert into public.play_subscriptions(
    purchase_token,user_id,product_id,order_id,status,expires_at,updated_at
  ) values (p_purchase_token,p_user_id,p_product_id,p_order_id,'active',p_expires_at,now())
  on conflict (purchase_token) do update
    set order_id = excluded.order_id, status = 'active',
        expires_at = greatest(public.play_subscriptions.expires_at, excluded.expires_at),
        updated_at = now()
    where public.play_subscriptions.user_id = excluded.user_id
      and public.play_subscriptions.product_id = excluded.product_id;
  if not exists (
    select 1 from public.play_subscriptions
    where purchase_token = p_purchase_token and user_id = p_user_id and product_id = p_product_id
  ) then raise exception 'Subscription token conflict'; end if;
  perform set_config('app.bypass_column_protection', 'on', true);
  update public.users
  set "isAdFree" = true,
      "adFreeUntil" = greatest(coalesce("adFreeUntil",p_expires_at),p_expires_at)
  where uid = p_user_id;
  return jsonb_build_object('success',true,'duplicate',v_inserted = 0,'adFreeUntil',p_expires_at);
end;
$$;
