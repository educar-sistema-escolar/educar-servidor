-- Work unit A: subject enrollment, academic history, and base schedules.

create table public.student_subject_enrollments (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students (id) on delete restrict,
  course_subject_id uuid not null references public.course_subjects (id) on delete restrict,
  academic_year integer not null check (academic_year > 0),
  is_active boolean not null default true,
  enrolled_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index student_subject_enrollments_active_unique_idx
  on public.student_subject_enrollments (student_id, course_subject_id, academic_year)
  where is_active = true;

create index student_subject_enrollments_student_idx
  on public.student_subject_enrollments (student_id, academic_year, is_active);

create index student_subject_enrollments_subject_idx
  on public.student_subject_enrollments (course_subject_id, academic_year, is_active);

create table public.academic_history (
  id uuid primary key default gen_random_uuid(),
  student_subject_enrollment_id uuid not null references public.student_subject_enrollments (id) on delete restrict,
  term smallint not null check (term between 1 and 4),
  grade numeric(5,2) not null check (grade between 0 and 10),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (student_subject_enrollment_id, term)
);

create index academic_history_enrollment_idx
  on public.academic_history (student_subject_enrollment_id, term);

create table public.academic_schedules (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses (id) on delete restrict,
  course_subject_id uuid references public.course_subjects (id) on delete restrict,
  academic_year integer not null check (academic_year > 0),
  day_of_week smallint not null check (day_of_week between 0 and 6),
  starts_at time not null,
  ends_at time not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (starts_at < ends_at)
);

create index academic_schedules_course_day_idx
  on public.academic_schedules (course_id, academic_year, day_of_week, starts_at)
  where is_active = true;

create or replace function public.validate_student_subject_enrollment()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  enrollment public.student_enrollments%rowtype;
  assignment public.course_subjects%rowtype;
  student_active boolean;
begin
  select * into assignment
  from public.course_subjects
  where id = new.course_subject_id
  for update;

  select is_active into student_active
  from public.students
  where id = new.student_id;

  select * into enrollment
  from public.student_enrollments
  where student_id = new.student_id
    and course_id = assignment.course_id
    and academic_year = new.academic_year
    and is_active = true
  for update;

  if new.is_active and (
    not found
    or not coalesce(student_active, false)
    or not assignment.is_active
    or assignment.academic_year <> new.academic_year
  ) then
    raise exception 'Active subject enrollment requires an active student, subject assignment, and matching course enrollment'
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

create trigger student_subject_enrollments_validate
  before insert or update on public.student_subject_enrollments
  for each row execute function public.validate_student_subject_enrollment();

create or replace function public.validate_academic_schedule()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  course_active boolean;
  course_year integer;
  subject_course_id uuid;
  subject_year integer;
  subject_active boolean;
begin
  -- ponytail: one global lock keeps overlap checks correct; use per-course/day locks if throughput matters.
  perform pg_advisory_xact_lock(814223);

  select is_active, academic_year into course_active, course_year
  from public.courses
  where id = new.course_id;

  if new.course_subject_id is not null then
    select course_id, academic_year, is_active
      into subject_course_id, subject_year, subject_active
    from public.course_subjects
    where id = new.course_subject_id;
  end if;

  if new.is_active and (
    not coalesce(course_active, false)
    or course_year <> new.academic_year
    or new.course_subject_id is not null and (
      subject_course_id <> new.course_id
      or subject_year <> new.academic_year
      or not coalesce(subject_active, false)
    )
  ) then
    raise exception 'Active schedule requires active course and matching academic year references'
      using errcode = 'check_violation';
  end if;

  if new.is_active and exists (
    select 1
    from public.academic_schedules existing
    where existing.id <> new.id
      and existing.is_active = true
      and existing.course_id = new.course_id
      and existing.academic_year = new.academic_year
      and existing.day_of_week = new.day_of_week
      and existing.starts_at < new.ends_at
      and new.starts_at < existing.ends_at
  ) then
    raise exception 'Active schedule overlaps an existing course schedule'
      using errcode = 'exclusion_violation';
  end if;

  return new;
end;
$$;

create trigger academic_schedules_validate
  before insert or update on public.academic_schedules
  for each row execute function public.validate_academic_schedule();

create or replace function public.prevent_last_academic_reference_deactivation()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if old.is_active and not new.is_active
     and tg_table_name = 'course_subjects'
     and exists (
       select 1
       from public.student_subject_enrollments
       where course_subject_id = old.id
         and is_active = true
     ) then
    raise exception 'Cannot deactivate a course subject with active student subject enrollments'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger course_subjects_prevent_active_reference_deactivation
  before update on public.course_subjects
  for each row execute function public.prevent_last_academic_reference_deactivation();

create or replace function public.enroll_student_in_subject(
  p_student_id uuid,
  p_course_subject_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  assignment public.course_subjects%rowtype;
  enrollment public.student_subject_enrollments%rowtype;
begin
  if not public.is_active_superadmin() then
    raise exception 'Active superadmin role required' using errcode = 'insufficient_privilege';
  end if;

  select * into assignment
  from public.course_subjects
  where id = p_course_subject_id;

  if not found or not assignment.is_active then
    raise exception 'Active course subject required' using errcode = 'check_violation';
  end if;

  insert into public.student_subject_enrollments (student_id, course_subject_id, academic_year)
  values (p_student_id, p_course_subject_id, assignment.academic_year)
  returning * into enrollment;

  return to_jsonb(enrollment);
end;
$$;

create or replace function public.record_academic_history(
  p_student_subject_enrollment_id uuid,
  p_term smallint,
  p_grade numeric,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  history_row public.academic_history%rowtype;
begin
  if not public.is_active_superadmin() then
    raise exception 'Active superadmin role required' using errcode = 'insufficient_privilege';
  end if;

  if not exists (
    select 1
    from public.student_subject_enrollments
    where id = p_student_subject_enrollment_id
      and is_active = true
  ) then
    raise exception 'Active student subject enrollment required' using errcode = 'check_violation';
  end if;

  insert into public.academic_history (student_subject_enrollment_id, term, grade, notes)
  values (p_student_subject_enrollment_id, p_term, p_grade, nullif(btrim(p_notes), ''))
  returning * into history_row;

  return to_jsonb(history_row);
end;
$$;

create trigger student_subject_enrollments_set_updated_at
  before update on public.student_subject_enrollments
  for each row execute function public.set_updated_at();

create trigger academic_history_set_updated_at
  before update on public.academic_history
  for each row execute function public.set_updated_at();

create trigger academic_schedules_set_updated_at
  before update on public.academic_schedules
  for each row execute function public.set_updated_at();

create trigger student_subject_enrollments_audit_log
  after insert or update or delete on public.student_subject_enrollments
  for each row execute function public.write_audit_log();

create trigger academic_history_audit_log
  after insert or update or delete on public.academic_history
  for each row execute function public.write_audit_log();

create trigger academic_schedules_audit_log
  after insert or update or delete on public.academic_schedules
  for each row execute function public.write_audit_log();

alter table public.student_subject_enrollments enable row level security;
alter table public.academic_history enable row level security;
alter table public.academic_schedules enable row level security;

create policy "Students guardians and teachers can read subject enrollments"
  on public.student_subject_enrollments for select to authenticated
  using (
    (select public.is_active_user())
    and (
      (select public.is_active_superadmin())
      or exists (
        select 1 from public.students student
        join public.people person on person.id = student.person_id
        where student.id = student_subject_enrollments.student_id
          and person.profile_id = (select auth.uid())
      )
      or public.is_guardian_of_student(student_subject_enrollments.student_id)
      or public.is_teacher_of_student(student_subject_enrollments.student_id)
    )
  );

create policy "Students guardians and teachers can read academic history"
  on public.academic_history for select to authenticated
  using (
    (select public.is_active_user())
    and (
      (select public.is_active_superadmin())
      or exists (
        select 1
        from public.student_subject_enrollments enrollment
        where enrollment.id = academic_history.student_subject_enrollment_id
          and (
            exists (
              select 1 from public.students student
              join public.people person on person.id = student.person_id
              where student.id = enrollment.student_id
                and person.profile_id = (select auth.uid())
            )
            or public.is_guardian_of_student(enrollment.student_id)
            or public.is_teacher_of_student(enrollment.student_id)
          )
      )
    )
  );

create policy "Students guardians and teachers can read schedules"
  on public.academic_schedules for select to authenticated
  using (
    (select public.is_active_user())
    and (
      (select public.is_active_superadmin())
      or exists (
        select 1
        from public.student_enrollments enrollment
        where enrollment.course_id = academic_schedules.course_id
          and enrollment.academic_year = academic_schedules.academic_year
          and enrollment.is_active = true
          and (
            exists (
              select 1 from public.students student
              join public.people person on person.id = student.person_id
              where student.id = enrollment.student_id
                and person.profile_id = (select auth.uid())
            )
            or public.is_guardian_of_student(enrollment.student_id)
            or public.is_teacher_of_student(enrollment.student_id)
          )
      )
    )
  );

create policy "Active superadmins manage subject enrollments"
  on public.student_subject_enrollments for all to authenticated
  using ((select public.is_active_superadmin()))
  with check ((select public.is_active_superadmin()));

create policy "Active superadmins manage academic history"
  on public.academic_history for all to authenticated
  using ((select public.is_active_superadmin()))
  with check ((select public.is_active_superadmin()));

create policy "Active superadmins manage schedules"
  on public.academic_schedules for all to authenticated
  using ((select public.is_active_superadmin()))
  with check ((select public.is_active_superadmin()));

grant select, insert, update, delete on
  public.student_subject_enrollments,
  public.academic_history,
  public.academic_schedules
to authenticated;

grant execute on function public.enroll_student_in_subject(uuid, uuid) to authenticated;
grant execute on function public.record_academic_history(uuid, smallint, numeric, text) to authenticated;

revoke execute on function public.enroll_student_in_subject(uuid, uuid) from public;
revoke execute on function public.record_academic_history(uuid, smallint, numeric, text) from public;
