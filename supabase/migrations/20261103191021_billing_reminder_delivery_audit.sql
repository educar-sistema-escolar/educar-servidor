begin;
alter table public.billing_reminders
  add column attempts integer not null default 0 check (attempts >= 0),
  add column last_attempt_at timestamptz,
  add column last_error text;

-- Recheck current family links and approved balances immediately before delivery.
create or replace function public.refresh_billing_reminder(p_reminder uuid)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public as $$
declare result jsonb;
begin
 if auth.role() is distinct from 'service_role' then raise exception 'Server service role required' using errcode='42501'; end if;
 select jsonb_build_object('recipient',profile.email,'payload',jsonb_build_object(
   'name',profile.full_name,'total_cents',sum(item.amount_cents-item.paid_cents),
   'items',jsonb_agg(jsonb_build_object('invoice_id',invoice.id,'student_id',student.id,
     'student_name',student_person.first_name||' '||student_person.last_name,'period',invoice.period,
     'due_date',invoice.due_date,'label',item.label,'amount_cents',item.amount_cents,'paid_cents',item.paid_cents))))
 into result
 from public.billing_reminders reminder
 join public.profiles profile on profile.id=reminder.guardian_id
 join public.people person on person.profile_id=profile.id
 join (select distinct guardian_person_id,student_id from public.student_guardians where is_active) relationship on relationship.guardian_person_id=person.id
 join public.students student on student.id=relationship.student_id and student.is_active
 join public.people student_person on student_person.id=student.person_id
 join public.invoices invoice on invoice.student_id=student.id
 join public.invoice_items item on item.invoice_id=invoice.id
 where reminder.id=p_reminder and profile.is_active and profile.account_status='active'
   and profile.role::text in ('parent','guardian') and person.is_active
   and (reminder.kind='month_end' and invoice.period=date_trunc('month',reminder.reminder_date)::date
     or reminder.kind='debt' and invoice.period<=reminder.reminder_date and item.amount_cents>item.paid_cents)
 group by reminder.id,profile.id
 having reminder.kind='month_end' or sum(item.amount_cents-item.paid_cents)>0;
 return result;
end;$$;
revoke all on function public.refresh_billing_reminder(uuid) from public,authenticated,anon;
grant execute on function public.refresh_billing_reminder(uuid) to service_role;
commit;
