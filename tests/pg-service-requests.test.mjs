import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import net from 'node:net';

const bin = process.env.TEST_PG_BIN || 'C:/Program Files/PostgreSQL/18/bin';
const executable = (name) => path.join(bin, `${name}${process.platform === 'win32' ? '.exe' : ''}`);
const id = (value) => `83000000-0000-4000-8000-${String(value).padStart(12, '0')}`;

test('PostgreSQL family sport/transport requests preserve RLS, capacity and enrollment rules', async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'educar-service-requests-test-'));
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
  const denied = (profileId, text) => {
    const result = spawnSync(executable('psql'), args, {
      input: `set role authenticated;select set_config('request.jwt.claim.sub','${id(profileId)}',false);select set_config('request.jwt.claim.role','authenticated',false);${text}`,
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
      create role anon nologin;
      create role authenticated nologin;
      create role service_role nologin;
      create schema auth;
      create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
      create table public.profiles(id uuid primary key,role text not null,is_active boolean not null default true,account_status text not null default 'active');
      create table public.people(id uuid primary key,profile_id uuid references profiles,first_name text,last_name text,is_active boolean not null default true);
      create table public.students(id uuid primary key,person_id uuid references people,is_active boolean not null default true);
      create table public.student_guardians(student_id uuid references students,guardian_person_id uuid references people,is_active boolean not null default true);
      create table public.educational_levels(id uuid primary key,name text not null);
      create table public.courses(id uuid primary key,name text not null,academic_year integer not null,educational_level_id uuid references educational_levels,is_active boolean not null default true);
      create table public.student_enrollments(id uuid primary key default gen_random_uuid(),student_id uuid references students,course_id uuid references courses,academic_year integer not null,is_active boolean not null default true);
      create table public.teachers(id uuid primary key,person_id uuid references people);
      create function public.set_updated_at() returns trigger language plpgsql as $$begin new.updated_at=now();return new;end$$;
      create function public.is_active_user() returns boolean language sql stable security definer set search_path=pg_catalog,public as $$select exists(select 1 from public.profiles where id=auth.uid() and is_active and account_status='active')$$;
      create function public.is_active_superadmin() returns boolean language sql stable security definer set search_path=pg_catalog,public as $$select exists(select 1 from public.profiles where id=auth.uid() and is_active and account_status='active' and role='superadmin')$$;
      create function public.is_guardian_of_student(p_student_id uuid) returns boolean language sql stable security definer set search_path=pg_catalog,public as $$select exists(select 1 from public.profiles p join public.people person on person.profile_id=p.id join public.student_guardians link on link.guardian_person_id=person.id join public.students s on s.id=link.student_id where p.id=auth.uid() and p.is_active and p.account_status='active' and p.role in ('parent','guardian') and person.is_active and link.is_active and s.is_active and s.id=p_student_id)$$;
      create function public.is_teacher_of_student(p_student_id uuid) returns boolean language sql stable as $$select false$$;
      grant usage on schema auth,public to authenticated;
      grant usage on schema auth,public to anon;
      grant select on public.profiles,public.people,public.students,public.student_guardians to authenticated;
      alter default privileges in schema public grant all on tables to anon,authenticated;
      alter default privileges in schema public grant execute on functions to anon,authenticated;
    `);

    sql(fs.readFileSync('supabase/migrations/20260922110000_work_unit_b_services.sql', 'utf8'));
    sql(fs.readFileSync('supabase/migrations/20261026152000_transport_cycle_sport_teacher.sql', 'utf8'));
    sql(fs.readFileSync('supabase/migrations/20261026170000_student_service_requests.sql', 'utf8'));
    sql(fs.readFileSync('supabase/migrations/20261026190000_restrict_student_service_request_access.sql', 'utf8'));
    sql(fs.readFileSync('supabase/migrations/20261026200000_secure_sport_request_options.sql', 'utf8'));

    assert.equal(sql(`select has_table_privilege('anon','public.student_service_requests','select')::text||'|'||has_table_privilege('authenticated','public.student_service_requests','select')::text||'|'||has_table_privilege('authenticated','public.student_service_requests','insert')::text||'|'||has_table_privilege('authenticated','public.student_service_requests','update')::text||'|'||has_table_privilege('authenticated','public.student_service_requests','delete')::text;`), 'false|true|false|false|false');
    assert.equal(sql(`select has_function_privilege('anon','public.list_service_enrollment_availability(integer)','execute')::text||'|'||has_function_privilege('anon','public.submit_student_service_request(uuid,text,integer,uuid,uuid,uuid)','execute')::text||'|'||has_function_privilege('anon','public.review_student_service_request(uuid,text,uuid,uuid,text)','execute')::text||'|'||has_function_privilege('authenticated','public.submit_student_service_request(uuid,text,integer,uuid,uuid,uuid)','execute')::text;`), 'false|false|false|true');

    sql(`
      insert into profiles(id,role) values ('${id(1)}','superadmin'),('${id(2)}','parent'),('${id(3)}','parent'),('${id(4)}','student');
      insert into people(id,profile_id,first_name,last_name) values
        ('${id(21)}','${id(2)}','Family','One'),('${id(22)}','${id(3)}','Family','Two'),
        ('${id(31)}','${id(4)}','Student','One'),('${id(32)}',null,'Student','Two'),('${id(33)}',null,'Student','Three'),
        ('${id(40)}',null,'Coach','Demo');
      insert into students(id,person_id) values ('${id(11)}','${id(31)}'),('${id(12)}','${id(32)}'),('${id(13)}','${id(33)}');
      insert into student_guardians(student_id,guardian_person_id) values ('${id(11)}','${id(21)}'),('${id(13)}','${id(21)}'),('${id(12)}','${id(22)}');
      insert into educational_levels(id,name) values ('${id(51)}','Primario');
      insert into courses(id,name,academic_year,educational_level_id) values ('${id(52)}','Primario 2027',2027,'${id(51)}');
      insert into student_enrollments(student_id,course_id,academic_year) values ('${id(11)}','${id(52)}',2027),('${id(12)}','${id(52)}',2027),('${id(13)}','${id(52)}',2027);
      insert into teachers(id,person_id) values ('${id(41)}','${id(40)}');
      insert into sports(id,code,name) values ('${id(61)}','FUT','Fútbol'),('${id(62)}','BAS','Básquet'),('${id(63)}','VOL','Vóley'),('${id(64)}','TEN','Tenis');
      insert into sport_groups(id,sport_id,name,educational_level_id,teacher_id,academic_year,capacity) values
        ('${id(71)}','${id(61)}','Fútbol Primario','${id(51)}','${id(41)}',2027,10),
        ('${id(72)}','${id(62)}','Básquet Primario','${id(51)}','${id(41)}',2027,10),
        ('${id(73)}','${id(63)}','Vóley Primario','${id(51)}','${id(41)}',2027,10),
        ('${id(74)}','${id(64)}','Tenis Primario','${id(51)}','${id(41)}',2027,1);
      insert into sport_group_schedules(id,sport_group_id,day_of_week,starts_at,ends_at) values
        ('${id(81)}','${id(71)}',1,'16:00','17:00'),('${id(82)}','${id(72)}',2,'16:00','17:00'),
        ('${id(83)}','${id(73)}',1,'16:30','17:30'),('${id(84)}','${id(74)}',3,'16:00','17:00');
      insert into transport_routes(id,route_number,name,capacity) values
        ('${id(91)}',1,'Centro',10),('${id(92)}',2,'Norte',1),('${id(93)}',3,'Sur',10),('${id(94)}',4,'Oeste',10);
      insert into transport_stops(id,route_id,name,stop_order) values
        ('${id(101)}','${id(91)}','Plaza Central',1),('${id(102)}','${id(92)}','Terminal Norte',1),
        ('${id(103)}','${id(93)}','Parque Sur',1),('${id(104)}','${id(94)}','Escuela',1);
      insert into student_sport_enrollments(student_id,sport_group_id,academic_year) values ('${id(12)}','${id(74)}',2027);
      insert into student_transport_enrollments(student_id,route_id,stop_id,academic_year) values ('${id(12)}','${id(92)}','${id(102)}',2027);
    `);

    assert.equal(as(2, `select available from list_service_enrollment_availability(2027) where service_type='sport' and service_id='${id(74)}';`), '0');
    assert.equal(as(2, `select count(*) from transport_routes where is_active;`), '4');
    assert.equal(as(2, `select teacher_first_name||' '||teacher_last_name from list_sport_request_options('${id(11)}',2027) where id='${id(71)}';`), 'Coach Demo');
    assert.match(denied(2, `select * from list_sport_request_options('${id(12)}',2027);`), /Student relationship is not authorized/);
    assert.equal(sql(`select has_function_privilege('anon','public.list_sport_request_options(uuid,integer)','execute')::text;`), 'false');

    const sportRequest = as(2, `select submit_student_service_request('${id(11)}','sport',2027,'${id(71)}',null,null)->>'id';`);
    assert.match(denied(2, `select submit_student_service_request('${id(11)}','sport',2027,'${id(71)}',null,null);`), /already has or requested this sport/);
    assert.match(denied(2, `select submit_student_service_request('${id(12)}','sport',2027,'${id(72)}',null,null);`), /linked family member/);
    assert.match(denied(4, `select submit_student_service_request('${id(11)}','sport',2027,'${id(72)}',null,null);`), /linked family member/);
    assert.equal(as(2, `select count(*) from student_service_requests where student_id='${id(11)}';`), '1');
    assert.equal(as(3, `select count(*) from student_service_requests where student_id='${id(11)}';`), '0');
    assert.match(denied(2, `select review_student_service_request('${sportRequest}'::uuid,'approve','${id(71)}',null,null);`), /Active superadmin role required/);

    const approvedSport = JSON.parse(as(1, `select review_student_service_request('${sportRequest}'::uuid,'approve','${id(71)}',null,null);`));
    assert.equal(approvedSport.status, 'approved');
    assert.equal(as(2, `select count(*) from student_sport_enrollments where student_id='${id(11)}' and sport_group_id='${id(71)}' and academic_year=2027 and is_active;`), '1');
    assert.match(denied(2, `select submit_student_service_request('${id(11)}','sport',2027,'${id(71)}',null,null);`), /already has or requested this sport/);

    const secondSport = as(2, `select submit_student_service_request('${id(11)}','sport',2027,'${id(72)}',null,null)->>'id';`);
    JSON.parse(as(1, `select review_student_service_request('${secondSport}'::uuid,'approve','${id(72)}',null,null);`));
    assert.match(denied(2, `select submit_student_service_request('${id(11)}','sport',2027,'${id(73)}',null,null);`), /at most two active or pending sports/);
    sql(`insert into student_sport_enrollments(student_id,sport_group_id,academic_year) values ('${id(13)}','${id(71)}',2027);`);
    assert.match(denied(2, `select submit_student_service_request('${id(13)}','sport',2027,'${id(73)}',null,null);`), /conflicts with another active or pending sport schedule/);
    assert.match(denied(2, `select submit_student_service_request('${id(13)}','sport',2027,'${id(74)}',null,null);`), /capacity reached/);

    const transportRequest = as(2, `select submit_student_service_request('${id(11)}','transport',2027,null,'${id(91)}','${id(101)}')->>'id';`);
    assert.match(denied(2, `select submit_student_service_request('${id(11)}','transport',2027,null,'${id(91)}','${id(101)}');`), /already has or requested transport/);
    assert.match(denied(2, `select submit_student_service_request('${id(13)}','transport',2027,null,'${id(92)}','${id(101)}');`), /must belong to the selected active route/);
    assert.match(denied(2, `select submit_student_service_request('${id(13)}','transport',2027,null,'${id(92)}','${id(102)}');`), /capacity reached/);
    const approvedTransport = JSON.parse(as(1, `select review_student_service_request('${transportRequest}'::uuid,'approve','${id(93)}','${id(103)}',null);`));
    assert.equal(approvedTransport.status, 'approved');
    assert.equal(as(2, `select route_id::text||'|'||stop_id::text||'|'||academic_year from student_transport_enrollments where student_id='${id(11)}' and is_active;`), `${id(93)}|${id(103)}|2027`);
    assert.equal(as(2, `select count(*) from student_service_requests where student_id='${id(11)}' and status='approved';`), '3');

    const pendingTransport = as(2, `select submit_student_service_request('${id(13)}','transport',2027,null,'${id(91)}','${id(101)}')->>'id';`);
    assert.equal(JSON.parse(as(1, `select review_student_service_request('${pendingTransport}'::uuid,'reject',null,null,'Revisar recorrido');`)).status, 'rejected');
    assert.equal(as(2, `select count(*) from student_service_requests where student_id='${id(13)}' and status='rejected';`), '1');

    console.log('Family service requests: own-child RLS, duplicate/max-two/overlap/full capacity, director assignment, valid/foreign stop, cycle 2027 and status refresh PASS.');
  } catch (error) {
    primaryError = error;
    throw error;
  } finally {
    try {
      if (started) run('pg_ctl', ['-D', data, '-m', 'immediate', '-w', 'stop']);
      const resolved = path.resolve(root);
      assert.ok(resolved.startsWith(path.resolve(os.tmpdir()) + path.sep) && path.basename(resolved).startsWith('educar-service-requests-test-'));
      fs.rmSync(resolved, { recursive: true, force: true, maxRetries: 10, retryDelay: 200 });
      assert.equal(fs.existsSync(resolved), false);
      console.log('Disposable service-request PostgreSQL cluster stopped and temporary files removed.');
    } catch (cleanupError) {
      if (primaryError) console.error('Cleanup failed after primary error:', cleanupError.message);
      else throw cleanupError;
    }
  }
});
