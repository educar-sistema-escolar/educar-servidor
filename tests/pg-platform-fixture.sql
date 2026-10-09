-- Test-only Supabase platform and adjacent institutional schema compatibility.
-- Financial tables/functions/policies are loaded from actual migrations unchanged.
create role authenticated nologin;
create role service_role nologin bypassrls;
create schema auth;
create schema storage;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create function auth.role() returns text language sql stable as $$select current_setting('request.jwt.claim.role',true)$$;
grant usage on schema auth,storage,public to authenticated,service_role;
create table public.profiles(id uuid primary key,full_name text,email text,role text,is_active boolean default true,account_status text default 'active');
create table public.people(id uuid primary key,profile_id uuid references profiles,first_name text,last_name text,is_active boolean default true);
create table public.students(id uuid primary key,person_id uuid references people,is_active boolean default true);
create table public.student_guardians(student_id uuid references students,guardian_person_id uuid references people,is_active boolean default true);
create table public.sports(id uuid primary key,name text);
create table public.educational_levels(id uuid primary key,name text);
create table public.teachers(id uuid primary key,person_id uuid);
create table public.sport_groups(id uuid primary key,name text,sport_id uuid,educational_level_id uuid,teacher_id uuid,is_active boolean default true);
create table public.sport_group_schedules(sport_group_id uuid,day_of_week integer,starts_at time,ends_at time,is_active boolean default true);
create table public.transport_routes(id uuid primary key,name text,is_active boolean default true);
create table public.dining_services(id uuid primary key,name text,is_active boolean default true);
create table public.student_sport_enrollments(student_id uuid,sport_group_id uuid,is_active boolean default true,academic_year integer);
create table public.student_transport_enrollments(student_id uuid,route_id uuid,is_active boolean default true,academic_year integer);
create table public.student_dining_enrollments(student_id uuid,dining_service_id uuid,is_active boolean default true,academic_year integer);
create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
create table storage.objects(id uuid default gen_random_uuid() primary key,bucket_id text,name text,owner_id text);
alter table storage.objects enable row level security;
create function storage.foldername(name text) returns text[] language sql immutable as $$select string_to_array(name,'/')$$;
grant select on public.profiles,public.people,public.students,public.student_guardians to authenticated;
grant select,insert,delete on storage.objects to authenticated;
