create table if not exists public.room_favorites (
  uid uuid not null references public.users(uid) on delete cascade,
  room_id uuid not null references public.rooms(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (uid, room_id)
);

create index if not exists room_favorites_uid_created_idx
  on public.room_favorites(uid, created_at desc);

alter table public.room_favorites enable row level security;
revoke all on public.room_favorites from public, anon, authenticated;

create or replace function public.toggle_room_favorite(p_room_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_exists boolean;
begin
  if v_uid is null then raise exception 'Not authenticated'; end if;
  if not exists (select 1 from public.rooms where id = p_room_id) then
    raise exception 'ROOM_NOT_FOUND';
  end if;
  select exists(
    select 1 from public.room_favorites
    where uid = v_uid and room_id = p_room_id
  ) into v_exists;
  if v_exists then
    delete from public.room_favorites where uid = v_uid and room_id = p_room_id;
    return false;
  end if;
  insert into public.room_favorites(uid, room_id) values (v_uid, p_room_id);
  return true;
end;
$$;

create or replace function public.get_room_favorite_status(p_room_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(
    select 1 from public.room_favorites
    where uid = auth.uid() and room_id = p_room_id
  );
$$;

create or replace function public.list_favorite_rooms()
returns table(
  id uuid,
  number bigint,
  title text,
  owner_id uuid,
  owner_name text,
  avatar text,
  private_room boolean,
  members bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select
    r.id,
    r.room_number,
    r.name,
    r.owner_uid,
    coalesce(u."userName", 'User'),
    coalesce(r.profile_url, ''),
    (r.password_hash is not null),
    (select count(*) from public.room_entries e where e.room_id = r.id and e.exited_at is null)
  from public.room_favorites f
  join public.rooms r on r.id = f.room_id
  left join public.users u on u.uid = r.owner_uid
  where f.uid = auth.uid()
  order by f.created_at desc;
$$;

revoke all on function public.toggle_room_favorite(uuid) from public, anon;
grant execute on function public.toggle_room_favorite(uuid) to authenticated;
revoke all on function public.get_room_favorite_status(uuid) from public, anon;
grant execute on function public.get_room_favorite_status(uuid) to authenticated;
revoke all on function public.list_favorite_rooms() from public, anon;
grant execute on function public.list_favorite_rooms() to authenticated;
