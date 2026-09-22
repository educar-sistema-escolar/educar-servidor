-- Execute with a privileged test role in a disposable Supabase database.
-- Replace placeholders with active fixtures.

-- Route numbers outside 1..4 must fail.
insert into public.transport_routes (route_number, name, capacity)
values (5, 'Invalid route', 10);

-- A third active sport for the same student/year must fail.
select public.enroll_student_in_sport_group(
  '00000000-0000-0000-0000-000000000001'::uuid,
  '00000000-0000-0000-0000-000000000002'::uuid
);

-- Duplicate active transport enrollment must fail.
select public.enroll_student_in_transport(
  '00000000-0000-0000-0000-000000000001'::uuid,
  '00000000-0000-0000-0000-000000000003'::uuid,
  null
);

-- An authenticated non-superadmin must not be able to insert service rows.
insert into public.student_dining_enrollments (student_id, dining_service_id, academic_year)
values (
  '00000000-0000-0000-0000-000000000001'::uuid,
  '00000000-0000-0000-0000-000000000004'::uuid,
  2026
);
