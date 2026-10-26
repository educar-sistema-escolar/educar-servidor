# Revisión para GitHub — backend

Fecha: 26/10/2026. Rama: codex/final-presentation-qa. Sin staging, commit, push, merge ni deploy.

Remoto actualizado con fetch; HEAD frente a origin/main: 0/0. Inventario completo de cambios de las tres etapas:

```text
 M .gitignore
 M supabase/config.toml
 M supabase/functions/admin-provision-user/index.ts
 M tests/billing-reminders.test.mjs
 M tests/pg-finance.test.mjs
?? REVISION_PARA_GITHUB.md
?? docs/operations/RESUMEN_ETAPA_1_MIGRACIONES.md
?? docs/operations/RESUMEN_ETAPA_3_QA_FINAL.md
?? docs/operations/demo-unblock-20261026.md
?? scripts/provision-demo-family.mjs
?? scripts/seed-demo.mjs
?? scripts/verify-demo-access.mjs
?? scripts/verify-stage1-live.mjs
?? scripts/verify-stage3-live.mjs
?? supabase/migrations/20261025120000_fix_enrollment_approval_and_dining_usage.sql
?? supabase/migrations/20261026030000_fix_demo_schedule_overlaps.sql
?? supabase/migrations/20261026120000_fix_guardian_link_ambiguity.sql
?? supabase/migrations/20261026133000_fix_approval_guardian_trigger_ambiguity.sql
?? supabase/migrations/20261026150000_recover_missing_forum_billing.sql
?? supabase/migrations/20261026151000_fix_forum_vote_record.sql
?? supabase/migrations/20261026152000_transport_cycle_sport_teacher.sql
?? tests/admin-provision-user.test.mjs
?? tests/database-regressions-acceptance.sql
?? tests/database-regressions-migration.test.mjs
?? tests/pending-rpcs-fixture.sql
?? tests/pg-schedule-regressions.test.mjs
?? tests/stage1-live-acceptance.sql
?? tests/stage1-postflight.sql
?? tests/stage3-academic-services.sql
?? tests/stage3-masterdata.sql
?? tests/stage3-modules-acceptance.sql
?? tests/stage3-postflight.sql
```

Revisión: rutas y servicios conectados, cambios previos preservados, lint/build/tests y verificaciones remotas descritos en RESUMEN_ETAPA_3_QA_FINAL.md. Sin valores configurados de credenciales ni claves privadas en los archivos candidatos. .env, temporales, evidencias, capturas y builds están ignorados y no se versionan. Las tres migraciones de Etapa 3 coinciden con su fuente registrada. No ejecutar seed/provision para repetir QA: usar verificaciones de lectura y SQL con ROLLBACK.

Mensaje de commit propuesto: Completar foro y facturacion y validar reglas academicas

No publicar antes de la revisión y autorización del usuario. La rama no tiene upstream propio todavía.
