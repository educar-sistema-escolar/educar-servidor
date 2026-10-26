select jsonb_build_object(
 'new_migrations',(select jsonb_agg(jsonb_build_object('version',version,'md5',md5(replace(statements[1],E'\r\n',E'\n')))) from supabase_migrations.schema_migrations where version >= '20261026150000'),
 'students',(select count(*) from public.students),
 'teachers',(select count(*) from public.teachers),
 'family_children',(select count(*) from public.student_guardians g join public.people p on p.id=g.guardian_person_id join public.profiles a on a.id=p.profile_id where a.email='familia.demo.2027@educar.example' and g.is_active),
 'forum_rows',(select count(*) from public.forum_discussions),
 'reply_rows',(select count(*) from public.forum_replies),
 'billing_values',(select count(*) from public.billing_values),
 'invoices',(select count(*) from public.invoices),
 'transfers',(select count(*) from public.transfer_submissions),
 'receipts',(select count(*) from public.transfer_receipts),
 'rls',(select jsonb_object_agg(relname,relrowsecurity) from pg_class where relnamespace='public'::regnamespace and relname in ('forum_discussions','forum_replies','forum_discussion_votes','forum_reply_votes','billing_values','invoices','invoice_items','transfer_submissions','transfer_submission_items','transfer_receipts'))
) as postflight;