-- Stage 1 administrative schema.
-- Existing profile creation and role semantics remain unchanged.

alter table public.profiles
  add column is_active boolean not null default true,
  add column updated_at timestamptz not null default now();

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function public.is_active_user()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles
    where id = auth.uid()
      and is_active = true
  );
$$;

create or replace function public.is_active_authority()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles
    where id = auth.uid()
      and role = 'authority'
      and is_active = true
  );
$$;

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

create policy "Active authorities can update profiles"
  on public.profiles
  for update
  to authenticated
  using ((select public.is_active_authority()))
  with check ((select public.is_active_authority()));

create table public.people (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid unique references public.profiles (id) on delete set null,
  first_name text not null check (btrim(first_name) <> ''),
  last_name text not null check (btrim(last_name) <> ''),
  email text,
  phone text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.students (
  id uuid primary key default gen_random_uuid(),
  person_id uuid not null unique references public.people (id) on delete restrict,
  student_number text unique,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.teachers (
  id uuid primary key default gen_random_uuid(),
  person_id uuid not null unique references public.people (id) on delete restrict,
  teacher_number text unique,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.educational_levels (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (btrim(code) <> ''),
  name text not null check (btrim(name) <> ''),
  sort_order integer not null default 0 check (sort_order >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.courses (
  id uuid primary key default gen_random_uuid(),
  educational_level_id uuid not null references public.educational_levels (id) on delete restrict,
  code text not null check (btrim(code) <> ''),
  name text not null check (btrim(name) <> ''),
  academic_year integer not null check (academic_year > 0),
  year_number integer check (year_number is null or year_number > 0),
  division text,
  shift text check (shift is null or shift in ('morning', 'afternoon', 'full_day')),
  capacity integer check (capacity is null or capacity > 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (educational_level_id, code, academic_year)
);

create table public.subjects (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (btrim(code) <> ''),
  name text not null check (btrim(name) <> ''),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.student_enrollments (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students (id) on delete restrict,
  course_id uuid not null,
  academic_year integer not null check (academic_year > 0),
  is_active boolean not null default true,
  enrolled_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (course_id) references public.courses (id) on delete restrict
);

create table public.course_subjects (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses (id) on delete restrict,
  subject_id uuid not null references public.subjects (id) on delete restrict,
  teacher_id uuid references public.teachers (id) on delete restrict,
  academic_year integer not null check (academic_year > 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_profile_id uuid references public.profiles (id) on delete set null,
  action text not null check (action in ('INSERT', 'UPDATE', 'DELETE')),
  entity_type text not null check (btrim(entity_type) <> ''),
  entity_id uuid not null,
  old_data jsonb,
  new_data jsonb,
  created_at timestamptz not null default now()
);

create unique index student_enrollments_one_active_course_per_year
  on public.student_enrollments (student_id, academic_year)
  where is_active = true;

create unique index course_subjects_one_active_link
  on public.course_subjects (course_id, subject_id, academic_year)
  where is_active = true;

create index profiles_active_role_idx
  on public.profiles (is_active, role);

create index courses_year_active_idx
  on public.courses (academic_year, is_active);

create index student_enrollments_course_idx
  on public.student_enrollments (course_id);

create index course_subjects_subject_idx
  on public.course_subjects (subject_id);

create index course_subjects_teacher_idx
  on public.course_subjects (teacher_id);

create index audit_logs_actor_created_idx
  on public.audit_logs (actor_profile_id, created_at desc);

create index audit_logs_entity_created_idx
  on public.audit_logs (entity_type, entity_id, created_at desc);

create trigger people_set_updated_at
  before update on public.people
  for each row execute function public.set_updated_at();

create trigger students_set_updated_at
  before update on public.students
  for each row execute function public.set_updated_at();

create trigger teachers_set_updated_at
  before update on public.teachers
  for each row execute function public.set_updated_at();

create trigger educational_levels_set_updated_at
  before update on public.educational_levels
  for each row execute function public.set_updated_at();

create trigger courses_set_updated_at
  before update on public.courses
  for each row execute function public.set_updated_at();

create trigger subjects_set_updated_at
  before update on public.subjects
  for each row execute function public.set_updated_at();

create trigger student_enrollments_set_updated_at
  before update on public.student_enrollments
  for each row execute function public.set_updated_at();

create trigger course_subjects_set_updated_at
  before update on public.course_subjects
  for each row execute function public.set_updated_at();

create or replace function public.write_audit_log()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  changed_id uuid;
begin
  if tg_op = 'DELETE' then
    changed_id := old.id;
    insert into public.audit_logs (
      actor_profile_id, action, entity_type, entity_id, old_data
    )
    values (
      auth.uid(), tg_op, tg_table_name, changed_id, to_jsonb(old)
    );
    return old;
  end if;

  changed_id := new.id;

  if tg_op = 'INSERT' then
    insert into public.audit_logs (
      actor_profile_id, action, entity_type, entity_id, new_data
    )
    values (
      auth.uid(), tg_op, tg_table_name, changed_id, to_jsonb(new)
    );
  else
    insert into public.audit_logs (
      actor_profile_id, action, entity_type, entity_id, old_data, new_data
    )
    values (
      auth.uid(), tg_op, tg_table_name, changed_id, to_jsonb(old), to_jsonb(new)
    );
  end if;

  return new;
end;
$$;

create trigger profiles_audit_log
  after update on public.profiles
  for each row execute function public.write_audit_log();

create trigger people_audit_log
  after insert or update or delete on public.people
  for each row execute function public.write_audit_log();

create trigger students_audit_log
  after insert or update or delete on public.students
  for each row execute function public.write_audit_log();

create trigger teachers_audit_log
  after insert or update or delete on public.teachers
  for each row execute function public.write_audit_log();

create trigger educational_levels_audit_log
  after insert or update or delete on public.educational_levels
  for each row execute function public.write_audit_log();

create trigger courses_audit_log
  after insert or update or delete on public.courses
  for each row execute function public.write_audit_log();

create trigger subjects_audit_log
  after insert or update or delete on public.subjects
  for each row execute function public.write_audit_log();

create trigger student_enrollments_audit_log
  after insert or update or delete on public.student_enrollments
  for each row execute function public.write_audit_log();

create trigger course_subjects_audit_log
  after insert or update or delete on public.course_subjects
  for each row execute function public.write_audit_log();

alter table public.people enable row level security;
alter table public.students enable row level security;
alter table public.teachers enable row level security;
alter table public.educational_levels enable row level security;
alter table public.courses enable row level security;
alter table public.subjects enable row level security;
alter table public.student_enrollments enable row level security;
alter table public.course_subjects enable row level security;
alter table public.audit_logs enable row level security;

create policy "Active users can read their own people record"
  on public.people
  for select
  to authenticated
  using (
    (select public.is_active_user())
    and (
      profile_id = (select auth.uid())
      or (select public.is_active_authority())
    )
  );

create policy "Active authorities can manage people"
  on public.people
  for all
  to authenticated
  using ((select public.is_active_authority()))
  with check ((select public.is_active_authority()));

create policy "Active users can read their own student record"
  on public.students
  for select
  to authenticated
  using (
    (select public.is_active_user())
    and (
      exists (
        select 1
        from public.people
        where people.id = students.person_id
          and people.profile_id = (select auth.uid())
      )
      or (select public.is_active_authority())
    )
  );

create policy "Active authorities can manage students"
  on public.students
  for all
  to authenticated
  using ((select public.is_active_authority()))
  with check ((select public.is_active_authority()));

create policy "Active users can read their own teacher record"
  on public.teachers
  for select
  to authenticated
  using (
    (select public.is_active_user())
    and (
      exists (
        select 1
        from public.people
        where people.id = teachers.person_id
          and people.profile_id = (select auth.uid())
      )
      or (select public.is_active_authority())
    )
  );

create policy "Active authorities can manage teachers"
  on public.teachers
  for all
  to authenticated
  using ((select public.is_active_authority()))
  with check ((select public.is_active_authority()));

create policy "Active users can read educational levels"
  on public.educational_levels
  for select
  to authenticated
  using (
    (select public.is_active_user())
    and (is_active or (select public.is_active_authority()))
  );

create policy "Active authorities can manage educational levels"
  on public.educational_levels
  for all
  to authenticated
  using ((select public.is_active_authority()))
  with check ((select public.is_active_authority()));

create policy "Active users can read courses"
  on public.courses
  for select
  to authenticated
  using (
    (select public.is_active_user())
    and (is_active or (select public.is_active_authority()))
  );

create policy "Active authorities can manage courses"
  on public.courses
  for all
  to authenticated
  using ((select public.is_active_authority()))
  with check ((select public.is_active_authority()));

create policy "Active users can read subjects"
  on public.subjects
  for select
  to authenticated
  using (
    (select public.is_active_user())
    and (is_active or (select public.is_active_authority()))
  );

create policy "Active authorities can manage subjects"
  on public.subjects
  for all
  to authenticated
  using ((select public.is_active_authority()))
  with check ((select public.is_active_authority()));

create policy "Active users can read their enrollments"
  on public.student_enrollments
  for select
  to authenticated
  using (
    (select public.is_active_user())
    and (
      (select public.is_active_authority())
      or exists (
        select 1
        from public.students
        join public.people on people.id = students.person_id
        where students.id = student_enrollments.student_id
          and people.profile_id = (select auth.uid())
      )
    )
  );

create policy "Active authorities can manage enrollments"
  on public.student_enrollments
  for all
  to authenticated
  using ((select public.is_active_authority()))
  with check ((select public.is_active_authority()));

create policy "Active users can read course subjects"
  on public.course_subjects
  for select
  to authenticated
  using (
    (select public.is_active_user())
    and (
      is_active
      or (select public.is_active_authority())
    )
  );

create policy "Active authorities can manage course subjects"
  on public.course_subjects
  for all
  to authenticated
  using ((select public.is_active_authority()))
  with check ((select public.is_active_authority()));

create policy "Active authorities can read audit logs"
  on public.audit_logs
  for select
  to authenticated
  using ((select public.is_active_authority()));

grant select, update on public.profiles to authenticated;
grant select, insert, update on
  public.people,
  public.students,
  public.teachers,
  public.educational_levels,
  public.courses,
  public.subjects,
  public.student_enrollments,
  public.course_subjects
to authenticated;
grant select on public.audit_logs to authenticated;

revoke delete on
  public.people,
  public.students,
  public.teachers,
  public.educational_levels,
  public.courses,
  public.subjects,
  public.student_enrollments,
  public.course_subjects
from authenticated;
