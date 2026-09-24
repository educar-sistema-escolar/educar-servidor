-- Student and guardian portal access is derived from the authenticated profile,
-- never from client-supplied student IDs or local browser role claims.

-- Keep privileged RPC authorization aligned with portal account revocation.
create or replace function public.is_active_superadmin()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.profiles profile
    where profile.id = (select auth.uid())
      and profile.role::text = 'superadmin'
      and profile.is_active = true
      and profile.account_status = 'active'
  );
$$;

create or replace function public.is_active_user()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.profiles profile
    where profile.id = (select auth.uid())
      and profile.is_active = true
      and profile.account_status = 'active'
  );
$$;

-- Permission fallback paths must use the same account revocation field as
-- direct superadmin checks, without changing role-to-permission mappings.
create or replace function public.is_allowed(permission_code text)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.profiles profile
    join public.role_permissions mapping
      on mapping.role_code = profile.role::text
    join public.permissions permission
      on permission.code = mapping.permission_code
    where profile.id = (select auth.uid())
      and profile.is_active = true
      and profile.account_status = 'active'
      and permission.code = $1
      and permission.is_active = true
  );
$$;

create or replace function public.is_student_of_student(p_student_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.profiles profile
    join public.people person on person.profile_id = profile.id
    join public.students student on student.person_id = person.id
    where profile.id = (select auth.uid())
      and profile.role::text = 'student'
      and profile.is_active = true
      and profile.account_status = 'active'
      and person.is_active = true
      and student.is_active = true
      and student.id = p_student_id
  );
$$;

create or replace function public.is_guardian_of_student(student_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.profiles profile
    join public.people guardian_person
      on guardian_person.profile_id = profile.id
    join public.student_guardians relationship
      on relationship.guardian_person_id = guardian_person.id
    join public.students student
      on student.id = relationship.student_id
    where profile.id = (select auth.uid())
      and profile.is_active = true
      and profile.account_status = 'active'
      and profile.role::text in ('guardian', 'parent')
      and guardian_person.is_active = true
      and relationship.is_active = true
      and student.id = $1
      and student.is_active = true
  );
$$;

create or replace function public.is_teacher_of_student(student_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.profiles profile
    join public.people teacher_person
      on teacher_person.profile_id = profile.id
    join public.teachers teacher
      on teacher.person_id = teacher_person.id
    join public.course_subjects assignment
      on assignment.teacher_id = teacher.id
    join public.courses course
      on course.id = assignment.course_id
    join public.student_enrollments enrollment
      on enrollment.course_id = assignment.course_id
     and enrollment.academic_year = assignment.academic_year
    join public.students student
      on student.id = enrollment.student_id
    where profile.id = (select auth.uid())
      and profile.is_active = true
      and profile.account_status = 'active'
      and profile.role::text = 'teacher'
      and teacher_person.is_active = true
      and teacher.is_active = true
      and assignment.is_active = true
      and course.is_active = true
      and enrollment.is_active = true
      and student.is_active = true
      and student.id = $1
  );
$$;

drop policy if exists "Active students can read their own person record" on public.people;
create policy "Active students can read their own person record"
  on public.people for select to authenticated
  using (
    (select public.is_active_user())
    and profile_id = (select auth.uid())
  );

drop policy if exists "Active students can read their own student record" on public.students;
create policy "Active students can read their own student record"
  on public.students for select to authenticated
  using ((select public.is_student_of_student(id)));

drop policy if exists "Related users can read sport enrollments" on public.student_sport_enrollments;
create policy "Related users can read sport enrollments"
  on public.student_sport_enrollments for select to authenticated
  using (
    (select public.is_active_user())
    and (
      (select public.is_active_superadmin())
      or public.is_student_of_student(student_id)
      or public.is_guardian_of_student(student_id)
      or public.is_teacher_of_student(student_id)
    )
  );

