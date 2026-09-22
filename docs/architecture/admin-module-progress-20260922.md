# Administrative module progress — 2026-09-22

## Migrations added

- `20260922100000_work_unit_a_academic_records.sql`: student-subject enrollment, academic history, schedules, constraints, RLS, and RPCs.
- `20260922110000_work_unit_b_services.sql`: sports, groups, sport schedules, transport/routes/stops, dining, usage, constraints, RLS, and RPCs.
- `20260922120000_reporting.sql`: superadmin-only JSON report RPC for the requested administrative report families.

Acceptance SQL is in `tests/work-unit-a-acceptance.sql`, `tests/work-unit-b-services-acceptance.sql`, and `tests/reporting-acceptance.sql`.

## Important runtime note

The Supabase CLI could not be linked or executed from this environment. The migration files were checked statically, but applying them and executing RLS/RPC acceptance remains a deployment operation for the project owner.

## Frontend contracts

The client consumes the RPC parameter names exactly as declared, including the `p_` prefix. Do not rename those arguments without updating the client repository.
