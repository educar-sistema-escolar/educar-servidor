# Stage 1 user provisioning

The administrative panel creates accounts through the `admin-provision-user` Edge Function.

## Security boundary

The function validates the caller's JWT and requires an active `superadmin` profile before using the server-side `SUPABASE_SERVICE_ROLE_KEY`. The service-role key must never be added to the Vite client or committed to this repository.

## Onboarding flow

1. A superadmin submits an email, name, and role.
2. Supabase Auth sends an invitation email.
3. The Auth trigger creates the profile with its default role.
4. The function performs the profile/person/domain link through the server-side `link_provisioned_identity` RPC and marks new accounts as invited.
5. If linking or status setup fails for a newly invited user, the Auth user is deleted so an unusable account is not left behind.

The current stage supports role assignment and identity linking for teacher/student/guardian accounts; teacher/student/parent portals remain future work. The `admin` role is a permission-catalog role only and is intentionally not a profile enum value.

## Required function secrets

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
