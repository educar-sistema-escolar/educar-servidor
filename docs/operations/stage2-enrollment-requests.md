# Stage 2 enrollment requests

`20260921220000_stage2_enrollment_requests.sql` owns the enrollment-request lifecycle.

## Lifecycle

1. The public enrollment form calls `submit_enrollment_request(jsonb)`. The definer RPC normalizes email, DNI, and phone values, validates the payload, and stores a `pending` request without exposing table writes to public clients.
2. An active `superadmin` lists requests through `list_enrollment_requests(text)`.
3. Approval calls `approve_enrollment_request(uuid, uuid)` with an active course. The function locks the request and course, reuses or creates the person/student record, reuses or creates the active `student_enrollments` row, and changes the request to `approved` in one transaction.
4. Rejection calls `reject_enrollment_request(uuid, text)` and stores the actor, timestamp, and optional reason.
5. Archive calls `archive_enrollment_request(uuid)` and stores the actor and timestamp. Archived requests are terminal.

RLS is enabled on the request table with no client table grants. Public intake and every administrative transition are intentionally available only through the validating RPCs, so approval cannot bypass course, capacity, or enrollment invariants. Active student DNI requests are unique; email has a normalized lookup index because responsible emails may legitimately be shared by siblings.

## Runtime verification still required

- Apply migrations in timestamp order through the target Supabase workflow.
- Verify anonymous submission, active-superadmin listing/mutations, and denial for inactive/non-superadmin callers.
- Verify duplicate normalized student DNI, mismatched academic year, inactive course/student, capacity exhaustion, and duplicate active enrollment failures.
- Verify an approval failure rolls back the person/student/enrollment/request changes together.

The repository has no executable local database harness, so static SQL inspection and `git diff --check` do not claim live migration, RLS, RPC, or transaction verification.
