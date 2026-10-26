import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const migration = await readFile(
  new URL('../supabase/migrations/20261025120000_fix_enrollment_approval_and_dining_usage.sql', import.meta.url),
  'utf8',
);
const scheduleMigration = await readFile(
  new URL('../supabase/migrations/20261026030000_fix_demo_schedule_overlaps.sql', import.meta.url),
  'utf8',
);
const acceptance = await readFile(
  new URL('./database-regressions-acceptance.sql', import.meta.url),
  'utf8',
);

test('approval RPC qualifies the resolved person id to avoid PL/pgSQL ambiguity', () => {
  assert.match(migration, /create or replace function public\.approve_enrollment_request\s*\(/i);
  assert.match(migration, /resolved_person_id\s+uuid/i);
  assert.match(migration, /where s\.person_id\s*=\s*resolved_person_id/i);
  assert.doesNotMatch(migration, /where s\.person_id\s*=\s*person_id\b/i);
  assert.match(migration, /public\.is_active_superadmin\(\)/i);
});

test('dining usage no longer receives the updated_at trigger it cannot support', () => {
  assert.match(migration, /drop trigger if exists dining_usage_set_updated_at on public\.dining_usage/i);
  assert.doesNotMatch(migration, /alter table public\.dining_usage\s+add column\s+updated_at/i);
});

test('disposable acceptance SQL covers approval, rejection, dining upsert, and rollback', () => {
  assert.match(acceptance, /public\.approve_enrollment_request\s*\(/i);
  assert.match(acceptance, /public\.reject_enrollment_request\s*\(/i);
  assert.match(acceptance, /student_enrollments enrollment/i);
  assert.match(acceptance, /public\.record_dining_usage\s*\(/i);
  assert.match(acceptance, /dining_usage_count\s*<>\s*1/i);
  assert.match(acceptance, /rollback\s*;/i);
});

test('schedule migration repairs DEMO rows and prevents cross-course and cross-sport teacher conflicts', () => {
  assert.match(scheduleMigration, /course\.code\s*=\s*'DEMO-27-PRI-A'/i);
  assert.match(scheduleMigration, /teacher\.teacher_number\s*=\s*'DEMO-2027-D01'/i);
  assert.match(scheduleMigration, /ranked_demo_schedules/i);
  assert.match(scheduleMigration, /existing_assignment\.teacher_id\s*=\s*subject_teacher_id/i);
  assert.match(scheduleMigration, /Teacher schedule overlaps another active course schedule/i);
  assert.match(scheduleMigration, /Teacher schedule overlaps another active sport group schedule/i);
  assert.match(scheduleMigration, /course_subjects_teacher_schedule_validate/i);
  assert.match(scheduleMigration, /sport_groups_teacher_schedule_validate/i);
  assert.match(acceptance, /DEMO academic schedules still overlap for a teacher/i);
  assert.match(acceptance, /DEMO sports schedules still overlap for a teacher/i);
});
