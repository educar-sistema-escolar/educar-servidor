-- Stage 2: superadmin-only, transactional provisioning for students and teachers.

alter table public.people
  add column dni text;

create unique index people_dni_normalized_unique_idx
  on public.people (lower(btrim(dni)))
  where dni is not null;

alter table public.teachers
  add column specialty text;

create or replace function public.create_student(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  person_id uuid;
  student_id uuid;
begin
  if not public.is_active_superadmin() then
    raise exception 'Active superadmin role required' using errcode = 'insufficient_privilege';
  end if;

  if jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Payload must be a JSON object' using errcode = 'invalid_parameter_value';
  end if;

  insert into public.people (profile_id, first_name, last_name, email, phone, dni)
  values (
    nullif(btrim(p_payload ->> 'profile_id'), '')::uuid,
    p_payload ->> 'first_name',
    p_payload ->> 'last_name',
    nullif(btrim(p_payload ->> 'email'), ''),
    nullif(btrim(p_payload ->> 'phone'), ''),
    nullif(btrim(p_payload ->> 'dni'), '')
  )
  returning id into person_id;

  insert into public.students (person_id, student_number)
  values (person_id, nullif(btrim(p_payload ->> 'student_number'), ''))
  returning id into student_id;

  return jsonb_build_object('id', student_id);
end;
$$;

create or replace function public.update_student(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  student_id uuid;
  person_id uuid;
begin
  if not public.is_active_superadmin() then
    raise exception 'Active superadmin role required' using errcode = 'insufficient_privilege';
  end if;

  if jsonb_typeof(p_payload) <> 'object' or nullif(btrim(p_payload ->> 'id'), '') is null then
    raise exception 'Payload must be an object containing id' using errcode = 'invalid_parameter_value';
  end if;

  student_id := (p_payload ->> 'id')::uuid;

  select s.person_id
    into strict person_id
    from public.students s
   where s.id = student_id;

  update public.people
     set profile_id = case when p_payload ? 'profile_id' then nullif(btrim(p_payload ->> 'profile_id'), '')::uuid else profile_id end,
         first_name = case when p_payload ? 'first_name' then p_payload ->> 'first_name' else first_name end,
         last_name = case when p_payload ? 'last_name' then p_payload ->> 'last_name' else last_name end,
         email = case when p_payload ? 'email' then nullif(btrim(p_payload ->> 'email'), '') else email end,
         phone = case when p_payload ? 'phone' then nullif(btrim(p_payload ->> 'phone'), '') else phone end,
         dni = case when p_payload ? 'dni' then nullif(btrim(p_payload ->> 'dni'), '') else dni end
   where id = person_id;

  update public.students
     set student_number = case when p_payload ? 'student_number' then nullif(btrim(p_payload ->> 'student_number'), '') else student_number end,
         is_active = case when p_payload ? 'is_active' then (p_payload ->> 'is_active')::boolean else is_active end
   where id = student_id;

  return jsonb_build_object('id', student_id);
end;
$$;

create or replace function public.create_teacher(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  person_id uuid;
  teacher_id uuid;
begin
  if not public.is_active_superadmin() then
    raise exception 'Active superadmin role required' using errcode = 'insufficient_privilege';
  end if;

  if jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Payload must be a JSON object' using errcode = 'invalid_parameter_value';
  end if;

  insert into public.people (profile_id, first_name, last_name, email, phone, dni)
  values (
    nullif(btrim(p_payload ->> 'profile_id'), '')::uuid,
    p_payload ->> 'first_name',
    p_payload ->> 'last_name',
    nullif(btrim(p_payload ->> 'email'), ''),
    nullif(btrim(p_payload ->> 'phone'), ''),
    nullif(btrim(p_payload ->> 'dni'), '')
  )
  returning id into person_id;

  insert into public.teachers (person_id, teacher_number, specialty)
  values (
    person_id,
    nullif(btrim(p_payload ->> 'teacher_number'), ''),
    nullif(btrim(p_payload ->> 'specialty'), '')
  )
  returning id into teacher_id;

  return jsonb_build_object('id', teacher_id);
end;
$$;

create or replace function public.update_teacher(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  teacher_id uuid;
  person_id uuid;
begin
  if not public.is_active_superadmin() then
    raise exception 'Active superadmin role required' using errcode = 'insufficient_privilege';
  end if;

  if jsonb_typeof(p_payload) <> 'object' or nullif(btrim(p_payload ->> 'id'), '') is null then
    raise exception 'Payload must be an object containing id' using errcode = 'invalid_parameter_value';
  end if;

  teacher_id := (p_payload ->> 'id')::uuid;

  select t.person_id
    into strict person_id
    from public.teachers t
   where t.id = teacher_id;

  update public.people
     set profile_id = case when p_payload ? 'profile_id' then nullif(btrim(p_payload ->> 'profile_id'), '')::uuid else profile_id end,
         first_name = case when p_payload ? 'first_name' then p_payload ->> 'first_name' else first_name end,
         last_name = case when p_payload ? 'last_name' then p_payload ->> 'last_name' else last_name end,
         email = case when p_payload ? 'email' then nullif(btrim(p_payload ->> 'email'), '') else email end,
         phone = case when p_payload ? 'phone' then nullif(btrim(p_payload ->> 'phone'), '') else phone end,
         dni = case when p_payload ? 'dni' then nullif(btrim(p_payload ->> 'dni'), '') else dni end
   where id = person_id;

  update public.teachers
     set teacher_number = case when p_payload ? 'teacher_number' then nullif(btrim(p_payload ->> 'teacher_number'), '') else teacher_number end,
         specialty = case when p_payload ? 'specialty' then nullif(btrim(p_payload ->> 'specialty'), '') else specialty end,
         is_active = case when p_payload ? 'is_active' then (p_payload ->> 'is_active')::boolean else is_active end
   where id = teacher_id;

  return jsonb_build_object('id', teacher_id);
end;
$$;

revoke execute on function public.create_student(jsonb) from public;
revoke execute on function public.update_student(jsonb) from public;
revoke execute on function public.create_teacher(jsonb) from public;
revoke execute on function public.update_teacher(jsonb) from public;

grant execute on function public.create_student(jsonb) to authenticated;
grant execute on function public.update_student(jsonb) to authenticated;
grant execute on function public.create_teacher(jsonb) to authenticated;
grant execute on function public.update_teacher(jsonb) to authenticated;
