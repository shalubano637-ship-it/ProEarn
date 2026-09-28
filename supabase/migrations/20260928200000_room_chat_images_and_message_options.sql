alter table public.room_messages add column if not exists reply_to_message_id uuid references public.room_messages(id) on delete set null;
drop function if exists public.get_room_messages(uuid,integer);
drop function if exists public.send_room_message(uuid,text,text);
create or replace function public.send_room_message(p_room_id uuid,p_text text default null,p_image_url text default null,p_reply_to_message_id uuid default null)
returns uuid language plpgsql security definer set search_path=public
as $$
declare v_id uuid;
begin
 if auth.uid() is null then raise exception 'Not authenticated'; end if;
 if nullif(trim(coalesce(p_text,'')),'') is null and nullif(trim(coalesce(p_image_url,'')),'') is null then raise exception 'Message cannot be empty'; end if;
 if not exists(select 1 from public.room_entries where room_id=p_room_id and uid=auth.uid() and exited_at is null) then raise exception 'NOT_IN_ROOM'; end if;
 if p_reply_to_message_id is not null and not exists(select 1 from public.room_messages where id=p_reply_to_message_id and room_id=p_room_id) then raise exception 'INVALID_REPLY'; end if;
 insert into public.room_messages(room_id,sender_id,text,image_url,reply_to_message_id)
 values(p_room_id,auth.uid(),nullif(trim(coalesce(p_text,'')),''),nullif(trim(coalesce(p_image_url,'')),''),p_reply_to_message_id)
 returning id into v_id;
 return v_id;
end; $$;
create or replace function public.get_room_messages(p_room_id uuid,p_limit integer default 100)
returns table(id uuid,sender_id uuid,sender_name text,sender_profile_url text,text text,image_url text,reply_to_message_id uuid,reply_text text,reply_sender_name text,created_at timestamptz)
language plpgsql security definer set search_path=public
as $$
declare v_entered_at timestamptz;
begin
 if auth.uid() is null then raise exception 'Not authenticated'; end if;
 select e.entered_at into v_entered_at from public.room_entries e where e.room_id=p_room_id and e.uid=auth.uid() and e.exited_at is null order by e.entered_at desc limit 1;
 if v_entered_at is null then raise exception 'NOT_IN_ROOM'; end if;
 return query
 select m.id,m.sender_id,coalesce(u."userName",'User'),coalesce(u."profileUrl",''),
        m.text,m.image_url,m.reply_to_message_id,rm.text,coalesce(ru."userName",'User'),m.created_at
 from public.room_messages m
 join public.users u on u.uid=m.sender_id
 left join public.room_messages rm on rm.id=m.reply_to_message_id
 left join public.users ru on ru.uid=rm.sender_id
 where m.room_id=p_room_id and m.created_at>=v_entered_at
 order by m.created_at asc limit greatest(1,least(coalesce(p_limit,100),200));
end; $$;
revoke all on function public.send_room_message(uuid,text,text,uuid) from public,anon;
grant execute on function public.send_room_message(uuid,text,text,uuid) to authenticated;
revoke all on function public.get_room_messages(uuid,integer) from public,anon;
grant execute on function public.get_room_messages(uuid,integer) to authenticated;