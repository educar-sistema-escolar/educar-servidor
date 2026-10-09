begin;
alter table public.transfer_submissions add column reviewed_at timestamptz;
create unique index billing_values_tuition_effective_idx on public.billing_values(concept,effective_from) where service_id is null;
alter table public.billing_values add constraint billing_values_safe_amount check(amount_cents<=9007199254740991);
alter table public.invoice_items add constraint invoice_items_safe_amount check(amount_cents<=9007199254740991);
alter table public.transfer_submissions add constraint transfers_safe_amount check(amount_cents<=9007199254740991);
create or replace function public.review_transfer(p_submission uuid,p_approve boolean) returns void language plpgsql security definer set search_path=pg_catalog,public as $$
declare submission public.transfer_submissions; item public.invoice_items; remaining bigint; allocation bigint;
begin
 if not public.is_billing_admin() then raise exception 'Administrator required' using errcode='42501'; end if;
 select * into submission from public.transfer_submissions where id=p_submission;
 if submission.id is null then raise exception 'Transfer not found'; end if;
 perform 1 from public.invoices where id=submission.invoice_id for update;
 select * into submission from public.transfer_submissions where id=p_submission for update;
 if submission.status<>'pending' then raise exception 'Transfer already reviewed'; end if;
 if p_approve is null then raise exception 'Review decision required'; end if;
 if p_approve then
  remaining=submission.amount_cents;
  if remaining>(select sum(i.amount_cents-i.paid_cents) from public.invoice_items i join public.transfer_submission_items si on si.item_id=i.id where si.submission_id=p_submission) then raise exception 'Transfer exceeds outstanding selected items'; end if;
  for item in select i.* from public.invoice_items i join public.transfer_submission_items si on si.item_id=i.id where si.submission_id=p_submission order by i.id for update of i loop
   allocation=least(remaining,item.amount_cents-item.paid_cents);
   update public.invoice_items set paid_cents=paid_cents+allocation where id=item.id;
   remaining=remaining-allocation;
  end loop;
  if remaining<>0 then raise exception 'Amount could not be allocated'; end if;
 end if;
 update public.transfer_submissions set reviewed_at=now(),status=case when p_approve then 'approved' else 'rejected' end where id=p_submission;
end;$$;
create or replace function public.issue_monthly_invoice(p_student uuid,p_period date,p_due date) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare result uuid;
begin
 if not public.is_billing_admin() then raise exception 'Administrator required' using errcode='42501'; end if;
 if p_period<>date_trunc('month',p_period)::date then raise exception 'Period must be the first day of a month'; end if;
 if not exists(select 1 from public.students where id=p_student and is_active) then raise exception 'Active student required'; end if;
 if not exists(select 1 from public.billing_values where concept='tuition' and service_id is null and effective_from<=p_period) then raise exception 'Configure tuition before issuing invoices'; end if;
 insert into public.invoices(student_id,period,due_date) values(p_student,p_period,p_due) returning id into result;
 insert into public.invoice_items(invoice_id,concept,service_id,label,amount_cents)
 select result,chosen.concept,chosen.service_id,chosen.label,chosen.amount_cents from (
  select distinct on (concept,service_id) * from public.billing_values v where effective_from<=p_period and (
   concept='tuition' and service_id is null
   or concept='sport' and exists(select 1 from public.student_sport_enrollments e where e.student_id=p_student and e.is_active and e.academic_year=extract(year from p_period) and e.sport_group_id=v.service_id)
   or concept='transport' and exists(select 1 from public.student_transport_enrollments e where e.student_id=p_student and e.is_active and e.academic_year=extract(year from p_period) and e.route_id=v.service_id)
   or concept='dining' and exists(select 1 from public.student_dining_enrollments e where e.student_id=p_student and e.is_active and e.academic_year=extract(year from p_period) and e.dining_service_id=v.service_id)
  ) order by concept,service_id,effective_from desc
 ) chosen;
 return result;
end;$$;
revoke all on function public.review_transfer(uuid,boolean),public.issue_monthly_invoice(uuid,date,date) from public;
grant execute on function public.review_transfer(uuid,boolean),public.issue_monthly_invoice(uuid,date,date) to authenticated;
commit;
