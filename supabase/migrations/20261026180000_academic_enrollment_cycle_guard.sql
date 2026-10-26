-- Prevent duplicate academic enrollment requests per student and cycle.
-- Keep future cycles available when the institution has an active course configured.

drop index if exists public.enrollment_requests_active_student_dni_unique_idx;

create unique index if not exists enrollment_requests_active_student_dni_year_unique_idx
  on public.enrollment_requests (lower(btrim(student_dni)), academic_year)
  where status in ('pending', 'approved');

create or replace function public.list_available_enrollment_years()
returns table(academic_year integer)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select distinct course.academic_year
  from public.courses course
  where course.is_active
    and course.academic_year >= extract(year from current_date)::integer
  order by course.academic_year;
$$;

create or replace function public.get_student_academic_enrollment_status(
  p_student_id uuid,
  p_academic_year integer
)
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  student_dni_value text;
  person_profile_id uuid;
  request_status text;
begin
  if p_academic_year is null or p_academic_year not between 1900 and 2200 then
    raise exception 'Academic year is invalid' using errcode = 'invalid_parameter_value';
  end if;

  if not public.is_active_user() then
    raise exception 'Active account required' using errcode = 'insufficient_privilege';
  end if;

  select regexp_replace(coalesce(person.dni, ''), '[^0-9]', '', 'g'), person.profile_id
    into student_dni_value, person_profile_id
  from public.students student
  join public.people person on person.id = student.person_id
  where student.id = p_student_id
    and student.is_active
    and person.is_active;

  if not found then
    raise exception 'Active student not found' using errcode = 'no_data_found';
  end if;

  if person_profile_id is distinct from auth.uid()
     and not public.is_guardian_of_student(p_student_id)
     and not public.is_active_superadmin() then
    raise exception 'Student relationship is not authorized' using errcode = 'insufficient_privilege';
  end if;

  if exists (
    select 1
    from public.student_enrollments enrollment
    where enrollment.student_id = p_student_id
      and enrollment.academic_year = p_academic_year
      and enrollment.is_active
  ) then
    return 'enrolled';
  end if;

  select request.status into request_status
  from public.enrollment_requests request
  where lower(btrim(request.student_dni)) = student_dni_value
    and request.academic_year = p_academic_year
    and request.status in ('pending', 'approved')
  order by (request.status = 'pending') desc, request.created_at desc
  limit 1;

  if request_status = 'pending' then
    return 'pending';
  elsif request_status = 'approved' then
    return 'already-requested';
  end if;

  return 'available';
end;
$$;

