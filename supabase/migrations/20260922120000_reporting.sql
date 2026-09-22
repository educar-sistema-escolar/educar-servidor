-- Administrative reports. The RPC keeps report access behind the same server-side authorization boundary.

create or replace function public.get_admin_report(p_report_code text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare result jsonb;
begin
  if not public.is_active_superadmin() then
    raise exception 'Active superadmin role required' using errcode = 'insufficient_privilege';
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
    where enrollment.is_active;
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
    join public.courses course on course.id = course_subject.course_id
    join public.educational_levels level on level.id = course.educational_level_id
    join public.subjects subject on subject.id = course_subject.subject_id
    left join public.teachers teacher on teacher.id = course_subject.teacher_id
    left join public.people teacher_person on teacher_person.id = teacher.person_id
    where enrollment.is_active;
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
    where course_subject.is_active;
  elsif p_report_code = 'students_by_sport' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'sport', sport.name, 'student', concat_ws(' ', person.last_name, person.first_name),
      'course', course.name, 'educational_level', level.name
    ) order by sport.name, person.last_name), '[]'::jsonb)
    into result
    from public.student_sport_enrollments enrollment
    join public.students student on student.id = enrollment.student_id
    join public.people person on person.id = student.person_id
    join public.sport_groups sport_group on sport_group.id = enrollment.sport_group_id
    join public.sports sport on sport.id = sport_group.sport_id
    left join public.student_enrollments student_course on student_course.student_id = student.id and student_course.academic_year = enrollment.academic_year and student_course.is_active
    left join public.courses course on course.id = student_course.course_id
    left join public.educational_levels level on level.id = course.educational_level_id
    where enrollment.is_active;
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
    join public.students student on student.id = enrollment.student_id
    join public.people person on person.id = student.person_id
    join public.sport_groups sport_group on sport_group.id = enrollment.sport_group_id
    join public.sports sport on sport.id = sport_group.sport_id
    left join public.educational_levels level on level.id = sport_group.educational_level_id
    left join public.teachers teacher on teacher.id = sport_group.teacher_id
    left join public.people teacher_person on teacher_person.id = teacher.person_id
    left join public.sport_group_schedules schedule on schedule.sport_group_id = sport_group.id and schedule.is_active
    left join public.student_enrollments student_course on student_course.student_id = student.id and student_course.academic_year = enrollment.academic_year and student_course.is_active
    left join public.courses course on course.id = student_course.course_id
    where enrollment.is_active;
  elsif p_report_code = 'students_by_transport' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'route', route.route_number, 'route_name', route.name,
      'student', concat_ws(' ', person.last_name, person.first_name),
      'student_number', student.student_number, 'stop', stop.name
    ) order by route.route_number, person.last_name), '[]'::jsonb)
    into result
    from public.student_transport_enrollments enrollment
    join public.students student on student.id = enrollment.student_id
    join public.people person on person.id = student.person_id
    join public.transport_routes route on route.id = enrollment.route_id
    left join public.transport_stops stop on stop.id = enrollment.stop_id
    where enrollment.is_active;
  elsif p_report_code = 'student_overview' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'student', concat_ws(' ', person.last_name, person.first_name),
      'student_number', student.student_number,
      'courses', (select coalesce(jsonb_agg(jsonb_build_object('course', course.name, 'educational_level', level.name)), '[]'::jsonb) from public.student_enrollments se join public.courses course on course.id = se.course_id join public.educational_levels level on level.id = course.educational_level_id where se.student_id = student.id and se.is_active),
      'subjects', (select coalesce(jsonb_agg(jsonb_build_object('subject', subject.name, 'teacher', concat_ws(' ', teacher_person.last_name, teacher_person.first_name))), '[]'::jsonb) from public.student_subject_enrollments sse join public.course_subjects cs on cs.id = sse.course_subject_id join public.subjects subject on subject.id = cs.subject_id left join public.teachers teacher on teacher.id = cs.teacher_id left join public.people teacher_person on teacher_person.id = teacher.person_id where sse.student_id = student.id and sse.is_active),
      'sports', (select coalesce(jsonb_agg(jsonb_build_object('sport', sport.name, 'group', sport_group.name)), '[]'::jsonb) from public.student_sport_enrollments ssp join public.sport_groups sport_group on sport_group.id = ssp.sport_group_id join public.sports sport on sport.id = sport_group.sport_id where ssp.student_id = student.id and ssp.is_active),
      'transport', (select coalesce(jsonb_agg(jsonb_build_object('route', route.route_number, 'name', route.name)), '[]'::jsonb) from public.student_transport_enrollments ste join public.transport_routes route on route.id = ste.route_id where ste.student_id = student.id and ste.is_active),
      'dining', (select coalesce(jsonb_agg(jsonb_build_object('service', service.name, 'academic_year', sde.academic_year)), '[]'::jsonb) from public.student_dining_enrollments sde join public.dining_services service on service.id = sde.dining_service_id where sde.student_id = student.id and sde.is_active)
    ) order by person.last_name, person.first_name), '[]'::jsonb)
    into result
    from public.students student join public.people person on person.id = student.person_id
    where student.is_active;
  else
    raise exception 'Unsupported administrative report: %', p_report_code using errcode = 'invalid_parameter_value';
  end if;

  return result;
end;
$$;

grant execute on function public.get_admin_report(text) to authenticated;
revoke execute on function public.get_admin_report(text) from public;
