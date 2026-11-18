-- Private-account follow requests and post visibility enforcement.
create table if not exists public.follow_requests (
  id uuid primary key default gen_random_uuid(),
  requester_uid uuid not null references public.users(uid) on delete cascade,
  target_uid uuid not null references public.users(uid) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted','declined','cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (requester_uid <> target_uid)
);
create unique index if not exists follow_requests_one_pending on public.follow_requests(requester_uid,target_uid) where status='pending';
create index if not exists follow_requests_target_pending on public.follow_requests(target_uid,created_at desc) where status='pending';
alter table public.follow_requests enable row level security;
drop policy if exists follow_requests_select_participants on public.follow_requests;
create policy follow_requests_select_participants on public.follow_requests for select to authenticated
using (auth.uid()=requester_uid or auth.uid()=target_uid);
alter table public.notifications add column if not exists "requestId" uuid;

create or replace function public.request_private_follow(p_target_uid uuid)
returns text language plpgsql security definer set search_path=public as $$
declare v_me uuid:=auth.uid(); v_private boolean; v_target_blocked text[]; v_request_id uuid; v_sender_name text; v_sender_profile text;
begin
 if v_me is null then raise exception 'Not authenticated'; end if;
 if p_target_uid is null or p_target_uid=v_me then raise exception 'Invalid target'; end if;
 select coalesce("isPrivateAccount",false),coalesce("blockedUsers",array[]::text[]) into v_private,v_target_blocked from public.users where uid=p_target_uid;
 if not found then raise exception 'User not found'; end if;
 if not v_private then raise exception 'Account is public'; end if;
 if exists(select 1 from public.users where uid=v_me and "blockedUsers" @> array[p_target_uid::text]) or v_target_blocked @> array[v_me::text] then raise exception 'Follow is not allowed'; end if;
 if exists(select 1 from public.users where uid=p_target_uid and followers @> array[v_me::text]) then return 'following'; end if;
 insert into public.follow_requests(requester_uid,target_uid,status) values(v_me,p_target_uid,'pending')
 on conflict (requester_uid,target_uid) where status='pending' do nothing returning id into v_request_id;
 if v_request_id is null then
   select id into v_request_id from public.follow_requests where requester_uid=v_me and target_uid=p_target_uid and status='pending';
   return 'pending';
 end if;
 select "userName","profileUrl" into v_sender_name,v_sender_profile from public.users where uid=v_me;
 insert into public.notifications("targetOwnerId",type,title,body,"senderId","senderName","senderProfile","senderProfileUrl",message,"targetPostId","requestId","isRead","timestamp")
 values(p_target_uid,'follow_request','Follow request','Someone sent you a follow request',v_me::text,coalesce(v_sender_name,'User'),coalesce(v_sender_profile,''),coalesce(v_sender_profile,''),'sent you a follow request.','',v_request_id,false,now());
 return 'pending';
end $$;

create or replace function public.get_follow_request_status(p_target_uid uuid)
returns text language sql stable security definer set search_path=public as $$
 select case
 when exists(select 1 from public.users where uid=p_target_uid and followers @> array[auth.uid()::text]) then 'following'
 when exists(select 1 from public.follow_requests where requester_uid=auth.uid() and target_uid=p_target_uid and status='pending') then 'pending'
 else 'none' end
$$;

create or replace function public.respond_follow_request(p_request_id uuid,p_accept boolean)
returns void language plpgsql security definer set search_path=public as $$
declare v_me uuid:=auth.uid(); v_request public.follow_requests%rowtype;
begin
 if v_me is null then raise exception 'Not authenticated'; end if;
 select * into v_request from public.follow_requests where id=p_request_id for update;
 if not found or v_request.target_uid<>v_me or v_request.status<>'pending' then raise exception 'Follow request is no longer available'; end if;
 if p_accept then
  if exists(select 1 from public.users where uid=v_me and "blockedUsers" @> array[v_request.requester_uid::text]) or exists(select 1 from public.users where uid=v_request.requester_uid and "blockedUsers" @> array[v_me::text]) then raise exception 'Blocked users cannot follow each other'; end if;
  perform set_config('app.bypass_column_protection','on',true);
  update public.users set followers=array_append(coalesce(followers,array[]::text[]),v_request.requester_uid::text) where uid=v_me and not (coalesce(followers,array[]::text[]) @> array[v_request.requester_uid::text]);
  update public.users set following=array_append(coalesce(following,array[]::text[]),v_me::text) where uid=v_request.requester_uid and not (coalesce(following,array[]::text[]) @> array[v_me::text]);
  perform set_config('app.bypass_column_protection','off',true);
  update public.follow_requests set status='accepted',updated_at=now() where id=p_request_id;
 else update public.follow_requests set status='declined',updated_at=now() where id=p_request_id;
 end if;
end $$;

create or replace function public.cancel_follow_request(p_target_uid uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
 if auth.uid() is null then raise exception 'Not authenticated'; end if;
 update public.follow_requests set status='cancelled',updated_at=now() where requester_uid=auth.uid() and target_uid=p_target_uid and status='pending';
end $$;

revoke all on function public.request_private_follow(uuid) from public,anon;
revoke all on function public.get_follow_request_status(uuid) from public,anon;
revoke all on function public.respond_follow_request(uuid,boolean) from public,anon;
revoke all on function public.cancel_follow_request(uuid) from public,anon;
grant execute on function public.request_private_follow(uuid) to authenticated;
grant execute on function public.get_follow_request_status(uuid) to authenticated;
grant execute on function public.respond_follow_request(uuid,boolean) to authenticated;
grant execute on function public.cancel_follow_request(uuid) to authenticated;

drop policy if exists posts_select_all on public.posts;
create policy posts_select_all on public.posts for select to authenticated using (
 "moderationStatus"='approved'
 and ("isPrivatePost"=false or "userName"=(select auth.uid())::text
   or exists(select 1 from public.users u where u.uid::text=posts."userName" and coalesce(u.followers,array[]::text[]) @> array[(select auth.uid())::text]))
 and ("userName"=(select auth.uid())::text or exists(select 1 from public.users u where u.uid::text=posts."userName"
   and (coalesce(u."isPrivateAccount",false)=false or u.uid=(select auth.uid())
     or coalesce(u.followers,array[]::text[]) @> array[(select auth.uid())::text])))
);
drop policy if exists comments_select_all on public.comments;
create policy comments_select_all on public.comments for select to authenticated
using (exists(select 1 from public.posts p where p.id=comments."postId"));
