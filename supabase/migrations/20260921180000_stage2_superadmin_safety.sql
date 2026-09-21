-- Stage 2: prevent locking the system out of its last active superadmin.

create or replace function public.prevent_last_superadmin_lockout()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.role = 'superadmin'
     and old.is_active = true
     and (new.role <> 'superadmin' or new.is_active = false)
     and not exists (
       select 1
       from public.profiles
       where id <> old.id
         and role = 'superadmin'
         and is_active = true
     ) then
    raise exception 'Cannot demote or deactivate the last active superadmin'
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

create trigger profiles_prevent_last_superadmin_lockout
  before update on public.profiles
  for each row execute function public.prevent_last_superadmin_lockout();
