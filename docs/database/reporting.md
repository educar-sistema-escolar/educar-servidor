# Administrative reports

`get_admin_report(report_code)` exposes real, permission-protected report rows as JSON for the admin client.

The completed overload `get_admin_report(report_code, filters)` accepts optional `academic_year`, `level_id`, `sport_id`, and `route_id` filters. Existing one-argument calls remain compatible.

Supported report codes:

- `student_overview`
- `students_by_course`
- `students_by_subject`
- `teachers_by_level`
- `students_by_sport`
- `students_by_sport_schedule`
- `students_by_transport`
- `teachers_by_level_courses`
- `teachers_by_course_schedule`
- `students_by_sport_level`
- `students_by_sport_schedule_teacher`
- `transport_and_dining`

The function requires an active `superadmin`. Exporting is intentionally kept in the client as CSV serialization of these rows; it does not create a second data source.
