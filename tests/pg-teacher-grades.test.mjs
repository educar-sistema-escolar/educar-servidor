import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import net from 'node:net';

test('teacher grades enforce assignment, ownership, range and uniqueness in PostgreSQL', async () => {
  const bin = process.env.TEST_PG_BIN || 'C:/Program Files/PostgreSQL/18/bin';
  const exe = name => path.join(bin, `${name}${process.platform === 'win32' ? '.exe' : ''}`);
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'educar-grade-test-'));
  const data = path.join(root, 'data');
  const server = net.createServer();
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const port = server.address().port;
  await new Promise(resolve => server.close(resolve));
  let started = false;
  function run(name, args, input) {
    const result = spawnSync(exe(name), args, { input, encoding: 'utf8', timeout: 180000, ...(name === 'pg_ctl' ? { stdio: 'ignore' } : {}) });
    if (result.error) throw result.error;
    assert.equal(result.status, 0, `${name}: ${(result.stderr || result.stdout || '').slice(-3000)}`);
  }
  try {
    run('initdb', ['-D', data, '-U', 'fixture_admin', '-A', 'trust', '--encoding=UTF8', '--no-locale']);
    started = true;
    run('pg_ctl', ['-D', data, '-l', path.join(root, 'server.log'), '-o', `-h 127.0.0.1 -p ${port}`, '-w', 'start']);
    const setup = `
      create role authenticated nologin; create schema auth;
      create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
      create table profiles(id uuid primary key,role text,is_active boolean,account_status text);
      create table people(id uuid primary key,profile_id uuid,is_active boolean);
      create table teachers(id uuid primary key,person_id uuid,is_active boolean);
      create table students(id uuid primary key,is_active boolean);
      create table courses(id uuid primary key,is_active boolean);
      create table course_subjects(id uuid primary key,course_id uuid,teacher_id uuid,academic_year int,is_active boolean);
      create table student_enrollments(student_id uuid,course_id uuid,academic_year int,is_active boolean);
      create table student_subject_enrollments(id uuid primary key,student_id uuid,course_subject_id uuid,academic_year int,is_active boolean);
      create table academic_history(id uuid primary key default gen_random_uuid(),student_subject_enrollment_id uuid not null references student_subject_enrollments,term smallint not null check(term between 1 and 4),grade numeric(5,2) not null check(grade between 0 and 10),notes text,created_at timestamptz default now(),updated_at timestamptz default now(),unique(student_subject_enrollment_id,term));
      create table audit_logs(id uuid default gen_random_uuid(),actor_profile_id uuid,entity_type text,entity_id uuid,action text,created_at timestamptz default now());
      insert into profiles values ('00000000-0000-0000-0000-000000000001','teacher',true,'active'),('00000000-0000-0000-0000-000000000002','teacher',true,'active'),('00000000-0000-0000-0000-000000000003','student',true,'active'),('00000000-0000-0000-0000-000000000004','guardian',true,'active');
      insert into people values ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001',true),('10000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000002',true);
      insert into teachers values ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',true),('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002',true);
      insert into students values ('30000000-0000-0000-0000-000000000001',true);
      insert into courses values ('40000000-0000-0000-0000-000000000001',true);
      insert into course_subjects values ('50000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001',2027,true);
      insert into student_enrollments values ('30000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001',2027,true);
      insert into student_subject_enrollments values ('60000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000001',2027,true);
    `;
    const migration = fs.readFileSync(new URL('../supabase/migrations/20261026190000_teacher_grade_management.sql', import.meta.url), 'utf8');
    const checks = `
      set role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
      select public.save_teacher_grade('60000000-0000-0000-0000-000000000001',null,1::smallint,8,'bien');
      do $$ declare grade_id uuid; begin
        select id into grade_id from public.academic_history limit 1;
      end $$;
    `;
    // The RPC result supplies the id; keep this test within a single SQL session.
    const assertions = checks.replace(/      do \$\$ declare grade_id[\s\S]*?end \$\$;\n/, () => `
      reset role;
      do $$ begin if (select created_by from academic_history limit 1) <> '00000000-0000-0000-0000-000000000001'::uuid then raise exception 'missing actor'; end if; end $$;
      select set_config('grade.id',(select id::text from academic_history limit 1),false);
      set role authenticated;
      select public.save_teacher_grade('60000000-0000-0000-0000-000000000001',current_setting('grade.id')::uuid,1::smallint,9,'editada');
      reset role;
      do $$ begin if (select grade from academic_history limit 1) <> 9 then raise exception 'update failed'; end if; end $$;
      set role authenticated;
      do $$ begin
        begin perform public.save_teacher_grade('60000000-0000-0000-0000-000000000001',null,1::smallint,8,null); raise exception 'duplicate accepted'; exception when unique_violation then null; end;
        begin perform public.save_teacher_grade('60000000-0000-0000-0000-000000000001',null,2::smallint,11,null); raise exception 'invalid grade accepted'; exception when check_violation then null; end;
        perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
        begin perform public.save_teacher_grade('60000000-0000-0000-0000-000000000001',null,2::smallint,8,null); raise exception 'other teacher accepted'; exception when insufficient_privilege then null; end;
        perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',false);
        begin perform public.save_teacher_grade('60000000-0000-0000-0000-000000000001',null,2::smallint,8,null); raise exception 'student accepted'; exception when insufficient_privilege then null; end;
        perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000004',false);
        begin perform public.save_teacher_grade('60000000-0000-0000-0000-000000000001',null,2::smallint,8,null); raise exception 'guardian accepted'; exception when insufficient_privilege then null; end;
      end $$;
      reset role;
      update course_subjects set teacher_id = '20000000-0000-0000-0000-000000000002';
      set role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
      do $$ begin
        begin perform public.save_teacher_grade('60000000-0000-0000-0000-000000000001',current_setting('grade.id')::uuid,1::smallint,7,null); raise exception 'other teacher edited grade'; exception when insufficient_privilege then null; end;
      end $$;
    `);
    run('psql', ['-h', '127.0.0.1', '-p', String(port), '-U', 'fixture_admin', '-d', 'postgres', '-X', '-q', '-v', 'ON_ERROR_STOP=1'], setup + migration + assertions);
  } finally {
    if (started) run('pg_ctl', ['-D', data, '-m', 'immediate', '-w', 'stop']);
    assert.ok(path.resolve(root).startsWith(path.resolve(os.tmpdir()) + path.sep));
    fs.rmSync(root, { recursive: true, force: true, maxRetries: 10, retryDelay: 200 });
  }
});