drop policy if exists "Related users can read transport enrollments" on public.student_transport_enrollments;
create policy "Related users can read transport enrollments"
  on public.student_transport_enrollments for select to authenticated
  using (
    (select public.is_active_user())
    and (
      (select public.is_active_superadmin())
      or public.is_student_of_student(student_id)
      or public.is_guardian_of_student(student_id)
      or public.is_teacher_of_student(student_id)
    )
  );

drop policy if exists "Related users can read dining enrollments" on public.student_dining_enrollments;
create policy "Related users can read dining enrollments"
  on public.student_dining_enrollments for select to authenticated
  using (
    (select public.is_active_user())
    and (
      (select public.is_active_superadmin())
      or public.is_student_of_student(student_id)
      or public.is_guardian_of_student(student_id)
      or public.is_teacher_of_student(student_id)
    )
  );

drop policy if exists "Related users can read dining usage" on public.dining_usage;
create policy "Related users can read dining usage"
  on public.dining_usage for select to authenticated
  using (
    (select public.is_active_user())
    and (
      (select public.is_active_superadmin())
      or exists (
        select 1
        from public.student_dining_enrollments enrollment
        where enrollment.id = dining_usage.dining_enrollment_id
          and (
            public.is_student_of_student(enrollment.student_id)
            or public.is_guardian_of_student(enrollment.student_id)
            or public.is_teacher_of_student(enrollment.student_id)
          )
      )
    )
  );

grant execute on function public.is_student_of_student(uuid) to authenticated;
revoke execute on function public.is_student_of_student(uuid) from public;

do $$
begin
  if exists (
    select 1
    from public.people
    where dni is not null
      and regexp_replace(dni, '[^0-9]', '', 'g') !~ '^[0-9]{7,8}$'
  ) then
    raise exception 'People contain invalid DNI values; repair them before enabling student portal links'
      using errcode = 'check_violation';
  end if;

  if exists (
    select 1
    from public.people
    where dni is not null
    group by regexp_replace(dni, '[^0-9]', '', 'g')
    having count(*) > 1
  ) then
    raise exception 'People contain duplicate digit-normalized DNI values; resolve them before enabling student portal links'
      using errcode = 'unique_violation';
  end if;
end;
$$;

update public.people
set dni = regexp_replace(dni, '[^0-9]', '', 'g')
where dni is not null
  and dni <> regexp_replace(dni, '[^0-9]', '', 'g');

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'people_dni_format_check'
      and conrelid = 'public.people'::regclass
  ) then
    alter table public.people
      add constraint people_dni_format_check
      check (dni is null or dni ~ '^[0-9]{7,8}$');
  end if;
end;
$$;

create or replace function public.normalize_person_dni()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if new.dni is not null then
    new.dni := regexp_replace(new.dni, '[^0-9]', '', 'g');
  end if;
  return new;
end;
$$;

revoke execute on function public.normalize_person_dni() from public, anon, authenticated;
drop trigger if exists people_normalize_dni on public.people;
create trigger people_normalize_dni
  before insert or update of dni on public.people
  for each row execute function public.normalize_person_dni();

create unique index if not exists people_dni_digits_unique_idx
  on public.people (regexp_replace(dni, '[^0-9]', '', 'g'))
  where dni is not null;

