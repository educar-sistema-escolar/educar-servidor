# Work unit B: sports, transport, and dining

## Implemented schema

- `sports`, `sport_groups`, `sport_group_schedules`, and `student_sport_enrollments`.
- `transport_routes`, `transport_stops`, and `student_transport_enrollments`.
- `dining_services`, `dining_slots`, `student_dining_enrollments`, and `dining_usage`.

The database enforces active-student references, group/service capacity, duplicate prevention, four route numbers (`1` through `4`), a maximum of two active sports per student/year, and overlapping sport schedules. Service writes are restricted to an active superadmin through RLS and the supplied RPCs.

## RPC contracts

- `enroll_student_in_sport_group(p_student_id, p_sport_group_id)`
- `enroll_student_in_transport(p_student_id, p_route_id, p_stop_id)`
- `enroll_student_in_dining(p_student_id, p_dining_service_id, p_academic_year)`
- `deactivate_student_service_enrollment(p_table, p_id)` where `p_table` is `sport`, `transport`, or `dining`.
- `record_dining_usage(p_dining_enrollment_id, p_service_date, p_used)`

Supabase runtime execution was not available in this environment. The migration and acceptance SQL remain ready for manual execution against a disposable database before production rollout.
