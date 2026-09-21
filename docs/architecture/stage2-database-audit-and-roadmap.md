# Stage 2 Database Audit and Roadmap

## Current backend and schema

- The server repository is a Supabase/Postgres schema-only backend; there is no application server or Edge Function in this repository.
- `profiles` owns authentication-linked identity and the `app_role` enum. The existing role rename migration changes `authority` to `superadmin`; the safety migration prevents demoting or deactivating the last active superadmin.
- Stage 1 provides `people`, `students`, `teachers`, academic catalog/enrollment tables, audit logs, timestamp/audit triggers, foreign keys, uniqueness constraints, and supporting indexes.
- This Stage 2 slice adds nullable `people.dni` with normalized partial uniqueness, nullable `teachers.specialty`, and four superadmin-only JSONB RPCs for atomic student/teacher provisioning and updates.

## Audited files and data flow

- `supabase/migrations/20260911210000_init_profiles_roles.sql`: profiles and the original role enum.
- `supabase/migrations/20260921150000_stage1_administrative_schema.sql`: people, academic catalog, enrollments, assignments, RLS, and audit triggers.
- `supabase/migrations/20260921174000_rename_authority_to_superadmin.sql`: pending role-name correction.
- `supabase/migrations/20260921180000_stage2_superadmin_safety.sql`: pending last-active-superadmin lockout protection.
- `supabase/migrations/20260921190000_stage2_admin_provisioning.sql`: this stage's identity fields and transactional RPCs.
- Client flow reviewed with this schema: `academicRepository.ts` previously performed separate `people` and role-table writes, so a failed second write could orphan a person row.

## RLS and authorization audit

- RLS is enabled on all application tables. Active users can read their permitted records; active superadmins manage administrative rows.
- The RPCs use `SECURITY DEFINER`, `search_path = public`, and an explicit `is_active_superadmin()` check. Their related person/role writes occur in one database function call, so an error aborts the transaction rather than leaving a partial role.
- Direct table grants and existing RLS policies remain unchanged; no unrelated domain is widened by this migration.

## Stage 2 plan

1. Preserve and apply the role rename and last-superadmin safety migrations.
2. Apply the provisioning migration after them.
3. Exercise authenticated superadmin and non-superadmin RPC calls against a disposable/local database.
4. Add transport/UI integration only in the owning client repository; this server slice intentionally adds no Edge Function.

## Stage 2 acceptance checklist

- [x] Superadmin-only RPC authorization is explicit and active-user aware.
- [x] Student and teacher create/update operations are atomic within one database function call.
- [x] DNI uniqueness is enforced at the database boundary when supplied.
- [x] Existing direct table RLS/grants are not widened by this migration.
- [ ] Apply migrations in timestamp order and verify `director@educar.com` is `superadmin` and active.
- [ ] Run disposable-database tests for allowed superadmin calls, rejected non-superadmin calls, duplicate DNI, rollback, and last-superadmin protection.
- [ ] Add business constraints for academic-year consistency, inactive assignments, and capacity after the rules are confirmed.

## Migration application caveat

The migration files are prepared locally only. Remote migration application was not performed or claimed. Apply them through the repository's normal Supabase migration workflow after reviewing the target project's current migration history and backup/rollback policy.

## Verification status

Static checks are limited to repository diff/whitespace and SQL shape inspection unless a local Postgres/Supabase runtime is available. Remote behavior, RLS execution, rollback behavior, and existing-data compatibility require a disposable database run.

## Later stages

- **Stage 3 — Users and permissions:** trusted account provisioning, role assignment, activation/deactivation UI, and complete authorization tests.
- **Stage 4 — Activities and schedules:** server-backed sports, activities, schedules, and participation flows.
- **Stage 5 — Transport and cafeteria:** routes, service assignments, availability, attendance, and operational administration.
- **Stage 6 — Reports:** permission-aware student, teacher, course, subject, sport, service, and export/reporting views.
- **Stage 7 — Production hardening:** audit-log review, observability, performance, backups/recovery, migration rehearsal, security review, and end-to-end release verification.
