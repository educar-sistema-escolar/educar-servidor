-- Practical CRUD through the same tables/RPC as web forms. No permanent fixtures.
begin;
set local statement_timeout='60s';
select set_config('request.jwt.claim.sub',(select id::text from profiles where email='director@educar.com'),true);
set local role authenticated;
do $$
declare lvl uuid; course uuid; subject uuid; teacher uuid;
begin
 insert into educational_levels(code,name,sort_order) values('QA4-TEMP','QA4 temporal',99) returning id into lvl;
 update educational_levels set name='QA4 editado',is_active=false where id=lvl;
 if not exists(select 1 from educational_levels where id=lvl and not is_active and name='QA4 editado') then raise exception 'Level update failed';end if;
 begin insert into educational_levels(code,name) values('QA4-TEMP','Duplicado');raise exception 'Duplicate level accepted';exception when unique_violation then null;end;
 update educational_levels set is_active=true where id=lvl;
 insert into courses(educational_level_id,code,name,academic_year,capacity) values(lvl,'QA4-TEMP','QA4 temporal',2027,20) returning id into course;
 update courses set name='QA4 editado',capacity=21,is_active=false where id=course;
 if not exists(select 1 from courses where id=course and capacity=21 and not is_active) then raise exception 'Course update failed';end if;
 begin insert into courses(educational_level_id,code,name,academic_year,capacity) values(lvl,'QA4-INVALID','Invalid',2027,-1);raise exception 'Negative capacity accepted';exception when check_violation then null;end;
 begin insert into courses(educational_level_id,code,name,academic_year) values(lvl,'QA4-TEMP','Duplicate',2027);raise exception 'Duplicate course accepted';exception when unique_violation then null;end;
 insert into subjects(code,name) values('QA4-TEMP','QA4 temporal') returning id into subject;
 update subjects set name='QA4 editado',is_active=false where id=subject;
 if not exists(select 1 from subjects where id=subject and name='QA4 editado' and not is_active) then raise exception 'Subject update failed';end if;
 begin insert into subjects(code,name) values('QA4-TEMP','Duplicado');raise exception 'Duplicate subject accepted';exception when unique_violation then null;end;
 teacher:=(create_teacher('{"first_name":"Prueba","last_name":"Temporal","dni":"49999041","teacher_number":"QA4-TEMP","specialty":"Prueba"}'::jsonb)->>'id')::uuid;
 perform update_teacher(jsonb_build_object('id',teacher,'specialty','Actualizado','is_active',false));
 if not exists(select 1 from teachers where id=teacher and specialty='Actualizado' and not is_active) then raise exception 'Teacher update failed';end if;
 begin perform create_teacher('{"first_name":"Prueba","last_name":"Duplicada","dni":"49999041"}'::jsonb);raise exception 'Duplicate teacher DNI accepted';exception when unique_violation then null;end;
 begin perform create_teacher('[]'::jsonb);raise exception 'Invalid teacher payload accepted';exception when invalid_parameter_value then null;end;
end $$;
reset role;
select set_config('request.jwt.claim.sub','',true);
set local role anon;
do $$
declare payload jsonb; request_id uuid;
begin
 payload:='{"studentFirstName":"Prueba","studentLastName":"Temporal","studentDni":"49999042","birthDate":"2015-04-01","educationalLevel":"Primario","schoolYear":"4to","turn":"Mañana","academicYear":2027,"responsibleFullName":"Responsable Temporal","responsibleDni":"29999042","responsibleRelation":"Madre","phone":"3624999942","email":"qa4@example.test"}'::jsonb;
 request_id:=(submit_enrollment_request(payload)->>'id')::uuid;
 if request_id is null then raise exception 'Public submission failed';end if;
 begin perform submit_enrollment_request(payload);raise exception 'Duplicate public request accepted';exception when unique_violation then null;end;
 begin perform submit_enrollment_request(payload||'{"studentDni":"1"}'::jsonb);raise exception 'Invalid DNI accepted';exception when invalid_parameter_value then null;end;
 begin perform submit_enrollment_request(payload||'{"email":"invalid"}'::jsonb);raise exception 'Invalid email accepted';exception when invalid_parameter_value then null;end;
 begin perform create_teacher('{}'::jsonb);raise exception 'Anonymous teacher mutation accepted';exception when insufficient_privilege then null;end;
end $$;
reset role;
rollback;
select 'PASS: level/course/subject create/edit/deactivate, duplicate and capacity checks, teacher RPC create/edit/duplicate/invalid, anonymous enrollment/duplicate/DNI/email, permissions; ROLLBACK' as acceptance;
