# Stage 1 database acceptance

Apply migrations in this exact order:

1. `20260911210000_init_profiles_roles.sql`
2. `20260921150000_stage1_administrative_schema.sql`
3. `20260921174000_rename_authority_to_superadmin.sql`
4. `20260921180000_stage2_superadmin_safety.sql`
5. `20260921190000_stage2_admin_provisioning.sql`
6. `20260921200000_stage1_closure.sql`

- [ ] Verify `people.birth_date` and `profiles.must_change_password`.
- [ ] Verify mismatched years, inactive active-references, capacity overflow, capacity reduction below current enrollment, and duplicate active enrollment are rejected.
- [ ] Verify profile audit rows contain only `role`/`is_active`, with no password or secret fields.
- [ ] Verify the last active superadmin cannot be demoted, deactivated, or deleted.
- [ ] Re-run `supabase/seed.sql` and verify it remains successful and does not create Auth users or passwords.

**Runtime limitations:** Supabase CLI/runtime execution was intentionally not run for this change. The repository has no executable database harness, so migration application, RLS behavior, trigger concurrency, rollback behavior, and seed execution remain pending runtime proof.
