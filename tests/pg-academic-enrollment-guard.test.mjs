import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import net from 'node:net';

const bin = process.env.TEST_PG_BIN || 'C:/Program Files/PostgreSQL/18/bin';
const executable = (name) => path.join(bin, `${name}${process.platform === 'win32' ? '.exe' : ''}`);
const id = (value) => `84000000-0000-4000-8000-${String(value).padStart(12, '0')}`;

test('academic enrollment guard blocks active and pending duplicates per year while permitting an open future cycle', async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'educar-academic-enrollment-test-'));
  const data = path.join(root, 'data');
  let started = false;
  let primaryError;
  const server = net.createServer();
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const port = server.address().port;
  await new Promise((resolve) => server.close(resolve));

  const run = (name, args, input) => {
    const result = spawnSync(executable(name), args, {
      input, encoding: 'utf8', timeout: 180000,
      ...(name === 'pg_ctl' ? { stdio: 'ignore' } : {}),
    });
    if (result.error) throw result.error;
    assert.equal(result.status, 0, `${name}: ${(result.stderr || result.stdout || 'process failed').slice(-2000)}`);
    return (result.stdout || '').trim();
  };
  const args = ['-h', '127.0.0.1', '-p', String(port), '-U', 'fixture_admin', '-d', 'postgres', '-X', '-q', '-t', '-A', '-v', 'ON_ERROR_STOP=1'];
  const sql = (text) => run('psql', args, text);
  const as = (profileId, text) => sql(`set role authenticated;select set_config('request.jwt.claim.sub','${id(profileId)}',false);select set_config('request.jwt.claim.role','authenticated',false);${text}`).split('\n').at(-1);
  const denied = (role, text) => {
    const result = spawnSync(executable('psql'), args, {
      input: `set role ${role};${text}`,
      encoding: 'utf8', timeout: 180000,
    });
    if (result.error) throw result.error;
    assert.notEqual(result.status, 0, 'operation unexpectedly succeeded');
    return result.stderr || result.stdout;
  };

  try {
    run('initdb', ['-D', data, '-U', 'fixture_admin', '-A', 'trust', '--encoding=UTF8', '--no-locale']);
    started = true;
    run('pg_ctl', ['-D', data, '-l', path.join(root, 'server.log'), '-o', `-h 127.0.0.1 -p ${port}`, '-w', 'start']);
    sql(`
      create role authenticated nologin;
      create role anon nologin;
      create schema auth;
      create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
      create table public.profiles(id uuid primary key,role text not null,is_active boolean not null default true);
      create table public.people(id uuid primary key,profile_id uuid references profiles,dni text,is_active boolean not null default true);
      create table public.students(id uuid primary key,person_id uuid references people,is_active boolean not null default true);
      create table public.student_guardians(student_id uuid references students,guardian_person_id uuid references people,is_active boolean not null default true);
      create table public.courses(id uuid primary key,academic_year integer not null,is_active boolean not null default true);
      create table public.student_enrollments(id uuid primary key default gen_random_uuid(),student_id uuid references students,course_id uuid references courses,academic_year integer not null,is_active boolean not null default true);
      create table public.enrollment_requests(
        id uuid primary key default gen_random_uuid(),student_first_name text not null,student_last_name text not null,
        student_dni text not null,birth_date date not null,educational_level text not null,school_year text not null,
        turn text not null,academic_year integer not null,responsible_full_name text not null,responsible_dni text not null,
        responsible_relation text not null,phone text not null,email text not null,notes text not null default '',
        status text not null default 'pending',source text not null default 'public-form',approved_course_id uuid,
        student_id uuid,enrollment_id uuid,rejection_reason text,created_by_profile_id uuid,updated_by_profile_id uuid,
        approved_by_profile_id uuid,rejected_by_profile_id uuid,archived_by_profile_id uuid,
        created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
        approved_at timestamptz,rejected_at timestamptz,archived_at timestamptz
      );
      create function public.is_active_user() returns boolean language sql stable as $$select exists(select 1 from profiles where id=auth.uid() and is_active)$$;
      create function public.is_active_superadmin() returns boolean language sql stable as $$select exists(select 1 from profiles where id=auth.uid() and role='superadmin' and is_active)$$;
      create function public.is_guardian_of_student(p_student_id uuid) returns boolean language sql stable as $$select exists(select 1 from student_guardians link join people guardian on guardian.id=link.guardian_person_id where link.student_id=p_student_id and link.is_active and guardian.profile_id=auth.uid() and guardian.is_active)$$;
      insert into profiles(id,role) values ('${id(1)}','parent'),('${id(2)}','student'),('${id(3)}','parent');
      insert into people(id,profile_id,dni) values ('${id(10)}','${id(1)}','20111222'),('${id(11)}','${id(2)}','12.345.678'),('${id(12)}',null,'23456789'),('${id(13)}','${id(3)}','30111222'),('${id(14)}',null,'34567890');
      insert into students(id,person_id) values ('${id(20)}','${id(11)}'),('${id(21)}','${id(12)}'),('${id(22)}','${id(14)}');
      insert into student_guardians(student_id,guardian_person_id) values ('${id(20)}','${id(10)}'),('${id(21)}','${id(10)}');
      insert into courses(id,academic_year) values ('${id(70)}',2027),('${id(71)}',2028);
      insert into student_enrollments(student_id,course_id,academic_year) values ('${id(20)}','${id(70)}',2027);
    `);

    const migration = fs.readFileSync(new URL('../supabase/migrations/20261026180000_academic_enrollment_cycle_guard.sql', import.meta.url), 'utf8');
    sql(migration);

    assert.equal(sql(`select string_agg(academic_year::text,',' order by academic_year) from list_available_enrollment_years();`), '2027,2028');
    assert.equal(as(1, `select get_student_academic_enrollment_status('${id(20)}',2027);`), 'enrolled');
    assert.equal(as(1, `select get_student_academic_enrollment_status('${id(21)}',2027);`), 'available');
    assert.match(denied('authenticated', `select set_config('request.jwt.claim.sub','${id(3)}',false);select get_student_academic_enrollment_status('${id(21)}',2027);`), /Student relationship is not authorized/);

    const payload = (dni, year, studentId = null) => JSON.stringify({studentFirstName:'Demo',studentLastName:'Student',studentDni:dni,studentId,birthDate:'2010-02-03',educationalLevel:'Primario',schoolYear:'3° Grado',turn:'Mañana',academicYear:year,responsibleFullName:'Demo Family',responsibleDni:'30111222',responsibleRelation:'Madre',phone:'3624123456',email:'familia@example.test',notes:''}).replaceAll("'", "''");
    assert.match(denied('authenticated', `select set_config('request.jwt.claim.sub','${id(1)}',false);select submit_enrollment_request('${payload('12345678',2027)}'::jsonb);`), /Select the linked student/);
    assert.match(denied('authenticated', `select set_config('request.jwt.claim.sub','${id(1)}',false);select submit_enrollment_request('${payload('23456789',2027,id(22))}'::jsonb);`), /unavailable or not authorized/);
    assert.match(denied('authenticated', `select set_config('request.jwt.claim.sub','${id(1)}',false);select submit_enrollment_request('${payload('23456789',2027,id(20))}'::jsonb);`), /DNI does not match/);
    assert.match(denied('anon', `select submit_enrollment_request('${payload('12345678',2027)}'::jsonb);`), /already has an active enrollment/);

    assert.match(as(1, `select submit_enrollment_request('${payload('12345678',2028,id(20))}'::jsonb)->>'id';`), /^[0-9a-f-]{36}$/i);
    assert.equal(as(1, `select get_student_academic_enrollment_status('${id(20)}',2028);`), 'pending');
    assert.match(denied('anon', `select submit_enrollment_request('${payload('12345678',2028)}'::jsonb);`), /active enrollment request already exists/);

    assert.match(as(1, `select submit_enrollment_request('${payload('23456789',2027,id(21))}'::jsonb)->>'id';`), /^[0-9a-f-]{36}$/i);
    assert.equal(as(1, `select get_student_academic_enrollment_status('${id(21)}',2027);`), 'pending');
    assert.match(denied('anon', `select submit_enrollment_request('${payload('23456789',2029)}'::jsonb);`), /cycle is not open for enrollment/);
    assert.equal(sql(`select count(*) from enrollment_requests where status='pending' and academic_year=2027;`), '1');

    console.log('Academic enrollment guard: active 2027 blocked, un-enrolled child allowed, linked-family scope enforced, pending duplicates blocked per year, and open future 2028 allowed.');
  } catch (error) {
    primaryError = error;
    throw error;
  } finally {
    try {
      if (started) run('pg_ctl', ['-D', data, '-m', 'immediate', '-w', 'stop']);
      const resolved = path.resolve(root);
      assert.ok(resolved.startsWith(path.resolve(os.tmpdir()) + path.sep) && path.basename(resolved).startsWith('educar-academic-enrollment-test-'));
      fs.rmSync(resolved, { recursive: true, force: true, maxRetries: 10, retryDelay: 200 });
      assert.equal(fs.existsSync(resolved), false);
      console.log('Disposable academic-enrollment PostgreSQL cluster stopped and temporary files removed.');
    } catch (cleanupError) {
      if (primaryError) console.error('Cleanup failed after primary error:', cleanupError.message);
      else throw cleanupError;
    }
  }
});
