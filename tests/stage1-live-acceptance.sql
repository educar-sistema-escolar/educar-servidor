-- Controlled acceptance on academic DEMO project nhwsgmijdsxzuxgpllhy.
-- Uses only explicit DEMO fixtures; all test mutations roll back.
begin;
set local lock_timeout = '10s';
set local statement_timeout = '60s';

do $$
declare
  results jsonb := '{}'::jsonb;
  admin_id uuid;
  parent_id uuid;
  test_student_id uuid;
  first_link jsonb;
  second_link jsonb;
  rejected jsonb;
  request_row public.enrollment_requests%rowtype;
  target_schedule public.academic_schedules%rowtype;
  other_assignment uuid;
  replacement_teacher uuid;
  sports_target uuid;
  sports_start time;
  sports_end time;
  message text;
begin
  select id into strict admin_id from public.profiles
    where email='director@educar.com' and role='superadmin' and is_active and account_status='active';
  perform set_config('request.jwt.claim.sub',admin_id::text,true);
  select * into strict request_row from public.enrollment_requests
    where id='43965105-2910-4f36-b37c-8625d5c6624f'
      and notes='DEMO-2027-REQUEST-PENDING' and academic_year=2027 and status='pending';
  rejected := public.reject_enrollment_request(request_row.id,'ETAPA 1 rechazo controlado con ROLLBACK');
  if rejected->>'status' <> 'rejected' or not exists (
    select 1 from public.enrollment_requests where id=request_row.id and status='rejected'
      and rejection_reason='ETAPA 1 rechazo controlado con ROLLBACK'
  ) then raise exception 'Rejection did not update status and reason'; end if;
  if public.reject_enrollment_request(request_row.id,'repeat') <> rejected then
    raise exception 'Rejection is not idempotent';
  end if;
  if exists (select 1 from public.students student join public.people person on person.id=student.person_id
    where person.dni=request_row.student_dni) then raise exception 'Rejection created a student'; end if;
  begin
    perform public.approve_enrollment_request(request_row.id,'d2027000-0000-4000-8000-000000000002');
    raise exception 'Rejected request unexpectedly approved';
  exception when check_violation then
    get stacked diagnostics message=message_text;
    if message <> 'Only pending enrollment requests can be approved' then raise; end if;
  end;
  results := results || jsonb_build_object('rejection',jsonb_build_object('status','rejected','repeat','same result','reapproval','denied','new_student',false));

  select schedule.* into strict target_schedule from public.academic_schedules schedule
    join public.courses course on course.id=schedule.course_id
    join public.course_subjects assignment on assignment.id=schedule.course_subject_id
    join public.teachers teacher on teacher.id=assignment.teacher_id
    where course.code='DEMO-27-PRI-A' and teacher.teacher_number='DEMO-2027-D01'
      and schedule.academic_year=2027 and schedule.day_of_week=1 and schedule.is_active;
  if target_schedule.starts_at <> time '09:00' or target_schedule.ends_at <> time '10:00' then
    raise exception 'DEMO academic repair is not present';
  end if;
  begin
    update public.academic_schedules set starts_at='08:30',ends_at='09:30' where id=target_schedule.id;
    raise exception 'Overlapping academic write unexpectedly succeeded';
  exception when exclusion_violation then
    get stacked diagnostics message=message_text;
    if message <> 'Teacher schedule overlaps another active course schedule' then raise; end if;
  end;
  update public.academic_schedules set starts_at='09:00',ends_at='10:00' where id=target_schedule.id;
  results := results || jsonb_build_object('academic_schedule',jsonb_build_object('overlap','rejected 23P01','adjacent','accepted','repaired_time','09:00-10:00'));

  select own_assignment.id,other.teacher_id into strict other_assignment,replacement_teacher
    from public.course_subjects own_assignment
    join public.academic_schedules own_schedule on own_schedule.course_subject_id=own_assignment.id and own_schedule.is_active
    join public.academic_schedules existing on existing.course_id<>own_schedule.course_id
      and existing.academic_year=own_schedule.academic_year and existing.day_of_week=own_schedule.day_of_week
      and existing.starts_at<own_schedule.ends_at and own_schedule.starts_at<existing.ends_at and existing.is_active
    join public.course_subjects other on other.id=existing.course_subject_id and other.is_active
    join public.courses own_course on own_course.id=own_assignment.course_id and own_course.code like 'DEMO-27-%'
    join public.courses other_course on other_course.id=other.course_id and other_course.code like 'DEMO-27-%'
    where own_assignment.is_active and own_assignment.teacher_id<>other.teacher_id and own_schedule.academic_year=2027 limit 1;
  begin
    update public.course_subjects set teacher_id=replacement_teacher where id=other_assignment;
    raise exception 'Overlapping teacher reassignment unexpectedly succeeded';
  exception when exclusion_violation then
    get stacked diagnostics message=message_text;
    if message <> 'Teacher assignment creates an overlapping academic schedule' then raise; end if;
  end;
  results := results || jsonb_build_object('teacher_reassignment',jsonb_build_object('conflicting_assignment','rejected 23P01'));

  select b.id,(a.starts_at+interval '30 minutes')::time,(a.ends_at+interval '30 minutes')::time
    into strict sports_target,sports_start,sports_end
    from public.sport_group_schedules a join public.sport_groups ga on ga.id=a.sport_group_id
    join public.sport_group_schedules b on b.sport_group_id<>a.sport_group_id and b.day_of_week=a.day_of_week and b.is_active
    join public.sport_groups gb on gb.id=b.sport_group_id
    where a.is_active and ga.is_active and gb.is_active and ga.teacher_id=gb.teacher_id
      and ga.academic_year=2027 and gb.academic_year=2027 and a.starts_at<b.starts_at
      and ga.name like 'DEMO %' and gb.name like 'DEMO %' limit 1;
  begin
    update public.sport_group_schedules set starts_at=sports_start,ends_at=sports_end where id=sports_target;
    raise exception 'Overlapping sports write unexpectedly succeeded';
  exception when exclusion_violation then
    get stacked diagnostics message=message_text;
    if message <> 'Teacher schedule overlaps another active sport group schedule' then raise; end if;
  end;
  results := results || jsonb_build_object('sports_schedule',jsonb_build_object('overlap','rejected 23P01'));

  select id into strict parent_id from public.profiles
    where email='familia.demo.2027@educar.example' and role='parent' and is_active;
  select id into strict test_student_id from public.students where student_number='DEMO-2027-A006' and is_active;
  if exists(select 1 from public.student_guardians link join public.people person on person.id=link.guardian_person_id
    where person.profile_id=parent_id and link.student_id=test_student_id) then
    raise exception 'Controlled third child is already linked';
  end if;
  first_link := public.link_student_guardian(test_student_id,parent_id,'tutor demo',false);
  second_link := public.link_student_guardian(test_student_id,parent_id,'tutor demo',false);
  if first_link->>'id' is null or first_link->>'id' <> second_link->>'id' then
    raise exception 'Guardian RPC is not idempotent';
  end if;
  if (select count(*) from public.student_guardians link join public.people person on person.id=link.guardian_person_id
    where person.profile_id=parent_id and link.student_id=test_student_id) <> 1 then
    raise exception 'Guardian RPC duplicated links';
  end if;
  results := results || jsonb_build_object('guardian_new_link',jsonb_build_object('insert','successful','repeat','same id','third_child','temporary, rolled back'));
  perform set_config('educar.stage1_results',results::text,true);
end;
$$;

select current_setting('educar.stage1_results')::jsonb as controlled_tests;
rollback;
