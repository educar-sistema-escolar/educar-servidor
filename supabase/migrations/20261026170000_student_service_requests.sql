-- Families request sport/transport services; superadmins review and assign
-- through the existing enrollment RPCs and their database validators.
create table public.student_service_requests (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete restrict,
  service_type text not null check (service_type in ('sport', 'transport')),
  academic_year integer not null check (academic_year between 1900 and 2200),
  requested_sport_group_id uuid references public.sport_groups(id) on delete restrict,
  requested_route_id uuid references public.transport_routes(id) on delete restrict,
  requested_stop_id uuid references public.transport_stops(id) on delete restrict,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  requested_by_profile_id uuid not null references public.profiles(id) on delete restrict,
  reviewed_by_profile_id uuid references public.profiles(id) on delete restrict,
  reviewed_at timestamptz,
  review_note text check (review_note is null or length(review_note) <= 500),
  assigned_sport_enrollment_id uuid references public.student_sport_enrollments(id) on delete restrict,
  assigned_transport_enrollment_id uuid references public.student_transport_enrollments(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (service_type = 'sport' and requested_sport_group_id is not null and requested_route_id is null and requested_stop_id is null and assigned_transport_enrollment_id is null)
    or
    (service_type = 'transport' and requested_sport_group_id is null and requested_route_id is not null and assigned_sport_enrollment_id is null)
  ),
  check (
    (status = 'approved' and ((service_type = 'sport' and assigned_sport_enrollment_id is not null) or (service_type = 'transport' and assigned_transport_enrollment_id is not null)))
    or (status <> 'approved' and assigned_sport_enrollment_id is null and assigned_transport_enrollment_id is null)
  )
);

create index student_service_requests_student_idx
  on public.student_service_requests(student_id, academic_year, status);
create index student_service_requests_review_idx
  on public.student_service_requests(service_type, created_at)
  where status = 'pending';

alter table public.student_service_requests enable row level security;
create policy "Families and superadmins can read service requests"
  on public.student_service_requests for select to authenticated
  using (
    (select public.is_active_user())
    and ((select public.is_active_superadmin()) or public.is_guardian_of_student(student_id))
  );
grant select on public.student_service_requests to authenticated;

create or replace function public.list_service_enrollment_availability(p_academic_year integer)
returns table(service_type text, service_id uuid, academic_year integer, capacity integer, occupied integer, available integer)
language plpgsql stable security definer set search_path = pg_catalog, public as $$
begin
  if not public.is_active_user() then
    raise exception 'Active account required' using errcode = 'insufficient_privilege';
  end if;
  if p_academic_year is null or p_academic_year not between 1900 and 2200 then
    raise exception 'Valid academic year required' using errcode = 'check_violation';
  end if;

  return query
    select 'sport'::text, group_row.id, group_row.academic_year, group_row.capacity,
      coalesce(enrolled.total, 0)::integer + coalesce(requested.total, 0)::integer,
      greatest(group_row.capacity - coalesce(enrolled.total, 0)::integer - coalesce(requested.total, 0)::integer, 0)
    from public.sport_groups group_row
    left join lateral (
      select count(*)::integer as total from public.student_sport_enrollments enrollment
      where enrollment.sport_group_id = group_row.id and enrollment.academic_year = p_academic_year and enrollment.is_active
    ) enrolled on true
    left join lateral (
      select count(*)::integer as total from public.student_service_requests request
      where request.requested_sport_group_id = group_row.id and request.academic_year = p_academic_year and request.status = 'pending'
    ) requested on true
    where group_row.is_active and group_row.academic_year = p_academic_year
    union all
    select 'transport'::text, route.id, p_academic_year, route.capacity,
      coalesce(enrolled.total, 0)::integer + coalesce(requested.total, 0)::integer,
      greatest(route.capacity - coalesce(enrolled.total, 0)::integer - coalesce(requested.total, 0)::integer, 0)
    from public.transport_routes route
    left join lateral (
      select count(*)::integer as total from public.student_transport_enrollments enrollment
      where enrollment.route_id = route.id and enrollment.academic_year = p_academic_year and enrollment.is_active
    ) enrolled on true
    left join lateral (
      select count(*)::integer as total from public.student_service_requests request
      where request.requested_route_id = route.id and request.academic_year = p_academic_year and request.status = 'pending'
    ) requested on true
    where route.is_active;
end;
$$;

create or replace function public.submit_student_service_request(
  p_student_id uuid,
  p_service_type text,
  p_academic_year integer,
  p_sport_group_id uuid default null,
  p_route_id uuid default null,
  p_stop_id uuid default null
)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  result_row public.student_service_requests%rowtype;
  sport_group public.sport_groups%rowtype;
  route public.transport_routes%rowtype;
  student_level uuid;
  current_count integer;
