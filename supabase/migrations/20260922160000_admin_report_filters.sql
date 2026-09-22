-- Apply the common filters to the report families that existed before the
-- completion migration. The detailed report branches remain in the previous
-- function and are reused unchanged.

alter function public.get_admin_report_with_filters(text, jsonb)
  rename to get_admin_report_with_filters_v1;

create or replace function public.get_admin_report_with_filters(
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

  if p_report_code = 'students_by_course' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'educational_level', level.name, 'course', course.name,
      'student_number', student.student_number, 'last_name', person.last_name,
      'first_name', person.first_name
    ) order by level.sort_order, course.name, person.last_name, person.first_name), '[]'::jsonb)
    into result
    from public.student_enrollments enrollment
    join public.students student on student.id = enrollment.student_id and student.is_active
    join public.people person on person.id = student.person_id
    join public.courses course on course.id = enrollment.course_id and course.is_active
    join public.educational_levels level on level.id = course.educational_level_id
    where enrollment.is_active
      and (academic_year_filter is null or enrollment.academic_year = academic_year_filter)
      and (level_filter is null or level.id = level_filter);
  elsif p_report_code = 'students_by_subject' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'educational_level', level.name, 'course', course.name, 'subject', subject.name,
      'teacher', concat_ws(' ', teacher_person.last_name, teacher_person.first_name),
      'student', concat_ws(' ', person.last_name, person.first_name),
      'student_number', student.student_number
    ) order by level.sort_order, course.name, subject.name, person.last_name), '[]'::jsonb)
    into result
    from public.student_subject_enrollments enrollment
    join public.students student on student.id = enrollment.student_id and student.is_active
    join public.people person on person.id = student.person_id
    join public.course_subjects course_subject on course_subject.id = enrollment.course_subject_id and course_subject.is_active
    join public.courses course on course.id = course_subject.course_id and course.is_active
    join public.educational_levels level on level.id = course.educational_level_id
    join public.subjects subject on subject.id = course_subject.subject_id and subject.is_active
    left join public.teachers teacher on teacher.id = course_subject.teacher_id
    left join public.people teacher_person on teacher_person.id = teacher.person_id
    where enrollment.is_active
      and (academic_year_filter is null or enrollment.academic_year = academic_year_filter)
      and (level_filter is null or level.id = level_filter);
  elsif p_report_code = 'teachers_by_level' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'educational_level', level.name,
      'teacher', concat_ws(' ', teacher_person.last_name, teacher_person.first_name),
      'subject', subject.name, 'course', course.name
    ) order by level.sort_order, teacher_person.last_name, subject.name, course.name), '[]'::jsonb)
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
  elsif p_report_code = 'students_by_sport' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'sport', sport.name, 'student', concat_ws(' ', person.last_name, person.first_name),
      'course', course.name, 'educational_level', level.name
    ) order by sport.name, person.last_name), '[]'::jsonb)
    into result
    from public.student_sport_enrollments enrollment
    join public.students student on student.id = enrollment.student_id and student.is_active
    join public.people person on person.id = student.person_id
    join public.sport_groups sport_group on sport_group.id = enrollment.sport_group_id and sport_group.is_active
    join public.sports sport on sport.id = sport_group.sport_id and sport.is_active
    left join public.student_enrollments student_course on student_course.student_id = student.id and student_course.academic_year = enrollment.academic_year and student_course.is_active
    left join public.courses course on course.id = student_course.course_id
    left join public.educational_levels level on level.id = course.educational_level_id
    where enrollment.is_active
      and (academic_year_filter is null or enrollment.academic_year = academic_year_filter)
      and (level_filter is null or level.id = level_filter)
      and (sport_filter is null or sport.id = sport_filter);
  elsif p_report_code = 'students_by_sport_schedule' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'sport', sport.name, 'educational_level', level.name,
      'schedule_day', schedule.day_of_week, 'starts_at', schedule.starts_at,
      'ends_at', schedule.ends_at,
      'teacher', concat_ws(' ', teacher_person.last_name, teacher_person.first_name),
      'student', concat_ws(' ', person.last_name, person.first_name),
      'course', course.name
    ) order by sport.name, schedule.day_of_week, schedule.starts_at, person.last_name), '[]'::jsonb)
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
  elsif p_report_code = 'students_by_transport' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'route', route.route_number, 'route_name', route.name,
      'student', concat_ws(' ', person.last_name, person.first_name),
      'student_number', student.student_number, 'stop', stop.name
    ) order by route.route_number, person.last_name), '[]'::jsonb)
    into result
    from public.student_transport_enrollments enrollment
    join public.students student on student.id = enrollment.student_id and student.is_active
    join public.people person on person.id = student.person_id
    join public.transport_routes route on route.id = enrollment.route_id and route.is_active
    left join public.transport_stops stop on stop.id = enrollment.stop_id
    where enrollment.is_active
      and (academic_year_filter is null or enrollment.academic_year = academic_year_filter)
      and (route_filter is null or route.id = route_filter);
  else
    return public.get_admin_report_with_filters_v1(p_report_code, p_filters);
  end if;

  return result;
end;
$$;

grant execute on function public.get_admin_report_with_filters(text, jsonb) to authenticated;
revoke execute on function public.get_admin_report_with_filters(text, jsonb) from public;
