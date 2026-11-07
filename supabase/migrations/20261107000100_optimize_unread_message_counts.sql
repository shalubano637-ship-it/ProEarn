-- Return all unread conversation counts in one indexed database query.
-- The authenticated user is always taken from auth.uid(), never from client input.
create or replace function public.get_unread_message_counts()
returns table(conversation_id uuid, unread_count bigint)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    c.id,
    count(m.id)::bigint
  from public.conversations c
  left join public.messages m
    on m."conversationId" = c.id
   and m."senderId" <> (select auth.uid())
   and (
     case
       when c."participantA" = (select auth.uid()) then c."lastReadAtA"
       else c."lastReadAtB"
     end is null
     or m."createdAt" > case
       when c."participantA" = (select auth.uid()) then c."lastReadAtA"
       else c."lastReadAtB"
     end
   )
  where (c."participantA" = (select auth.uid()) or c."participantB" = (select auth.uid()))
    and (select auth.uid()) is not null
  group by c.id;
$$;

revoke all on function public.get_unread_message_counts() from public, anon;
grant execute on function public.get_unread_message_counts() to authenticated;

create index if not exists messages_conversation_created_sender_idx
  on public.messages ("conversationId", "createdAt", "senderId");
