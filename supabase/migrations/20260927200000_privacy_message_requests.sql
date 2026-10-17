alter table public.users
  add column if not exists "isPrivateAccount" boolean not null default false,
  add column if not exists "whoCanMessage" text not null default 'everyone';

alter table public.posts
  add column if not exists "isPrivatePost" boolean not null default false;

alter table public.users
  drop constraint if exists users_who_can_message_check;

alter table public.users
  add constraint users_who_can_message_check
  check ("whoCanMessage" in ('everyone','followers','no_one'));

create table if not exists public.message_requests (
  id uuid primary key default gen_random_uuid(),
  "conversationId" uuid not null references public.conversations(id) on delete cascade,
  "senderId" uuid not null references public.users(uid) on delete cascade,
  "recipientId" uuid not null references public.users(uid) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted','rejected')),
  "createdAt" timestamptz not null default now(),
  "updatedAt" timestamptz not null default now(),
  unique ("conversationId")
);

alter table public.message_requests enable row level security;

drop policy if exists message_requests_select_own on public.message_requests;
create policy message_requests_select_own on public.message_requests
for select to authenticated
using ((select auth.uid()) = "senderId" or (select auth.uid()) = "recipientId");

drop policy if exists message_requests_insert_own on public.message_requests;
create policy message_requests_insert_own on public.message_requests
for insert to authenticated
with check ((select auth.uid()) = "senderId");

drop policy if exists message_requests_update_recipient on public.message_requests;
create policy message_requests_update_recipient on public.message_requests
for update to authenticated
using ((select auth.uid()) = "recipientId")
with check ((select auth.uid()) = "recipientId");

create or replace function public.get_or_create_conversation(p_other_uid uuid)
returns uuid language plpgsql security definer set search_path = ''
as $function$
declare
  v_me uuid := auth.uid();
  v_a uuid;
  v_b uuid;
  v_conversation_id uuid;
  v_other_private boolean;
  v_other_who text;
  v_is_following boolean;
begin
  if v_me is null then raise exception 'Not authenticated'; end if;
  if p_other_uid is null or v_me = p_other_uid then raise exception 'Invalid recipient'; end if;

  if v_me < p_other_uid then v_a := v_me; v_b := p_other_uid;
  else v_a := p_other_uid; v_b := v_me; end if;

  select id into v_conversation_id from public.conversations
  where "participantA"=v_a and "participantB"=v_b;

  if v_conversation_id is not null then return v_conversation_id; end if;

  select "isPrivateAccount","whoCanMessage" into v_other_private,v_other_who
  from public.users where uid=p_other_uid;

  select exists(
    select 1 from public.users
    where uid=p_other_uid and v_me::text = any(followers)
  ) into v_is_following;

  if coalesce(v_other_who,'everyone') = 'no_one' then raise exception 'MESSAGES_DISABLED'; end if;
  if coalesce(v_other_who,'everyone') = 'followers' and not v_is_following then raise exception 'FOLLOW_REQUIRED'; end if;

  insert into public.conversations ("participantA","participantB")
  values(v_a,v_b) returning id into v_conversation_id;

  if coalesce(v_other_private,false) and not v_is_following then
    insert into public.message_requests ("conversationId","senderId","recipientId")
    values(v_conversation_id,v_me,p_other_uid)
    on conflict ("conversationId") do nothing;
  end if;

  return v_conversation_id;
end;
$function$;

create or replace function public.send_message(
  p_conversation_id uuid,
  p_text text,
  p_image_url text default null,
  p_reply_to_message_id text default null
)
returns uuid language plpgsql security definer set search_path = ''
as $function$
declare
  v_sender uuid := auth.uid();
  v_other uuid;
  v_private boolean;
  v_who text;
  v_is_following boolean;
  v_request public.message_requests;
  v_new_id uuid;
