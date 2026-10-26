-- Existing DEMO fixtures only; all changes and attempted enrollments ROLLBACK.
begin;
set local statement_timeout='60s';
select set_config('request.jwt.claim.sub',(select id::text from public.profiles where email='director@educar.com'),true);
set local role authenticated;
do $test$
declare pupil uuid; course uuid; level uuid; groups uuid[]; route uuid; other_stop uuid;
 entry jsonb; target uuid; teacher uuid; person public.people%rowtype; subject uuid;
begin
 select s.id,e.course_id,c.educational_level_id into strict pupil,course,level
 from public.students s join public.student_enrollments e on e.student_id=s.id and e.is_active
 join public.courses c on c.id=e.course_id
 where e.academic_year=2027
 and exists(select 1 from public.people p where p.id=s.person_id and p.dni='47100002');
 select array_agg(id order by name) into groups from public.sport_groups
 where academic_year=2027 and educational_level_id=level and is_active;
 if cardinality(groups)<3 then raise exception 'Expected existing sports groups';end if;
 entry:=public.enroll_student_in_sport_group(pupil,groups[1]);
 if (entry->>'academic_year')::int<>2027 then raise exception 'Sport cycle incorrect';end if;
 begin
  perform public.enroll_student_in_sport_group(pupil,groups[1]);raise exception 'Duplicate sport accepted';
 exception when unique_violation then null;end;
 perform public.enroll_student_in_sport_group(pupil,groups[2]);
 begin
  perform public.enroll_student_in_sport_group(pupil,groups[3]);raise exception 'Third sport accepted';
 exception when check_violation then if sqlerrm not like '%two active sports%' then raise;end if;end;
 -- Deactivate only the temporary rows created above, within this rollback transaction.
 update public.student_sport_enrollments set is_active=false where student_id=pupil;
 update public.sport_groups set capacity=greatest(1,(select count(*) from public.student_sport_enrollments where sport_group_id=groups[1] and is_active)) where id=groups[1];
 begin
  perform public.enroll_student_in_sport_group(pupil,groups[1]);raise exception 'Full sport accepted';
 exception when check_violation then if sqlerrm not like '%capacity%' then raise;end if;end;
 begin
  perform public.enroll_student_in_sport_group(pupil,(select id from public.sport_groups where educational_level_id<>level and academic_year=2027 and is_active limit 1));raise exception 'Wrong sport level accepted';
 exception when check_violation then null;end;
 if (select count(*) from public.transport_routes where is_active) <> 4 then raise exception 'Four routes missing';end if;
 select id into route from public.transport_routes where route_number=1 and is_active;
 select id into other_stop from public.transport_stops where route_id<>route and is_active limit 1;
 entry:=public.enroll_student_in_transport(pupil,route,null,2027);
 if (entry->>'academic_year')::int<>2027 then raise exception 'Transport ignored selected cycle';end if;
 begin
  perform public.enroll_student_in_transport(pupil,route,null,2027);raise exception 'Duplicate transport accepted';
 exception when unique_violation then null;end;
 begin
  perform public.enroll_student_in_transport(pupil,route,other_stop,2028);raise exception 'Foreign stop accepted';
 exception when check_violation then null;end;
 update public.student_transport_enrollments set is_active=false where id=(entry->>'id')::uuid;
 update public.transport_routes set capacity=greatest(1,(select count(*) from public.student_transport_enrollments where route_id=route and academic_year=2027 and is_active)) where id=route;
 begin
  perform public.enroll_student_in_transport(pupil,route,null,2027);raise exception 'Full transport accepted';
 exception when check_violation then if sqlerrm not like '%capacity%' then raise;end if;end;
 begin
  insert into public.transport_routes(route_number,name,capacity) values(5,'Invalid',10);raise exception 'Fifth route accepted';
 exception when check_violation then null;end;
 select id into target from public.dining_services where is_active limit 1;
 perform public.enroll_student_in_dining(pupil,target,2027);
 begin
  perform public.enroll_student_in_dining(pupil,target,2027);raise exception 'Duplicate dining accepted';
 exception when unique_violation then null;end;
 update public.student_dining_enrollments set is_active=false where student_id=pupil and dining_service_id=target and academic_year=2027;
 update public.dining_services set capacity=greatest(1,(select count(*) from public.student_dining_enrollments where dining_service_id=target and academic_year=2027 and is_active)) where id=target;
 begin
  perform public.enroll_student_in_dining(pupil,target,2027);raise exception 'Full dining accepted';
 exception when check_violation then if sqlerrm not like '%capacity%' then raise;end if;end;
 select id into subject from public.course_subjects where course_id=course and academic_year=2027 and is_active limit 1;
 entry:=public.enroll_student_in_subject(pupil,subject);
 begin
  perform public.enroll_student_in_subject(pupil,subject);raise exception 'Duplicate academic enrollment accepted';
 exception when unique_violation then null;end;
 begin
  perform public.enroll_student_in_subject(pupil,(select id from public.course_subjects where course_id<>course and academic_year=2027 and is_active limit 1));raise exception 'Foreign course accepted';
 exception when check_violation then null;end;

end $test$;
reset role;
rollback;
select 'PASS: sports positive/duplicate/max2/capacity, transport selected cycle/duplicate/stop/4routes, dining duplicate, academic positive/duplicate/foreign-course; ROLLBACK' as acceptance;
