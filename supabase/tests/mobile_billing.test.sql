begin;
select plan(4);
select has_table('public','invoices');
select has_table('public','invoice_items');
select has_column('public','invoice_items','amount_cents');
select ok((select relrowsecurity from pg_class where oid='public.invoices'::regclass),'Invoices require RLS');
select * from finish();
rollback;
