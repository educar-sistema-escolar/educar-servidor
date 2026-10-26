import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import net from 'node:net';

const bin = process.env.TEST_PG_BIN || 'C:/Program Files/PostgreSQL/18/bin';
const executable = (name) => path.join(bin, `${name}${process.platform === 'win32' ? '.exe' : ''}`);
const id = (value) => `82000000-0000-4000-8000-${String(value).padStart(12, '0')}`;

test('PostgreSQL schedule migration repairs DEMO fixtures and rejects teacher overlaps', async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'educar-schedule-test-'));
  const data = path.join(root, 'data');
  let started = false;
  let primaryError;
  const server = net.createServer();
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const port = server.address().port;
  await new Promise((resolve) => server.close(resolve));

  const run = (name, args, input) => {
    const result = spawnSync(executable(name), args, {
      input,
      encoding: 'utf8',
      timeout: 180000,
      ...(name === 'pg_ctl' ? { stdio: 'ignore' } : {}),
    });
    if (result.error) throw result.error;
    assert.equal(result.status, 0, `${name}: ${(result.stderr || result.stdout || 'process failed').slice(-1800)}`);
    return (result.stdout || '').trim();
  };
  const psqlArgs = ['-h', '127.0.0.1', '-p', String(port), '-U', 'fixture_admin', '-d', 'postgres', '-X', '-q', '-t', '-A', '-v', 'ON_ERROR_STOP=1'];
  const sql = (text) => run('psql', psqlArgs, text);
  const expectConflict = (statement, expectedMessage) => sql(`
    do $$
    declare actual_message text;
    begin
      begin
        ${statement}
        raise exception 'Expected schedule conflict guard to reject the write';
      exception when exclusion_violation then
        get stacked diagnostics actual_message = message_text;
        if actual_message <> '${expectedMessage}' then
          raise exception 'Unexpected schedule conflict: %', actual_message;
        end if;
      end;
    end;
    $$;
  `);

  try {
    run('initdb', ['-D', data, '-U', 'fixture_admin', '-A', 'trust', '--encoding=UTF8', '--no-locale']);
    started = true;
    run('pg_ctl', ['-D', data, '-l', path.join(root, 'server.log'), '-o', `-h 127.0.0.1 -p ${port}`, '-w', 'start']);

    sql(`
      create table public.courses (
        id uuid primary key, code text not null, academic_year integer not null, is_active boolean not null
      );
      create table public.teachers (id uuid primary key, teacher_number text not null unique);
      create table public.course_subjects (
        id uuid primary key, course_id uuid not null, teacher_id uuid, academic_year integer not null, is_active boolean not null
      );
      create table public.academic_schedules (
        id uuid primary key, course_id uuid not null, course_subject_id uuid, academic_year integer not null,
        day_of_week smallint not null, starts_at time not null, ends_at time not null, is_active boolean not null
      );
      create table public.educational_levels (id uuid primary key, name text not null, sort_order integer not null);
      create table public.sports (id uuid primary key);
      create table public.sport_groups (
        id uuid primary key, sport_id uuid not null, name text not null, educational_level_id uuid not null,
        teacher_id uuid, academic_year integer not null, is_active boolean not null,
        created_at timestamptz not null default now(), updated_at timestamptz not null default now()
      );
      create table public.sport_group_schedules (
        id uuid primary key, sport_group_id uuid not null, day_of_week smallint not null,
        starts_at time not null, ends_at time not null, is_active boolean not null
      );

      insert into public.teachers(id, teacher_number) values ('${id(1)}', 'DEMO-2027-D01'), ('${id(2)}', 'DEMO-2027-D02');
      insert into public.courses(id, code, academic_year, is_active) values
        ('${id(10)}', 'DEMO-27-INI-A', 2027, true),
        ('${id(11)}', 'DEMO-27-PRI-A', 2027, true),
        ('${id(12)}', 'DEMO-27-SEC-A', 2027, true);
      insert into public.course_subjects(id, course_id, teacher_id, academic_year, is_active) values
        ('${id(20)}', '${id(10)}', '${id(1)}', 2027, true),
        ('${id(21)}', '${id(11)}', '${id(1)}', 2027, true),
        ('${id(22)}', '${id(12)}', '${id(2)}', 2027, true);
      insert into public.academic_schedules(id, course_id, course_subject_id, academic_year, day_of_week, starts_at, ends_at, is_active) values
        ('${id(30)}', '${id(10)}', '${id(20)}', 2027, 1, '08:00', '09:00', true),
        ('${id(31)}', '${id(11)}', '${id(21)}', 2027, 1, '08:00', '09:00', true),
        ('${id(32)}', '${id(12)}', '${id(22)}', 2027, 1, '08:30', '09:30', true);

      insert into public.educational_levels(id, name, sort_order) values
        ('${id(40)}', 'Initial', 1), ('${id(41)}', 'Primary', 2), ('${id(42)}', 'Secondary', 3);
      insert into public.sports(id) values ('${id(50)}');
      insert into public.sport_groups(id, sport_id, name, educational_level_id, teacher_id, academic_year, is_active) values
        ('${id(60)}', '${id(50)}', 'DEMO Fútbol Inicial', '${id(40)}', '${id(1)}', 2027, true),
        ('${id(61)}', '${id(50)}', 'DEMO Fútbol Primario', '${id(41)}', '${id(1)}', 2027, true),
        ('${id(62)}', '${id(50)}', 'DEMO Fútbol Secundario', '${id(42)}', '${id(1)}', 2027, true),
        ('${id(63)}', '${id(50)}', 'DEMO Fútbol Adicional', '${id(40)}', '${id(2)}', 2027, true);
      insert into public.sport_group_schedules(id, sport_group_id, day_of_week, starts_at, ends_at, is_active) values
        ('${id(70)}', '${id(60)}', 1, '16:00', '17:00', true),
        ('${id(71)}', '${id(61)}', 1, '16:00', '17:00', true),
        ('${id(72)}', '${id(62)}', 1, '16:00', '17:00', true),
        ('${id(73)}', '${id(63)}', 1, '16:30', '17:30', true);
    `);

    const migration = fs.readFileSync('supabase/migrations/20261026030000_fix_demo_schedule_overlaps.sql', 'utf8');
    sql(migration);
    sql(`
      create trigger academic_schedules_validate
        before insert or update on public.academic_schedules
        for each row execute function public.validate_academic_schedule();
      create trigger sport_group_schedules_validate
        before insert or update on public.sport_group_schedules
        for each row execute function public.validate_sport_group_schedule();
    `);

    assert.equal(sql(`select starts_at::text || '|' || ends_at::text from public.academic_schedules where id='${id(31)}';`), '09:00:00|10:00:00');
    assert.equal(sql(`select string_agg(starts_at::text || '-' || ends_at::text, ',' order by group_row.name) from public.sport_group_schedules schedule join public.sport_groups group_row on group_row.id=schedule.sport_group_id where group_row.id in ('${id(60)}','${id(61)}','${id(62)}');`), '16:00:00-17:00:00,17:00:00-18:00:00,18:00:00-19:00:00');

    expectConflict(`update public.academic_schedules set starts_at='08:30', ends_at='09:30' where id='${id(31)}';`, 'Teacher schedule overlaps another active course schedule');
    expectConflict(`update public.course_subjects set teacher_id='${id(1)}' where id='${id(22)}';`, 'Teacher assignment creates an overlapping academic schedule');
    expectConflict(`update public.sport_groups set teacher_id='${id(1)}' where id='${id(63)}';`, 'Teacher assignment creates an overlapping sport schedule');

    sql(`update public.sport_group_schedules set is_active=false where id='${id(71)}';`);
    expectConflict(`insert into public.sport_group_schedules(id, sport_group_id, day_of_week, starts_at, ends_at, is_active) values ('${id(74)}','${id(61)}',1,'16:30','17:30',true);`, 'Teacher schedule overlaps another active sport group schedule');

    console.log('Disposable PostgreSQL verified DEMO schedule repair, academic/sports overlap guards, and teacher reassignment guards.');

    sql(`
      create table public.profiles (id uuid primary key, role text, is_active boolean);
      create table public.people (id uuid primary key, profile_id uuid, is_active boolean);
      create table public.students (id uuid primary key, is_active boolean);
      create table public.student_guardians (
        id uuid primary key default gen_random_uuid(), student_id uuid, guardian_person_id uuid,
        relationship_type text, is_primary boolean, is_active boolean, updated_at timestamptz,
        unique(student_id, guardian_person_id, relationship_type)
      );
      create function public.is_active_superadmin() returns boolean language sql as 'select true';
      insert into profiles values ('${id(90)}','parent',true);
      insert into people values ('${id(91)}','${id(90)}',true);
      insert into students values ('${id(92)}',true);
    `);
    sql(fs.readFileSync('supabase/migrations/20261026120000_fix_guardian_link_ambiguity.sql', 'utf8'));
    for (let repeat = 0; repeat < 2; repeat++) {
      sql(`select public.link_student_guardian('${id(92)}','${id(90)}','tutor demo',false);`);
    }
    assert.equal(sql('select count(*) from public.student_guardians;'), '1');
    sql(`create or replace function public.is_active_superadmin() returns boolean language sql as 'select false';
      do $$ begin
        begin
          perform public.link_student_guardian('${id(92)}','${id(90)}','tutor demo',false);
          raise exception 'Expected permission denial';
        exception when insufficient_privilege then null; end;
      end $$;`);
    console.log('Guardian link migration: first insert, idempotent repeat and non-admin denial PASS.');

    sql(fs.readFileSync('tests/pending-rpcs-fixture.sql', 'utf8'));
    const services = fs.readFileSync('supabase/migrations/20260922110000_work_unit_b_services.sql', 'utf8');
    const diningStart = services.indexOf('create or replace function public.record_dining_usage(');
    sql(services.slice(diningStart, services.indexOf('end; $$;', diningStart) + 'end; $$;'.length));
    sql(fs.readFileSync('supabase/migrations/20261025120000_fix_enrollment_approval_and_dining_usage.sql', 'utf8'));
    sql(fs.readFileSync('supabase/migrations/20261026133000_fix_approval_guardian_trigger_ambiguity.sql', 'utf8'));
    const portalMigration = fs.readFileSync('supabase/migrations/20260923090000_student_portal_access.sql', 'utf8');
    const approvalTriggerStart = portalMigration.indexOf('create or replace function public.link_approved_enrollment_guardian()');
    sql(portalMigration.slice(approvalTriggerStart, portalMigration.indexOf('$$;', approvalTriggerStart) + 3));
    sql(`create trigger enrollment_requests_link_guardian_after_approval
      after update of status,student_id on public.enrollment_requests for each row
      when (new.status='approved') execute function public.link_approved_enrollment_guardian();`);
    sql(`
      insert into enrollment_requests(id, academic_year, student_first_name, student_last_name, student_dni)
        values ('${id(95)}',2027,'Demo','Regression','43000995');
      insert into student_dining_enrollments values ('${id(96)}',true);
      do $$ declare approved jsonb; repeated jsonb; begin
        approved := public.approve_enrollment_request('${id(95)}','${id(10)}');
        repeated := public.approve_enrollment_request('${id(95)}','${id(10)}');
        if approved->>'status' <> 'approved' or approved->>'student_id' is null
          or approved->>'enrollment_id' is null or repeated <> approved
          or (select count(*) from student_enrollments) <> 1 then
          raise exception 'Approval or idempotency regression';
        end if;
        perform public.link_approved_enrollment_guardian_for_request(request)
          from public.enrollment_requests request where request.id='${id(95)}';
        if (select count(*) from student_guardians link join people person on person.id=link.guardian_person_id
          where link.student_id=(approved->>'student_id')::uuid and person.dni='44000995') <> 1 then
          raise exception 'Approval guardian trigger must create exactly one DNI link';
        end if;
        perform public.record_dining_usage('${id(96)}','2027-03-01',true);
        perform public.record_dining_usage('${id(96)}','2027-03-01',false);
        if (select count(*) from dining_usage) <> 1 or (select used from dining_usage) then
          raise exception 'Dining upsert regression';
        end if;
      end $$;
    `);
    console.log('Approval creates student/enrollment exactly once; dining upsert true -> false PASS.');
  } catch (error) {
    primaryError = error;
    throw error;
  } finally {
    try {
      if (started) run('pg_ctl', ['-D', data, '-m', 'immediate', '-w', 'stop']);
      const resolvedRoot = path.resolve(root);
      assert.ok(resolvedRoot.startsWith(path.resolve(os.tmpdir()) + path.sep) && path.basename(resolvedRoot).startsWith('educar-schedule-test-'));
      fs.rmSync(resolvedRoot, { recursive: true, force: true, maxRetries: 10, retryDelay: 200 });
      assert.equal(fs.existsSync(resolvedRoot), false);
    } catch (cleanupError) {
      if (primaryError) console.error('Cleanup failed after primary error:', cleanupError.message);
      else throw cleanupError;
    }
  }
});
