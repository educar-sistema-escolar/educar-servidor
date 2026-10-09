begin;
create or replace function public.billing_report(p_start date,p_end date) returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public as $$
declare result jsonb;
begin
 if not public.is_billing_admin() then raise exception 'Administrator required' using errcode='42501'; end if;
 if p_start is null or p_end is null or p_start>p_end then raise exception 'Invalid period'; end if;
 select jsonb_build_object(
 'income',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'student_id',i.student_id,'reference',t.reference,'amount_cents',t.amount_cents,'paid_at',t.reviewed_at)) from public.transfer_submissions t join public.invoices i on i.id=t.invoice_id where t.status='approved' and (t.reviewed_at at time zone 'America/Argentina/Buenos_Aires')::date between p_start and p_end),'[]'::jsonb),
 'invoices',coalesce((select jsonb_agg(row_to_json(summary)) from(select i.id,i.student_id,p.first_name||' '||p.last_name student_name,i.period,i.due_date,sum(it.amount_cents) total_cents,sum(it.paid_cents) paid_cents,case when sum(it.amount_cents)=sum(it.paid_cents) then 'complete' else 'incomplete' end status from public.invoices i join public.students s on s.id=i.student_id join public.people p on p.id=s.person_id join public.invoice_items it on it.invoice_id=i.id where i.period between p_start and p_end group by i.id,p.first_name,p.last_name) summary),'[]'::jsonb),
 'services',coalesce((select jsonb_agg(row_to_json(details)) from(select i.student_id,it.label,it.concept,it.amount_cents,it.paid_cents,sg.name group_name,sp.name sport,el.name level,teacher.first_name||' '||teacher.last_name teacher,tr.name route,(select jsonb_agg(jsonb_build_object('day',day_of_week,'start',starts_at,'end',ends_at)) from public.sport_group_schedules where sport_group_id=sg.id and is_active) schedules from public.invoice_items it join public.invoices i on i.id=it.invoice_id left join public.sport_groups sg on it.concept='sport' and sg.id=it.service_id left join public.sports sp on sp.id=sg.sport_id left join public.educational_levels el on el.id=sg.educational_level_id left join public.teachers t on t.id=sg.teacher_id left join public.people teacher on teacher.id=t.person_id left join public.transport_routes tr on it.concept='transport' and tr.id=it.service_id where i.period between p_start and p_end and it.concept in ('sport','transport')) details),'[]'::jsonb)
 ) into result;return result;
end;$$;
revoke all on function public.billing_report(date,date) from public;
grant execute on function public.billing_report(date,date) to authenticated;
commit;
