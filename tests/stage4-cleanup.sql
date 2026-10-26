-- Remove only the disposable fixtures created through web forms in stage 4.
-- Never removes institutional DEMO 2027 records or Auth accounts.
begin;
-- The course must be removed before its temporary level. Foreign keys remain active.
delete from courses where code='QA4-UI-TEMP' and name='Prueba curso temporal'
 and academic_year=2027 and educational_level_id in
 (select id from educational_levels where code='QA4-UI-TEMP' and name='Prueba nivel temporal');
delete from subjects where code='QA4-UI-TEMP' and name='Prueba materia temporal';
delete from educational_levels where code='QA4-UI-TEMP' and name='Prueba nivel temporal';
do $$ declare person uuid; begin
 select p.id into person from people p join teachers t on t.person_id=p.id
 where t.teacher_number='QA4-UI-TEMP' and p.dni='49999043'
 and p.email='qa4-docente@example.test' and p.profile_id is null;
 if person is not null then
  delete from teachers where person_id=person and teacher_number='QA4-UI-TEMP';
  delete from people where id=person and profile_id is null;
 end if;
 delete from enrollment_requests where student_dni='49999044'
 and email='qa4-public@example.test'
 and notes='QA4-UI-TEMP: prueba ficticia, eliminar al finalizar.' and status='pending';
 if exists(select 1 from teachers where teacher_number='QA4-UI-TEMP')
 or exists(select 1 from enrollment_requests where student_dni='49999044')
 or exists(select 1 from courses where code='QA4-UI-TEMP')
 or exists(select 1 from subjects where code='QA4-UI-TEMP')
 or exists(select 1 from educational_levels where code='QA4-UI-TEMP')
 then raise exception 'Temporary fixture cleanup failed';end if;
end $$;
commit;
