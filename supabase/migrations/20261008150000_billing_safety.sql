begin;
create policy "Billing admins inspect associated receipt files" on storage.objects for select to authenticated using(bucket_id='transfer-receipts' and public.is_billing_admin() and exists(select 1 from public.transfer_receipts r where r.storage_path=name));
create policy "Families remove unattached receipt uploads" on storage.objects for delete to authenticated using(bucket_id='transfer-receipts' and (storage.foldername(name))[1]=auth.uid()::text and not exists(select 1 from public.transfer_receipts r where r.storage_path=name));
create or replace function public.validate_billing_service() returns trigger language plpgsql set search_path=pg_catalog,public as $$
begin
 if new.concept='tuition' and new.service_id is not null or new.concept<>'tuition' and new.service_id is null then raise exception 'Service reference does not match billing concept'; end if;
 if new.concept='sport' and not exists(select 1 from public.sport_groups where id=new.service_id and is_active) or new.concept='transport' and not exists(select 1 from public.transport_routes where id=new.service_id and is_active) or new.concept='dining' and not exists(select 1 from public.dining_services where id=new.service_id and is_active) then raise exception 'Active billing service required'; end if;return new;
end;$$;
create trigger billing_values_service before insert or update on public.billing_values for each row execute function public.validate_billing_service();
commit;
