# Stage 1 user provisioning

The administrative panel creates accounts through the `admin-provision-user` Edge Function.

## Security boundary

The function validates the caller's JWT and requires an active `superadmin` profile before using the server-side `SUPABASE_SERVICE_ROLE_KEY`. The service-role key must never be added to the Vite client or committed to this repository.

## Onboarding flow

1. A superadmin submits an email, name, and role.
2. Supabase Auth sends an invitation email.
3. The Auth trigger creates the profile with its default role.
4. The function updates the profile with the requested role and active status.
5. If profile setup fails, the invited Auth user is deleted so an unusable account is not left behind.

The current stage supports role assignment, not teacher/student/parent portals. The `admin` role is intentionally not available yet.

## Required function secrets

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
