-- Keep Auth's case-insensitive email identity aligned with the application profile.
do $$
begin
  if exists (
    select lower(btrim(email))
    from public.profiles
    group by lower(btrim(email))
    having count(*) > 1
  ) then
    raise exception 'Existing profiles contain duplicate normalized emails' using errcode = 'unique_violation';
  end if;
end $$;

create unique index if not exists profiles_email_normalized_unique_idx
  on public.profiles (lower(btrim(email)));
