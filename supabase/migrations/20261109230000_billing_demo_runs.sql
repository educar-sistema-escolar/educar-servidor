begin;
create table if not exists public.billing_demo_runs (
  id uuid primary key default gen_random_uuid(),
  guardian_id uuid not null references public.profiles(id),
  source_reminder_id uuid not null references public.billing_reminders(id),
  kind text not null check (kind in ('debt','month_end')),
  reminder_date date not null,
  recipient text not null,
  status text not null default 'ready' check (status in ('ready','sending','sent','failed')),
  attempts integer not null default 0,
  last_attempt_at timestamptz,
  last_error text,
  provider_id text,
  created_at timestamptz not null default now(),
  requested_by uuid not null references public.profiles(id)
);
alter table public.billing_demo_runs enable row level security;
drop policy if exists "Billing admins read demo runs" on public.billing_demo_runs;
create policy "Billing admins read demo runs" on public.billing_demo_runs for select to authenticated using (public.is_billing_admin());
grant select on public.billing_demo_runs to authenticated;
grant select, update on public.billing_demo_runs to service_role;

create or replace function public.create_billing_demo_run(p_kind text) returns uuid
language plpgsql security definer set search_path=pg_catalog,public as $$
declare source public.billing_reminders%rowtype; result uuid;
begin
 if not public.is_billing_admin() then raise exception 'Administrator required' using errcode='42501'; end if;
 if p_kind not in ('debt','month_end') then raise exception 'Invalid demo kind'; end if;
 perform pg_advisory_xact_lock(hashtext('billing-demo'));
 if exists(select 1 from public.billing_demo_runs where created_at > now()-interval '60 seconds') then
   raise exception 'Esperá un minuto antes de otra prueba.';
 end if;
 if exists(select 1 from public.billing_demo_runs where status in ('ready','sending')) then
   raise exception 'Hay una prueba pendiente de revisión; no se puede repetir.';
 end if;
 if (select count(*) from public.billing_demo_runs where created_at > now()-interval '24 hours') >= 12 then
   raise exception 'Se alcanzó el límite de pruebas de las últimas 24 horas.';
 end if;
 select * into source from public.billing_reminders
 where guardian_id='00000000-0000-4000-8000-00000000e901' and kind=p_kind and status='sent'
 order by reminder_date desc limit 1;
 if source.id is null then raise exception 'No hay datos DEMO disponibles.'; end if;
 insert into public.billing_demo_runs(guardian_id,source_reminder_id,kind,reminder_date,recipient,requested_by)
 values(source.guardian_id,source.id,source.kind,source.reminder_date,source.recipient,auth.uid()) returning id into result;
 return result;
end;$$;
revoke all on function public.create_billing_demo_run(text) from public,anon;
grant execute on function public.create_billing_demo_run(text) to authenticated;
commit;
