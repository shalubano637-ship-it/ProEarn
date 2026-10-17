-- Room leaderboard
-- Ranks rooms by unique people who entered the room.
-- Today/Yesterday/day_before_yesterday use IST dates; all_time counts all entries.

create or replace function public.get_room_leaderboard(
  p_period text default 'today',
  p_limit integer default 50
)
returns table(
  room_id uuid,
  room_number bigint,
  room_name text,
  owner_uid uuid,
  owner_name text,
  profile_url text,
  private_room boolean,
  score bigint
)
language sql
stable
security definer
set search_path = public
as $$
  with bounds as (
    select case
      when lower(coalesce(p_period, 'today')) = 'today'
        then (public.ist_today())::date
      when lower(coalesce(p_period, 'today')) = 'yesterday'
        then ((public.ist_today())::date - 1)
      when lower(coalesce(p_period, 'today')) = 'day_before_yesterday'
        then ((public.ist_today())::date - 2)
      else null::date
    end as day
  ),
  ranked as (
    select re.room_id, count(distinct re.uid)::bigint as score
    from public.room_entries as re
    cross join bounds as b
    where b.day is null
       or (re.entered_at at time zone 'Asia/Kolkata')::date = b.day
    group by re.room_id
  )
  select
    r.id,
    r.room_number,
    r.name,
    r.owner_uid,
    coalesce(pp."userName", u."userName", 'User'),
    coalesce(pp."profileUrl", u."profileUrl", ''),
    (r.password_hash is not null),
    ranked.score
  from ranked
  join public.rooms as r on r.id = ranked.room_id
  left join public.public_profiles as pp on pp.uid = r.owner_uid
  left join public.users as u on u.uid = r.owner_uid
  order by ranked.score desc, r.room_number asc
  limit greatest(1, least(coalesce(p_limit, 50), 1000));
$$;

revoke all on function public.get_room_leaderboard(text, integer) from public, anon;
grant execute on function public.get_room_leaderboard(text, integer) to authenticated;

create index if not exists room_entries_room_entered_uid_idx
  on public.room_entries(room_id, entered_at, uid);
