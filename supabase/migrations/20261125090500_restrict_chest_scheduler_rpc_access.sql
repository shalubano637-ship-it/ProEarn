-- Scheduler functions are internal implementation details, not public RPC APIs.
revoke all on function public.process_scheduled_gift_chest_timer(text)
  from public, anon, authenticated;
grant execute on function public.process_scheduled_gift_chest_timer(text)
  to service_role;

revoke all on function public.schedule_gift_chest_timer_job()
  from public, anon, authenticated;
