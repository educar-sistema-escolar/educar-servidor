-- Completes the report families required by the administrative module.
-- Existing report codes remain backward compatible through the one-argument RPC.

insert into public.permissions (code, description)
values
  ('reports:read', 'Read administrative reports'),
  ('academic:manage', 'Manage academic administration'),
  ('services:manage', 'Manage sports, transport, and dining services'),
  ('accounts:manage', 'Manage institutional accounts and links')
on conflict (code) do update
set description = excluded.description, is_active = true;

insert into public.role_permissions (role_code, permission_code)
select 'superadmin', code from public.permissions
where code in ('reports:read', 'academic:manage', 'services:manage', 'accounts:manage')
on conflict (role_code, permission_code) do nothing;

-- Permission mappings are additive to the existing superadmin policies. This
-- lets a future admin role use the same data paths without weakening the
-- director's current superadmin access.
do $$
declare table_name text;
begin
  foreach table_name in array array['people','students','teachers','educational_levels','courses','subjects','student_enrollments','course_subjects','student_subject_enrollments','academic_history','academic_schedules'] loop
    execute format('drop policy if exists %I on public.%I', 'Configurable academic admins manage ' || table_name, table_name);
    execute format('create policy %I on public.%I for all to authenticated using ((select public.is_active_user()) and (select public.is_allowed(''academic:manage''))) with check ((select public.is_active_user()) and (select public.is_allowed(''academic:manage'')))', 'Configurable academic admins manage ' || table_name, table_name);
  end loop;

  foreach table_name in array array['sports','sport_groups','sport_group_schedules','student_sport_enrollments','transport_routes','transport_stops','student_transport_enrollments','dining_services','dining_slots','student_dining_enrollments','dining_usage'] loop
    execute format('drop policy if exists %I on public.%I', 'Configurable service admins manage ' || table_name, table_name);
    execute format('create policy %I on public.%I for all to authenticated using ((select public.is_active_user()) and (select public.is_allowed(''services:manage''))) with check ((select public.is_active_user()) and (select public.is_allowed(''services:manage'')))', 'Configurable service admins manage ' || table_name, table_name);
  end loop;
end $$;

drop policy if exists "Configurable account admins manage profiles" on public.profiles;
create policy "Configurable account admins manage profiles"
  on public.profiles for update to authenticated
  using ((select public.is_active_user()) and (select public.is_allowed('accounts:manage')))
  with check ((select public.is_active_user()) and (select public.is_allowed('accounts:manage')));

