-- Run only after applying all migrations in a disposable Supabase project.
-- Requires two pending requests for different students, a matching active
-- course for each request, and one active dining enrollment. Every test write
-- is rolled back at the end.
begin;

do $$
declare
  admin_profile_id uuid;
  approval_request_id uuid;
  rejected_request_id uuid;
  approval_course_id uuid;
  rejected_student_dni text;
  approval_student_dni text;
  approval_academic_year integer;
  rejected_student_count_before integer;
  approval_result jsonb;
  rejection_result jsonb;
  dining_enrollment_id uuid;
  dining_result jsonb;
  second_dining_result jsonb;
  dining_usage_count integer;
begin
  select p.id into admin_profile_id
  from public.profiles p
  where p.role = 'superadmin'
    and p.is_active
    and p.account_status = 'active'
  order by p.created_at
  limit 1;

  if admin_profile_id is null then
    raise exception 'Regression test requires an active superadmin fixture';
  end if;
  perform set_config('request.jwt.claim.sub', admin_profile_id::text, true);

  if exists (
    select 1
    from public.academic_schedules first_schedule
    join public.course_subjects first_assignment on first_assignment.id = first_schedule.course_subject_id
    join public.courses first_course on first_course.id = first_schedule.course_id
    join public.academic_schedules second_schedule
      on second_schedule.id > first_schedule.id
     and second_schedule.is_active
     and second_schedule.academic_year = first_schedule.academic_year
     and second_schedule.day_of_week = first_schedule.day_of_week
     and first_schedule.starts_at < second_schedule.ends_at
     and second_schedule.starts_at < first_schedule.ends_at
    join public.course_subjects second_assignment on second_assignment.id = second_schedule.course_subject_id
    join public.courses second_course on second_course.id = second_schedule.course_id
    where first_schedule.is_active
      and first_assignment.is_active
      and first_assignment.teacher_id is not null
      and second_assignment.is_active
      and second_assignment.teacher_id = first_assignment.teacher_id
      and second_course.id <> first_course.id
      and first_course.code like 'DEMO-27-%'
      and second_course.code like 'DEMO-27-%'
  ) then
    raise exception 'DEMO academic schedules still overlap for a teacher';
  end if;

  if exists (
    select 1
    from public.sport_group_schedules first_schedule
    join public.sport_groups first_group on first_group.id = first_schedule.sport_group_id
    join public.sport_group_schedules second_schedule
      on second_schedule.id > first_schedule.id
     and second_schedule.is_active
     and second_schedule.day_of_week = first_schedule.day_of_week
     and first_schedule.starts_at < second_schedule.ends_at
     and second_schedule.starts_at < first_schedule.ends_at
    join public.sport_groups second_group on second_group.id = second_schedule.sport_group_id
    where first_schedule.is_active
      and first_group.is_active
      and first_group.teacher_id is not null
      and second_group.is_active
      and second_group.teacher_id = first_group.teacher_id
      and second_group.academic_year = first_group.academic_year
      and second_group.id <> first_group.id
      and first_group.name ~ '^DEMO (Fútbol|Básquet|Vóley|Natación) (Inicial|Primario|Secundario)$'
      and second_group.name ~ '^DEMO (Fútbol|Básquet|Vóley|Natación) (Inicial|Primario|Secundario)$'
  ) then
    raise exception 'DEMO sports schedules still overlap for a teacher';
  end if;

  select request.id, course.id, request.student_dni, request.academic_year
  into approval_request_id, approval_course_id, approval_student_dni, approval_academic_year
  from public.enrollment_requests request
  join public.educational_levels level
    on lower(btrim(level.name)) = lower(btrim(request.educational_level))
  join public.courses course
    on course.educational_level_id = level.id
   and course.academic_year = request.academic_year
   and course.is_active
  where request.status = 'pending'
  order by request.created_at
  limit 1;

  if approval_request_id is null then
    raise exception 'Approval regression requires a pending request and matching active course';
  end if;

  select candidate.id, candidate.student_dni
  into rejected_request_id, rejected_student_dni
  from public.enrollment_requests candidate
  where candidate.status = 'pending'
    and candidate.id <> approval_request_id
    and candidate.student_dni <> approval_student_dni
    and exists (
      select 1
      from public.educational_levels level
      join public.courses course
        on course.educational_level_id = level.id
       and course.academic_year = candidate.academic_year
       and course.is_active
      where lower(btrim(level.name)) = lower(btrim(candidate.educational_level))
    )
  order by candidate.created_at
  limit 1;

  if rejected_request_id is null then
    raise exception 'Rejection regression requires a second pending request for a different student';
  end if;

  approval_result := public.approve_enrollment_request(approval_request_id, approval_course_id);
  if approval_result->>'status' <> 'approved'
    or nullif(approval_result->>'student_id', '') is null
    or nullif(approval_result->>'enrollment_id', '') is null then
    raise exception 'Expected approval to return student and enrollment IDs, got %', approval_result;
  end if;

  if not exists (
    select 1
    from public.people person
    join public.students student on student.person_id = person.id
    join public.student_enrollments enrollment on enrollment.student_id = student.id
    where lower(btrim(person.dni)) = lower(btrim(approval_student_dni))
      and student.id = (approval_result->>'student_id')::uuid
      and enrollment.id = (approval_result->>'enrollment_id')::uuid
      and enrollment.course_id = approval_course_id
      and enrollment.academic_year = approval_academic_year
      and enrollment.is_active
      and student.is_active
  ) then
    raise exception 'Approved request did not create or reuse the correct active student enrollment';
  end if;

  select count(*) into rejected_student_count_before
  from public.people person
  join public.students student on student.person_id = person.id
  where lower(btrim(person.dni)) = lower(btrim(rejected_student_dni));

  rejection_result := public.reject_enrollment_request(rejected_request_id, 'Disposable regression check');
  if rejection_result->>'status' <> 'rejected'
    or not exists (
      select 1
      from public.enrollment_requests request
      where request.id = rejected_request_id
        and request.status = 'rejected'
        and request.rejection_reason = 'Disposable regression check'
    ) then
    raise exception 'Expected rejection to persist status and reason, got %', rejection_result;
  end if;

  if (select count(*)
      from public.people person
      join public.students student on student.person_id = person.id
      where lower(btrim(person.dni)) = lower(btrim(rejected_student_dni))) > rejected_student_count_before then
    raise exception 'Rejecting a request unexpectedly created a student';
  end if;

  if exists (
    select 1
    from public.enrollment_requests request
    where request.id = rejected_request_id
      and (request.student_id is not null or request.enrollment_id is not null)
  ) then
    raise exception 'Rejected request unexpectedly references a student or enrollment';
  end if;

  select enrollment.id into dining_enrollment_id
  from public.student_dining_enrollments enrollment
  where enrollment.is_active
  order by enrollment.created_at
  limit 1;

  if dining_enrollment_id is null then
    raise exception 'Dining regression requires an active dining enrollment fixture';
  end if;

  dining_result := public.record_dining_usage(dining_enrollment_id, date '2099-01-01', true);
  second_dining_result := public.record_dining_usage(dining_enrollment_id, date '2099-01-01', false);
  if (dining_result->>'used')::boolean is distinct from true
    or (second_dining_result->>'used')::boolean is distinct from false then
    raise exception 'Expected dining usage upsert to change true to false, got % then %', dining_result, second_dining_result;
  end if;

  select count(*) into dining_usage_count
  from public.dining_usage dining_row
  where dining_row.dining_enrollment_id = dining_enrollment_id
    and dining_row.service_date = date '2099-01-01';

  if dining_usage_count <> 1 then
    raise exception 'Expected one idempotent dining usage row, found %', dining_usage_count;
  end if;
end;
$$;

rollback;
