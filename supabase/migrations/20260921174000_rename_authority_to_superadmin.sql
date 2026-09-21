-- Rename the existing administrative role without changing the current role model.
-- Existing authority profiles, including the Director, become superadmin.

alter type public.app_role
  rename value 'authority' to 'superadmin';

create or replace function public.is_authority()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles
    where id = auth.uid()
      and role = 'superadmin'
  );
$$;

alter function public.is_authority()
  rename to is_superadmin;

create or replace function public.is_active_authority()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles
    where id = auth.uid()
      and role = 'superadmin'
      and is_active = true
  );
$$;

alter function public.is_active_authority()
  rename to is_active_superadmin;

comment on column public.profiles.role is
  'Application role. Current administrative role: superadmin.';
