begin;
create table public.transfer_submissions (
 id uuid primary key default gen_random_uuid(), invoice_id uuid not null references public.invoices(id), guardian_id uuid not null references public.profiles(id),
 reference text not null check(length(btrim(reference)) between 1 and 100), amount_cents bigint not null check(amount_cents > 0), status text not null default 'pending' check(status in ('pending','approved','rejected')),
 created_at timestamptz not null default now(), unique(guardian_id,reference)
);
create table public.transfer_submission_items (
 submission_id uuid not null references public.transfer_submissions(id), item_id uuid not null references public.invoice_items(id), primary key(submission_id,item_id)
);
create table public.transfer_receipts (
 id uuid primary key default gen_random_uuid(), submission_id uuid not null references public.transfer_submissions(id), storage_path text not null unique,
 filename text not null check(length(filename) between 1 and 200), created_at timestamptz not null default now()
);
alter table public.transfer_submissions enable row level security;
alter table public.transfer_submission_items enable row level security;
alter table public.transfer_receipts enable row level security;
create policy "Families read submissions" on public.transfer_submissions for select to authenticated using(public.can_read_invoice(invoice_id));
create policy "Families read selected concepts" on public.transfer_submission_items for select to authenticated using(exists(select 1 from public.transfer_submissions s where s.id=submission_id));
create policy "Families read associated receipts" on public.transfer_receipts for select to authenticated using(exists(select 1 from public.transfer_submissions s where s.id=submission_id));
grant select on public.transfer_submissions,public.transfer_submission_items,public.transfer_receipts to authenticated;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('transfer-receipts','transfer-receipts',false,5242880,array['application/pdf','image/jpeg','image/png']) on conflict(id) do nothing;
create policy "Families upload private receipts" on storage.objects for insert to authenticated with check(bucket_id='transfer-receipts' and (storage.foldername(name))[1]=auth.uid()::text and exists(select 1 from public.profiles where id=auth.uid() and is_active and account_status='active' and role::text in ('parent','guardian')));
create policy "Families read own private receipt files" on storage.objects for select to authenticated using(bucket_id='transfer-receipts' and (storage.foldername(name))[1]=auth.uid()::text);
create or replace function public.submit_transfer(p_invoice uuid,p_items uuid[],p_amount bigint,p_reference text,p_path text,p_filename text) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare result uuid; outstanding bigint; item_count integer; existing public.transfer_submissions;
begin
 if not public.can_read_invoice(p_invoice) or not exists(select 1 from public.profiles where id=auth.uid() and role::text in ('parent','guardian') and is_active and account_status='active') then raise exception 'Invoice access denied' using errcode='42501'; end if;
 perform 1 from public.invoices where id=p_invoice for update;
 select * into existing from public.transfer_submissions where guardian_id=auth.uid() and reference=btrim(p_reference);
 if existing.id is not null then
  if existing.invoice_id=p_invoice and existing.amount_cents=p_amount
   and (select array_agg(item_id order by item_id) from public.transfer_submission_items where submission_id=existing.id)=(select array_agg(x order by x) from unnest(p_items) x)
   and exists(select 1 from public.transfer_receipts where submission_id=existing.id and storage_path=p_path and filename=p_filename)
  then return existing.id; end if;
  raise exception 'Transfer reference already belongs to a different operation';
 end if;
 if p_items is null or cardinality(p_items)=0 or cardinality(p_items)<>(select count(distinct x) from unnest(p_items) x) then raise exception 'Select distinct pending concepts'; end if;
 select count(*),sum(amount_cents-paid_cents) into item_count,outstanding from public.invoice_items where invoice_id=p_invoice and id=any(p_items) and amount_cents>paid_cents;
 if item_count<>cardinality(p_items) or p_amount is null or p_amount<=0 or p_amount>outstanding then raise exception 'Invalid selected concepts or amount'; end if;
 if exists(select 1 from public.transfer_submission_items si join public.transfer_submissions s on s.id=si.submission_id where si.item_id=any(p_items) and s.status='pending') then raise exception 'Selected concepts already have a pending transfer'; end if;
 if p_reference is null or length(btrim(p_reference)) not between 1 and 100 then raise exception 'Invalid transfer reference'; end if;
 if p_path is null or split_part(p_path,'/',1)<>auth.uid()::text or not exists(select 1 from storage.objects where bucket_id='transfer-receipts' and name=p_path and owner_id=auth.uid()::text) then raise exception 'Upload a receipt owned by the current user'; end if;
 if p_filename is null or length(p_filename) not between 1 and 200 then raise exception 'Invalid receipt filename'; end if;
 insert into public.transfer_submissions(invoice_id,guardian_id,reference,amount_cents) values(p_invoice,auth.uid(),btrim(p_reference),p_amount) returning id into result;
 insert into public.transfer_submission_items select result,unnest(p_items);
 insert into public.transfer_receipts(submission_id,storage_path,filename) values(result,p_path,p_filename);
 return result;
end; $$;
create or replace function public.attach_transfer_receipt(p_submission uuid,p_path text,p_filename text) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare result uuid;
begin
 if not exists(select 1 from public.transfer_submissions where id=p_submission and guardian_id=auth.uid() and status='pending' and public.can_read_invoice(invoice_id)) then raise exception 'Submission access denied' using errcode='42501'; end if;
 if split_part(p_path,'/',1)<>auth.uid()::text or not exists(select 1 from storage.objects where bucket_id='transfer-receipts' and name=p_path and owner_id=auth.uid()::text) then raise exception 'Invalid receipt ownership'; end if;
 insert into public.transfer_receipts(submission_id,storage_path,filename) values(p_submission,p_path,p_filename) returning id into result; return result;
end; $$;
revoke all on function public.submit_transfer(uuid,uuid[],bigint,text,text,text),public.attach_transfer_receipt(uuid,text,text) from public;
grant execute on function public.submit_transfer(uuid,uuid[],bigint,text,text,text),public.attach_transfer_receipt(uuid,text,text) to authenticated;
commit;
