create table public.enrollment_requests (
  id uuid primary key default gen_random_uuid(),
  student_first_name text not null check (btrim(student_first_name) <> ''),
  student_last_name text not null check (btrim(student_last_name) <> ''),
  student_dni text not null check (student_dni ~ '^[0-9]{7,8}$'),
  birth_date date not null,
  educational_level text not null check (btrim(educational_level) <> ''),
  school_year text not null check (btrim(school_year) <> ''),
  turn text not null check (btrim(turn) <> ''),
  academic_year integer not null check (academic_year > 0),
  responsible_full_name text not null check (btrim(responsible_full_name) <> ''),
  responsible_dni text not null check (responsible_dni ~ '^[0-9]{7,8}$'),
  responsible_relation text not null check (btrim(responsible_relation) <> ''),
  phone text not null check (phone ~ '^[0-9]{8,15}$'),
  email text not null check (btrim(email) <> ''),
  notes text not null default '',
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'archived')),
  source text not null default 'public-form' check (source = 'public-form'),
  approved_course_id uuid references public.courses (id) on delete restrict,
  student_id uuid references public.students (id) on delete set null,
  enrollment_id uuid references public.student_enrollments (id) on delete set null,
  rejection_reason text,
  created_by_profile_id uuid references public.profiles (id) on delete set null,
  updated_by_profile_id uuid references public.profiles (id) on delete set null,
  approved_by_profile_id uuid references public.profiles (id) on delete set null,
  rejected_by_profile_id uuid references public.profiles (id) on delete set null,
  archived_by_profile_id uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  approved_at timestamptz,
  rejected_at timestamptz,
  archived_at timestamptz
);

create unique index enrollment_requests_active_student_dni_unique_idx
  on public.enrollment_requests (lower(btrim(student_dni)))
  where status in ('pending', 'approved');

create unique index enrollment_requests_enrollment_unique_idx
  on public.enrollment_requests (enrollment_id)
  where enrollment_id is not null;

create index enrollment_requests_status_created_idx
  on public.enrollment_requests (status, created_at desc);

create index enrollment_requests_email_normalized_idx
  on public.enrollment_requests (lower(btrim(email)));

create index enrollment_requests_course_idx
  on public.enrollment_requests (approved_course_id)
  where approved_course_id is not null;

create index enrollment_requests_actor_created_idx
  on public.enrollment_requests (updated_by_profile_id, updated_at desc);

create trigger enrollment_requests_set_updated_at
  before update on public.enrollment_requests
  for each row execute function public.set_updated_at();

create trigger enrollment_requests_audit_log
  after insert or update on public.enrollment_requests
  for each row execute function public.write_audit_log();

alter table public.enrollment_requests enable row level security;

-- WHY: The lifecycle RPCs must be the only client boundary so approval cannot bypass enrollment checks.
revoke all on public.enrollment_requests from anon, authenticated;

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

  if exists (
    select 1
    from public.enrollment_requests
    where lower(btrim(student_dni)) = student_dni_normalized
      and status in ('pending', 'approved')
  ) then
    raise exception 'An active enrollment request already exists for this student DNI'
      using errcode = 'unique_violation';
  end if;

  if public.is_active_superadmin() then
    created_by := auth.uid();
  end if;

  insert into public.enrollment_requests (
    student_first_name,
    student_last_name,
    student_dni,
    birth_date,
    educational_level,
    school_year,
    turn,
    academic_year,
    responsible_full_name,
    responsible_dni,
    responsible_relation,
    phone,
    email,
    notes,
    created_by_profile_id,
    updated_by_profile_id
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
    created_by
  )
  returning * into request_row;

  return to_jsonb(request_row);
end;
$$;

create or replace function public.list_enrollment_requests(p_status text default null)
returns setof public.enrollment_requests
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if not public.is_active_superadmin() then
    raise exception 'Active superadmin role required' using errcode = 'insufficient_privilege';
  end if;

  if p_status is not null and p_status not in ('pending', 'approved', 'rejected', 'archived') then
    raise exception 'Enrollment request status is invalid' using errcode = 'invalid_parameter_value';
  end if;

  return query
    select *
    from public.enrollment_requests
    where p_status is null or status = p_status
    order by created_at desc;
end;
$$;

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
  person_id uuid;
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

  select p.id into person_id
  from public.people p
  where lower(btrim(p.dni)) = request_row.student_dni
  for update;

  if person_id is null then
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
    returning id into person_id;
  end if;

  select s.id, s.is_active
    into student_id_value, student_active
  from public.students s
  where s.person_id = person_id
  for update;

  if student_id_value is null then
    insert into public.students (person_id)
    values (person_id)
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
    -- WHY: Locking the course serializes concurrent approvals before the capacity check.
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

create or replace function public.reject_enrollment_request(
  p_request_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  request_row public.enrollment_requests%rowtype;
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

  if request_row.status = 'rejected' then
    return jsonb_build_object('id', request_row.id, 'status', request_row.status);
  end if;

  if request_row.status <> 'pending' then
    raise exception 'Only pending enrollment requests can be rejected'
      using errcode = 'check_violation';
  end if;

  update public.enrollment_requests
  set status = 'rejected',
      rejection_reason = nullif(btrim(p_reason), ''),
      rejected_at = now(),
      rejected_by_profile_id = auth.uid(),
      updated_by_profile_id = auth.uid()
  where id = request_row.id
  returning * into request_row;

  return jsonb_build_object('id', request_row.id, 'status', request_row.status);
end;
$$;

create or replace function public.archive_enrollment_request(p_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  request_row public.enrollment_requests%rowtype;
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

  if request_row.status = 'archived' then
    return jsonb_build_object('id', request_row.id, 'status', request_row.status);
  end if;

  update public.enrollment_requests
  set status = 'archived',
      archived_at = now(),
      archived_by_profile_id = auth.uid(),
      updated_by_profile_id = auth.uid()
  where id = request_row.id
  returning * into request_row;

  return jsonb_build_object('id', request_row.id, 'status', request_row.status);
end;
$$;

revoke execute on function public.submit_enrollment_request(jsonb) from public;
revoke execute on function public.list_enrollment_requests(text) from public;
revoke execute on function public.approve_enrollment_request(uuid, uuid) from public;
revoke execute on function public.reject_enrollment_request(uuid, text) from public;
revoke execute on function public.archive_enrollment_request(uuid) from public;

grant execute on function public.submit_enrollment_request(jsonb) to anon, authenticated;
grant execute on function public.list_enrollment_requests(text) to authenticated;
grant execute on function public.approve_enrollment_request(uuid, uuid) to authenticated;
grant execute on function public.reject_enrollment_request(uuid, text) to authenticated;
grant execute on function public.archive_enrollment_request(uuid) to authenticated;