-- Email is not a person key: shared family addresses are common. Reuse it only
-- when the match is unique; ambiguous matches require an explicit identity fix.
create or replace function public.link_provisioned_identity(
  p_profile_id uuid,
  p_email text,
  p_full_name text,
  p_role public.app_role
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  profile_row public.profiles%rowtype;
  person_id uuid;
  student_id uuid;
  teacher_id uuid;
  person_created boolean := false;
  student_created boolean := false;
  teacher_created boolean := false;
  normalized_email text;
  normalized_name text;
  first_name_value text;
  last_name_value text;
  matching_person_count integer;
begin
  if not public.is_active_superadmin() then
    raise exception 'Active superadmin role required' using errcode = 'insufficient_privilege';
  end if;

  normalized_email := lower(btrim(coalesce(p_email, '')));
  normalized_name := regexp_replace(btrim(coalesce(p_full_name, '')), '\s+', ' ', 'g');

  if p_profile_id is null
     or normalized_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
     or length(normalized_email) > 320
     or length(normalized_name) < 2
     or length(normalized_name) > 160
     or normalized_name ~ '[[:cntrl:]]'
     or array_length(regexp_split_to_array(normalized_name, '\s+'), 1) < 2 then
    raise exception 'Identity data is invalid' using errcode = 'invalid_parameter_value';
  end if;

  select * into profile_row
  from public.profiles
  where id = p_profile_id
  for update;

  if not found then
    raise exception 'Profile not found' using errcode = 'no_data_found';
  end if;
  if not profile_row.is_active then
    raise exception 'Profile is inactive' using errcode = 'insufficient_privilege';
  end if;

  select person.id into person_id
  from public.people person
  where person.profile_id = p_profile_id
  for update;

  if person_id is null then
    select count(*) into matching_person_count
    from public.people person
    where lower(btrim(person.email)) = normalized_email;

    if matching_person_count > 1 then
      raise exception 'Multiple people match this email; resolve the identity before provisioning'
        using errcode = 'unique_violation';
    end if;

    if matching_person_count = 1 then
      select person.id into person_id
      from public.people person
      where lower(btrim(person.email)) = normalized_email
      for update;
    end if;
  end if;

  first_name_value := split_part(normalized_name, ' ', 1);
  last_name_value := nullif(btrim(substr(normalized_name, length(first_name_value) + 1)), '');

  if person_id is null then
    insert into public.people (profile_id, first_name, last_name, email)
    values (p_profile_id, first_name_value, coalesce(last_name_value, first_name_value), normalized_email)
    returning id into person_id;
    person_created := true;
  else
    if exists (
      select 1 from public.people person
      where person.id = person_id
        and person.profile_id is not null
        and person.profile_id <> p_profile_id
    ) then
      raise exception 'Person is already linked to another profile' using errcode = 'unique_violation';
    end if;

    update public.people
    set profile_id = p_profile_id,
        first_name = first_name_value,
        last_name = coalesce(last_name_value, first_name_value),
        email = normalized_email,
        is_active = true,
        updated_at = now()
    where id = person_id;
  end if;

  update public.profiles
  set email = normalized_email,
      full_name = normalized_name,
      role = p_role,
      updated_at = now()
  where id = p_profile_id;

  if p_role::text = 'student' then
    select student.id into student_id
    from public.students student
    where student.person_id = person_id
    for update;

    if student_id is null then
      insert into public.students (person_id) values (person_id) returning id into student_id;
      student_created := true;
    else
      update public.students set is_active = true, updated_at = now() where id = student_id;
    end if;
  elsif p_role::text = 'teacher' then
    select teacher.id into teacher_id
    from public.teachers teacher
    where teacher.person_id = person_id
    for update;

    if teacher_id is null then
      insert into public.teachers (person_id) values (person_id) returning id into teacher_id;
      teacher_created := true;
    else
      update public.teachers set is_active = true, updated_at = now() where id = teacher_id;
    end if;
  end if;

  return jsonb_build_object(
    'profile_id', p_profile_id,
    'person_id', person_id,
    'person_created', person_created,
    'student_id', student_id,
    'student_created', student_created,
    'teacher_id', teacher_id,
    'teacher_created', teacher_created,
    'role', p_role::text
  );
end;
$$;

-- Admission approval records the responsible by exact DNI. Email is contact
-- data only and is never used to choose or merge an identity.
create or replace function public.link_approved_enrollment_guardian_for_request(
  p_request public.enrollment_requests
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  request_row public.enrollment_requests%rowtype;
  guardian_person_id uuid;
  first_name_value text;
  last_name_value text;
  primary_value boolean;
  relationship_value text;
begin
  request_row := p_request;

  if request_row.status <> 'approved' or request_row.student_id is null then
    return;
  end if;

  perform 1
  from public.students student
  where student.id = request_row.student_id
    and student.is_active = true
  for update;

  if not found then
    raise exception 'Approved enrollment requires an active student'
      using errcode = 'check_violation';
  end if;

  select person.id into guardian_person_id
  from public.people person
  where regexp_replace(coalesce(person.dni, ''), '[^0-9]', '', 'g') = request_row.responsible_dni
  for update;

  if guardian_person_id is null then
    first_name_value := split_part(regexp_replace(btrim(request_row.responsible_full_name), '\s+', ' ', 'g'), ' ', 1);
    last_name_value := nullif(btrim(substr(regexp_replace(btrim(request_row.responsible_full_name), '\s+', ' ', 'g'), length(first_name_value) + 1)), '');

    insert into public.people (first_name, last_name, email, phone, dni)
    values (
      first_name_value,
      coalesce(last_name_value, first_name_value),
      request_row.email,
      request_row.phone,
      request_row.responsible_dni
    )
    on conflict do nothing
    returning id into guardian_person_id;

    if guardian_person_id is null then
      select person.id into guardian_person_id
      from public.people person
      where regexp_replace(coalesce(person.dni, ''), '[^0-9]', '', 'g') = request_row.responsible_dni
      for update;
    end if;
  end if;

  if guardian_person_id is null then
    raise exception 'Responsible identity could not be linked by DNI'
      using errcode = 'unique_violation';
  end if;

  relationship_value := lower(regexp_replace(btrim(request_row.responsible_relation), '\s+', ' ', 'g'));
  select not exists (
    select 1
    from public.student_guardians relationship
    where relationship.student_id = request_row.student_id
      and relationship.is_active = true
      and relationship.is_primary = true
  ) into primary_value;

  insert into public.student_guardians (
    student_id,
    guardian_person_id,
    relationship_type,
    is_primary,
    is_active
  )
  values (
    request_row.student_id,
    guardian_person_id,
    relationship_value,
    primary_value,
    true
  )
  on conflict (student_id, guardian_person_id, lower(btrim(relationship_type)))
  do update set
    is_active = true,
    is_primary = (student_guardians.is_primary or excluded.is_primary)
      and not exists (
        select 1
        from public.student_guardians other_relationship
        where other_relationship.student_id = excluded.student_id
          and other_relationship.is_active = true
          and other_relationship.is_primary = true
          and other_relationship.id <> student_guardians.id
      ),
    updated_at = now();

  return;
end;
$$;

create or replace function public.link_approved_enrollment_guardian()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  perform public.link_approved_enrollment_guardian_for_request(new);

  return new;
end;
$$;

revoke execute on function public.link_approved_enrollment_guardian_for_request(public.enrollment_requests) from public, anon, authenticated;
revoke execute on function public.link_approved_enrollment_guardian() from public, anon, authenticated;

drop trigger if exists enrollment_requests_link_guardian_after_approval on public.enrollment_requests;
create trigger enrollment_requests_link_guardian_after_approval
  after update of status, student_id on public.enrollment_requests
  for each row
  when (new.status = 'approved')
  execute function public.link_approved_enrollment_guardian();

-- Backfill approved requests without rewriting the request row or firing its
-- update/audit triggers.
do $$
declare
  request_row public.enrollment_requests%rowtype;
begin
  for request_row in
    select request.*
    from public.enrollment_requests request
    where request.status = 'approved'
      and request.student_id is not null
      and exists (
        select 1
        from public.students student
        where student.id = request.student_id
          and student.is_active = true
      )
      and not exists (
        select 1
        from public.student_guardians relationship
        join public.people person on person.id = relationship.guardian_person_id
        where relationship.student_id = request.student_id
          and regexp_replace(coalesce(person.dni, ''), '[^0-9]', '', 'g') = request.responsible_dni
          and lower(btrim(relationship.relationship_type)) = lower(btrim(request.responsible_relation))
      )
  loop
    perform public.link_approved_enrollment_guardian_for_request(request_row);
  end loop;
end;
$$;
