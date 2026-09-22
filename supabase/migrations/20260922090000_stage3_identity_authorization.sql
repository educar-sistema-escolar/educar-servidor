-- Stage 3: identity links, relationship-aware authorization, and invitations.

alter type public.app_role add value if not exists 'guardian';

alter table public.profiles
  add column if not exists account_status text not null default 'active',
  add column if not exists invited_at timestamptz,
  add column if not exists activated_at timestamptz;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'profiles_account_status_check'
      and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles
      add constraint profiles_account_status_check
      check (account_status in ('invited', 'active', 'inactive'));
  end if;
end $$;

create or replace function public.mark_profile_active_after_confirmation()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if new.email_confirmed_at is not null then
    update public.profiles
    set account_status = case when is_active then 'active' else 'inactive' end,
        activated_at = case when is_active then coalesce(activated_at, now()) else null end,
        updated_at = now()
    where id = new.id
      and account_status = 'invited';
  end if;
  return new;
end;
$$;

drop trigger if exists auth_user_confirmation_updates_profile on auth.users;
create trigger auth_user_confirmation_updates_profile
  after update of email_confirmed_at on auth.users
  for each row execute function public.mark_profile_active_after_confirmation();

create table if not exists public.permissions (
  code text primary key check (btrim(code) <> ''),
  description text not null check (btrim(description) <> ''),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.role_permissions (
  role_code text not null check (role_code in ('superadmin', 'admin', 'teacher', 'student', 'guardian', 'parent')),
  permission_code text not null references public.permissions (code) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (role_code, permission_code)
);

insert into public.permissions (code, description)
values
  ('identity:read:self', 'Read the authenticated identity and linked person record'),
  ('identity:manage', 'Create and manage institutional identities'),
  ('student:read:self', 'Read the authenticated student record'),
  ('student:read:children', 'Read students linked to the authenticated guardian'),
  ('student:read:assigned', 'Read students in actively assigned courses or subjects'),
  ('guardian:link:manage', 'Create and maintain student-guardian relationships'),
  ('permissions:manage', 'Manage permission catalog and role mappings')
on conflict (code) do update
  set description = excluded.description,
      is_active = true;

insert into public.role_permissions (role_code, permission_code)
select seed.role_code, seed.permission_code
from (values
  ('superadmin', 'identity:read:self'),
  ('superadmin', 'identity:manage'),
  ('superadmin', 'student:read:self'),
  ('superadmin', 'student:read:children'),
  ('superadmin', 'student:read:assigned'),
  ('superadmin', 'guardian:link:manage'),
  ('superadmin', 'permissions:manage'),
  ('admin', 'identity:read:self'),
  ('admin', 'identity:manage'),
  ('admin', 'student:read:children'),
  ('admin', 'student:read:assigned'),
  ('teacher', 'identity:read:self'),
  ('teacher', 'student:read:assigned'),
  ('student', 'identity:read:self'),
  ('student', 'student:read:self'),
  ('guardian', 'identity:read:self'),
  ('guardian', 'student:read:children'),
  ('parent', 'identity:read:self'),
  ('parent', 'student:read:children')
) as seed(role_code, permission_code)
on conflict (role_code, permission_code) do nothing;

create table if not exists public.student_guardians (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students (id) on delete cascade,
  guardian_person_id uuid not null references public.people (id) on delete cascade,
  relationship_type text not null check (btrim(relationship_type) <> ''),
  is_primary boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (student_id, guardian_person_id, relationship_type)
);

create unique index if not exists student_guardians_one_primary_idx
  on public.student_guardians (student_id)
  where is_active = true and is_primary = true;

create unique index if not exists student_guardians_relationship_unique_idx
  on public.student_guardians (student_id, guardian_person_id, lower(btrim(relationship_type)));

create index if not exists student_guardians_guardian_idx
  on public.student_guardians (guardian_person_id, is_active);

create index if not exists student_guardians_student_idx
  on public.student_guardians (student_id, is_active);

drop trigger if exists student_guardians_set_updated_at on public.student_guardians;
create trigger student_guardians_set_updated_at
  before update on public.student_guardians
  for each row execute function public.set_updated_at();

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
    where profile.id = auth.uid()
      and profile.is_active = true
      and permission.code = $1
      and permission.is_active = true
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
    where profile.id = auth.uid()
      and profile.is_active = true
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
    where profile.id = auth.uid()
      and profile.is_active = true
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

  update public.profiles
  set email = normalized_email,
      full_name = normalized_name,
      role = p_role,
      updated_at = now()
  where id = p_profile_id;

  select id into person_id
  from public.people
  where profile_id = p_profile_id
  for update;

  if person_id is null then
    select id into person_id
    from public.people
    where lower(btrim(email)) = normalized_email
    order by created_at
    limit 1
    for update;
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
      select 1 from public.people
      where id = person_id
        and profile_id is not null
        and profile_id <> p_profile_id
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

  if p_role::text = 'student' then
    select student.id into student_id
    from public.students student
    where student.person_id = person_id
    for update;

    if student_id is null then
      insert into public.students (person_id)
      values (person_id)
      returning id into student_id;
      student_created := true;
    else
      update public.students
      set is_active = true,
          updated_at = now()
      where id = student_id;
    end if;
  elsif p_role::text = 'teacher' then
    select teacher.id into teacher_id
    from public.teachers teacher
    where teacher.person_id = person_id
    for update;

    if teacher_id is null then
      insert into public.teachers (person_id)
      values (person_id)
      returning id into teacher_id;
      teacher_created := true;
    else
      update public.teachers
      set is_active = true,
          updated_at = now()
      where id = teacher_id;
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

create or replace function public.link_student_guardian(
  p_student_id uuid,
  p_guardian_profile_id uuid,
  p_relationship_type text,
  p_is_primary boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  guardian_person_id uuid;
  relationship_id uuid;
  relationship_value text;
begin
  if not public.is_active_superadmin() then
    raise exception 'Active superadmin role required' using errcode = 'insufficient_privilege';
  end if;

  relationship_value := lower(regexp_replace(btrim(coalesce(p_relationship_type, '')), '\s+', ' ', 'g'));

  if p_student_id is null or p_guardian_profile_id is null or length(relationship_value) < 2 or length(relationship_value) > 80 then
    raise exception 'Guardian relationship data is invalid' using errcode = 'invalid_parameter_value';
  end if;

  if not exists (
    select 1 from public.students
    where id = p_student_id and is_active = true
  ) then
    raise exception 'Active student required' using errcode = 'no_data_found';
  end if;

  select person.id into guardian_person_id
  from public.profiles profile
  join public.people person on person.profile_id = profile.id
  where profile.id = p_guardian_profile_id
    and profile.is_active = true
    and profile.role::text in ('guardian', 'parent')
    and person.is_active = true
  for update;

  if guardian_person_id is null then
    raise exception 'Active guardian profile required' using errcode = 'invalid_parameter_value';
  end if;

  if p_is_primary then
    update public.student_guardians
    set is_primary = false,
        updated_at = now()
    where student_id = p_student_id
      and is_primary = true;
  end if;

  insert into public.student_guardians (
    student_id,
    guardian_person_id,
    relationship_type,
    is_primary,
    is_active
  )
  values (
    p_student_id,
    guardian_person_id,
    relationship_value,
    p_is_primary,
    true
  )
  on conflict (student_id, guardian_person_id, relationship_type)
  do update set
    is_primary = excluded.is_primary,
    is_active = true,
    updated_at = now()
  returning id into relationship_id;

  return jsonb_build_object(
    'id', relationship_id,
    'student_id', p_student_id,
    'guardian_person_id', guardian_person_id,
    'relationship_type', relationship_value,
    'is_primary', p_is_primary
  );
end;
$$;

alter table public.permissions enable row level security;
alter table public.role_permissions enable row level security;
alter table public.student_guardians enable row level security;

drop policy if exists "Active users can read permissions" on public.permissions;
create policy "Active users can read permissions"
  on public.permissions for select to authenticated
  using ((select public.is_active_user()));

drop policy if exists "Active superadmins can manage permissions" on public.permissions;
create policy "Active superadmins can manage permissions"
  on public.permissions for all to authenticated
  using ((select public.is_active_superadmin()))
  with check ((select public.is_active_superadmin()));

drop policy if exists "Active users can read their role permissions" on public.role_permissions;
create policy "Active users can read their role permissions"
  on public.role_permissions for select to authenticated
  using (
    (select public.is_active_user())
    and (role_code = (select role::text from public.profiles where id = auth.uid()))
  );

drop policy if exists "Active superadmins can manage role permissions" on public.role_permissions;
create policy "Active superadmins can manage role permissions"
  on public.role_permissions for all to authenticated
  using ((select public.is_active_superadmin()))
  with check ((select public.is_active_superadmin()));

drop policy if exists "Users can read their own profile" on public.profiles;
create policy "Active users can read their own profile"
  on public.profiles for select to authenticated
  using ((select public.is_active_user()) and id = (select auth.uid()));

drop policy if exists "Active users can read linked student people" on public.people;
create policy "Active users can read linked student people"
  on public.people for select to authenticated
  using (
    (select public.is_active_user())
    and exists (
      select 1
      from public.students student
      where student.person_id = people.id
        and (
          public.is_guardian_of_student(student.id)
          or public.is_teacher_of_student(student.id)
        )
    )
  );

drop policy if exists "Active users can read linked students" on public.students;
create policy "Active users can read linked students"
  on public.students for select to authenticated
  using (
    (select public.is_active_user())
    and (
      public.is_guardian_of_student(students.id)
      or public.is_teacher_of_student(students.id)
    )
  );

drop policy if exists "Active users can read their enrollments" on public.student_enrollments;
create policy "Active users can read their enrollments"
  on public.student_enrollments for select to authenticated
  using (
    (select public.is_active_user())
    and (
      (select public.is_active_superadmin())
      or exists (
        select 1
        from public.students student
        join public.people person on person.id = student.person_id
        where student.id = student_enrollments.student_id
          and person.profile_id = (select auth.uid())
      )
      or public.is_guardian_of_student(student_enrollments.student_id)
      or public.is_teacher_of_student(student_enrollments.student_id)
    )
  );

drop policy if exists "Active users can read student guardian links" on public.student_guardians;
create policy "Active users can read student guardian links"
  on public.student_guardians for select to authenticated
  using (
    (select public.is_active_user())
    and (
      (select public.is_active_superadmin())
      or exists (
        select 1
        from public.students student
        join public.people student_person on student_person.id = student.person_id
        where student.id = student_guardians.student_id
          and student_person.profile_id = (select auth.uid())
      )
      or exists (
        select 1
        from public.people guardian_person
        join public.profiles guardian_profile on guardian_profile.id = guardian_person.profile_id
        where guardian_person.id = student_guardians.guardian_person_id
          and guardian_profile.id = (select auth.uid())
          and guardian_profile.is_active = true
          and guardian_profile.role::text in ('guardian', 'parent')
      )
    )
  );

drop policy if exists "Active superadmins can manage student guardian links" on public.student_guardians;
create policy "Active superadmins can manage student guardian links"
  on public.student_guardians for all to authenticated
  using ((select public.is_active_superadmin()))
  with check ((select public.is_active_superadmin()));

grant select, insert, update, delete on public.permissions, public.role_permissions to authenticated;
grant select on public.student_guardians to authenticated;
grant execute on function public.is_allowed(text) to authenticated;
grant execute on function public.is_guardian_of_student(uuid) to authenticated;
grant execute on function public.is_teacher_of_student(uuid) to authenticated;
grant execute on function public.link_provisioned_identity(uuid, text, text, public.app_role) to authenticated;
grant execute on function public.link_student_guardian(uuid, uuid, text, boolean) to authenticated;

revoke execute on function public.is_allowed(text) from public;
revoke execute on function public.is_guardian_of_student(uuid) from public;
revoke execute on function public.is_teacher_of_student(uuid) from public;
revoke execute on function public.link_provisioned_identity(uuid, text, text, public.app_role) from public;
revoke execute on function public.link_student_guardian(uuid, uuid, text, boolean) from public;
