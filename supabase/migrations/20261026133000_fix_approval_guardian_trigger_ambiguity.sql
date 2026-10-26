-- Approval also fires the DNI guardian-link trigger. Avoid its ON CONFLICT name collision.
create or replace function public.link_approved_enrollment_guardian_for_request(
  p_request public.enrollment_requests
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  request_row public.enrollment_requests%rowtype;
  resolved_guardian_person_id uuid;
  first_name_value text;
  last_name_value text;
  primary_value boolean;
  relationship_value text;
begin
  request_row := p_request;

  if request_row.status <> 'approved' or request_row.student_id is null then
    return;
  end if;

  perform 1
  from public.students student
  where student.id = request_row.student_id
    and student.is_active = true
  for update;

  if not found then
    raise exception 'Approved enrollment requires an active student'
      using errcode = 'check_violation';
  end if;

  select person.id into resolved_guardian_person_id
  from public.people person
  where regexp_replace(coalesce(person.dni, ''), '[^0-9]', '', 'g') = request_row.responsible_dni
  for update;

  if resolved_guardian_person_id is null then
    first_name_value := split_part(regexp_replace(btrim(request_row.responsible_full_name), '\s+', ' ', 'g'), ' ', 1);
    last_name_value := nullif(btrim(substr(regexp_replace(btrim(request_row.responsible_full_name), '\s+', ' ', 'g'), length(first_name_value) + 1)), '');

    insert into public.people (first_name, last_name, email, phone, dni)
    values (
      first_name_value,
      coalesce(last_name_value, first_name_value),
      request_row.email,
      request_row.phone,
      request_row.responsible_dni
    )
    on conflict do nothing
    returning id into resolved_guardian_person_id;

    if resolved_guardian_person_id is null then
      select person.id into resolved_guardian_person_id
      from public.people person
      where regexp_replace(coalesce(person.dni, ''), '[^0-9]', '', 'g') = request_row.responsible_dni
      for update;
    end if;
  end if;

  if resolved_guardian_person_id is null then
    raise exception 'Responsible identity could not be linked by DNI'
      using errcode = 'unique_violation';
  end if;

  relationship_value := lower(regexp_replace(btrim(request_row.responsible_relation), '\s+', ' ', 'g'));
  select not exists (
    select 1
    from public.student_guardians relationship
    where relationship.student_id = request_row.student_id
      and relationship.is_active = true
      and relationship.is_primary = true
  ) into primary_value;

  insert into public.student_guardians (
    student_id,
    guardian_person_id,
    relationship_type,
    is_primary,
    is_active
  )
  values (
    request_row.student_id,
    resolved_guardian_person_id,
    relationship_value,
    primary_value,
    true
  )
  on conflict (student_id, guardian_person_id, lower(btrim(relationship_type)))
  do update set
    is_active = true,
    is_primary = (student_guardians.is_primary or excluded.is_primary)
      and not exists (
        select 1
        from public.student_guardians other_relationship
        where other_relationship.student_id = excluded.student_id
          and other_relationship.is_active = true
          and other_relationship.is_primary = true
          and other_relationship.id <> student_guardians.id
      ),
    updated_at = now();

  return;
end;
$$;
