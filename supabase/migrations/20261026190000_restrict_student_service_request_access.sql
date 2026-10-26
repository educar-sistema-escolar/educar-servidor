-- Supabase default ACLs grant table/function access to anon and authenticated.
-- Keep service requests readable through RLS and writable only through the RPCs.
revoke all on table public.student_service_requests from anon;
revoke insert, update, delete, truncate, references, trigger
  on table public.student_service_requests from authenticated;
grant select on table public.student_service_requests to authenticated;

revoke all on function public.list_service_enrollment_availability(integer) from public, anon;
revoke all on function public.submit_student_service_request(uuid, text, integer, uuid, uuid, uuid) from public, anon;
revoke all on function public.review_student_service_request(uuid, text, uuid, uuid, text) from public, anon;
grant execute on function public.list_service_enrollment_availability(integer) to authenticated;
grant execute on function public.submit_student_service_request(uuid, text, integer, uuid, uuid, uuid) to authenticated;
grant execute on function public.review_student_service_request(uuid, text, uuid, uuid, text) to authenticated;

notify pgrst, 'reload schema';
