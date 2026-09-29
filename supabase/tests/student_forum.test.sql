begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(45);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('81000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'forum.student.one@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Forum Student One"}', now(), now()),
  ('81000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'forum.student.two@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Forum Student Two"}', now(), now()),
  ('81000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'forum.parent@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Forum Parent"}', now(), now()),
  ('81000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'forum.inactive.account@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Forum Inactive Account"}', now(), now()),
  ('81000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'forum.inactive.person@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Forum Inactive Person"}', now(), now()),
  ('81000000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'forum.inactive.student@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Forum Inactive Student"}', now(), now());

update public.profiles
set role = case id
      when '81000000-0000-0000-0000-000000000003'::uuid then 'parent'::public.app_role
      else 'student'::public.app_role
    end,
    full_name = case id
      when '81000000-0000-0000-0000-000000000001'::uuid then 'Forum Student One'
      when '81000000-0000-0000-0000-000000000002'::uuid then 'Forum Student Two'
      when '81000000-0000-0000-0000-000000000003'::uuid then 'Forum Parent'
      when '81000000-0000-0000-0000-000000000004'::uuid then 'Forum Inactive Account'
      when '81000000-0000-0000-0000-000000000005'::uuid then 'Forum Inactive Person'
      else 'Forum Inactive Student'
    end,
    account_status = case when id = '81000000-0000-0000-0000-000000000004'::uuid then 'inactive' else 'active' end,
    is_active = true
where id in (
  '81000000-0000-0000-0000-000000000001',
  '81000000-0000-0000-0000-000000000002',
  '81000000-0000-0000-0000-000000000003',
  '81000000-0000-0000-0000-000000000004',
  '81000000-0000-0000-0000-000000000005',
  '81000000-0000-0000-0000-000000000006'
);

insert into public.people (id, profile_id, first_name, last_name, email)
values
  ('81000000-0000-0000-0000-000000000011', '81000000-0000-0000-0000-000000000001', 'Forum', 'Student One', 'forum.student.one@example.test'),
  ('81000000-0000-0000-0000-000000000012', '81000000-0000-0000-0000-000000000002', 'Forum', 'Student Two', 'forum.student.two@example.test'),
  ('81000000-0000-0000-0000-000000000013', '81000000-0000-0000-0000-000000000004', 'Forum', 'Inactive Account', 'forum.inactive.account@example.test'),
  ('81000000-0000-0000-0000-000000000015', '81000000-0000-0000-0000-000000000005', 'Forum', 'Inactive Person', 'forum.inactive.person@example.test'),
  ('81000000-0000-0000-0000-000000000016', '81000000-0000-0000-0000-000000000006', 'Forum', 'Inactive Student', 'forum.inactive.student@example.test');

update public.people set is_active = false where id = '81000000-0000-0000-0000-000000000015';

insert into public.students (id, person_id)
values
  ('81000000-0000-0000-0000-000000000021', '81000000-0000-0000-0000-000000000011'),
  ('81000000-0000-0000-0000-000000000022', '81000000-0000-0000-0000-000000000012'),
  ('81000000-0000-0000-0000-000000000024', '81000000-0000-0000-0000-000000000013'),
  ('81000000-0000-0000-0000-000000000025', '81000000-0000-0000-0000-000000000015'),
  ('81000000-0000-0000-0000-000000000026', '81000000-0000-0000-0000-000000000016');

update public.students set is_active = false where id = '81000000-0000-0000-0000-000000000026';

set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000001', true);
select ok(public.is_active_forum_student(), 'active linked student passes forum access check');

insert into public.forum_discussions (
  id, author_id, author_name, category, title, lead, content, status, score, replies_count, created_at
)
values (
  '81000000-0000-0000-0000-000000000101',
  '81000000-0000-0000-0000-000000000002',
  'Forged Author', 'Académico', 'Test discussion', 'A test lead', 'A test discussion body',
  'published', 99, 99, '2000-01-01T00:00:00Z'
);

select is((select author_id::text from public.forum_discussions where id = '81000000-0000-0000-0000-000000000101'), '81000000-0000-0000-0000-000000000001', 'discussion author identity is derived from auth.uid()');
select is((select author_name from public.forum_discussions where id = '81000000-0000-0000-0000-000000000101'), 'Forum Student One', 'discussion display name is derived from the profile');
select is((select score from public.forum_discussions where id = '81000000-0000-0000-0000-000000000101'), 0, 'discussion scores cannot be client supplied');
select is((select replies_count from public.forum_discussions where id = '81000000-0000-0000-0000-000000000101'), 0, 'discussion reply count cannot be client supplied');

insert into public.forum_replies (id, discussion_id, author_id, author_name, content)
values (
  '81000000-0000-0000-0000-000000000102',
  '81000000-0000-0000-0000-000000000101',
  '81000000-0000-0000-0000-000000000002',
  'Forged Reply Author',
  'A shared reply'
);

select is((select author_id::text from public.forum_replies where discussion_id = '81000000-0000-0000-0000-000000000101'), '81000000-0000-0000-0000-000000000001', 'reply author identity is derived from auth.uid()');
select is((select author_name from public.forum_replies where id = '81000000-0000-0000-0000-000000000102'), 'Forum Student One', 'reply display name is derived from the profile');
select is((select replies_count from public.forum_discussions where id = '81000000-0000-0000-0000-000000000101'), 1, 'reply trigger maintains shared reply count');

insert into public.forum_replies (id, discussion_id, parent_reply_id, content)
values ('81000000-0000-0000-0000-000000000103', '81000000-0000-0000-0000-000000000101', '81000000-0000-0000-0000-000000000102', 'A nested shared reply');
select is((select replies_count from public.forum_discussions where id = '81000000-0000-0000-0000-000000000101'), 2, 'nested replies contribute to the discussion count');

insert into public.forum_discussion_votes (discussion_id, voter_id, direction)
values ('81000000-0000-0000-0000-000000000101', '81000000-0000-0000-0000-000000000002', 'up');
select is((select voter_id::text from public.forum_discussion_votes where discussion_id = '81000000-0000-0000-0000-000000000101'), '81000000-0000-0000-0000-000000000001', 'discussion vote identity is derived from auth.uid()');
select is((select score from public.forum_discussions where id = '81000000-0000-0000-0000-000000000101'), 1, 'discussion vote updates shared score');
select throws_ok(
  $$insert into public.forum_discussion_votes (discussion_id, direction) values ('81000000-0000-0000-0000-000000000101', 'up')$$,
  '23505',
  'duplicate key value violates unique constraint "forum_discussion_votes_discussion_id_voter_id_key"',
  'a student can have only one vote per discussion'
);
update public.forum_discussion_votes set direction = 'down'
where discussion_id = '81000000-0000-0000-0000-000000000101';
select is((select score from public.forum_discussions where id = '81000000-0000-0000-0000-000000000101'), -1, 'changing vote direction adjusts score atomically');
delete from public.forum_discussion_votes
where discussion_id = '81000000-0000-0000-0000-000000000101';
select is((select score from public.forum_discussions where id = '81000000-0000-0000-0000-000000000101'), 0, 'removing a vote restores the score');
insert into public.forum_discussion_votes (discussion_id, voter_id, direction)
values ('81000000-0000-0000-0000-000000000101', '81000000-0000-0000-0000-000000000002', 'up');

insert into public.forum_reply_votes (reply_id, voter_id, direction)
values ('81000000-0000-0000-0000-000000000102', '81000000-0000-0000-0000-000000000002', 'down');
select is((select voter_id::text from public.forum_reply_votes where reply_id = '81000000-0000-0000-0000-000000000102'), '81000000-0000-0000-0000-000000000001', 'reply vote identity is derived from auth.uid()');
select is((select score from public.forum_replies where id = '81000000-0000-0000-0000-000000000102'), -1, 'reply vote updates shared score');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000002', true);
select is((select count(*)::integer from public.forum_discussions where id = '81000000-0000-0000-0000-000000000101'), 1, 'another active student sees the same discussion');
select is((select count(*)::integer from public.forum_replies where discussion_id = '81000000-0000-0000-0000-000000000101'), 2, 'another active student sees the same replies');
select is((select count(*)::integer from public.forum_discussion_votes where discussion_id = '81000000-0000-0000-0000-000000000101'), 0, 'students cannot read another student vote identity');
select is((select count(*)::integer from public.forum_reply_votes where reply_id = '81000000-0000-0000-0000-000000000102'), 0, 'students cannot read another student reply vote identity');
select is((with changed as (
  update public.forum_discussion_votes set direction = 'down'
  where discussion_id = '81000000-0000-0000-0000-000000000101'
  returning 1
) select count(*)::integer from changed), 0, 'students cannot mutate another owner discussion vote');
select is((with changed as (
  delete from public.forum_discussion_votes
  where discussion_id = '81000000-0000-0000-0000-000000000101'
  returning 1
) select count(*)::integer from changed), 0, 'students cannot delete another owner discussion vote');
select is((with changed as (
  update public.forum_reply_votes set direction = 'up'
  where reply_id = '81000000-0000-0000-0000-000000000102'
  returning 1
) select count(*)::integer from changed), 0, 'students cannot mutate another owner reply vote');
select is((with changed as (
  delete from public.forum_reply_votes
  where reply_id = '81000000-0000-0000-0000-000000000102'
  returning 1
) select count(*)::integer from changed), 0, 'students cannot delete another owner reply vote');
select is((select score from public.forum_discussions where id = '81000000-0000-0000-0000-000000000101'), 1, 'cross-owner vote attempts leave discussion score unchanged');
select is((select score from public.forum_replies where id = '81000000-0000-0000-0000-000000000102'), -1, 'cross-owner vote attempts leave reply score unchanged');
reset role;

set local role anon;
select throws_ok(
  $$select count(*) from public.forum_discussions$$,
  '42501',
  'permission denied for table forum_discussions',
  'anonymous users cannot read student forum discussions'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000003', true);
select is((select count(*)::integer from public.forum_discussions), 0, 'parent accounts cannot read the student forum');
select throws_ok(
  $$insert into public.forum_discussions (category, title, lead, content) values ('Académico', 'Parent post', 'A parent lead', 'A parent body')$$,
  '42501',
  'Active student account required',
  'parent accounts cannot publish as students'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000004', true);
select is((select count(*)::integer from public.forum_discussions), 0, 'inactive student accounts cannot read forum content');
select throws_ok(
  $$insert into public.forum_discussions (category, title, lead, content) values ('Académico', 'Inactive post', 'An inactive lead', 'An inactive body')$$,
  '42501',
  'Active student account required',
  'inactive student accounts cannot publish'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000005', true);
select ok(not public.is_active_forum_student(), 'inactive institutional person fails the forum access check');
select is((select count(*)::integer from public.forum_discussions), 0, 'inactive institutional person cannot read forum content');
select throws_ok(
  $$insert into public.forum_discussions (category, title, lead, content) values ('Académico', 'Inactive person post', 'An inactive person lead', 'An inactive person body')$$,
  '42501',
  'Active student account required',
  'inactive institutional person cannot publish'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000006', true);
select ok(not public.is_active_forum_student(), 'inactive student record fails the forum access check');
select is((select count(*)::integer from public.forum_discussions), 0, 'inactive student record cannot read forum content');
select throws_ok(
  $$insert into public.forum_discussions (category, title, lead, content) values ('Académico', 'Inactive student post', 'An inactive student lead', 'An inactive student body')$$,
  '42501',
  'Active student account required',
  'inactive student record cannot publish'
);
reset role;

select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000001', true);
delete from public.forum_replies where id = '81000000-0000-0000-0000-000000000102';
select is((select replies_count from public.forum_discussions where id = '81000000-0000-0000-0000-000000000101'), 0, 'cascaded reply deletion decrements the shared reply count');
select throws_ok(
  $$insert into public.forum_discussions (author_id, author_name, category, title, lead, content) values ('81000000-0000-0000-0000-000000000001', 'Forum Student One', 'Académico', repeat('x', 181), 'A valid lead', 'A valid body')$$,
  '23514',
  'new row for relation "forum_discussions" violates check constraint "forum_discussions_title_length_check"',
  'database rejects overlong discussion titles'
);
select throws_ok(
  $$insert into public.forum_discussions (category, title, lead, content) values ('Académico', E'\t\n\r', 'A valid lead', 'A valid body')$$,
  '23514',
  'new row for relation "forum_discussions" violates check constraint "forum_discussions_title_length_check"',
  'database rejects whitespace-only discussion titles'
);
select throws_ok(
  $$insert into public.forum_discussions (category, title, lead, content) values ('Académico', 'A valid title', E'\t\n\r', 'A valid body')$$,
  '23514',
  'new row for relation "forum_discussions" violates check constraint "forum_discussions_lead_length_check"',
  'database rejects whitespace-only discussion leads'
);
select throws_ok(
  $$insert into public.forum_discussions (category, title, lead, content) values ('Académico', 'A valid title', 'A valid lead', E'\t\n\r')$$,
  '23514',
  'new row for relation "forum_discussions" violates check constraint "forum_discussions_content_length_check"',
  'database rejects whitespace-only discussion content'
);
select throws_ok(
  $$insert into public.forum_replies (discussion_id, content) values ('81000000-0000-0000-0000-000000000101', E'\t\n\r')$$,
  '23514',
  'new row for relation "forum_replies" violates check constraint "forum_replies_content_length_check"',
  'database rejects whitespace-only replies'
);
select throws_ok(
  $$insert into public.forum_discussions (author_id, author_name, category, title, lead, content, status) values ('81000000-0000-0000-0000-000000000001', 'Forum Student One', 'Académico', 'Valid title', 'A valid lead', 'A valid body', 'pending')$$,
  '23514',
  'new row for relation "forum_discussions" violates check constraint "forum_discussions_status_check"',
  'database rejects unsupported discussion status values'
);
select throws_ok(
  $$update public.forum_discussions set author_id = '81000000-0000-0000-0000-000000000002' where id = '81000000-0000-0000-0000-000000000101'$$,
  '42501',
  'Forum author is immutable',
  'discussion author cannot be changed after insert'
);

select * from finish();
rollback;