create or replace function public.submit_enrollment_request(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  request_row public.enrollment_requests%rowtype;
  student_dni_normalized text;
  responsible_dni_normalized text;
  phone_normalized text;
  email_normalized text;
  academic_year_value integer;
  birth_date_value date;
  created_by uuid;
  linked_student_id uuid;
  linked_student_dni text;
begin
  if jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Payload must be a JSON object' using errcode = 'invalid_parameter_value';
  end if;

  student_dni_normalized := regexp_replace(coalesce(p_payload ->> 'studentDni', ''), '[^0-9]', '', 'g');
  responsible_dni_normalized := regexp_replace(coalesce(p_payload ->> 'responsibleDni', ''), '[^0-9]', '', 'g');
  phone_normalized := regexp_replace(coalesce(p_payload ->> 'phone', ''), '[^0-9]', '', 'g');
  email_normalized := lower(btrim(coalesce(p_payload ->> 'email', '')));

  if length(btrim(coalesce(p_payload ->> 'studentFirstName', ''))) = 0
     or length(btrim(coalesce(p_payload ->> 'studentLastName', ''))) = 0
     or length(btrim(coalesce(p_payload ->> 'responsibleFullName', ''))) = 0
     or length(btrim(coalesce(p_payload ->> 'responsibleRelation', ''))) = 0
     or length(btrim(coalesce(p_payload ->> 'educationalLevel', ''))) = 0
     or length(btrim(coalesce(p_payload ->> 'schoolYear', ''))) = 0
     or length(btrim(coalesce(p_payload ->> 'turn', ''))) = 0
     or length(email_normalized) = 0 then
    raise exception 'Required enrollment fields are missing' using errcode = 'invalid_parameter_value';
  end if;

  if student_dni_normalized !~ '^[0-9]{7,8}$'
     or responsible_dni_normalized !~ '^[0-9]{7,8}$'
     or phone_normalized !~ '^[0-9]{8,15}$' then
    raise exception 'Enrollment DNI or phone is invalid' using errcode = 'invalid_parameter_value';
  end if;

  if student_dni_normalized = responsible_dni_normalized then
    raise exception 'Student and responsible DNI cannot be equal' using errcode = 'invalid_parameter_value';
  end if;

  if email_normalized !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception 'Enrollment email is invalid' using errcode = 'invalid_parameter_value';
  end if;

  if coalesce(p_payload ->> 'birthDate', '') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
    raise exception 'Birth date is invalid' using errcode = 'invalid_parameter_value';
  end if;
  birth_date_value := (p_payload ->> 'birthDate')::date;

  if coalesce(p_payload ->> 'academicYear', '') = '' then
    academic_year_value := extract(year from current_date)::integer;
  elsif p_payload ->> 'academicYear' !~ '^[0-9]{4}$' then
    raise exception 'Academic year is invalid' using errcode = 'invalid_parameter_value';
  else
    academic_year_value := (p_payload ->> 'academicYear')::integer;
  end if;

  if academic_year_value not between 1900 and 2200 then
    raise exception 'Academic year is invalid' using errcode = 'invalid_parameter_value';
  end if;

  if nullif(btrim(coalesce(p_payload ->> 'studentId', '')), '') is not null then
    begin
      linked_student_id := (p_payload ->> 'studentId')::uuid;
    exception when invalid_text_representation then
      raise exception 'Linked student id is invalid' using errcode = 'invalid_parameter_value';
    end;

    if auth.uid() is null or not public.is_active_user() then
      raise exception 'An active account is required for a linked-student request' using errcode = 'insufficient_privilege';
    end if;

    select regexp_replace(coalesce(person.dni, ''), '[^0-9]', '', 'g')
      into linked_student_dni
    from public.students student
    join public.people person on person.id = student.person_id
    where student.id = linked_student_id
      and student.is_active
      and person.is_active
      and (
        person.profile_id = auth.uid()
        or public.is_guardian_of_student(student.id)
        or public.is_active_superadmin()
      )
    for update of student, person;

    if not found then
      raise exception 'Linked student is unavailable or not authorized' using errcode = 'insufficient_privilege';
    end if;

    if linked_student_dni !~ '^[0-9]{7,8}$' or linked_student_dni <> student_dni_normalized then
      raise exception 'The student DNI does not match the linked student' using errcode = 'invalid_parameter_value';
    end if;
  elsif auth.uid() is not null and exists (
    select 1 from public.profiles profile
    where profile.id = auth.uid()
      and profile.is_active
      and profile.role::text in ('student', 'parent', 'guardian')
  ) then
    raise exception 'Select the linked student from the institutional portal before requesting enrollment' using errcode = 'insufficient_privilege';
  end if;

  -- Serialize requests for one DNI/cycle and coordinate with admin approval's person-row lock.
  perform pg_advisory_xact_lock(hashtextextended(student_dni_normalized || ':' || academic_year_value::text, 0));
  perform person.id
  from public.people person
  where regexp_replace(coalesce(person.dni, ''), '[^0-9]', '', 'g') = student_dni_normalized
  for update;

  if not exists (
    select 1 from public.courses course
    where course.is_active and course.academic_year = academic_year_value
  ) then
    raise exception 'The selected academic cycle is not open for enrollment' using errcode = 'check_violation';
  end if;

  if exists (
    select 1
    from public.students student
    join public.people person on person.id = student.person_id
    join public.student_enrollments enrollment on enrollment.student_id = student.id
    where (
        (linked_student_id is not null and student.id = linked_student_id)
        or (linked_student_id is null and regexp_replace(coalesce(person.dni, ''), '[^0-9]', '', 'g') = student_dni_normalized)
      )
      and student.is_active
      and enrollment.academic_year = academic_year_value
      and enrollment.is_active
  ) then
    raise exception 'The student already has an active enrollment for this academic cycle' using errcode = 'unique_violation';
  end if;

  if exists (
    select 1
    from public.enrollment_requests
    where lower(btrim(student_dni)) = student_dni_normalized
      and academic_year = academic_year_value
      and status in ('pending', 'approved')
  ) then
    raise exception 'An active enrollment request already exists for this student and academic cycle'
      using errcode = 'unique_violation';
  end if;

  if public.is_active_superadmin() then
    created_by := auth.uid();
  end if;

  insert into public.enrollment_requests (
    student_first_name, student_last_name, student_dni, birth_date, educational_level,
    school_year, turn, academic_year, responsible_full_name, responsible_dni,
    responsible_relation, phone, email, notes, created_by_profile_id, updated_by_profile_id, student_id
  )
  values (
    regexp_replace(btrim(p_payload ->> 'studentFirstName'), '\s+', ' ', 'g'),
    regexp_replace(btrim(p_payload ->> 'studentLastName'), '\s+', ' ', 'g'),
    student_dni_normalized,
    birth_date_value,
    regexp_replace(btrim(p_payload ->> 'educationalLevel'), '\s+', ' ', 'g'),
    regexp_replace(btrim(p_payload ->> 'schoolYear'), '\s+', ' ', 'g'),
    regexp_replace(btrim(p_payload ->> 'turn'), '\s+', ' ', 'g'),
    academic_year_value,
    regexp_replace(btrim(p_payload ->> 'responsibleFullName'), '\s+', ' ', 'g'),
    responsible_dni_normalized,
    regexp_replace(btrim(p_payload ->> 'responsibleRelation'), '\s+', ' ', 'g'),
    phone_normalized,
    email_normalized,
    btrim(coalesce(p_payload ->> 'notes', '')),
    created_by,
    created_by,
    linked_student_id
  )
  returning * into request_row;

  return to_jsonb(request_row);
end;
$$;

revoke all on function public.list_available_enrollment_years() from public;
revoke all on function public.get_student_academic_enrollment_status(uuid, integer) from public, anon;
revoke execute on function public.submit_enrollment_request(jsonb) from public;
grant execute on function public.list_available_enrollment_years() to anon, authenticated;
grant execute on function public.get_student_academic_enrollment_status(uuid, integer) to authenticated;
grant execute on function public.submit_enrollment_request(jsonb) to anon, authenticated;
