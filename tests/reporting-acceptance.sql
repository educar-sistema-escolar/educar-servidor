-- Execute with an active superadmin in a disposable Supabase database.

select public.get_admin_report('students_by_course');
select public.get_admin_report('students_by_subject');
select public.get_admin_report('teachers_by_level');
select public.get_admin_report('students_by_sport_schedule');
select public.get_admin_report('students_by_transport');
select public.get_admin_report('student_overview');

-- An unsupported report code must fail with invalid_parameter_value.
select public.get_admin_report('unsupported_report');
