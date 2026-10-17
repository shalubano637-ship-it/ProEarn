-- Fix duplicate gift inventory rows when a signup reward selects an already-owned gift,
-- and allow image-only room messages while preserving text NOT NULL.

create or replace function public.claim_signup_daily_reward(p_day_number integer)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare
 v_me uuid:=auth.uid(); v_user public.users%rowtype; v_next_day int; v_tier text;
 v_gift_id uuid; v_gift_name text; v_gift_url text;
begin
 if v_me is null then raise exception 'Not authenticated'; end if;
 select * into v_user from public.users where uid=v_me for update;
 if not coalesce(v_user."signupRewardEligible",false) then raise exception 'REWARD_NOT_AVAILABLE'; end if;
 if v_user."firstLoginRewardClaimedAt" is null then raise exception 'FIRST_LOGIN_REWARD_REQUIRED'; end if;
 select coalesce(min(n),8) into v_next_day from generate_series(1,7) as n
 where not exists(select 1 from public.signup_daily_rewards r where r.uid=v_me and r.day_number=n);
 if p_day_number<>v_next_day or p_day_number<1 or p_day_number>7 then raise exception 'NEXT_REWARD_ONLY'; end if;
 v_tier:=case when p_day_number<=2 then 'low' when p_day_number<=4 then 'medium' else 'high' end;
 select id,name,"gifUrl" into v_gift_id,v_gift_name,v_gift_url from public.gifts where tier=v_tier and "isActive" order by random() limit 1;
 if v_gift_id is null then raise exception 'No gifts available for tier'; end if;
 insert into public.gift_inventory("ownerUid","giftId",count,source) values(v_me,v_gift_id,1,'signup')
 on conflict("ownerUid","giftId") do update set count=public.gift_inventory.count+1;
 insert into public.signup_daily_rewards(uid,day_number,tier) values(v_me,p_day_number,v_tier);
 return jsonb_build_object('day',p_day_number,'tier',v_tier,'giftId',v_gift_id,'giftName',v_gift_name,'giftUrl',v_gift_url);
end; $function$;
revoke all on function public.claim_signup_daily_reward(integer) from public,anon;
grant execute on function public.claim_signup_daily_reward(integer) to authenticated;

create or replace function public.send_room_message(p_room_id uuid,p_text text default null,p_image_url text default null,p_reply_to_message_id uuid default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_text text:=coalesce(nullif(trim(coalesce(p_text,'')),''),'');
begin
 if auth.uid() is null then raise exception 'Not authenticated'; end if;
 if v_text='' and nullif(trim(coalesce(p_image_url,'')),'') is null then raise exception 'Message cannot be empty'; end if;
 if not exists(select 1 from public.room_entries where room_id=p_room_id and uid=auth.uid() and exited_at is null) then raise exception 'NOT_IN_ROOM'; end if;
 if p_reply_to_message_id is not null and not exists(select 1 from public.room_messages where id=p_reply_to_message_id and room_id=p_room_id) then raise exception 'INVALID_REPLY'; end if;
 insert into public.room_messages(room_id,sender_id,text,image_url,reply_to_message_id)
 values(p_room_id,auth.uid(),v_text,nullif(trim(coalesce(p_image_url,'')),''),p_reply_to_message_id) returning id into v_id;
 return v_id;
end; $$;
revoke all on function public.send_room_message(uuid,text,text,uuid) from public,anon;
grant execute on function public.send_room_message(uuid,text,text,uuid) to authenticated;
update public.room_messages set text='' where text is null;
alter table public.room_messages alter column text set default '';
alter table public.room_messages alter column text set not null;