create or replace function public.get_admin_report(
  p_report_code text,
  p_filters jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  result jsonb;
  academic_year_filter integer := nullif(p_filters ->> 'academic_year', '')::integer;
  level_filter uuid := nullif(p_filters ->> 'level_id', '')::uuid;
  sport_filter uuid := nullif(p_filters ->> 'sport_id', '')::uuid;
  route_filter uuid := nullif(p_filters ->> 'route_id', '')::uuid;
begin
  if not public.is_active_superadmin() and not public.is_allowed('reports:read') then
    raise exception 'Administrative report permission required' using errcode = 'insufficient_privilege';
  end if;

  if p_report_code in ('student_overview', 'students_by_course', 'students_by_subject', 'teachers_by_level', 'students_by_sport', 'students_by_sport_schedule', 'students_by_transport') then
    return public.get_admin_report(p_report_code);
  elsif p_report_code = 'teachers_by_level_courses' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'educational_level', level.name,
      'teacher', concat_ws(' ', teacher_person.last_name, teacher_person.first_name),
      'course', course.name,
      'subject', subject.name,
      'academic_year', course_subject.academic_year
    ) order by level.sort_order, teacher_person.last_name, course.name, subject.name), '[]'::jsonb)
    into result
    from public.course_subjects course_subject
    join public.courses course on course.id = course_subject.course_id and course.is_active
    join public.educational_levels level on level.id = course.educational_level_id
    join public.subjects subject on subject.id = course_subject.subject_id and subject.is_active
    join public.teachers teacher on teacher.id = course_subject.teacher_id and teacher.is_active
    join public.people teacher_person on teacher_person.id = teacher.person_id
    where course_subject.is_active
      and (academic_year_filter is null or course_subject.academic_year = academic_year_filter)
      and (level_filter is null or level.id = level_filter);
  elsif p_report_code = 'teachers_by_course_schedule' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'educational_level', level.name,
      'teacher', concat_ws(' ', teacher_person.last_name, teacher_person.first_name),
      'course', course.name,
      'subject', subject.name,
      'day_of_week', schedule.day_of_week,
      'starts_at', schedule.starts_at,
      'ends_at', schedule.ends_at,
      'academic_year', schedule.academic_year
    ) order by level.sort_order, teacher_person.last_name, course.name, schedule.day_of_week, schedule.starts_at), '[]'::jsonb)
    into result
    from public.academic_schedules schedule
    join public.courses course on course.id = schedule.course_id and course.is_active
    join public.educational_levels level on level.id = course.educational_level_id
    left join public.course_subjects course_subject on course_subject.id = schedule.course_subject_id and course_subject.is_active
    left join public.subjects subject on subject.id = course_subject.subject_id
    left join public.teachers teacher on teacher.id = course_subject.teacher_id and teacher.is_active
    left join public.people teacher_person on teacher_person.id = teacher.person_id
    where schedule.is_active
      and (academic_year_filter is null or schedule.academic_year = academic_year_filter)
      and (level_filter is null or level.id = level_filter);
  elsif p_report_code = 'students_by_sport_level' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'sport', sport.name,
      'educational_level', level.name,
      'student', concat_ws(' ', person.last_name, person.first_name),
      'course', course.name,
      'academic_year', enrollment.academic_year
    ) order by sport.name, level.sort_order, person.last_name, person.first_name), '[]'::jsonb)
    into result
    from public.student_sport_enrollments enrollment
    join public.students student on student.id = enrollment.student_id and student.is_active
    join public.people person on person.id = student.person_id
    join public.sport_groups sport_group on sport_group.id = enrollment.sport_group_id and sport_group.is_active
    join public.sports sport on sport.id = sport_group.sport_id and sport.is_active
    left join public.educational_levels level on level.id = sport_group.educational_level_id
    left join public.student_enrollments student_course on student_course.student_id = student.id and student_course.academic_year = enrollment.academic_year and student_course.is_active
    left join public.courses course on course.id = student_course.course_id
    where enrollment.is_active
      and (academic_year_filter is null or enrollment.academic_year = academic_year_filter)
      and (level_filter is null or level.id = level_filter)
      and (sport_filter is null or sport.id = sport_filter);
  elsif p_report_code = 'students_by_sport_schedule_teacher' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'sport', sport.name,
      'educational_level', level.name,
      'teacher', concat_ws(' ', teacher_person.last_name, teacher_person.first_name),
      'day_of_week', schedule.day_of_week,
      'starts_at', schedule.starts_at,
      'ends_at', schedule.ends_at,
      'student', concat_ws(' ', person.last_name, person.first_name),
      'course', course.name,
      'academic_year', enrollment.academic_year
    ) order by sport.name, level.sort_order, schedule.day_of_week, schedule.starts_at, person.last_name), '[]'::jsonb)
    into result
    from public.student_sport_enrollments enrollment
    join public.students student on student.id = enrollment.student_id and student.is_active
    join public.people person on person.id = student.person_id
    join public.sport_groups sport_group on sport_group.id = enrollment.sport_group_id and sport_group.is_active
    join public.sports sport on sport.id = sport_group.sport_id and sport.is_active
    left join public.educational_levels level on level.id = sport_group.educational_level_id
    left join public.teachers teacher on teacher.id = sport_group.teacher_id and teacher.is_active
    left join public.people teacher_person on teacher_person.id = teacher.person_id
    left join public.sport_group_schedules schedule on schedule.sport_group_id = sport_group.id and schedule.is_active
    left join public.student_enrollments student_course on student_course.student_id = student.id and student_course.academic_year = enrollment.academic_year and student_course.is_active
    left join public.courses course on course.id = student_course.course_id
    where enrollment.is_active
      and (academic_year_filter is null or enrollment.academic_year = academic_year_filter)
      and (level_filter is null or level.id = level_filter)
      and (sport_filter is null or sport.id = sport_filter);
  elsif p_report_code = 'transport_and_dining' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'student', concat_ws(' ', person.last_name, person.first_name),
      'student_number', student.student_number,
      'route', route.route_number,
      'route_name', route.name,
      'stop', stop.name,
      'dining_service', dining_service.name,
      'dining_days_used', coalesce(dining_usage.used_days, 0),
      'academic_year', transport.academic_year
    ) order by route.route_number, person.last_name), '[]'::jsonb)
    into result
    from public.student_transport_enrollments transport
    join public.students student on student.id = transport.student_id and student.is_active
    join public.people person on person.id = student.person_id
    join public.transport_routes route on route.id = transport.route_id
    left join public.transport_stops stop on stop.id = transport.stop_id
    left join public.student_dining_enrollments dining on dining.student_id = transport.student_id and dining.academic_year = transport.academic_year and dining.is_active
    left join public.dining_services dining_service on dining_service.id = dining.dining_service_id
    left join (
      select dining_enrollment_id, count(*) filter (where used) as used_days
      from public.dining_usage
      group by dining_enrollment_id
    ) dining_usage on dining_usage.dining_enrollment_id = dining.id
    where transport.is_active
      and (academic_year_filter is null or transport.academic_year = academic_year_filter)
      and (route_filter is null or route.id = route_filter);
  else
    raise exception 'Unsupported administrative report: %', p_report_code using errcode = 'invalid_parameter_value';
  end if;

  return result;
end;
$$;

grant execute on function public.get_admin_report(text, jsonb) to authenticated;
revoke execute on function public.get_admin_report(text, jsonb) from public;
