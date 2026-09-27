alter table public.users add column if not exists "termsVersion" text;

alter table public.posts
  add column if not exists "moderationStatus" text not null default 'approved',
  add column if not exists "moderationCheckedAt" timestamptz,
  add column if not exists "moderationReason" text,
  add column if not exists "mediaObjectKey" text;

alter table public.reports
  add column if not exists severity text not null default 'normal',
  add column if not exists "reviewedAt" timestamptz,
  add column if not exists "reviewedBy" uuid,
  add column if not exists "actionTaken" text;

create table if not exists public.account_deletion_requests (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  reason text,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  processed_at timestamptz
);

alter table public.account_deletion_requests enable row level security;
revoke all on public.account_deletion_requests from anon, authenticated;

drop policy if exists posts_insert_own on public.posts;

drop trigger if exists protect_posts_columns on public.posts;
create trigger protect_posts_columns
before update on public.posts
for each row execute function protect_columns('getsCount', 'likedBy', 'multiplier', 'unlockTime');
