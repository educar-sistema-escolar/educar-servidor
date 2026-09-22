-- Run with a privileged test role in a disposable Supabase database.
-- Replace the UUID placeholders with active fixtures before executing.

-- Duplicate active subject enrollment: expect unique_violation.
select public.enroll_student_in_subject(
  '00000000-0000-0000-0000-000000000001'::uuid,
  '00000000-0000-0000-0000-000000000002'::uuid
);
select public.enroll_student_in_subject(
  '00000000-0000-0000-0000-000000000001'::uuid,
  '00000000-0000-0000-0000-000000000002'::uuid
);

-- Course membership mismatch: expect check_violation from the enrollment trigger.
insert into public.student_subject_enrollments (student_id, course_subject_id, academic_year)
values (
  '00000000-0000-0000-0000-000000000001'::uuid,
  '00000000-0000-0000-0000-000000000002'::uuid,
  1900
);

-- Schedule overlap: expect exclusion_violation from the advisory-lock trigger.
insert into public.academic_schedules (
  course_id, academic_year, day_of_week, starts_at, ends_at
)
values (
  '00000000-0000-0000-0000-000000000003'::uuid,
  2026,
  1,
  '08:00',
  '09:00'
);
insert into public.academic_schedules (
  course_id, academic_year, day_of_week, starts_at, ends_at
)
values (
  '00000000-0000-0000-0000-000000000003'::uuid,
  2026,
  1,
  '08:30',
  '09:30'
);

-- Unauthorized access: execute as an authenticated non-superadmin and expect an empty result.
select * from public.student_subject_enrollments;
select * from public.academic_history;
select * from public.academic_schedules;
-- Direct insert/update/delete as the same role must be rejected by RLS.