begin
  if v_sender is null then raise exception 'Not authenticated'; end if;

  select case when c."participantA"=v_sender then c."participantB" else c."participantA" end
  into v_other
  from public.conversations c
  where c.id=p_conversation_id
    and (c."participantA"=v_sender or c."participantB"=v_sender);

  if v_other is null then raise exception 'Not a participant in this conversation'; end if;
  if (p_text is null or length(trim(p_text))=0) and p_image_url is null then raise exception 'Message must have text or an image'; end if;

  select "isPrivateAccount","whoCanMessage"
  into v_private,v_who
  from public.users
  where uid=v_other;

  select exists(
    select 1 from public.users
    where uid=v_other and v_sender::text = any(followers)
  ) into v_is_following;

  if coalesce(v_who,'everyone')='no_one' then
    raise exception 'MESSAGES_DISABLED';
  end if;

  if coalesce(v_who,'everyone')='followers' and not v_is_following then
    raise exception 'FOLLOW_REQUIRED';
  end if;

  select * into v_request
  from public.message_requests
  where "conversationId"=p_conversation_id;

  if v_request.id is not null and v_request.status='pending' and v_request."recipientId"=v_sender then
    raise exception 'MESSAGE_REQUEST_PENDING';
  end if;

  if v_request.id is null and coalesce(v_private,false) and not v_is_following then
    insert into public.message_requests ("conversationId","senderId","recipientId")
    values(p_conversation_id,v_sender,v_other)
    on conflict ("conversationId") do nothing
    returning * into v_request;
  end if;

  if p_reply_to_message_id is not null and not exists (
    select 1 from public.messages
    where id::text=p_reply_to_message_id and "conversationId"=p_conversation_id
  ) then
    raise exception 'Cannot reply to a message from a different conversation';
  end if;

  insert into public.messages ("conversationId","senderId",text,"imageUrl","replyToMessageId")
  values(p_conversation_id,v_sender,p_text,p_image_url,p_reply_to_message_id)
  returning id into v_new_id;

  return v_new_id;
end;
$function$;

create or replace function public.accept_message_request(p_request_id uuid)
returns void language plpgsql security definer set search_path = ''
as $function$
begin
  update public.message_requests
  set status='accepted',"updatedAt"=now()
  where id=p_request_id and "recipientId"=auth.uid() and status='pending';
  if not found then raise exception 'Request not found'; end if;
end;
$function$;

create or replace function public.reject_message_request(p_request_id uuid)
returns void language plpgsql security definer set search_path = ''
as $function$
begin
  update public.message_requests
  set status='rejected',"updatedAt"=now()
  where id=p_request_id and "recipientId"=auth.uid() and status='pending';
  if not found then raise exception 'Request not found'; end if;
end;
$function$;

create or replace function public.get_pending_message_requests()
returns table(
  id uuid,
  "conversationId" uuid,
  "senderId" uuid,
  "senderUserName" text,
  "senderProfileUrl" text,
  "createdAt" timestamptz
)
language sql security definer set search_path = ''
as $function$
  select r.id,r."conversationId",r."senderId",u."userName",u."profileUrl",r."createdAt"
  from public.message_requests r
  join public.users u on u.uid=r."senderId"
  where r."recipientId"=(select auth.uid()) and r.status='pending'
  order by r."createdAt" desc;
$function$;

revoke execute on function public.get_or_create_conversation(uuid) from public, anon;
grant execute on function public.get_or_create_conversation(uuid) to authenticated;
revoke execute on function public.send_message(uuid,text,text,text) from public, anon;
grant execute on function public.send_message(uuid,text,text,text) to authenticated;
revoke execute on function public.accept_message_request(uuid) from public, anon;
grant execute on function public.accept_message_request(uuid) to authenticated;
revoke execute on function public.reject_message_request(uuid) from public, anon;
grant execute on function public.reject_message_request(uuid) to authenticated;
revoke execute on function public.get_pending_message_requests() from public, anon;
grant execute on function public.get_pending_message_requests() to authenticated;

drop policy if exists posts_select_all on public.posts;
create policy posts_select_all on public.posts
for select to anon, authenticated
using (
  "moderationStatus"='approved'
  and (
    "isPrivatePost"=false
    or "userName"=(select auth.uid())::text
    or exists (
      select 1 from public.users u
      where u.uid::text=posts."userName"
        and (select auth.uid())::text = any(u.followers)
    )
  )
);

drop view if exists public.public_profiles;
create view public.public_profiles as
select uid,"userName",bio,link,"profileUrl","fullName","createdAt","totalGets",
case when not "isPrivateAccount" or uid=auth.uid() or auth.uid()::text = any(followers)
then followers else array[]::text[] end as followers,
case when not "isPrivateAccount" or uid=auth.uid() or auth.uid()::text = any(followers)
then following else array[]::text[] end as following,
popularity,"isPrivateAccount","whoCanMessage"
from public.users;