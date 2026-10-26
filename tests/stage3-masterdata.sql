begin;
set local statement_timeout='60s';
select set_config('request.jwt.claim.sub',(select id::text from public.profiles where email='director@educar.com'),true);
set local role authenticated;
do $test$
declare pupil uuid; teacher uuid; person public.people%rowtype; other_dni text; original_count integer;
begin
 select id into pupil from public.students where student_number='DEMO-2027-A005';
 select p.* into person from public.people p join public.students s on s.person_id=p.id where s.id=pupil;
 perform public.update_student(jsonb_build_object('id',pupil,'phone','3624000000'));
 if (select phone from public.people where id=person.id) is distinct from '3624000000' then raise exception 'Student update failed';end if;
 select dni into other_dni from public.people where id<>person.id and dni is not null limit 1;
 begin
 perform public.update_student(jsonb_build_object('id',pupil,'dni',other_dni));raise exception 'Duplicate student DNI accepted';
 exception when unique_violation then null;end;
 select id into teacher from public.teachers where teacher_number='DEMO-2027-D01';
 perform public.update_teacher(jsonb_build_object('id',teacher,'specialty','QA rollback'));
 if (select specialty from public.teachers where id=teacher)<>'QA rollback' then raise exception 'Teacher update failed';end if;
 select p.* into person from public.people p join public.teachers t on t.person_id=p.id where t.id=teacher;
 begin
 perform public.create_teacher(jsonb_build_object('first_name',person.first_name,'last_name',person.last_name,'dni',person.dni,'teacher_number','QA-ROLLBACK'));
 raise exception 'Duplicate teacher DNI accepted';
 exception when unique_violation then null;end;
 begin
 perform public.create_student(jsonb_build_object('first_name',person.first_name,'last_name',person.last_name,'dni',person.dni,'student_number','QA-ROLLBACK'));
 raise exception 'Duplicate person DNI accepted';
 exception when unique_violation then null;end;
 begin
 update public.sport_groups set teacher_id=null where is_active;
 raise exception 'Active sport without teacher accepted';
 exception when check_violation then null;end;
 begin
 insert into public.subjects(code,name) select code,name from public.subjects limit 1;
 raise exception 'Duplicate subject accepted';
 exception when unique_violation then null;end;
 begin
 insert into public.student_enrollments(student_id,course_id,academic_year)
 select student_id,course_id,academic_year from public.student_enrollments where student_id=pupil and is_active limit 1;
 raise exception 'Duplicate course enrollment accepted';
 exception when unique_violation then null;end;
end $test$;
reset role;
select set_config('request.jwt.claim.sub',(select id::text from public.profiles where email='profesor@gmail.com'),true);
set local role authenticated;
do $test$ begin
 begin perform public.update_teacher(jsonb_build_object('id',gen_random_uuid(),'specialty','Denied'));raise exception 'Teacher admin mutation allowed';
 exception when insufficient_privilege then null;end;
end $test$;
reset role;
rollback;
select 'PASS: student/teacher updates, duplicate DNI/teacher/subject/course denied, mandatory sport teacher and nonadmin RPC denial; ROLLBACK' as acceptance;
