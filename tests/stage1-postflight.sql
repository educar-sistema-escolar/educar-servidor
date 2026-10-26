-- Read-only proof of the applied DEMO stage. History before this stage stays untouched.
select 'Migración 1: aprobación/comedor' as control,
  case when exists(select 1 from supabase_migrations.schema_migrations where version='20261025120000')
    and position('resolved_person_id' in pg_get_functiondef('public.approve_enrollment_request(uuid,uuid)'::regprocedure))>0
    and not exists(select 1 from pg_trigger where tgrelid='public.dining_usage'::regclass and tgname='dining_usage_set_updated_at')
  then 'APLICADA' else 'FALLO' end as resultado
union all
select 'Migración 2: horarios',case when exists(select 1 from supabase_migrations.schema_migrations where version='20261026030000')
  and position('Teacher schedule overlaps another active course schedule' in pg_get_functiondef('public.validate_academic_schedule()'::regprocedure))>0
  and exists(select 1 from pg_trigger where tgrelid='public.course_subjects'::regclass and tgname='course_subjects_teacher_schedule_validate' and tgenabled<>'D')
  and exists(select 1 from pg_trigger where tgrelid='public.sport_groups'::regclass and tgname='sport_groups_teacher_schedule_validate' and tgenabled<>'D')
  then 'APLICADA' else 'FALLO' end
union all
select 'Migración 3: asociación familiar',case when exists(select 1 from supabase_migrations.schema_migrations where version='20261026120000')
  and position('resolved_guardian_person_id' in pg_get_functiondef('public.link_student_guardian(uuid,uuid,text,boolean)'::regprocedure))>0
  then 'APLICADA' else 'FALLO' end
union all
select 'Corrección: trigger del responsable',case when exists(select 1 from supabase_migrations.schema_migrations where version='20261026133000')
  and position('resolved_guardian_person_id' in pg_get_functiondef('public.link_approved_enrollment_guardian_for_request(public.enrollment_requests)'::regprocedure))>0
  then 'APLICADA' else 'FALLO' end
union all
select 'RLS en las seis tablas verificadas',case when (select count(*) from pg_class where relnamespace='public'::regnamespace
  and relname in ('profiles','people','students','student_enrollments','student_guardians','dining_usage') and relrowsecurity)=6
  then 'ACTIVA' else 'FALLO' end
union all
select 'Familia DEMO: dos hijos activos',case when (select count(distinct link.student_id) from public.student_guardians link
  join public.people person on person.id=link.guardian_person_id join public.profiles profile on profile.id=person.profile_id
  where profile.email='familia.demo.2027@educar.example' and link.is_active)=2 then 'VERIFICADO' else 'FALLO' end
union all
select 'Solicitud de prueba con ROLLBACK',case when exists(select 1 from public.enrollment_requests
  where id='43965105-2910-4f36-b37c-8625d5c6624f' and status='pending') then 'SIGUE PENDIENTE' else 'FALLO' end;
