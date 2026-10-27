-- Grade ownership is derived from the authenticated account, never from the client.
alter table public.academic_history
  add column created_by uuid references public.profiles(id) on delete set null,
  add column updated_by uuid references public.profiles(id) on delete set null;

-- Legacy rows keep unknown attribution; changing them would also alter their
-- timestamps and create misleading audit events. Existing audit logs remain intact.

create function public.set_grade_actor() returns trigger
language plpgsql security definer set search_path = pg_catalog, public as $$
begin
  if tg_op = 'INSERT' then
    new.created_by := auth.uid();
  else
    new.created_by := old.created_by;
  end if;
  new.updated_by := auth.uid();
  return new;
end $$;

create trigger academic_history_set_actor before insert or update on public.academic_history
for each row execute function public.set_grade_actor();

create function public.save_teacher_grade(p_enrollment_id uuid, p_history_id uuid, p_term smallint, p_grade numeric, p_notes text default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare result public.academic_history%rowtype;
begin
  if not exists (
    select 1 from public.student_subject_enrollments sse
    join public.student_enrollments se on se.student_id = sse.student_id and se.academic_year = sse.academic_year and se.is_active
    join public.course_subjects cs on cs.id = sse.course_subject_id and cs.course_id = se.course_id and cs.academic_year = sse.academic_year and cs.is_active
    join public.courses c on c.id = cs.course_id and c.is_active
    join public.students s on s.id = sse.student_id and s.is_active
    join public.teachers t on t.id = cs.teacher_id and t.is_active
    join public.people p on p.id = t.person_id and p.is_active
    join public.profiles profile on profile.id = p.profile_id and profile.is_active and profile.account_status = 'active' and profile.role::text = 'teacher'
    where sse.id = p_enrollment_id and sse.is_active and profile.id = auth.uid()
  ) then
    raise exception 'Active assigned subject and enrollment required' using errcode = '42501';
  end if;
  if p_term not between 1 and 4 or p_grade is null or p_grade not between 0 and 10 then
    raise exception 'Invalid term or grade' using errcode = '23514';
  end if;
  if p_history_id is null then
    insert into public.academic_history(student_subject_enrollment_id, term, grade, notes)
    values (p_enrollment_id, p_term, p_grade, nullif(btrim(p_notes), '')) returning * into result;
  else
    update public.academic_history set grade = p_grade, notes = nullif(btrim(p_notes), '')
    where id = p_history_id and student_subject_enrollment_id = p_enrollment_id and term = p_term and created_by = auth.uid()
    returning * into result;
    if not found then raise exception 'Grade is not owned by this teacher' using errcode = '42501'; end if;
  end if;
  return to_jsonb(result);
end $$;

revoke all on function public.save_teacher_grade(uuid, uuid, smallint, numeric, text) from public;
grant execute on function public.save_teacher_grade(uuid, uuid, smallint, numeric, text) to authenticated;
