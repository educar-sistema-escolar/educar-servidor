begin;
create table public.billing_reminders (
 id uuid primary key default gen_random_uuid(), guardian_id uuid not null references public.profiles(id), kind text not null check(kind in ('month_end','debt')),
 reminder_date date not null, recipient text not null, payload jsonb not null, status text not null default 'ready' check(status in ('ready','sending','sent','failed')),
 provider_id text, created_at timestamptz not null default now(), unique(guardian_id,kind,reminder_date)
);
alter table public.billing_reminders enable row level security;
create policy "Billing admins read reminder outcomes" on public.billing_reminders for select to authenticated using(public.is_billing_admin());
grant select on public.billing_reminders to authenticated;
create or replace function public.prepare_billing_reminders(p_date date) returns integer language plpgsql security definer set search_path=pg_catalog,public as $$
declare last_business date; reminder_kind text; affected integer;
begin
 if auth.role() is distinct from 'service_role' then raise exception 'Server service role required' using errcode='42501'; end if;
 last_business=(date_trunc('month',p_date)+interval '1 month - 1 day')::date;
 while extract(isodow from last_business)>5 loop last_business=last_business-1; end loop;
 reminder_kind=case when p_date=last_business then 'month_end' when extract(day from p_date)=20 then 'debt' else null end;
 if reminder_kind is null then return 0; end if;
 insert into public.billing_reminders(guardian_id,kind,reminder_date,recipient,payload)
 select profile.id,reminder_kind,p_date,profile.email,jsonb_build_object('name',profile.full_name,'total_cents',sum(item.amount_cents-item.paid_cents),'items',jsonb_agg(jsonb_build_object('invoice_id',invoice.id,'student_id',invoice.student_id,'period',invoice.period,'label',item.label,'amount_cents',item.amount_cents,'paid_cents',item.paid_cents)))
 from public.profiles profile join public.people person on person.profile_id=profile.id join (select distinct guardian_person_id,student_id from public.student_guardians where is_active) relationship on relationship.guardian_person_id=person.id join public.students student on student.id=relationship.student_id and student.is_active join public.invoices invoice on invoice.student_id=student.id join public.invoice_items item on item.invoice_id=invoice.id
 where profile.is_active and profile.account_status='active' and profile.role::text in ('parent','guardian') and person.is_active and item.amount_cents>item.paid_cents and invoice.period<=p_date
 group by profile.id having sum(item.amount_cents-item.paid_cents)>0 on conflict(guardian_id,kind,reminder_date) do nothing;
 get diagnostics affected=row_count;return affected;
end;$$;
revoke all on function public.prepare_billing_reminders(date) from public,authenticated;
grant execute on function public.prepare_billing_reminders(date) to service_role;
commit;
