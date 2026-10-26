-- Extends the disposable schedule fixture; never run against a remote database.
create schema auth;
create function auth.uid() returns uuid language sql as 'select null::uuid';
create or replace function public.is_active_superadmin() returns boolean language sql as 'select true';
alter table public.courses add column capacity integer;
alter table public.people alter column id set default gen_random_uuid();
alter table public.people alter column is_active set default true;
alter table public.people add column first_name text, add column last_name text,
  add column email text, add column phone text, add column dni text, add column birth_date date;
alter table public.students alter column id set default gen_random_uuid();
alter table public.students alter column is_active set default true;
alter table public.students add column person_id uuid;
create table public.student_enrollments (
  id uuid primary key default gen_random_uuid(), student_id uuid, course_id uuid,
  academic_year integer, is_active boolean default true
);
create table public.enrollment_requests (
  id uuid primary key default gen_random_uuid(), status text default 'pending',
  academic_year integer, student_first_name text, student_last_name text,
  email text, phone text, student_dni text, birth_date date,
  responsible_full_name text default 'Responsible Demo', responsible_dni text default '44000995',
  responsible_relation text default 'tutor demo',
  approved_course_id uuid, student_id uuid, enrollment_id uuid,
  approved_at timestamptz, approved_by_profile_id uuid,
  rejected_at timestamptz, rejected_by_profile_id uuid,
  rejection_reason text, updated_by_profile_id uuid
);
create unique index student_guardians_relationship_expression_unique
  on public.student_guardians(student_id,guardian_person_id,lower(btrim(relationship_type)));
create table public.student_dining_enrollments (id uuid primary key, is_active boolean);
create table public.dining_usage (
  id uuid primary key default gen_random_uuid(), dining_enrollment_id uuid,
  service_date date, used boolean, unique(dining_enrollment_id,service_date)
);
create function public.set_updated_at() returns trigger language plpgsql as $$
begin new.updated_at=now(); return new; end $$;
create trigger dining_usage_set_updated_at before update on public.dining_usage
  for each row execute function public.set_updated_at();
