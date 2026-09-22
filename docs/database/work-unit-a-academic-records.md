# Work unit A: academic records and schedules

## Schema

- `student_subject_enrollments` links an active student to an active `course_subjects` row for the same `academic_year`, and requires an active `student_enrollments` row for that course and year.
- `academic_history` stores one grade per subject enrollment and term. `term` is 1–4 and `grade` is 0–10; `(student_subject_enrollment_id, term)` is unique.
- `academic_schedules` stores a course, optional course subject, academic year, day (`0` Sunday through `6` Saturday), and a half-open time interval. Active rows cannot overlap for the same course, year, and day.

All three tables use RLS. Student, guardian/tutor, and teacher reads are relationship-scoped through the existing helpers. Direct writes require an active superadmin; the RPCs are the supported write boundary.

## RPC contracts

- `enroll_student_in_subject(student_id, course_subject_id)` creates an active subject enrollment and returns the inserted row as JSON.
- `record_academic_history(student_subject_enrollment_id, term, grade, notes)` creates one term result and returns the inserted row as JSON.

Both functions are `SECURITY DEFINER`, use `SET search_path = pg_catalog, public`, check `is_active_superadmin()`, and are executable by `authenticated` only.

## Acceptance and validation

Manual SQL checks are in `tests/work-unit-a-acceptance.sql` for duplicate enrollment, course membership mismatch, overlapping schedules, and unauthorized access. Supabase runtime validation was not available in this execution environment; the migration and acceptance SQL were checked statically only.
