-- Keep the PL/pgSQL variable distinct from the ON CONFLICT column name.
create or replace function public.link_student_guardian(
  p_student_id uuid,
  p_guardian_profile_id uuid,
  p_relationship_type text,
  p_is_primary boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  resolved_guardian_person_id uuid;
  relationship_id uuid;
  relationship_value text;
begin
  if not public.is_active_superadmin() then
    raise exception 'Active superadmin role required' using errcode = 'insufficient_privilege';
  end if;

  relationship_value := lower(regexp_replace(btrim(coalesce(p_relationship_type, '')), '\s+', ' ', 'g'));

  if p_student_id is null or p_guardian_profile_id is null or length(relationship_value) < 2 or length(relationship_value) > 80 then
    raise exception 'Guardian relationship data is invalid' using errcode = 'invalid_parameter_value';
  end if;

  if not exists (
    select 1 from public.students
    where id = p_student_id and is_active = true
  ) then
    raise exception 'Active student required' using errcode = 'no_data_found';
  end if;

  select person.id into resolved_guardian_person_id
  from public.profiles profile
  join public.people person on person.profile_id = profile.id
  where profile.id = p_guardian_profile_id
    and profile.is_active = true
    and profile.role::text in ('guardian', 'parent')
    and person.is_active = true
  for update;

  if resolved_guardian_person_id is null then
    raise exception 'Active guardian profile required' using errcode = 'invalid_parameter_value';
  end if;

  if p_is_primary then
    update public.student_guardians
    set is_primary = false,
        updated_at = now()
    where student_id = p_student_id
      and is_primary = true;
  end if;

  insert into public.student_guardians (
    student_id,
    guardian_person_id,
    relationship_type,
    is_primary,
    is_active
  )
  values (
    p_student_id,
    resolved_guardian_person_id,
    relationship_value,
    p_is_primary,
    true
  )
  on conflict (student_id, guardian_person_id, relationship_type)
  do update set
    is_primary = excluded.is_primary,
    is_active = true,
    updated_at = now()
  returning id into relationship_id;

  return jsonb_build_object(
    'id', relationship_id,
    'student_id', p_student_id,
    'guardian_person_id', resolved_guardian_person_id,
    'relationship_type', relationship_value,
    'is_primary', p_is_primary
  );
end;
$$;
