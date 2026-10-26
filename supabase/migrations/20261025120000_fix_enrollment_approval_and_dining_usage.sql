-- Correct two runtime defects found by the DEMO acceptance checks.
-- Keep the existing function signatures, authorization checks and RLS policies.

create or replace function public.approve_enrollment_request(
  p_request_id uuid,
  p_course_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  request_row public.enrollment_requests%rowtype;
  course_row public.courses%rowtype;
  resolved_person_id uuid;
  student_id_value uuid;
  enrollment_id_value uuid;
  existing_enrollment_course_id uuid;
  student_active boolean;
  active_enrollment_count integer;
begin
  if not public.is_active_superadmin() then
    raise exception 'Active superadmin role required' using errcode = 'insufficient_privilege';
  end if;

  select * into request_row
  from public.enrollment_requests
  where id = p_request_id
  for update;

  if not found then
    raise exception 'Enrollment request not found' using errcode = 'no_data_found';
  end if;

  if request_row.status = 'approved' then
    if request_row.approved_course_id is distinct from p_course_id then
      raise exception 'Enrollment request is already approved for another course'
        using errcode = 'unique_violation';
    end if;
    return jsonb_build_object(
      'id', request_row.id,
      'status', request_row.status,
      'student_id', request_row.student_id,
      'enrollment_id', request_row.enrollment_id,
      'approved_course_id', request_row.approved_course_id
    );
  end if;

  if request_row.status <> 'pending' then
    raise exception 'Only pending enrollment requests can be approved'
      using errcode = 'check_violation';
  end if;

  select * into course_row
  from public.courses
  where id = p_course_id
  for update;

  if not found or not course_row.is_active then
    raise exception 'Approval requires an active course' using errcode = 'check_violation';
  end if;

  if course_row.academic_year <> request_row.academic_year then
    raise exception 'Course academic year does not match the request'
      using errcode = 'check_violation';
  end if;

  select p.id into resolved_person_id
  from public.people p
  where lower(btrim(p.dni)) = request_row.student_dni
  for update;

  if resolved_person_id is null then
    insert into public.people (
      first_name,
      last_name,
      email,
      phone,
      dni,
      birth_date
    )
    values (
      request_row.student_first_name,
      request_row.student_last_name,
      request_row.email,
      request_row.phone,
      request_row.student_dni,
      request_row.birth_date
    )
    returning id into resolved_person_id;
  end if;

  select s.id, s.is_active
    into student_id_value, student_active
  from public.students s
  where s.person_id = resolved_person_id
  for update;

  if student_id_value is null then
    insert into public.students (person_id)
    values (resolved_person_id)
    returning id into student_id_value;
  elsif not student_active then
    raise exception 'Approval requires an active student' using errcode = 'check_violation';
  end if;

  select e.id, e.course_id
  into enrollment_id_value, existing_enrollment_course_id
  from public.student_enrollments e
  where e.student_id = student_id_value
    and e.academic_year = request_row.academic_year
    and e.is_active
  for update;

  if enrollment_id_value is not null then
    if existing_enrollment_course_id <> p_course_id then
      raise exception 'Student already has an active enrollment for this academic year'
        using errcode = 'unique_violation';
    end if;
  else
    -- Locking the course serializes concurrent approvals before the capacity check.
    if course_row.capacity is not null then
      select count(*) into active_enrollment_count
      from public.student_enrollments
      where course_id = p_course_id
        and is_active;

      if active_enrollment_count >= course_row.capacity then
        raise exception 'Course capacity reached' using errcode = 'check_violation';
      end if;
    end if;

    insert into public.student_enrollments (student_id, course_id, academic_year)
    values (student_id_value, p_course_id, request_row.academic_year)
    returning id into enrollment_id_value;
  end if;

  update public.enrollment_requests
  set status = 'approved',
      approved_course_id = p_course_id,
      student_id = student_id_value,
      enrollment_id = enrollment_id_value,
      approved_at = now(),
      approved_by_profile_id = auth.uid(),
      rejected_at = null,
      rejected_by_profile_id = null,
      rejection_reason = null,
      updated_by_profile_id = auth.uid()
  where id = request_row.id
  returning * into request_row;

  return jsonb_build_object(
    'id', request_row.id,
    'status', request_row.status,
    'student_id', request_row.student_id,
    'enrollment_id', request_row.enrollment_id,
    'approved_course_id', request_row.approved_course_id
  );
end;
$$;

-- dining_usage intentionally has no updated_at column; its upsert only changes used.
drop trigger if exists dining_usage_set_updated_at on public.dining_usage;
