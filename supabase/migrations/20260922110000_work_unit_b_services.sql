-- Work unit B: sports, transport, and dining services.

create table public.sports (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (btrim(code) <> ''),
  name text not null unique check (btrim(name) <> ''),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.sport_groups (
  id uuid primary key default gen_random_uuid(),
  sport_id uuid not null references public.sports (id) on delete restrict,
  name text not null check (btrim(name) <> ''),
  educational_level_id uuid references public.educational_levels (id) on delete restrict,
  teacher_id uuid references public.teachers (id) on delete restrict,
  academic_year integer not null check (academic_year > 0),
  capacity integer not null check (capacity > 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (sport_id, name, academic_year)
);

create table public.sport_group_schedules (
  id uuid primary key default gen_random_uuid(),
  sport_group_id uuid not null references public.sport_groups (id) on delete restrict,
  day_of_week smallint not null check (day_of_week between 0 and 6),
  starts_at time not null,
  ends_at time not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (starts_at < ends_at)
);

create table public.student_sport_enrollments (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students (id) on delete restrict,
  sport_group_id uuid not null references public.sport_groups (id) on delete restrict,
  academic_year integer not null check (academic_year > 0),
  is_active boolean not null default true,
  enrolled_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index student_sport_enrollments_active_idx
  on public.student_sport_enrollments (student_id, sport_group_id, academic_year)
  where is_active = true;

create table public.transport_routes (
  id uuid primary key default gen_random_uuid(),
  route_number smallint not null unique check (route_number between 1 and 4),
  name text not null check (btrim(name) <> ''),
  capacity integer not null check (capacity > 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.transport_stops (
  id uuid primary key default gen_random_uuid(),
  route_id uuid not null references public.transport_routes (id) on delete restrict,
  name text not null check (btrim(name) <> ''),
  stop_order integer not null check (stop_order > 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (route_id, stop_order)
);

create table public.student_transport_enrollments (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students (id) on delete restrict,
  route_id uuid not null references public.transport_routes (id) on delete restrict,
  stop_id uuid references public.transport_stops (id) on delete restrict,
  academic_year integer not null check (academic_year > 0),
  is_active boolean not null default true,
  enrolled_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index student_transport_enrollments_active_idx
  on public.student_transport_enrollments (student_id, academic_year)
  where is_active = true;

create table public.dining_services (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (btrim(code) <> ''),
  name text not null check (btrim(name) <> ''),
  capacity integer not null check (capacity > 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.dining_slots (
  id uuid primary key default gen_random_uuid(),
  dining_service_id uuid not null references public.dining_services (id) on delete restrict,
  service_date date not null,
  capacity integer not null check (capacity > 0),
  is_available boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (dining_service_id, service_date)
);

create table public.student_dining_enrollments (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students (id) on delete restrict,
  dining_service_id uuid not null references public.dining_services (id) on delete restrict,
  academic_year integer not null check (academic_year > 0),
  is_active boolean not null default true,
  enrolled_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index student_dining_enrollments_active_idx
  on public.student_dining_enrollments (student_id, academic_year)
  where is_active = true;

create table public.dining_usage (
  id uuid primary key default gen_random_uuid(),
  dining_enrollment_id uuid not null references public.student_dining_enrollments (id) on delete restrict,
  service_date date not null,
  used boolean not null default true,
  created_at timestamptz not null default now(),
  unique (dining_enrollment_id, service_date)
);

create index student_sport_enrollments_student_idx
  on public.student_sport_enrollments (student_id, academic_year, is_active);
create index sport_group_schedules_group_idx
  on public.sport_group_schedules (sport_group_id, day_of_week, starts_at)
  where is_active = true;
create index student_transport_enrollments_route_idx
  on public.student_transport_enrollments (route_id, academic_year, is_active);
create index dining_usage_date_idx
  on public.dining_usage (service_date, used);

create or replace function public.validate_sport_group_schedule()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  group_year integer;
begin
  perform pg_advisory_xact_lock(814224);

  select academic_year into group_year
  from public.sport_groups
  where id = new.sport_group_id and is_active = true;

  if new.is_active and group_year is null then
    raise exception 'Active schedule requires an active sport group' using errcode = 'check_violation';
  end if;

  if new.is_active and exists (
    select 1 from public.sport_group_schedules current_schedule
    where current_schedule.id <> new.id
      and current_schedule.sport_group_id = new.sport_group_id
      and current_schedule.is_active
      and current_schedule.day_of_week = new.day_of_week
      and current_schedule.starts_at < new.ends_at
      and new.starts_at < current_schedule.ends_at
  ) then
    raise exception 'Sport group schedule overlaps an existing schedule' using errcode = 'exclusion_violation';
  end if;

  return new;
end;
$$;

create trigger sport_group_schedules_validate
  before insert or update on public.sport_group_schedules
  for each row execute function public.validate_sport_group_schedule();

create or replace function public.validate_student_sport_enrollment()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  group_row public.sport_groups%rowtype;
  student_level uuid;
  student_active boolean;
  current_count integer;
begin
  perform pg_advisory_xact_lock(hashtextextended(new.student_id::text || ':' || new.academic_year::text, 814225));

  select * into group_row from public.sport_groups where id = new.sport_group_id for update;
  select course.educational_level_id into student_level
  from public.student_enrollments enrollment
  join public.courses course on course.id = enrollment.course_id
  where enrollment.student_id = new.student_id
    and enrollment.academic_year = new.academic_year
    and enrollment.is_active
  limit 1;
  select is_active into student_active from public.students where id = new.student_id;

  if new.is_active and (
    not coalesce(group_row.is_active, false)
    or group_row.academic_year <> new.academic_year
    or not coalesce(student_active, false)
    or student_level is null
    or group_row.educational_level_id is not null and group_row.educational_level_id <> student_level
  ) then
    raise exception 'Active sport enrollment requires an active group and matching student course' using errcode = 'check_violation';
  end if;

  if new.is_active then
    select count(*) into current_count
    from public.student_sport_enrollments
    where student_id = new.student_id
      and academic_year = new.academic_year
      and is_active
      and id <> new.id;

    if current_count >= 2 then
      raise exception 'A student can have at most two active sports' using errcode = 'check_violation';
    end if;

    if exists (
      select 1
      from public.student_sport_enrollments other_enrollment
      join public.sport_groups other_group on other_group.id = other_enrollment.sport_group_id
      where other_enrollment.student_id = new.student_id
        and other_enrollment.academic_year = new.academic_year
        and other_enrollment.is_active
        and other_enrollment.id <> new.id
        and other_group.sport_id = group_row.sport_id
    ) then
      raise exception 'A student cannot enroll twice in the same sport' using errcode = 'unique_violation';
    end if;

    if exists (
      select 1
      from public.student_sport_enrollments other_enrollment
      join public.sport_group_schedules other_schedule on other_schedule.sport_group_id = other_enrollment.sport_group_id
      join public.sport_group_schedules new_schedule on new_schedule.sport_group_id = new.sport_group_id
      where other_enrollment.student_id = new.student_id
        and other_enrollment.academic_year = new.academic_year
        and other_enrollment.is_active
        and other_enrollment.id <> new.id
        and other_schedule.is_active and new_schedule.is_active
        and other_schedule.day_of_week = new_schedule.day_of_week
        and other_schedule.starts_at < new_schedule.ends_at
        and new_schedule.starts_at < other_schedule.ends_at
    ) then
      raise exception 'Sport enrollment conflicts with another active sport schedule' using errcode = 'exclusion_violation';
    end if;

    if group_row.capacity <= (
      select count(*) from public.student_sport_enrollments
      where sport_group_id = new.sport_group_id and academic_year = new.academic_year and is_active and id <> new.id
    ) then
      raise exception 'Sport group capacity reached' using errcode = 'check_violation';
    end if;
  end if;

  return new;
end;
$$;

create trigger student_sport_enrollments_validate
  before insert or update on public.student_sport_enrollments
  for each row execute function public.validate_student_sport_enrollment();

create or replace function public.validate_transport_enrollment()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  route_capacity integer;
  route_active boolean;
begin
  perform pg_advisory_xact_lock(hashtextextended(new.student_id::text || ':' || new.academic_year::text, 814226));
  select capacity, is_active into route_capacity, route_active
  from public.transport_routes where id = new.route_id for update;
  if new.is_active and not exists (select 1 from public.students where id = new.student_id and is_active) then
    raise exception 'Active transport enrollment requires an active student' using errcode = 'check_violation';
  end if;
  if new.is_active and not coalesce(route_active, false) then
    raise exception 'Active transport enrollment requires an active route' using errcode = 'check_violation';
  end if;
  if new.stop_id is not null and not exists (
    select 1 from public.transport_stops where id = new.stop_id and route_id = new.route_id and is_active
  ) then
    raise exception 'Transport stop must belong to the selected active route' using errcode = 'check_violation';
  end if;
  if new.is_active and route_capacity <= (
    select count(*) from public.student_transport_enrollments
    where route_id = new.route_id and academic_year = new.academic_year and is_active and id <> new.id
  ) then
    raise exception 'Transport route capacity reached' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger student_transport_enrollments_validate
  before insert or update on public.student_transport_enrollments
  for each row execute function public.validate_transport_enrollment();

create or replace function public.validate_dining_enrollment()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  service_capacity integer;
  service_active boolean;
begin
  perform pg_advisory_xact_lock(hashtextextended(new.student_id::text || ':' || new.academic_year::text, 814227));
  select capacity, is_active into service_capacity, service_active
  from public.dining_services where id = new.dining_service_id for update;
  if new.is_active and not exists (select 1 from public.students where id = new.student_id and is_active) then
    raise exception 'Active dining enrollment requires an active student' using errcode = 'check_violation';
  end if;
  if new.is_active and not coalesce(service_active, false) then
    raise exception 'Active dining enrollment requires an active service' using errcode = 'check_violation';
  end if;
  if new.is_active and service_capacity <= (
    select count(*) from public.student_dining_enrollments
    where dining_service_id = new.dining_service_id and academic_year = new.academic_year and is_active and id <> new.id
  ) then
    raise exception 'Dining service capacity reached' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger student_dining_enrollments_validate
  before insert or update on public.student_dining_enrollments
  for each row execute function public.validate_dining_enrollment();

create or replace function public.enroll_student_in_sport_group(p_student_id uuid, p_sport_group_id uuid)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare result_row public.student_sport_enrollments%rowtype; group_year integer;
begin
  if not public.is_active_superadmin() then raise exception 'Active superadmin role required' using errcode = 'insufficient_privilege'; end if;
  select academic_year into group_year from public.sport_groups where id = p_sport_group_id;
  if group_year is null then raise exception 'Sport group not found' using errcode = 'check_violation'; end if;
  insert into public.student_sport_enrollments (student_id, sport_group_id, academic_year)
  values (p_student_id, p_sport_group_id, group_year) returning * into result_row;
  return to_jsonb(result_row);
end; $$;

create or replace function public.enroll_student_in_transport(p_student_id uuid, p_route_id uuid, p_stop_id uuid default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare result_row public.student_transport_enrollments%rowtype;
begin
  if not public.is_active_superadmin() then raise exception 'Active superadmin role required' using errcode = 'insufficient_privilege'; end if;
  insert into public.student_transport_enrollments (student_id, route_id, stop_id, academic_year)
  values (p_student_id, p_route_id, p_stop_id, extract(year from current_date)::integer) returning * into result_row;
  return to_jsonb(result_row);
end; $$;

create or replace function public.enroll_student_in_dining(p_student_id uuid, p_dining_service_id uuid, p_academic_year integer)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare result_row public.student_dining_enrollments%rowtype;
begin
  if not public.is_active_superadmin() then raise exception 'Active superadmin role required' using errcode = 'insufficient_privilege'; end if;
  insert into public.student_dining_enrollments (student_id, dining_service_id, academic_year)
  values (p_student_id, p_dining_service_id, p_academic_year) returning * into result_row;
  return to_jsonb(result_row);
end; $$;

create or replace function public.deactivate_student_service_enrollment(p_table text, p_id uuid)
returns void language plpgsql security definer set search_path = pg_catalog, public as $$
begin
  if not public.is_active_superadmin() then raise exception 'Active superadmin role required' using errcode = 'insufficient_privilege'; end if;
  if p_table = 'sport' then update public.student_sport_enrollments set is_active = false where id = p_id;
  elsif p_table = 'transport' then update public.student_transport_enrollments set is_active = false where id = p_id;
  elsif p_table = 'dining' then update public.student_dining_enrollments set is_active = false where id = p_id;
  else raise exception 'Unsupported service enrollment'; end if;
end; $$;

create or replace function public.record_dining_usage(p_dining_enrollment_id uuid, p_service_date date, p_used boolean default true)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare result_row public.dining_usage%rowtype;
begin
  if not public.is_active_superadmin() then raise exception 'Active superadmin role required' using errcode = 'insufficient_privilege'; end if;
  if not exists (select 1 from public.student_dining_enrollments where id = p_dining_enrollment_id and is_active) then raise exception 'Active dining enrollment required' using errcode = 'check_violation'; end if;
  insert into public.dining_usage (dining_enrollment_id, service_date, used) values (p_dining_enrollment_id, p_service_date, p_used)
  on conflict (dining_enrollment_id, service_date) do update set used = excluded.used returning * into result_row;
  return to_jsonb(result_row);
end; $$;

do $$
declare table_name text;
begin
  foreach table_name in array array['sports','sport_groups','sport_group_schedules','student_sport_enrollments','transport_routes','transport_stops','student_transport_enrollments','dining_services','dining_slots','student_dining_enrollments','dining_usage'] loop
    execute format('create trigger %I_set_updated_at before update on public.%I for each row execute function public.set_updated_at()', table_name, table_name);
  end loop;
end $$;

alter table public.sports enable row level security;
alter table public.sport_groups enable row level security;
alter table public.sport_group_schedules enable row level security;
alter table public.student_sport_enrollments enable row level security;
alter table public.transport_routes enable row level security;
alter table public.transport_stops enable row level security;
alter table public.student_transport_enrollments enable row level security;
alter table public.dining_services enable row level security;
alter table public.dining_slots enable row level security;
alter table public.student_dining_enrollments enable row level security;
alter table public.dining_usage enable row level security;

create policy "Active users can read service catalogs" on public.sports for select to authenticated using ((select public.is_active_user()));
create policy "Active users can read sport groups" on public.sport_groups for select to authenticated using ((select public.is_active_user()));
create policy "Active users can read sport schedules" on public.sport_group_schedules for select to authenticated using ((select public.is_active_user()));
create policy "Active users can read transport routes" on public.transport_routes for select to authenticated using ((select public.is_active_user()));
create policy "Active users can read transport stops" on public.transport_stops for select to authenticated using ((select public.is_active_user()));
create policy "Active users can read dining services" on public.dining_services for select to authenticated using ((select public.is_active_user()));
create policy "Active users can read dining slots" on public.dining_slots for select to authenticated using ((select public.is_active_user()));

create policy "Related users can read sport enrollments" on public.student_sport_enrollments for select to authenticated using ((select public.is_active_user()) and ((select public.is_active_superadmin()) or public.is_guardian_of_student(student_id) or public.is_teacher_of_student(student_id)));
create policy "Related users can read transport enrollments" on public.student_transport_enrollments for select to authenticated using ((select public.is_active_user()) and ((select public.is_active_superadmin()) or public.is_guardian_of_student(student_id) or public.is_teacher_of_student(student_id)));
create policy "Related users can read dining enrollments" on public.student_dining_enrollments for select to authenticated using ((select public.is_active_user()) and ((select public.is_active_superadmin()) or public.is_guardian_of_student(student_id) or public.is_teacher_of_student(student_id)));
create policy "Related users can read dining usage" on public.dining_usage for select to authenticated using ((select public.is_active_superadmin()) or exists (select 1 from public.student_dining_enrollments e where e.id = dining_usage.dining_enrollment_id and (public.is_guardian_of_student(e.student_id) or public.is_teacher_of_student(e.student_id))));

do $$
declare table_name text;
begin
  foreach table_name in array array['sports','sport_groups','sport_group_schedules','student_sport_enrollments','transport_routes','transport_stops','student_transport_enrollments','dining_services','dining_slots','student_dining_enrollments','dining_usage'] loop
    execute format('create policy %I on public.%I for all to authenticated using ((select public.is_active_superadmin())) with check ((select public.is_active_superadmin()))', 'Active superadmins manage ' || table_name, table_name);
    execute format('grant select, insert, update, delete on public.%I to authenticated', table_name);
  end loop;
end $$;

grant execute on function public.enroll_student_in_sport_group(uuid, uuid) to authenticated;
grant execute on function public.enroll_student_in_transport(uuid, uuid, uuid) to authenticated;
grant execute on function public.enroll_student_in_dining(uuid, uuid, integer) to authenticated;
grant execute on function public.deactivate_student_service_enrollment(text, uuid) to authenticated;
grant execute on function public.record_dining_usage(uuid, date, boolean) to authenticated;

revoke execute on function public.enroll_student_in_sport_group(uuid, uuid) from public;
revoke execute on function public.enroll_student_in_transport(uuid, uuid, uuid) from public;
revoke execute on function public.enroll_student_in_dining(uuid, uuid, integer) from public;
revoke execute on function public.deactivate_student_service_enrollment(text, uuid) from public;
revoke execute on function public.record_dining_usage(uuid, date, boolean) from public;
