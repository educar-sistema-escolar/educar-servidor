-- Provide only the sports catalogue fields families need for a linked student.
-- Teacher records remain protected by their own RLS policy.
create or replace function public.list_sport_request_options(
  p_student_id uuid,
  p_academic_year integer
)
returns table(
  id uuid,
  sport_id uuid,
  name text,
  educational_level_id uuid,
  academic_year integer,
  capacity integer,
  sport_name text,
  level_name text,
  teacher_first_name text,
  teacher_last_name text,
  schedules jsonb
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
begin
  if not public.is_active_user() then
    raise exception 'Active account required' using errcode = 'insufficient_privilege';
  end if;

  if p_academic_year is null or p_academic_year not between 1900 and 2200 then
    raise exception 'Valid academic year required' using errcode = 'check_violation';
  end if;

  if not public.is_active_superadmin()
     and not public.is_guardian_of_student(p_student_id)
     and not exists (
       select 1
       from public.students student
       join public.people person on person.id = student.person_id
       where student.id = p_student_id
         and student.is_active
         and person.is_active
         and person.profile_id = auth.uid()
     ) then
    raise exception 'Student relationship is not authorized' using errcode = 'insufficient_privilege';
  end if;

  return query
    select group_row.id,
      group_row.sport_id,
      group_row.name,
      group_row.educational_level_id,
      group_row.academic_year,
      group_row.capacity,
      sport.name,
      level.name,
      teacher.first_name,
      teacher.last_name,
      coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', schedule.id,
          'day_of_week', schedule.day_of_week,
          'starts_at', schedule.starts_at,
          'ends_at', schedule.ends_at,
          'is_active', schedule.is_active
        ) order by schedule.day_of_week, schedule.starts_at)
        from public.sport_group_schedules schedule
        where schedule.sport_group_id = group_row.id
          and schedule.is_active
      ), '[]'::jsonb)
    from public.sport_groups group_row
    join public.sports sport on sport.id = group_row.sport_id
    left join public.educational_levels level on level.id = group_row.educational_level_id
    left join public.teachers coach on coach.id = group_row.teacher_id
    left join public.people teacher on teacher.id = coach.person_id
    where group_row.is_active
      and group_row.academic_year = p_academic_year
    order by group_row.name;
end;
$$;

revoke all on function public.list_sport_request_options(uuid, integer) from public, anon;
grant execute on function public.list_sport_request_options(uuid, integer) to authenticated;

notify pgrst, 'reload schema';
