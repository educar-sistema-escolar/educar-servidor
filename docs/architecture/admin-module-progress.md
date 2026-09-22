# Administrative module implementation status

## Delivered in this slice

- Added configurable administrative permissions for reports, academic data, services, and accounts.
- Added permission-aware RLS policies for administrative data paths while preserving the current `superadmin` access.
- Added the filtered `get_admin_report(text, jsonb)` RPC overload and the remaining report families required by the administrative module.
- Updated reporting acceptance SQL and database documentation.

## Deployment note

The migration `supabase/migrations/20260922130000_admin_reports_completion.sql` is ready to apply. The Supabase CLI connection currently hangs in the local environment, so it was not pushed remotely by this change. Apply it manually in the Supabase SQL Editor, then run `tests/reporting-acceptance.sql`.

## Deliberate scope

Teacher, student, family, and community portals remain outside the administrative module implementation.
