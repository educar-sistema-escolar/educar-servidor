# Administrative reports

`get_admin_report(report_code)` exposes real, permission-protected report rows as JSON for the admin client.

Supported report codes:

- `student_overview`
- `students_by_course`
- `students_by_subject`
- `teachers_by_level`
- `students_by_sport`
- `students_by_sport_schedule`
- `students_by_transport`

The function requires an active `superadmin`. Exporting is intentionally kept in the client as CSV serialization of these rows; it does not create a second data source.
