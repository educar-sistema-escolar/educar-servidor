-- Keep the one-argument report RPC unambiguous for existing clients and SQL checks.
-- The filtered implementation previously had a default jsonb argument, which made
-- get_admin_report('code') ambiguous once both overloads existed.

alter function public.get_admin_report(text, jsonb)
  rename to get_admin_report_with_filters;

create or replace function public.get_admin_report(
  p_report_code text,
  p_filters jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  return public.get_admin_report_with_filters(p_report_code, p_filters);
end;
$$;

grant execute on function public.get_admin_report(text, jsonb) to authenticated;
revoke execute on function public.get_admin_report(text, jsonb) from public;
