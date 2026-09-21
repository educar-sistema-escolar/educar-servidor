# Stage 2 Database Audit and Roadmap

## Current backend and schema

- The server repository is a Supabase/Postgres backend with the Stage 1 provisioning Edge Function; there is no general application server in this repository.
- `profiles` owns authentication-linked identity and the `app_role` enum. The existing role rename migration changes `authority` to `superadmin`; the safety migration prevents demoting or deactivating the last active superadmin.
- Stage 1 provides `people`, `students`, `teachers`, academic catalog/enrollment tables, audit logs, timestamp/audit triggers, foreign keys, uniqueness constraints, and supporting indexes.
- Stage 1 account provisioning is delivered by the `admin-provision-user` Edge Function; it is not part of this Stage 2 database slice.
- This Stage 2 slice adds nullable `people.dni` with normalized partial uniqueness, nullable `teachers.specialty`, atomic student/teacher provisioning RPCs, and persistent enrollment requests with a server-owned approval lifecycle.

## Audited files and data flow

- `supabase/migrations/20260911210000_init_profiles_roles.sql`: profiles and the original role enum.
- `supabase/migrations/20260921150000_stage1_administrative_schema.sql`: people, academic catalog, enrollments, assignments, RLS, and audit triggers.
- `supabase/migrations/20260921174000_rename_authority_to_superadmin.sql`: pending role-name correction.
- `supabase/migrations/20260921180000_stage2_superadmin_safety.sql`: pending last-active-superadmin lockout protection.
- `supabase/migrations/20260921190000_stage2_admin_provisioning.sql`: this stage's identity fields and transactional RPCs.
- `supabase/migrations/20260921220000_stage2_enrollment_requests.sql`: persistent request lifecycle, superadmin RPC boundary, and atomic approval/enrollment.
- Client flow reviewed with this schema: `academicRepository.ts` previously performed separate `people` and role-table writes, so a failed second write could orphan a person row.

## RLS and authorization audit

- RLS is enabled on all application tables. Active users can read their permitted records; active superadmins manage administrative rows.
- The RPCs use `SECURITY DEFINER`, `search_path = public`, and an explicit `is_active_superadmin()` check. Their related person/role writes occur in one database function call, so an error aborts the transaction rather than leaving a partial role.
- Direct table grants and existing RLS policies remain unchanged; no unrelated domain is widened by this migration.

## Stage 2 enrollment lifecycle

1. Apply the role rename, last-superadmin safety, provisioning, closure, and enrollment-request migrations in timestamp order.
2. Accept public submissions only through `submit_enrollment_request(jsonb)`; table RLS remains active-superadmin-only.
3. Exercise authenticated superadmin and non-superadmin request RPC calls against a disposable/local database.
4. Approve with an explicit active course; the RPC locks the request/course and creates or reuses the student and enrollment atomically.

## Stage 2 acceptance checklist

- [x] Superadmin-only RPC authorization is explicit and active-user aware.
- [x] Student and teacher create/update operations are atomic within one database function call.
- [x] DNI uniqueness is enforced at the database boundary when supplied.
- [x] Enrollment request persistence and pending/approved/rejected/archived transitions are defined.
- [x] Approval creates or reuses the student and active enrollment in one transaction with course/year/capacity checks.
- [x] Existing direct table RLS/grants are not widened by this migration.
- [ ] Apply migrations in timestamp order and verify `director@educar.com` is `superadmin` and active.
- [ ] Run disposable-database tests for allowed superadmin calls, rejected non-superadmin calls, duplicate DNI, approval rollback, capacity, and last-superadmin protection.

## Migration application caveat

The migration files are prepared locally only. Remote migration application was not performed or claimed. Apply them through the repository's normal Supabase migration workflow after reviewing the target project's current migration history and backup/rollback policy.

## Verification status

Static checks are limited to repository diff/whitespace and SQL shape inspection unless a local Postgres/Supabase runtime is available. Remote behavior, RLS execution, rollback behavior, and existing-data compatibility require a disposable database run.

## Later stages

- **Stage 3 — Users and permissions:** permission-management UI, complete authorization tests, and audit-log operations.
- **Stage 4 — Activities and schedules:** server-backed sports, activities, schedules, and participation flows.
- **Stage 5 — Transport and cafeteria:** routes, service assignments, availability, attendance, and operational administration.
- **Stage 6 — Reports:** permission-aware student, teacher, course, subject, sport, service, and export/reporting views.
- **Stage 7 — Production hardening:** audit-log review, observability, performance, backups/recovery, migration rehearsal, security review, and end-to-end release verification.

## Canonical Stage 1 closure

Stage 1 database/integrity closure is migration `20260921200000_stage1_closure.sql`, after the existing Stage 2 provisioning migration. The canonical administrative role is `superadmin`; account provisioning is delivered by the Stage 1 Edge Function, while this Stage 2 scope adds no Node API and does not alter sports, transport, dining, or reports. **Canonical status: SQL/seed/docs closure prepared locally; runtime acceptance is still pending.**

Exact migration order: `20260911210000_init_profiles_roles.sql` → `20260921150000_stage1_administrative_schema.sql` → `20260921174000_rename_authority_to_superadmin.sql` → `20260921180000_stage2_superadmin_safety.sql` → `20260921190000_stage2_admin_provisioning.sql` → `20260921200000_stage1_closure.sql` → `20260921220000_stage2_enrollment_requests.sql`.

The closure adds only missing `birth_date` and `must_change_password`, enforces enrollment and course-subject integrity (academic year, active references, capacity including capacity reductions, and uniqueness), protects logical deletion references, audits only profile role/activity changes without secret fields, and extends last-active-superadmin protection to deletion. `supabase/seed.sql` provides idempotent development academic data without Auth credentials. See `tests/stage1-acceptance.md` for the manual checklist.

Runtime Supabase application and acceptance checks remain pending because this repository has no executable database harness. Static inspection and `git diff --check` do not claim runtime success. `supabase/seed.sql` is development-only and creates no Auth users, passwords, or service-role code.
