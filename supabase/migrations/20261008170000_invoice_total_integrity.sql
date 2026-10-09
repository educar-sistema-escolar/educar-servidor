begin;
create or replace function public.validate_invoice_total() returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
begin
 perform 1 from public.invoices where id=new.invoice_id for update;
 if (select coalesce(sum(amount_cents),0) from public.invoice_items where invoice_id=new.invoice_id)>9007199254740991 then raise exception 'Invoice total exceeds safe monetary range' using errcode='23514';end if;return new;
end;$$;
create trigger invoice_items_total after insert or update on public.invoice_items for each row execute function public.validate_invoice_total();
commit;
