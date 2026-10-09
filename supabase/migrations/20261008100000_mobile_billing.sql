begin;
create table public.billing_values (
 id uuid primary key default gen_random_uuid(), concept text not null check(concept in ('tuition','sport','transport','dining')),
 service_id uuid, label text not null check(length(btrim(label)) between 1 and 120), amount_cents bigint not null check(amount_cents > 0), effective_from date not null,
 unique(concept,service_id,effective_from)
);
create table public.invoices (
 id uuid primary key default gen_random_uuid(), student_id uuid not null references public.students(id), period date not null, due_date date not null,
 created_at timestamptz not null default now(), unique(student_id,period), check(due_date >= period)
);
create table public.invoice_items (
 id uuid primary key default gen_random_uuid(), invoice_id uuid not null references public.invoices(id), concept text not null check(concept in ('tuition','sport','transport','dining')),
 service_id uuid, label text not null check(length(btrim(label)) between 1 and 120), amount_cents bigint not null check(amount_cents > 0), paid_cents bigint not null default 0 check(paid_cents >= 0 and paid_cents <= amount_cents)
);
create or replace function public.can_read_invoice(p_invoice uuid) returns boolean language sql stable security definer set search_path=pg_catalog,public as $$
 select exists(select 1 from public.invoices i join public.profiles p on p.id=auth.uid() where i.id=p_invoice and p.is_active and p.account_status='active' and (p.role::text in ('superadmin','admin') or public.is_guardian_of_student(i.student_id)));
$$;
create or replace function public.is_billing_admin() returns boolean language sql stable security definer set search_path=pg_catalog,public as $$
 select exists(select 1 from public.profiles where id=auth.uid() and is_active and account_status='active' and role::text in ('superadmin','admin'));
$$;
alter table public.billing_values enable row level security;
alter table public.invoices enable row level security;
alter table public.invoice_items enable row level security;
create policy "Billing admins configure values" on public.billing_values for all to authenticated using(public.is_billing_admin()) with check(public.is_billing_admin());
create policy "Families read own invoices" on public.invoices for select to authenticated using(public.can_read_invoice(id));
create policy "Families read own invoice items" on public.invoice_items for select to authenticated using(public.can_read_invoice(invoice_id));
create policy "Billing admins issue invoices" on public.invoices for insert to authenticated with check(public.is_billing_admin());
create policy "Billing admins issue price snapshots" on public.invoice_items for insert to authenticated with check(public.is_billing_admin());
grant select,insert,update,delete on public.billing_values to authenticated;
grant select,insert on public.invoices,public.invoice_items to authenticated;
revoke all on function public.can_read_invoice(uuid),public.is_billing_admin() from public;
grant execute on function public.can_read_invoice(uuid),public.is_billing_admin() to authenticated;
comment on column public.invoice_items.amount_cents is 'Immutable issued price snapshot; changes to configured values never reprice existing invoices.';
commit;
