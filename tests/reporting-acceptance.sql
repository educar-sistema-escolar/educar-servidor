-- Execute with an active superadmin in a disposable Supabase database.

select public.get_admin_report('students_by_course');
select public.get_admin_report('students_by_subject');
select public.get_admin_report('teachers_by_level');
select public.get_admin_report('students_by_sport_schedule');
select public.get_admin_report('students_by_transport');
select public.get_admin_report('student_overview');
select public.get_admin_report('teachers_by_level_courses', '{}'::jsonb);
select public.get_admin_report('teachers_by_course_schedule', '{}'::jsonb);
select public.get_admin_report('students_by_sport_level', '{}'::jsonb);
select public.get_admin_report('students_by_sport_schedule_teacher', '{}'::jsonb);
select public.get_admin_report('transport_and_dining', '{}'::jsonb);

-- Unsupported report codes must fail with invalid_parameter_value without
-- aborting the rest of this acceptance script.
do $$
begin
  perform public.get_admin_report('unsupported_report');
  raise exception 'Expected invalid_parameter_value was not raised';
exception when invalid_parameter_value then
  raise notice 'PASS: unsupported report rejected with invalid_parameter_value';
end;
$$;
