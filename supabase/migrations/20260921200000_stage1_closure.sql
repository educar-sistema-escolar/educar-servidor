-- Stage 1 closure: database integrity, safe profile auditing, and no Auth provisioning.
alter table public.people add column if not exists birth_date date;
alter table public.profiles add column if not exists must_change_password boolean not null default false;

do $$ begin
  if exists (select 1 from public.student_enrollments e join public.courses c on c.id=e.course_id where e.academic_year<>c.academic_year or (e.is_active and not c.is_active))
     or exists (select 1 from public.student_enrollments e join public.students s on s.id=e.student_id where e.is_active and not s.is_active)
     or exists (select 1 from public.student_enrollments e join public.courses c on c.id=e.course_id where e.is_active and c.capacity is not null and (select count(*) from public.student_enrollments x where x.course_id=e.course_id and x.is_active)>c.capacity)
     or exists (select 1 from public.course_subjects cs join public.courses c on c.id=cs.course_id where cs.academic_year<>c.academic_year or (cs.is_active and not c.is_active))
     or exists (select 1 from public.course_subjects cs join public.subjects s on s.id=cs.subject_id where cs.is_active and not s.is_active)
     or exists (select 1 from public.course_subjects cs join public.teachers t on t.id=cs.teacher_id where cs.is_active and cs.teacher_id is not null and not t.is_active) then
    raise exception 'Existing Stage 1 data violates closure invariants' using errcode='check_violation';
  end if;
end $$;

create or replace function public.validate_student_enrollment() returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
declare c public.courses%rowtype; active_count integer; student_active boolean;
begin
  select * into c from public.courses where id=new.course_id for update;
  if new.academic_year<>c.academic_year then raise exception 'Enrollment academic_year must match course academic_year' using errcode='check_violation'; end if;
  if new.is_active and (not found or not c.is_active) then raise exception 'Enrollment requires an active course' using errcode='check_violation'; end if;
  select is_active into student_active from public.students where id=new.student_id;
  if new.is_active and coalesce(student_active,false)=false then raise exception 'Enrollment requires an active student' using errcode='check_violation'; end if;
  if new.is_active and c.capacity is not null then
    select count(*) into active_count from public.student_enrollments where course_id=new.course_id and is_active and id<>new.id;
    if active_count>=c.capacity then raise exception 'Course capacity reached' using errcode='check_violation'; end if;
  end if;
  return new;
end $$;

create or replace function public.validate_course_subject() returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
declare course_active boolean; course_year integer; subject_active boolean; teacher_active boolean;
begin
  select is_active,academic_year into course_active,course_year from public.courses where id=new.course_id;
  select is_active into subject_active from public.subjects where id=new.subject_id;
  if new.teacher_id is not null then select is_active into teacher_active from public.teachers where id=new.teacher_id; end if;
  if new.academic_year<>course_year then raise exception 'Course subject academic_year must match course academic_year' using errcode='check_violation'; end if;
  if new.is_active and (not coalesce(course_active,false) or not coalesce(subject_active,false) or not coalesce(teacher_active,true)) then raise exception 'Active assignment requires active course, subject, and teacher' using errcode='check_violation'; end if;
  return new;
end $$;

create or replace function public.prevent_active_reference_deactivation() returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
begin
  if old.is_active and not new.is_active then
    if tg_table_name='courses' and exists(select 1 from public.student_enrollments where course_id=old.id and is_active) then raise exception 'Cannot deactivate a course with active enrollments' using errcode='check_violation'; end if;
    if tg_table_name='students' and exists(select 1 from public.student_enrollments where student_id=old.id and is_active) then raise exception 'Cannot deactivate a student with active enrollments' using errcode='check_violation'; end if;
    if tg_table_name='subjects' and exists(select 1 from public.course_subjects where subject_id=old.id and is_active) then raise exception 'Cannot deactivate a subject with active assignments' using errcode='check_violation'; end if;
    if tg_table_name='teachers' and exists(select 1 from public.course_subjects where teacher_id=old.id and is_active) then raise exception 'Cannot deactivate a teacher with active assignments' using errcode='check_violation'; end if;
  end if;
  return new;
end $$;

