create or replace function public.revoke_play_subscription(
  p_user_id uuid,
  p_purchase_token text
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_until timestamptz;
begin
  if p_user_id is null or p_purchase_token is null then
    raise exception 'Invalid subscription';
  end if;

  update public.play_subscriptions
  set status = 'revoked', updated_at = now()
  where user_id = p_user_id and purchase_token = p_purchase_token;

  select max(expires_at) into v_until
  from public.play_subscriptions
  where user_id = p_user_id and status = 'active' and expires_at > now();

  perform set_config('app.bypass_column_protection', 'on', true);
  update public.users
  set "isAdFree" = v_until is not null,
      "adFreeUntil" = v_until
  where uid = p_user_id;

  return jsonb_build_object('success',true,'active',v_until is not null,'expiresAt',v_until);
end;
$$;
revoke all on function public.revoke_play_subscription(uuid,text) from public, anon, authenticated;
grant execute on function public.revoke_play_subscription(uuid,text) to service_role;
