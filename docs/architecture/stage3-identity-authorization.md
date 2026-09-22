# Stage 3: identity and authorization

## Implemented

- Migration `20260922090000_stage3_identity_authorization.sql` adds the permission catalog, role mappings, `student_guardians`, indexes, status fields, relationship helpers, RLS, and two small server-side linking RPCs.
- `is_allowed`, `is_guardian_of_student`, and `is_teacher_of_student` are `SECURITY DEFINER` functions with `search_path = pg_catalog, public`; inactive profiles and inactive domain records are excluded.
- `admin-provision-user` validates an active superadmin JWT, rejects unknown input fields, uses service-role only inside the Edge Function, links `profiles` to `people` and the teacher/student domain entity, supports guardian/legacy parent roles, and compensates newly-created Auth users when linking fails.
- Repeating the same active email and role is idempotent; conflicting or inactive accounts return a safe conflict.
- RLS preserves the existing superadmin policies and adds self, guardian-child, and actively-assigned teacher scopes without public access.

## Manual application and verification

The Supabase CLI/link is blocked in the current environment. Apply the migration manually through the SQL editor in timestamp order, verify the migration ledger, and reconcile its history when CLI access is restored. Do not put the service-role key in the client.

Pending runtime checks: apply the migration, test authenticated superadmin/non-superadmin calls, exercise invitation/idempotency/compensation, and verify guardian and teacher RLS against a disposable database.

## Out of scope

Complete recovery/first-access callbacks, teacher/student/family portals, advanced permission administration UI, reports, and stages 4–8. Sports, transport, cafeteria, reports, and unrelated academic logic were not changed.
