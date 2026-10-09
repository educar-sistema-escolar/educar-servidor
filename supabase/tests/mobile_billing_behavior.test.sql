begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select plan(12);
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
('81000000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','billing.parent@example.test','',now(),'{"provider":"email"}','{}',now(),now()),
('81000000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','billing.admin@example.test','',now(),'{"provider":"email"}','{}',now(),now());
update public.profiles set role=case when id='81000000-0000-4000-8000-000000000001' then 'guardian'::public.app_role else 'superadmin'::public.app_role end,is_active=true,account_status='active' where id in ('81000000-0000-4000-8000-000000000001','81000000-0000-4000-8000-000000000002');
insert into public.people(id,profile_id,first_name,last_name,dni) values
('81000000-0000-4000-8000-000000000011','81000000-0000-4000-8000-000000000001','Billing','Parent','81000001'),
('81000000-0000-4000-8000-000000000012',null,'Billing','Child','81000002'),
('81000000-0000-4000-8000-000000000013',null,'Unrelated','Child','81000003');
insert into public.students(id,person_id) values('81000000-0000-4000-8000-000000000021','81000000-0000-4000-8000-000000000012'),('81000000-0000-4000-8000-000000000022','81000000-0000-4000-8000-000000000013');
insert into public.student_guardians(student_id,guardian_person_id,relationship_type) values('81000000-0000-4000-8000-000000000021','81000000-0000-4000-8000-000000000011','parent');
insert into public.invoices(id,student_id,period,due_date) values('81000000-0000-4000-8000-000000000031','81000000-0000-4000-8000-000000000021','2026-10-01','2026-10-10'),('81000000-0000-4000-8000-000000000032','81000000-0000-4000-8000-000000000022','2026-10-01','2026-10-10');
insert into public.invoice_items(id,invoice_id,concept,label,amount_cents) values('81000000-0000-4000-8000-000000000041','81000000-0000-4000-8000-000000000031','tuition','Tuition',10000),('81000000-0000-4000-8000-000000000042','81000000-0000-4000-8000-000000000032','tuition','Tuition',10000);
insert into storage.objects(bucket_id,name,owner_id) values('transfer-receipts','81000000-0000-4000-8000-000000000001/test.pdf','81000000-0000-4000-8000-000000000001');
select set_config('request.jwt.claim.sub','81000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claim.role','authenticated',true);
set local role authenticated;
select is((select count(*) from public.invoices),1::bigint,'Parent sees only linked child invoices');
select throws_ok($$select public.submit_transfer('81000000-0000-4000-8000-000000000032',array['81000000-0000-4000-8000-000000000042']::uuid[],5000,'foreign','81000000-0000-4000-8000-000000000001/test.pdf','test.pdf')$$,'42501','Invoice access denied','Foreign invoice denied');
select throws_ok($$select public.submit_transfer('81000000-0000-4000-8000-000000000031',array['81000000-0000-4000-8000-000000000042']::uuid[],5000,'cross','81000000-0000-4000-8000-000000000001/test.pdf','test.pdf')$$,'P0001','Invalid selected concepts or amount','Cross-invoice concepts denied');
select lives_ok($$select public.submit_transfer('81000000-0000-4000-8000-000000000031',array['81000000-0000-4000-8000-000000000041']::uuid[],5000,'BANK-TEST','81000000-0000-4000-8000-000000000001/test.pdf','test.pdf')$$,'Valid partial transfer recorded');
select is((select status from public.transfer_submissions where reference='BANK-TEST'),'pending','Upload never settles debt');
select is((select paid_cents from public.invoice_items where id='81000000-0000-4000-8000-000000000041'),0::bigint,'Pending transfer leaves paid cents unchanged');
select lives_ok($$select public.submit_transfer('81000000-0000-4000-8000-000000000031',array['81000000-0000-4000-8000-000000000041']::uuid[],5000,'BANK-TEST','81000000-0000-4000-8000-000000000001/test.pdf','test.pdf')$$,'Identical retry is idempotent');
select is((select count(*) from public.transfer_submissions where reference='BANK-TEST'),1::bigint,'Retry creates no duplicate');
select throws_ok($$select public.submit_transfer('81000000-0000-4000-8000-000000000031',array['81000000-0000-4000-8000-000000000041']::uuid[],4000,'BANK-TEST','81000000-0000-4000-8000-000000000001/test.pdf','test.pdf')$$,'P0001','Transfer reference already belongs to a different operation','Changed duplicate payload rejected');
reset role;
select set_config('request.jwt.claim.sub','81000000-0000-4000-8000-000000000002',true);
set local role authenticated;
select lives_ok($$select public.review_transfer((select id from public.transfer_submissions where reference='BANK-TEST'),true)$$,'Admin approves pending transfer');
select is((select paid_cents from public.invoice_items where id='81000000-0000-4000-8000-000000000041'),5000::bigint,'Approved amount allocated exactly once');
reset role;
update public.profiles set is_active=false where id='81000000-0000-4000-8000-000000000001';
select set_config('request.jwt.claim.sub','81000000-0000-4000-8000-000000000001',true);
set local role authenticated;
select throws_ok($$select public.submit_transfer('81000000-0000-4000-8000-000000000031',array['81000000-0000-4000-8000-000000000041']::uuid[],5000,'INACTIVE','81000000-0000-4000-8000-000000000001/test.pdf','test.pdf')$$,'42501','Invoice access denied','Inactive parent submission denied');
select * from finish();
rollback;