create or replace function public.validate_course_capacity() returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
begin
  if new.capacity is not null and (
    select count(*)
    from public.student_enrollments
    where course_id = new.id and is_active
  ) > new.capacity then
    raise exception 'Course capacity is below active enrollment count' using errcode='check_violation';
  end if;
  return new;
end $$;

drop trigger if exists student_enrollments_validate on public.student_enrollments;
create trigger student_enrollments_validate before insert or update on public.student_enrollments for each row execute function public.validate_student_enrollment();
drop trigger if exists course_subjects_validate on public.course_subjects;
create trigger course_subjects_validate before insert or update on public.course_subjects for each row execute function public.validate_course_subject();
drop trigger if exists courses_prevent_active_reference_deactivation on public.courses;
create trigger courses_prevent_active_reference_deactivation before update on public.courses for each row execute function public.prevent_active_reference_deactivation();
drop trigger if exists students_prevent_active_reference_deactivation on public.students;
create trigger students_prevent_active_reference_deactivation before update on public.students for each row execute function public.prevent_active_reference_deactivation();
drop trigger if exists subjects_prevent_active_reference_deactivation on public.subjects;
create trigger subjects_prevent_active_reference_deactivation before update on public.subjects for each row execute function public.prevent_active_reference_deactivation();
drop trigger if exists teachers_prevent_active_reference_deactivation on public.teachers;
create trigger teachers_prevent_active_reference_deactivation before update on public.teachers for each row execute function public.prevent_active_reference_deactivation();
drop trigger if exists courses_validate_capacity on public.courses;
create trigger courses_validate_capacity before update on public.courses for each row execute function public.validate_course_capacity();

create or replace function public.write_audit_log() returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
begin
  if tg_table_name='profiles' then
    if tg_op<>'UPDATE' or (old.role is not distinct from new.role and old.is_active is not distinct from new.is_active) then return new; end if;
    insert into public.audit_logs(actor_profile_id,action,entity_type,entity_id,old_data,new_data) values(auth.uid(),'UPDATE','profiles',new.id,jsonb_build_object('role',old.role,'is_active',old.is_active),jsonb_build_object('role',new.role,'is_active',new.is_active));
    return new;
  end if;
  if tg_op='DELETE' then insert into public.audit_logs(actor_profile_id,action,entity_type,entity_id,old_data) values(auth.uid(),tg_op,tg_table_name,old.id,to_jsonb(old)); return old; end if;
  if tg_op='INSERT' then insert into public.audit_logs(actor_profile_id,action,entity_type,entity_id,new_data) values(auth.uid(),tg_op,tg_table_name,new.id,to_jsonb(new)); else insert into public.audit_logs(actor_profile_id,action,entity_type,entity_id,old_data,new_data) values(auth.uid(),tg_op,tg_table_name,new.id,to_jsonb(old),to_jsonb(new)); end if;
  return new;
end $$;

drop policy if exists "Authorities can read every profile" on public.profiles;
create policy "Active superadmins can read every profile" on public.profiles for select to authenticated using ((select public.is_active_superadmin()));
drop policy if exists "Active authorities can update profiles" on public.profiles;
create policy "Active superadmins can update profiles" on public.profiles for update to authenticated using ((select public.is_active_superadmin())) with check ((select public.is_active_superadmin()));

create or replace function public.prevent_last_superadmin_lockout() returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
begin
  perform pg_advisory_xact_lock(814221);
  if tg_op='DELETE' then
    if old.role='superadmin' and old.is_active and not exists(select 1 from public.profiles where id<>old.id and role='superadmin' and is_active) then raise exception 'Cannot delete the last active superadmin' using errcode='check_violation'; end if;
    return old;
  end if;
  if old.role='superadmin' and old.is_active and (new.role<>'superadmin' or not new.is_active) and not exists(select 1 from public.profiles where id<>old.id and role='superadmin' and is_active) then raise exception 'Cannot demote or deactivate the last active superadmin' using errcode='check_violation'; end if;
  return new;
end $$;
drop trigger if exists profiles_prevent_last_superadmin_lockout on public.profiles;
create trigger profiles_prevent_last_superadmin_lockout before update or delete on public.profiles for each row execute function public.prevent_last_superadmin_lockout();
