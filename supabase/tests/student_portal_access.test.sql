begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(17);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('70000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'portal.student@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Portal Student"}', now(), now()),
  ('70000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'portal.admin@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Portal Admin"}', now(), now()),
  ('70000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'portal.guardian@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Portal Guardian"}', now(), now());

update public.profiles
set role = case id
      when '70000000-0000-0000-0000-000000000001'::uuid then 'student'::public.app_role
      when '70000000-0000-0000-0000-000000000002'::uuid then 'superadmin'::public.app_role
      else 'guardian'::public.app_role
    end,
    full_name = case id
      when '70000000-0000-0000-0000-000000000001'::uuid then 'Portal Student'
      when '70000000-0000-0000-0000-000000000002'::uuid then 'Portal Admin'
      else 'Portal Guardian'
    end,
    is_active = true,
    account_status = 'active'
where id in (
  '70000000-0000-0000-0000-000000000001',
  '70000000-0000-0000-0000-000000000002',
  '70000000-0000-0000-0000-000000000003'
);

insert into public.people (id, profile_id, first_name, last_name, email, dni)
values
  ('70000000-0000-0000-0000-000000000011', '70000000-0000-0000-0000-000000000001', 'Portal', 'Student', 'portal.student@example.test', '70000001'),
  ('70000000-0000-0000-0000-000000000012', null, 'Other', 'Student', 'other.student@example.test', '70000002'),
  ('70000000-0000-0000-0000-000000000013', null, 'Shared', 'Contact One', 'shared@example.test', '70000005'),
  ('70000000-0000-0000-0000-000000000014', null, 'Shared', 'Contact Two', 'shared@example.test', '70000006');

insert into public.students (id, person_id, student_number)
values
  ('70000000-0000-0000-0000-000000000021', '70000000-0000-0000-0000-000000000011', 'PORTAL-1'),
  ('70000000-0000-0000-0000-000000000022', '70000000-0000-0000-0000-000000000012', 'PORTAL-2');

insert into public.educational_levels (id, code, name, sort_order)
values ('70000000-0000-0000-0000-000000000031', 'portal-test', 'Portal Test', 90);

insert into public.courses (id, educational_level_id, code, name, academic_year, year_number, capacity)
values ('70000000-0000-0000-0000-000000000032', '70000000-0000-0000-0000-000000000031', 'PORTAL-1', 'Portal Course', 2026, 1, 5);

insert into public.subjects (id, code, name)
values ('70000000-0000-0000-0000-000000000033', 'portal-test', 'Portal Subject');

insert into public.course_subjects (id, course_id, subject_id, academic_year)
values ('70000000-0000-0000-0000-000000000034', '70000000-0000-0000-0000-000000000032', '70000000-0000-0000-0000-000000000033', 2026);

insert into public.student_enrollments (id, student_id, course_id, academic_year)
values
  ('70000000-0000-0000-0000-000000000041', '70000000-0000-0000-0000-000000000021', '70000000-0000-0000-0000-000000000032', 2026),
  ('70000000-0000-0000-0000-000000000042', '70000000-0000-0000-0000-000000000022', '70000000-0000-0000-0000-000000000032', 2026);

insert into public.student_subject_enrollments (id, student_id, course_subject_id, academic_year)
values
  ('70000000-0000-0000-0000-000000000043', '70000000-0000-0000-0000-000000000021', '70000000-0000-0000-0000-000000000034', 2026),
  ('70000000-0000-0000-0000-000000000044', '70000000-0000-0000-0000-000000000022', '70000000-0000-0000-0000-000000000034', 2026);

insert into public.sports (id, code, name)
values ('70000000-0000-0000-0000-000000000051', 'portal-test', 'Portal Sport');

insert into public.sport_groups (id, sport_id, name, academic_year, capacity)
values ('70000000-0000-0000-0000-000000000052', '70000000-0000-0000-0000-000000000051', 'Portal Group', 2026, 5);

insert into public.student_sport_enrollments (id, student_id, sport_group_id, academic_year)
values
  ('70000000-0000-0000-0000-000000000053', '70000000-0000-0000-0000-000000000021', '70000000-0000-0000-0000-000000000052', 2026),
  ('70000000-0000-0000-0000-000000000054', '70000000-0000-0000-0000-000000000022', '70000000-0000-0000-0000-000000000052', 2026);

set local role authenticated;
select set_config('request.jwt.claim.sub', '70000000-0000-0000-0000-000000000001', true);
select ok(public.is_student_of_student('70000000-0000-0000-0000-000000000021'), 'student identity maps to its own active student row');
select is((select count(*)::integer from public.students), 1, 'student cannot enumerate other student records');
select is((select count(*)::integer from public.student_enrollments), 1, 'student sees only their course enrollment');
select is((select count(*)::integer from public.student_subject_enrollments), 1, 'student sees only their subject enrollment');
select is((select count(*)::integer from public.student_sport_enrollments), 1, 'student sees only their service enrollment');
select is((select count(*)::integer from public.student_sport_enrollments where student_id = '70000000-0000-0000-0000-000000000022'), 0, 'student cannot read another student service enrollment');
select throws_ok(
  $$select public.link_provisioned_identity('70000000-0000-0000-0000-000000000002', 'admin@example.test', 'Portal Admin', 'parent')$$,
  '42501',
  'Active superadmin role required',
  'student role cannot invoke privileged identity provisioning'
);
update public.student_sport_enrollments
set academic_year = 2027
where id = '70000000-0000-0000-0000-000000000053';
select is((select academic_year from public.student_sport_enrollments where id = '70000000-0000-0000-0000-000000000053'), 2026, 'student cannot mutate their service enrollment');
reset role;

update public.profiles set account_status = 'inactive' where id = '70000000-0000-0000-0000-000000000002';
set local role authenticated;
select set_config('request.jwt.claim.sub', '70000000-0000-0000-0000-000000000002', true);
select ok(not public.is_active_superadmin(), 'inactive account status revokes the shared superadmin guard');
select ok(not public.is_allowed('reports:read'), 'inactive account status blocks permission-based report access');
select throws_ok(
  $$select public.link_provisioned_identity('70000000-0000-0000-0000-000000000002', 'admin@example.test', 'Portal Admin', 'parent')$$,
  '42501',
  'Active superadmin role required',
  'inactive superadmin cannot invoke privileged identity provisioning'
);
select throws_ok(
  $$select public.get_admin_report_with_filters('students_by_course', '{}'::jsonb)$$,
  '42501',
  'Administrative report permission required',
  'inactive superadmin cannot use the report RPC permission fallback'
);
reset role;
update public.profiles set account_status = 'active' where id = '70000000-0000-0000-0000-000000000002';

insert into public.enrollment_requests (
  student_first_name, student_last_name, student_dni, birth_date,
  educational_level, school_year, turn, academic_year,
  responsible_full_name, responsible_dni, responsible_relation,
  phone, email, status
)
values (
  'New', 'Student', '70000003', '2016-05-12',
  'Portal Test', '1', 'morning', 2026,
  'Responsible Person', '70000004', 'Madre',
  '1123456789', 'responsible@example.test', 'pending'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '70000000-0000-0000-0000-000000000002', true);
select throws_ok(
  $$select public.link_provisioned_identity('70000000-0000-0000-0000-000000000002', 'shared@example.test', 'Portal Admin', 'parent')$$,
  '23505',
  'Multiple people match this email; resolve the identity before provisioning',
  'ambiguous email does not select the first person record'
);
select public.approve_enrollment_request(
  (select id from public.enrollment_requests where student_dni = '70000003'),
  '70000000-0000-0000-0000-000000000032'
);
update public.people
set profile_id = '70000000-0000-0000-0000-000000000003'
where dni = '70000004';
select set_config('request.jwt.claim.sub', '70000000-0000-0000-0000-000000000003', true);
select ok(public.is_guardian_of_student((
  select student.id
  from public.students student
  join public.people person on person.id = student.person_id
  where person.dni = '70000003'
)), 'guardian identity is linked to the approved student');
select is((
  select count(*)::integer
  from public.students student
  join public.people person on person.id = student.person_id
  where person.dni = '70000003'
), 1, 'guardian RLS exposes the linked student');
select is((
  select count(*)::integer
  from public.students student
  join public.people person on person.id = student.person_id
  where person.dni <> '70000003'
), 0, 'guardian RLS hides unrelated student records');
reset role;

select is((
  select count(*)::integer
  from public.student_guardians relationship
  join public.people person on person.id = relationship.guardian_person_id
  where person.dni = '70000004'
    and lower(btrim(relationship.relationship_type)) = 'madre'
    and relationship.is_active
), 1, 'approved admission creates one guardian relationship by exact DNI');

select * from finish();
rollback;
