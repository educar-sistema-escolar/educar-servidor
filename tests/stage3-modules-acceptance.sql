-- Real project acceptance: uses existing identities and ROLLBACK; no demo seed.
begin;
set local statement_timeout = '30s';
select set_config('request.jwt.claim.sub', (select id::text from public.profiles where email='estudiante@gmail.com'), true);
set local role authenticated;
do $test$
declare discussion uuid; reply uuid; actual integer;
begin
 insert into public.forum_discussions(category,title,lead,content) values ('Académico','QA transaccional','Sin persistencia','Este registro se revierte al terminar la prueba.') returning id into discussion;
 if not exists(select 1 from public.forum_discussions where id=discussion and author_id=auth.uid()) then raise exception 'Forum author or read failed'; end if;
 insert into public.forum_replies(discussion_id,content) values(discussion,'Respuesta transaccional') returning id into reply;
 select replies_count into actual from public.forum_discussions where id=discussion;
 if actual <> 1 then raise exception 'Reply count failed'; end if;
 insert into public.forum_discussion_votes(discussion_id,direction) values(discussion,'up');
 select score into actual from public.forum_discussions where id=discussion;
 if actual <> 1 then raise exception 'Discussion score failed'; end if;
 update public.forum_discussion_votes set direction='down' where discussion_id=discussion;
 select score into actual from public.forum_discussions where id=discussion;
 if actual <> -1 then raise exception 'Discussion vote update failed'; end if;
 delete from public.forum_discussion_votes where discussion_id=discussion;
 insert into public.forum_reply_votes(reply_id,direction) values(reply,'up');
 if (select score from public.forum_replies where id=reply) <> 1 then raise exception 'Reply score failed'; end if;
 begin
   insert into public.forum_discussions(category,title,lead,content) values ('Académico',' ','Invalid','Invalid');
   raise exception 'Blank title accepted';
 exception when check_violation then null; end;
end $test$;
reset role;
select set_config('request.jwt.claim.sub', (select id::text from public.profiles where email='familia.demo.2027@educar.example'), true);
set local role authenticated;
do $test$
begin
 if exists(select 1 from public.forum_discussions) then raise exception 'Parent can read student forum'; end if;
 begin
   insert into public.forum_discussions(category,title,lead,content) values('Académico','Denied','Denied','Denied');
   raise exception 'Parent published';
 exception when insufficient_privilege then null; end;
end $test$;
reset role;
-- Billing: create temporary prices only for already configured active services.
select set_config('request.jwt.claim.sub', (select id::text from public.profiles where email='director@educar.com'), true);
set local role authenticated;
insert into public.billing_values(concept,label,amount_cents,effective_from) values('tuition','QA transaccional',10000,'2027-01-01');
insert into public.billing_values(concept,service_id,label,amount_cents,effective_from)
 select 'sport',id,'QA transaccional',1000,date '2027-01-01' from public.sport_groups where is_active
 union all select 'transport',id,'QA transaccional',1000,date '2027-01-01' from public.transport_routes where is_active
 union all select 'dining',id,'QA transaccional',1000,date '2027-01-01' from public.dining_services where is_active;
select public.issue_monthly_invoice((select id from public.students where student_number='DEMO-2027-A005'),'2027-12-01','2027-12-10');
do $test$
begin
 if not exists(select 1 from public.invoice_items) then raise exception 'Invoice items missing';end if;
 begin
  perform public.issue_monthly_invoice((select id from public.students where student_number='DEMO-2027-A005'),'2027-12-01','2027-12-10');
  raise exception 'Duplicate invoice accepted';
 exception when unique_violation then null;end;
end $test$;
reset role;
insert into storage.objects(bucket_id,name,owner_id)
 select 'transfer-receipts',id::text||'/qa-transaction.pdf',id::text from public.profiles where email='familia.demo.2027@educar.example';
select set_config('request.jwt.claim.sub', (select id::text from public.profiles where email='familia.demo.2027@educar.example'), true);
set local role authenticated;
do $test$
declare invoice uuid; items uuid[]; transfer uuid; repeated uuid;
begin
 select id into invoice from public.invoices where period='2027-12-01';
 select array_agg(id order by id) into items from public.invoice_items where invoice_id=invoice;
 transfer := public.submit_transfer(invoice,items,5000,'QA-TRANSACTION',auth.uid()::text||'/qa-transaction.pdf','qa-transaction.pdf');
 repeated := public.submit_transfer(invoice,items,5000,'QA-TRANSACTION',auth.uid()::text||'/qa-transaction.pdf','qa-transaction.pdf');
 if transfer <> repeated then raise exception 'Transfer not idempotent'; end if;
 if (select sum(paid_cents) from public.invoice_items where invoice_id=invoice) <> 0 then raise exception 'Pending transfer counted as paid'; end if;
end $test$;
reset role;
select set_config('request.jwt.claim.sub', (select id::text from public.profiles where email='director@educar.com'), true);
set local role authenticated;
select public.review_transfer((select id from public.transfer_submissions where reference='QA-TRANSACTION'),true);
do $test$ begin
 if (select sum(paid_cents) from public.invoice_items) <> 5000 then raise exception 'Approval allocation failed'; end if;
 begin
  perform public.review_transfer((select id from public.transfer_submissions where reference='QA-TRANSACTION'),true);
  raise exception 'Repeat review accepted';
 exception when raise_exception then if sqlerrm <> 'Transfer already reviewed' then raise;end if;end;
end $test$;
reset role;
select set_config('request.jwt.claim.sub', (select id::text from public.profiles where email='familia.demo.2027@educar.example'), true);
set local role authenticated;
do $test$
begin
 if (select count(*) from public.invoices) <> 1 then raise exception 'Family invoice isolation failed';end if;
 if exists(select 1 from public.billing_values) then raise exception 'Family can read private price config';end if;
 begin
 perform public.issue_monthly_invoice((select student_id from public.invoices limit 1),'2027-11-01','2027-11-10');
 raise exception 'Family issued invoice';
 exception when insufficient_privilege then null;end;
end $test$;
reset role;
select set_config('request.jwt.claim.sub', (select id::text from public.profiles where email='profesor@gmail.com'), true);
set local role authenticated;
do $test$ begin
 if exists(select 1 from public.invoices) then raise exception 'Teacher can see invoices';end if;
 if exists(select 1 from public.forum_discussions) then raise exception 'Teacher can see student forum';end if;
end $test$;
reset role;
rollback;
select 'PASS: forum creation/replies/votes/validation/RLS and billing issue/duplicate/family isolation; all writes rolled back' as acceptance;
