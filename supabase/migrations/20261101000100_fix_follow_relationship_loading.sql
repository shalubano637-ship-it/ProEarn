create or replace function public.get_follow_relationships(p_target_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_me uuid := auth.uid();
  v_private boolean;
  v_followers text[];
  v_following text[];
  v_is_following boolean;
begin
  if v_me is null then
    raise exception 'Not authenticated';
  end if;

  select coalesce("isPrivateAccount", false), coalesce(followers, array[]::text[]), coalesce(following, array[]::text[])
    into v_private, v_followers, v_following
  from public.users
  where uid = p_target_id;

  if not found then
    raise exception 'Profile not found';
  end if;

  v_is_following := v_followers @> array[v_me::text];

  if v_private and p_target_id <> v_me and not v_is_following then
    return jsonb_build_object(
      'followers', '[]'::jsonb,
      'following', '[]'::jsonb,
      'can_view', false
    );
  end if;

  return jsonb_build_object(
    'followers', to_jsonb(v_followers),
    'following', to_jsonb(v_following),
    'can_view', true
  );
end;
$function$;

revoke all on function public.get_follow_relationships(uuid) from public, anon;
grant execute on function public.get_follow_relationships(uuid) to authenticated;
