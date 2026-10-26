-- Read-only evidence for CentroEducativo. Does not issue invoices or change data.
select jsonb_build_object(
 'students',(select count(*) from students),
 'teachers',(select count(*) from teachers),
 'requests',(select count(*) from enrollment_requests),
 'levels',(select count(*) from educational_levels),
 'courses',(select count(*) from courses),
 'subjects',(select count(*) from subjects),
 'posts',(select count(*) from forum_discussions),
 'replies',(select count(*) from forum_replies),
 'prices',(select count(*) from billing_values),
 'invoices',(select count(*) from invoices),
 'transfers',(select jsonb_agg(jsonb_build_object('id',id,'reference',reference,'status',status)) from transfer_submissions),
 'receipts',(select count(*) from transfer_receipts),
 'receipt_objects',(select count(*) from storage.objects where bucket_id='transfer-receipts'),
 'bucket_private',(select not public from storage.buckets where id='transfer-receipts'),
 'rls_enabled',(select bool_and(relrowsecurity) from pg_class where oid in
 ('public.forum_discussions'::regclass,'public.forum_replies'::regclass,
 'public.billing_values'::regclass,'public.invoices'::regclass,
 'public.invoice_items'::regclass,'public.transfer_submissions'::regclass,
 'public.transfer_receipts'::regclass)),
 'temporary_rows',(select count(*) from educational_levels where code='QA4-UI-TEMP')
 +(select count(*) from courses where code='QA4-UI-TEMP')
 +(select count(*) from subjects where code='QA4-UI-TEMP')
 +(select count(*) from people where dni in ('49999043','49999044'))
 +(select count(*) from enrollment_requests where student_dni='49999044')
) as postflight;

select s.student_number,i.id,i.period,i.due_date,
 sum(it.amount_cents) as total_cents,sum(it.paid_cents) as paid_cents,
 case when bool_and(it.paid_cents=it.amount_cents) then 'complete' else 'incomplete' end as status
from invoices i join students s on s.id=i.student_id join invoice_items it on it.invoice_id=i.id
where s.student_number in ('DEMO-2027-A005','DEMO-2027-A010')
 and i.period in ('2027-03-01','2027-04-01')
group by s.student_number,i.id order by s.student_number,i.period;