begin
  if not public.is_active_user() or not public.is_guardian_of_student(p_student_id) then
    raise exception 'Only a linked family member can request a student service' using errcode = 'insufficient_privilege';
  end if;
  if p_academic_year is null or p_academic_year not between 1900 and 2200 then
    raise exception 'Valid academic year required' using errcode = 'check_violation';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    p_student_id::text || ':' || p_academic_year::text,
    case when p_service_type = 'transport' then 814226 else 814225 end
  ));
  if not exists (
    select 1 from public.student_enrollments enrollment
    join public.courses course on course.id = enrollment.course_id
    where enrollment.student_id = p_student_id and enrollment.academic_year = p_academic_year
      and enrollment.is_active and course.is_active
  ) then
    raise exception 'An active student enrollment is required for the selected academic year' using errcode = 'check_violation';
  end if;

  if p_service_type = 'sport' then
    if p_sport_group_id is null or p_route_id is not null or p_stop_id is not null then
      raise exception 'Select one sport group only' using errcode = 'check_violation';
    end if;
    select * into sport_group from public.sport_groups where id = p_sport_group_id for update;
    if not found then
      raise exception 'Active sport group for the selected academic year required' using errcode = 'check_violation';
    end if;
    if not sport_group.is_active or sport_group.academic_year <> p_academic_year then
      raise exception 'Active sport group for the selected academic year required' using errcode = 'check_violation';
    end if;
    if sport_group.educational_level_id is not null and not exists (
      select 1 from public.student_enrollments enrollment
      join public.courses course on course.id = enrollment.course_id
      where enrollment.student_id = p_student_id and enrollment.academic_year = p_academic_year
        and enrollment.is_active and course.is_active
        and course.educational_level_id = sport_group.educational_level_id
    ) then
      raise exception 'Sport group is not compatible with the student educational level' using errcode = 'check_violation';
    end if;
    if exists (
      select 1 from public.student_sport_enrollments enrollment
      join public.sport_groups existing_group on existing_group.id = enrollment.sport_group_id
      where enrollment.student_id = p_student_id and enrollment.academic_year = p_academic_year
        and enrollment.is_active and existing_group.sport_id = sport_group.sport_id
    ) or exists (
      select 1 from public.student_service_requests request
      join public.sport_groups existing_group on existing_group.id = request.requested_sport_group_id
      where request.student_id = p_student_id and request.academic_year = p_academic_year
        and request.service_type = 'sport' and request.status = 'pending'
        and existing_group.sport_id = sport_group.sport_id
    ) then
      raise exception 'Student already has or requested this sport' using errcode = 'unique_violation';
    end if;
    select count(*) into current_count from public.student_sport_enrollments
      where student_id = p_student_id and academic_year = p_academic_year and is_active;
    current_count := current_count + (select count(*) from public.student_service_requests
      where student_id = p_student_id and academic_year = p_academic_year and service_type = 'sport' and status = 'pending');
    if current_count >= 2 then
      raise exception 'A student can have at most two active or pending sports' using errcode = 'check_violation';
    end if;
    if exists (
      select 1
      from (
        select enrollment.sport_group_id from public.student_sport_enrollments enrollment
        where enrollment.student_id = p_student_id and enrollment.academic_year = p_academic_year and enrollment.is_active
        union all
        select request.requested_sport_group_id from public.student_service_requests request
        where request.student_id = p_student_id and request.academic_year = p_academic_year
          and request.service_type = 'sport' and request.status = 'pending'
      ) selected_group
      join public.sport_group_schedules old_schedule on old_schedule.sport_group_id = selected_group.sport_group_id and old_schedule.is_active
      join public.sport_group_schedules new_schedule on new_schedule.sport_group_id = sport_group.id and new_schedule.is_active
      where old_schedule.day_of_week = new_schedule.day_of_week
        and old_schedule.starts_at < new_schedule.ends_at and new_schedule.starts_at < old_schedule.ends_at
    ) then
      raise exception 'Sport enrollment conflicts with another active or pending sport schedule' using errcode = 'exclusion_violation';
    end if;
    select count(*) into current_count from public.student_sport_enrollments
      where sport_group_id = sport_group.id and academic_year = p_academic_year and is_active;
    current_count := current_count + (select count(*) from public.student_service_requests
      where requested_sport_group_id = sport_group.id and academic_year = p_academic_year and status = 'pending');
    if current_count >= sport_group.capacity then
      raise exception 'Sport group capacity reached' using errcode = 'check_violation';
    end if;
  elsif p_service_type = 'transport' then
    if p_route_id is null or p_sport_group_id is not null then
      raise exception 'Select one transport route only' using errcode = 'check_violation';
    end if;
    select * into route from public.transport_routes where id = p_route_id for update;
    if not found then
      raise exception 'Active transport route required' using errcode = 'check_violation';
    end if;
    if not route.is_active then
      raise exception 'Active transport route required' using errcode = 'check_violation';
    end if;
    if p_stop_id is not null and not exists (
      select 1 from public.transport_stops where id = p_stop_id and route_id = route.id and is_active
    ) then
      raise exception 'Transport stop must belong to the selected active route' using errcode = 'check_violation';
    end if;
    if exists (select 1 from public.student_transport_enrollments
        where student_id = p_student_id and academic_year = p_academic_year and is_active)
      or exists (select 1 from public.student_service_requests
        where student_id = p_student_id and academic_year = p_academic_year and service_type = 'transport' and status = 'pending') then
      raise exception 'Student already has or requested transport for this academic year' using errcode = 'unique_violation';
    end if;
    select count(*) into current_count from public.student_transport_enrollments
      where route_id = route.id and academic_year = p_academic_year and is_active;
    current_count := current_count + (select count(*) from public.student_service_requests
      where requested_route_id = route.id and academic_year = p_academic_year and status = 'pending');
    if current_count >= route.capacity then
      raise exception 'Transport route capacity reached' using errcode = 'check_violation';
    end if;
  else
    raise exception 'Unsupported student service type' using errcode = 'check_violation';
  end if;

  insert into public.student_service_requests(
    student_id, service_type, academic_year, requested_sport_group_id,
    requested_route_id, requested_stop_id, requested_by_profile_id
  ) values (
    p_student_id, p_service_type, p_academic_year, p_sport_group_id,
    p_route_id, p_stop_id, auth.uid()
  ) returning * into result_row;
  return to_jsonb(result_row);
