-- Repair the known DEMO 2027 overlaps, then reject future teacher overlaps
-- across academic classes and sports groups. No non-DEMO schedule is changed.

update public.academic_schedules schedule
set starts_at = time '09:00',
    ends_at = time '10:00'
from public.courses course
join public.course_subjects assignment on assignment.course_id = course.id
join public.teachers teacher on teacher.id = assignment.teacher_id
where schedule.course_id = course.id
  and schedule.course_subject_id = assignment.id
  and course.code = 'DEMO-27-PRI-A'
  and course.academic_year = 2027
  and teacher.teacher_number = 'DEMO-2027-D01'
  and schedule.academic_year = 2027
  and schedule.day_of_week = 1
  and schedule.starts_at = time '08:00'
  and schedule.ends_at = time '09:00';

with ranked_demo_schedules as (
  select
    schedule.id,
    row_number() over (
      partition by group_row.sport_id, group_row.teacher_id, group_row.academic_year, schedule.day_of_week
      order by level.sort_order, group_row.id
    ) as level_position
  from public.sport_group_schedules schedule
  join public.sport_groups group_row on group_row.id = schedule.sport_group_id
  join public.educational_levels level on level.id = group_row.educational_level_id
  where group_row.academic_year = 2027
    and group_row.is_active
    and schedule.is_active
    and group_row.name ~ '^DEMO (Fútbol|Básquet|Vóley|Natación) (Inicial|Primario|Secundario)$'
)
update public.sport_group_schedules schedule
set starts_at = make_time(15 + ranked.level_position::integer, 0, 0),
    ends_at = make_time(16 + ranked.level_position::integer, 0, 0)
from ranked_demo_schedules ranked
where schedule.id = ranked.id
  and ranked.level_position between 1 and 3;

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
  subject_teacher_id uuid;
begin
  perform pg_advisory_xact_lock(814223);

  select is_active, academic_year into course_active, course_year
  from public.courses
  where id = new.course_id;

  if new.course_subject_id is not null then
    select course_id, academic_year, is_active, teacher_id
      into subject_course_id, subject_year, subject_active, subject_teacher_id
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
      and existing.is_active
      and existing.course_id = new.course_id
      and existing.academic_year = new.academic_year
      and existing.day_of_week = new.day_of_week
      and existing.starts_at < new.ends_at
      and new.starts_at < existing.ends_at
  ) then
    raise exception 'Active schedule overlaps an existing course schedule'
      using errcode = 'exclusion_violation';
  end if;

  if new.is_active and subject_teacher_id is not null and exists (
    select 1
    from public.academic_schedules existing
    join public.course_subjects existing_assignment on existing_assignment.id = existing.course_subject_id
    where existing.id <> new.id
      and existing.is_active
      and existing.course_id <> new.course_id
      and existing.academic_year = new.academic_year
      and existing.day_of_week = new.day_of_week
      and existing_assignment.is_active
      and existing_assignment.teacher_id = subject_teacher_id
      and existing.starts_at < new.ends_at
      and new.starts_at < existing.ends_at
  ) then
    raise exception 'Teacher schedule overlaps another active course schedule'
      using errcode = 'exclusion_violation';
  end if;

  return new;
end;
$$;

create or replace function public.validate_course_subject_teacher_schedule()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  perform pg_advisory_xact_lock(814223);

  if new.is_active and new.teacher_id is not null and exists (
    select 1
    from public.academic_schedules own_schedule
    join public.academic_schedules existing
      on existing.academic_year = own_schedule.academic_year
     and existing.day_of_week = own_schedule.day_of_week
     and existing.starts_at < own_schedule.ends_at
     and own_schedule.starts_at < existing.ends_at
     and existing.is_active
    join public.course_subjects existing_assignment
      on existing_assignment.id = existing.course_subject_id
     and existing_assignment.is_active
     and existing_assignment.teacher_id = new.teacher_id
    where own_schedule.course_subject_id = new.id
      and own_schedule.is_active
      and existing.course_subject_id <> new.id
      and existing.course_id <> own_schedule.course_id
  ) then
    raise exception 'Teacher assignment creates an overlapping academic schedule'
      using errcode = 'exclusion_violation';
  end if;

  return new;
end;
$$;

drop trigger if exists course_subjects_teacher_schedule_validate on public.course_subjects;
create trigger course_subjects_teacher_schedule_validate
  before update of teacher_id, is_active, academic_year on public.course_subjects
  for each row execute function public.validate_course_subject_teacher_schedule();

create or replace function public.validate_sport_group_schedule()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  group_year integer;
  group_teacher_id uuid;
begin
  perform pg_advisory_xact_lock(814224);

  select academic_year, teacher_id
    into group_year, group_teacher_id
  from public.sport_groups
  where id = new.sport_group_id and is_active;

  if new.is_active and group_year is null then
    raise exception 'Active schedule requires an active sport group' using errcode = 'check_violation';
  end if;

  if new.is_active and exists (
    select 1
    from public.sport_group_schedules current_schedule
    where current_schedule.id <> new.id
      and current_schedule.sport_group_id = new.sport_group_id
      and current_schedule.is_active
      and current_schedule.day_of_week = new.day_of_week
      and current_schedule.starts_at < new.ends_at
      and new.starts_at < current_schedule.ends_at
  ) then
    raise exception 'Sport group schedule overlaps an existing schedule' using errcode = 'exclusion_violation';
  end if;

  if new.is_active and group_teacher_id is not null and exists (
    select 1
    from public.sport_group_schedules other_schedule
    join public.sport_groups other_group on other_group.id = other_schedule.sport_group_id
    where other_schedule.id <> new.id
      and other_group.id <> new.sport_group_id
      and other_group.is_active
      and other_group.teacher_id = group_teacher_id
      and other_group.academic_year = group_year
      and other_schedule.is_active
      and other_schedule.day_of_week = new.day_of_week
      and other_schedule.starts_at < new.ends_at
      and new.starts_at < other_schedule.ends_at
  ) then
    raise exception 'Teacher schedule overlaps another active sport group schedule'
      using errcode = 'exclusion_violation';
  end if;

  return new;
end;
$$;

create or replace function public.validate_sport_group_teacher_schedule_assignment()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  perform pg_advisory_xact_lock(814224);

  if new.is_active and new.teacher_id is not null and exists (
    select 1
    from public.sport_group_schedules own_schedule
    join public.sport_group_schedules other_schedule
      on other_schedule.day_of_week = own_schedule.day_of_week
     and other_schedule.starts_at < own_schedule.ends_at
     and own_schedule.starts_at < other_schedule.ends_at
     and other_schedule.is_active
    join public.sport_groups other_group
      on other_group.id = other_schedule.sport_group_id
     and other_group.id <> new.id
     and other_group.is_active
     and other_group.teacher_id = new.teacher_id
     and other_group.academic_year = new.academic_year
    where own_schedule.sport_group_id = new.id
      and own_schedule.is_active
  ) then
    raise exception 'Teacher assignment creates an overlapping sport schedule'
      using errcode = 'exclusion_violation';
  end if;

  return new;
end;
$$;

drop trigger if exists sport_groups_teacher_schedule_validate on public.sport_groups;
create trigger sport_groups_teacher_schedule_validate
  before update of teacher_id, academic_year, is_active on public.sport_groups
  for each row execute function public.validate_sport_group_teacher_schedule_assignment();
