alter table public.chest_progress
  add column if not exists "pushSentAt" timestamptz;

alter table public.coin_chest_progress
  add column if not exists "pushSentAt" timestamptz;