end;
$$;

create or replace function public.review_student_service_request(
  p_request_id uuid,
  p_action text,
  p_assigned_service_id uuid default null,
  p_assigned_stop_id uuid default null,
  p_note text default null
)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  request_row public.student_service_requests%rowtype;
  enrollment_result jsonb;
begin
  if not public.is_active_superadmin() then
    raise exception 'Active superadmin role required' using errcode = 'insufficient_privilege';
  end if;
  if p_action is null or p_action not in ('approve', 'reject') then
    raise exception 'Unsupported service request decision' using errcode = 'check_violation';
  end if;
  if p_note is not null and length(btrim(p_note)) > 500 then
    raise exception 'Review note must be 500 characters or fewer' using errcode = 'check_violation';
  end if;
  select * into request_row from public.student_service_requests where id = p_request_id for update;
  if not found then
    raise exception 'Pending service request required' using errcode = 'check_violation';
  end if;
  if request_row.status <> 'pending' then
    raise exception 'Pending service request required' using errcode = 'check_violation';
  end if;

  if p_action = 'reject' then
    update public.student_service_requests set status = 'rejected', reviewed_by_profile_id = auth.uid(),
      reviewed_at = now(), review_note = nullif(btrim(p_note), ''), updated_at = now()
    where id = request_row.id returning * into request_row;
    return to_jsonb(request_row);
  end if;

  if p_assigned_service_id is null then
    raise exception 'Select the service assignment before approving' using errcode = 'check_violation';
  end if;
  if request_row.service_type = 'sport' then
    if p_assigned_stop_id is not null then raise exception 'Sport assignment cannot include a transport stop' using errcode = 'check_violation'; end if;
    if not exists (select 1 from public.sport_groups where id = p_assigned_service_id and academic_year = request_row.academic_year and is_active) then
      raise exception 'Active sport group for the requested academic year required' using errcode = 'check_violation';
    end if;
    enrollment_result := public.enroll_student_in_sport_group(request_row.student_id, p_assigned_service_id);
    update public.student_service_requests set status = 'approved', reviewed_by_profile_id = auth.uid(),
      reviewed_at = now(), review_note = nullif(btrim(p_note), ''),
      assigned_sport_enrollment_id = (enrollment_result->>'id')::uuid, updated_at = now()
    where id = request_row.id returning * into request_row;
  else
    enrollment_result := public.enroll_student_in_transport(
      request_row.student_id, p_assigned_service_id, p_assigned_stop_id, request_row.academic_year
    );
    update public.student_service_requests set status = 'approved', reviewed_by_profile_id = auth.uid(),
      reviewed_at = now(), review_note = nullif(btrim(p_note), ''),
      assigned_transport_enrollment_id = (enrollment_result->>'id')::uuid, updated_at = now()
    where id = request_row.id returning * into request_row;
  end if;
  return to_jsonb(request_row);
end;
$$;

revoke all on function public.list_service_enrollment_availability(integer) from public;
revoke all on function public.submit_student_service_request(uuid, text, integer, uuid, uuid, uuid) from public;
revoke all on function public.review_student_service_request(uuid, text, uuid, uuid, text) from public;
grant execute on function public.list_service_enrollment_availability(integer) to authenticated;
grant execute on function public.submit_student_service_request(uuid, text, integer, uuid, uuid, uuid) to authenticated;
grant execute on function public.review_student_service_request(uuid, text, uuid, uuid, text) to authenticated;

notify pgrst, 'reload schema';
