-- Run only in CentroEducativo / nhwsgmijdsxzuxgpllhy after inspecting preflight.
-- Additive DEMO 2027 fixtures. Re-running preserves existing data and identities.
begin;
set local statement_timeout='60s';
select set_config('request.jwt.claim.sub',(select p.id::text from profiles p join people pe on pe.profile_id=p.id join students s on s.person_id=pe.id where s.student_number='DEMO-2027-A001'),true);
set local role authenticated;
insert into forum_discussions(id,category,title,lead,content) values
('84000000-0000-4000-8000-000000000001','Académico','DEMO 2027: bienvenida al ciclo lectivo','Organizamos el comienzo de clases.','Espacio ficticio de presentación. Recordemos consultar los horarios y traer los materiales para las primeras actividades.'),
('84000000-0000-4000-8000-000000000002','Grupos de Estudio','DEMO 2027: grupo de repaso de Matemática','Compartimos estrategias de estudio.','Propongo repasar los ejercicios de clase en la biblioteca durante los recreos autorizados. ¿Qué temas les gustaría practicar?')
on conflict(id) do nothing;
reset role;
select set_config('request.jwt.claim.sub',(select p.id::text from profiles p join people pe on pe.profile_id=p.id join students s on s.person_id=pe.id where s.student_number='DEMO-2027-A002'),true);
set local role authenticated;
insert into forum_discussions(id,category,title,lead,content) values
('84000000-0000-4000-8000-000000000003','Vida Escolar','DEMO 2027: jornada de cuidado de la escuela','Ideas para una institución más sustentable.','Podemos separar residuos y cuidar el patio entre todos. Compartamos propuestas para presentar a nuestros docentes.') on conflict(id) do nothing;
insert into forum_replies(id,discussion_id,content) values
('84000000-0000-4000-8000-000000000011','84000000-0000-4000-8000-000000000001','¡Buen comienzo! Ya consulté mis materias y horarios en el portal.'),
('84000000-0000-4000-8000-000000000012','84000000-0000-4000-8000-000000000002','Me gustaría practicar fracciones y compartir los apuntes de clase.') on conflict(id) do nothing;
insert into forum_discussion_votes(discussion_id,direction) values('84000000-0000-4000-8000-000000000001','up'),('84000000-0000-4000-8000-000000000002','up') on conflict do nothing;
reset role;
select set_config('request.jwt.claim.sub',(select p.id::text from profiles p join people pe on pe.profile_id=p.id join students s on s.person_id=pe.id where s.student_number='DEMO-2027-A003'),true);
set local role authenticated;
insert into forum_discussions(id,category,title,lead,content) values
('84000000-0000-4000-8000-000000000004','Deportes','DEMO 2027: encuentro deportivo escolar','Consultemos los grupos y sus horarios.','Antes de inscribirnos, revisemos los cupos y horarios del portal para evitar cruces con las clases. ¿Qué actividades eligieron?') on conflict(id) do nothing;
insert into forum_replies(id,discussion_id,content) values
('84000000-0000-4000-8000-000000000013','84000000-0000-4000-8000-000000000003','Propongo carteles hechos con materiales reutilizados para los cestos.') on conflict(id) do nothing;
insert into forum_discussion_votes(discussion_id,direction) values('84000000-0000-4000-8000-000000000003','up') on conflict do nothing;
insert into forum_reply_votes(reply_id,direction) values('84000000-0000-4000-8000-000000000011','up') on conflict do nothing;
reset role;
select set_config('request.jwt.claim.sub',(select id::text from profiles where email='director@educar.com'),true);
set local role authenticated;
insert into billing_values(concept,label,amount_cents,effective_from) values('tuition','DEMO 2027 - Cuota mensual',6500000,'2027-01-01') on conflict do nothing;
insert into billing_values(concept,service_id,label,amount_cents,effective_from)
select 'sport',id,'DEMO 2027 - Actividad deportiva',1200000,date '2027-01-01' from sport_groups where is_active
union all select 'transport',id,'DEMO 2027 - Transporte escolar',2800000,date '2027-01-01' from transport_routes where is_active
union all select 'dining',id,'DEMO 2027 - Comedor',3500000,date '2027-01-01' from dining_services where is_active
on conflict do nothing;
do $$
declare pupil uuid; period_value date;
begin
 for pupil in select id from students where student_number in ('DEMO-2027-A005','DEMO-2027-A010') loop
  foreach period_value in array array[date '2027-03-01',date '2027-04-01'] loop
   if not exists(select 1 from invoices where student_id=pupil and period=period_value) then
    perform issue_monthly_invoice(pupil,period_value,period_value+9);
   end if;
  end loop;
 end loop;
end $$;
reset role;
commit;
select jsonb_build_object('demo_posts',(select count(*) from forum_discussions where id::text like '84000000-%'),'demo_replies',(select count(*) from forum_replies where id::text like '84000000-%'),'invoices',(select count(*) from invoices),'students',(select count(*) from students),'teachers',(select count(*) from teachers)) as postflight;
