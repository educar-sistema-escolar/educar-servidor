begin;
create or replace function public.can_delete_unattached_receipt(p_path text) returns boolean language sql stable security definer set search_path=pg_catalog,public as $$
 select exists(select 1 from public.profiles where id=auth.uid() and is_active and account_status='active' and role::text in ('parent','guardian'))
 and split_part(p_path,'/',1)=auth.uid()::text
 and exists(select 1 from storage.objects where bucket_id='transfer-receipts' and name=p_path and owner_id=auth.uid()::text)
 and not exists(select 1 from public.transfer_receipts where storage_path=p_path);
$$;
revoke all on function public.can_delete_unattached_receipt(text) from public;
grant execute on function public.can_delete_unattached_receipt(text) to authenticated;
drop policy "Families remove unattached receipt uploads" on storage.objects;
create policy "Families remove unattached receipt uploads" on storage.objects for delete to authenticated using(bucket_id='transfer-receipts' and public.can_delete_unattached_receipt(name));
commit;
