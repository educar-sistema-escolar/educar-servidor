-- Transport enrollment must use the selected academic cycle, including DEMO 2027.
create or replace function public.enroll_student_in_transport(
 p_student_id uuid, p_route_id uuid, p_stop_id uuid, p_academic_year integer
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare result_row public.student_transport_enrollments%rowtype;
begin
 if not public.is_active_superadmin() then raise exception 'Active superadmin role required' using errcode='42501';end if;
 if p_academic_year is null or p_academic_year not between 1900 and 2200 then
  raise exception 'Valid academic year required' using errcode='23514';end if;
 insert into public.student_transport_enrollments(student_id,route_id,stop_id,academic_year)
 values(p_student_id,p_route_id,p_stop_id,p_academic_year) returning * into result_row;
 return to_jsonb(result_row);
end; $$;
revoke all on function public.enroll_student_in_transport(uuid,uuid,uuid,integer) from public;
grant execute on function public.enroll_student_in_transport(uuid,uuid,uuid,integer) to authenticated;
-- The legacy three-argument RPC remains available for current-cycle clients.
do $$ begin
 if not exists(select 1 from pg_constraint where conrelid='public.sport_groups'::regclass and conname='sport_groups_active_teacher_required') then
  alter table public.sport_groups add constraint sport_groups_active_teacher_required check(not is_active or teacher_id is not null);
 end if;
end $$;
notify pgrst, 'reload schema';
