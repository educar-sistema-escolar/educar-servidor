-- Incremental recovery for the deployment audited on 2026-10-26.
-- Reuses the reviewed module definitions; on a fresh full chain it is a no-op.
-- Refuses partial modules rather than guessing or creating duplicate tables.
do $recovery$
declare present integer;
begin
 select count(*) into present from unnest(array['public.forum_discussions','public.forum_replies','public.forum_discussion_votes','public.forum_reply_votes']) t where to_regclass(t) is not null;
 if present = 0 then
   execute $module$
-- Shared student forum content. The authenticated identity is always supplied
-- by Supabase Auth and validated against the active institutional student row.

create or replace function public.is_active_forum_student()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.profiles profile
    join public.people person on person.profile_id = profile.id
    join public.students student on student.person_id = person.id
    where profile.id = (select auth.uid())
      and profile.role::text = 'student'
      and profile.is_active = true
      and profile.account_status = 'active'
      and person.is_active = true
      and student.is_active = true
  );
$$;

revoke all on function public.is_active_forum_student() from public, anon;
grant execute on function public.is_active_forum_student() to authenticated;

create table public.forum_discussions (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles (id) on delete cascade,
  author_name text not null,
  category text not null constraint forum_discussions_category_check
    check (category in ('Académico', 'Vida Escolar', 'Grupos de Estudio', 'Intercambio', 'Deportes')),
  title text not null constraint forum_discussions_title_length_check
    check (length(btrim(title)) between 1 and 180 and title ~ '[^[:space:]]'),
  lead text not null constraint forum_discussions_lead_length_check
    check (length(btrim(lead)) between 1 and 200 and lead ~ '[^[:space:]]'),
  content text not null constraint forum_discussions_content_length_check
    check (length(btrim(content)) between 1 and 10000 and content ~ '[^[:space:]]'),
  status text not null default 'published' constraint forum_discussions_status_check
    check (status in ('published', 'hidden')),
  score integer not null default 0,
  replies_count integer not null default 0 constraint forum_discussions_replies_count_check
    check (replies_count >= 0),
  created_at timestamptz not null default now()
);

create index forum_discussions_created_at_idx
  on public.forum_discussions (created_at desc, id desc)
  where status = 'published';
create index forum_discussions_score_idx
  on public.forum_discussions (score desc, created_at desc)
  where status = 'published';
create index forum_discussions_replies_count_idx
  on public.forum_discussions (replies_count desc, created_at desc)
  where status = 'published';
create index forum_discussions_author_id_idx
  on public.forum_discussions (author_id);

create table public.forum_replies (
  id uuid primary key default gen_random_uuid(),
  discussion_id uuid not null references public.forum_discussions (id) on delete cascade,
  parent_reply_id uuid,
  author_id uuid not null references public.profiles (id) on delete cascade,
  author_name text not null,
  content text not null constraint forum_replies_content_length_check
    check (length(btrim(content)) between 1 and 2000 and content ~ '[^[:space:]]'),
  status text not null default 'published' constraint forum_replies_status_check
    check (status in ('published', 'hidden')),
  score integer not null default 0,
  created_at timestamptz not null default now(),
  unique (id, discussion_id),
  constraint forum_replies_parent_same_discussion_fk
    foreign key (parent_reply_id, discussion_id)
    references public.forum_replies (id, discussion_id) on delete cascade,
  constraint forum_replies_not_own_parent_check
    check (parent_reply_id is null or parent_reply_id <> id)
);

create index forum_replies_discussion_created_at_idx
  on public.forum_replies (discussion_id, created_at, id)
  where status = 'published';
create index forum_replies_discussion_id_idx
  on public.forum_replies (discussion_id);
create index forum_replies_parent_reply_id_idx
  on public.forum_replies (parent_reply_id)
  where parent_reply_id is not null;
create index forum_replies_author_id_idx
  on public.forum_replies (author_id);

create table public.forum_discussion_votes (
  id uuid primary key default gen_random_uuid(),
  discussion_id uuid not null references public.forum_discussions (id) on delete cascade,
  voter_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  direction text not null constraint forum_discussion_votes_direction_check
    check (direction in ('up', 'down')),
  created_at timestamptz not null default now(),
  unique (discussion_id, voter_id)
);

create table public.forum_reply_votes (
  id uuid primary key default gen_random_uuid(),
  reply_id uuid not null references public.forum_replies (id) on delete cascade,
  voter_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  direction text not null constraint forum_reply_votes_direction_check
    check (direction in ('up', 'down')),
  created_at timestamptz not null default now(),
  unique (reply_id, voter_id)
);

create index forum_discussion_votes_voter_id_idx
  on public.forum_discussion_votes (voter_id);
create index forum_reply_votes_voter_id_idx
  on public.forum_reply_votes (voter_id);

alter table public.forum_discussions enable row level security;
alter table public.forum_replies enable row level security;
alter table public.forum_discussion_votes enable row level security;
alter table public.forum_reply_votes enable row level security;

create policy "Active students can read published forum discussions"
  on public.forum_discussions for select to authenticated
  using ((select public.is_active_forum_student()) and status = 'published');

create policy "Active students can publish forum discussions"
  on public.forum_discussions for insert to authenticated
  with check (
    (select public.is_active_forum_student())
    and author_id = (select auth.uid())
    and status = 'published'
    and score = 0
    and replies_count = 0
  );

create policy "Active students can read replies in published discussions"
  on public.forum_replies for select to authenticated
  using (
    (select public.is_active_forum_student())
    and status = 'published'
    and exists (
      select 1 from public.forum_discussions discussion
      where discussion.id = forum_replies.discussion_id
        and discussion.status = 'published'
    )
  );

create policy "Active students can publish replies"
  on public.forum_replies for insert to authenticated
  with check (
    (select public.is_active_forum_student())
    and author_id = (select auth.uid())
    and status = 'published'
    and score = 0
    and exists (
      select 1 from public.forum_discussions discussion
      where discussion.id = forum_replies.discussion_id
        and discussion.status = 'published'
    )
  );

create policy "Students can read their own discussion votes"
  on public.forum_discussion_votes for select to authenticated
  using ((select public.is_active_forum_student()) and voter_id = (select auth.uid()));

create policy "Students can cast their own discussion votes"
  on public.forum_discussion_votes for insert to authenticated
  with check (
    (select public.is_active_forum_student())
    and voter_id = (select auth.uid())
    and exists (
      select 1 from public.forum_discussions discussion
      where discussion.id = forum_discussion_votes.discussion_id
        and discussion.status = 'published'
    )
  );

create policy "Students can change their own discussion votes"
  on public.forum_discussion_votes for update to authenticated
  using ((select public.is_active_forum_student()) and voter_id = (select auth.uid()))
  with check (
    (select public.is_active_forum_student())
    and voter_id = (select auth.uid())
    and exists (
      select 1 from public.forum_discussions discussion
      where discussion.id = forum_discussion_votes.discussion_id
        and discussion.status = 'published'
    )
  );

create policy "Students can remove their own discussion votes"
  on public.forum_discussion_votes for delete to authenticated
  using ((select public.is_active_forum_student()) and voter_id = (select auth.uid()));

create policy "Students can read their own reply votes"
  on public.forum_reply_votes for select to authenticated
  using ((select public.is_active_forum_student()) and voter_id = (select auth.uid()));

create policy "Students can cast their own reply votes"
  on public.forum_reply_votes for insert to authenticated
  with check (
    (select public.is_active_forum_student())
    and voter_id = (select auth.uid())
    and exists (
      select 1
      from public.forum_replies reply
      join public.forum_discussions discussion on discussion.id = reply.discussion_id
      where reply.id = forum_reply_votes.reply_id
        and reply.status = 'published'
        and discussion.status = 'published'
    )
  );

create policy "Students can change their own reply votes"
  on public.forum_reply_votes for update to authenticated
  using ((select public.is_active_forum_student()) and voter_id = (select auth.uid()))
  with check (
    (select public.is_active_forum_student())
    and voter_id = (select auth.uid())
    and exists (
      select 1
      from public.forum_replies reply
      join public.forum_discussions discussion on discussion.id = reply.discussion_id
      where reply.id = forum_reply_votes.reply_id
        and reply.status = 'published'
        and discussion.status = 'published'
    )
  );

create policy "Students can remove their own reply votes"
  on public.forum_reply_votes for delete to authenticated
  using ((select public.is_active_forum_student()) and voter_id = (select auth.uid()));

revoke all on public.forum_discussions, public.forum_replies,
  public.forum_discussion_votes, public.forum_reply_votes from public, anon;

grant select, insert on public.forum_discussions to authenticated;
grant select, insert on public.forum_replies to authenticated;
grant select, insert, update, delete on public.forum_discussion_votes to authenticated;
grant select, insert, update, delete on public.forum_reply_votes to authenticated;

create or replace function public.set_forum_author()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if tg_op = 'UPDATE' then
    if new.author_id is distinct from old.author_id
       or new.author_name is distinct from old.author_name then
      raise exception 'Forum author is immutable' using errcode = 'insufficient_privilege';
    end if;
    return new;
  end if;

  if not public.is_active_forum_student() then
    raise exception 'Active student account required' using errcode = 'insufficient_privilege';
  end if;

  new.author_id := (select auth.uid());
  select coalesce(nullif(btrim(profile.full_name), ''), 'Estudiante')
  into new.author_name
  from public.profiles profile
  where profile.id = (select auth.uid())
    and profile.role::text = 'student'
    and profile.is_active = true
    and profile.account_status = 'active';
  new.created_at := now();
  new.score := 0;
  if tg_table_name = 'forum_discussions' then
    new.replies_count := 0;
  end if;
  return new;
end;
$$;

revoke all on function public.set_forum_author() from public, anon, authenticated;

create trigger forum_discussions_set_author
  before insert or update on public.forum_discussions
  for each row execute function public.set_forum_author();
create trigger forum_replies_set_author
  before insert or update on public.forum_replies
  for each row execute function public.set_forum_author();

create or replace function public.validate_forum_reply_parent()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if new.parent_reply_id is not null and not exists (
    select 1 from public.forum_replies parent
    where parent.id = new.parent_reply_id
      and parent.discussion_id = new.discussion_id
      and parent.parent_reply_id is null
      and parent.status = 'published'
  ) then
    raise exception 'Replies may only target a root reply in the same discussion'
      using errcode = 'invalid_parameter_value';
  end if;
  return new;
end;
$$;

revoke all on function public.validate_forum_reply_parent() from public, anon, authenticated;
create trigger forum_replies_validate_parent
  before insert on public.forum_replies
  for each row execute function public.validate_forum_reply_parent();

create or replace function public.adjust_forum_replies_count()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  discussion_id uuid;
  delta integer;
begin
  if tg_op = 'INSERT' then
    discussion_id := new.discussion_id;
    delta := 1;
  else
    discussion_id := old.discussion_id;
    delta := -1;
  end if;

  update public.forum_discussions
  set replies_count = replies_count + delta
  where id = discussion_id;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function public.adjust_forum_replies_count() from public, anon, authenticated;
create trigger forum_replies_adjust_count
  after insert or delete on public.forum_replies
  for each row execute function public.adjust_forum_replies_count();

create or replace function public.set_forum_vote_identity()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if not public.is_active_forum_student() then
    raise exception 'Active student account required' using errcode = 'insufficient_privilege';
  end if;
  if tg_op = 'UPDATE' then
    if new.voter_id is distinct from old.voter_id
       or (tg_table_name = 'forum_discussion_votes' and new.discussion_id is distinct from old.discussion_id)
       or (tg_table_name = 'forum_reply_votes' and new.reply_id is distinct from old.reply_id) then
      raise exception 'Forum vote identity is immutable' using errcode = 'insufficient_privilege';
    end if;
  else
    new.voter_id := (select auth.uid());
    new.created_at := now();
  end if;
  return new;
end;
$$;

revoke all on function public.set_forum_vote_identity() from public, anon, authenticated;
create trigger forum_discussion_votes_set_identity
  before insert or update on public.forum_discussion_votes
  for each row execute function public.set_forum_vote_identity();
create trigger forum_reply_votes_set_identity
  before insert or update on public.forum_reply_votes
  for each row execute function public.set_forum_vote_identity();

create or replace function public.update_forum_discussion_score()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  delta integer;
  target_id uuid;
begin
  if tg_op = 'INSERT' then
    target_id := new.discussion_id;
    delta := case new.direction when 'up' then 1 else -1 end;
  elsif tg_op = 'DELETE' then
    target_id := old.discussion_id;
    delta := case old.direction when 'up' then -1 else 1 end;
  else
    target_id := new.discussion_id;
    delta := (case new.direction when 'up' then 1 else -1 end)
      - (case old.direction when 'up' then 1 else -1 end);
  end if;

  if delta <> 0 then
    update public.forum_discussions
    set score = score + delta
    where id = target_id;
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function public.update_forum_discussion_score() from public, anon, authenticated;
create trigger forum_discussion_votes_update_score
  after insert or update or delete on public.forum_discussion_votes
  for each row execute function public.update_forum_discussion_score();

create or replace function public.update_forum_reply_score()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  delta integer;
  target_id uuid;
begin
  if tg_op = 'INSERT' then
    target_id := new.reply_id;
    delta := case new.direction when 'up' then 1 else -1 end;
  elsif tg_op = 'DELETE' then
    target_id := old.reply_id;
    delta := case old.direction when 'up' then -1 else 1 end;
  else
    target_id := new.reply_id;
    delta := (case new.direction when 'up' then 1 else -1 end)
      - (case old.direction when 'up' then 1 else -1 end);
  end if;

  if delta <> 0 then
    update public.forum_replies
    set score = score + delta
    where id = target_id;
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function public.update_forum_reply_score() from public, anon, authenticated;
create trigger forum_reply_votes_update_score
  after insert or update or delete on public.forum_reply_votes
  for each row execute function public.update_forum_reply_score();

$module$;
 elsif present <> 4 then
   raise exception 'Partial module detected; inspect its catalog before recovery';
 end if;
end $recovery$;
do $recovery$
declare present integer;
begin
 select count(*) into present from unnest(array['public.billing_values','public.invoices','public.invoice_items','public.transfer_submissions','public.transfer_submission_items','public.transfer_receipts','public.billing_non_business_days','public.billing_reminders']) t where to_regclass(t) is not null;
 if present = 0 then
   execute $module$
-- Source: 20261008100000_mobile_billing.sql

create table public.billing_values (
 id uuid primary key default gen_random_uuid(), concept text not null check(concept in ('tuition','sport','transport','dining')),
 service_id uuid, label text not null check(length(btrim(label)) between 1 and 120), amount_cents bigint not null check(amount_cents > 0), effective_from date not null,
 unique(concept,service_id,effective_from)
);
create table public.invoices (
 id uuid primary key default gen_random_uuid(), student_id uuid not null references public.students(id), period date not null, due_date date not null,
 created_at timestamptz not null default now(), unique(student_id,period), check(due_date >= period)
);
create table public.invoice_items (
 id uuid primary key default gen_random_uuid(), invoice_id uuid not null references public.invoices(id), concept text not null check(concept in ('tuition','sport','transport','dining')),
 service_id uuid, label text not null check(length(btrim(label)) between 1 and 120), amount_cents bigint not null check(amount_cents > 0), paid_cents bigint not null default 0 check(paid_cents >= 0 and paid_cents <= amount_cents)
);
create or replace function public.can_read_invoice(p_invoice uuid) returns boolean language sql stable security definer set search_path=pg_catalog,public as $$
 select exists(select 1 from public.invoices i join public.profiles p on p.id=auth.uid() where i.id=p_invoice and p.is_active and p.account_status='active' and (p.role::text in ('superadmin','admin') or public.is_guardian_of_student(i.student_id)));
$$;
create or replace function public.is_billing_admin() returns boolean language sql stable security definer set search_path=pg_catalog,public as $$
 select exists(select 1 from public.profiles where id=auth.uid() and is_active and account_status='active' and role::text in ('superadmin','admin'));
$$;
alter table public.billing_values enable row level security;
alter table public.invoices enable row level security;
alter table public.invoice_items enable row level security;
create policy "Billing admins configure values" on public.billing_values for all to authenticated using(public.is_billing_admin()) with check(public.is_billing_admin());
create policy "Families read own invoices" on public.invoices for select to authenticated using(public.can_read_invoice(id));
create policy "Families read own invoice items" on public.invoice_items for select to authenticated using(public.can_read_invoice(invoice_id));
create policy "Billing admins issue invoices" on public.invoices for insert to authenticated with check(public.is_billing_admin());
create policy "Billing admins issue price snapshots" on public.invoice_items for insert to authenticated with check(public.is_billing_admin());
grant select,insert,update,delete on public.billing_values to authenticated;
grant select,insert on public.invoices,public.invoice_items to authenticated;
revoke all on function public.can_read_invoice(uuid),public.is_billing_admin() from public;
grant execute on function public.can_read_invoice(uuid),public.is_billing_admin() to authenticated;
comment on column public.invoice_items.amount_cents is 'Immutable issued price snapshot; changes to configured values never reprice existing invoices.';

-- Source: 20261008110000_mobile_transfers.sql

create table public.transfer_submissions (
 id uuid primary key default gen_random_uuid(), invoice_id uuid not null references public.invoices(id), guardian_id uuid not null references public.profiles(id),
 reference text not null check(length(btrim(reference)) between 1 and 100), amount_cents bigint not null check(amount_cents > 0), status text not null default 'pending' check(status in ('pending','approved','rejected')),
 created_at timestamptz not null default now(), unique(guardian_id,reference)
);
create table public.transfer_submission_items (
 submission_id uuid not null references public.transfer_submissions(id), item_id uuid not null references public.invoice_items(id), primary key(submission_id,item_id)
);
create table public.transfer_receipts (
 id uuid primary key default gen_random_uuid(), submission_id uuid not null references public.transfer_submissions(id), storage_path text not null unique,
 filename text not null check(length(filename) between 1 and 200), created_at timestamptz not null default now()
);
alter table public.transfer_submissions enable row level security;
alter table public.transfer_submission_items enable row level security;
alter table public.transfer_receipts enable row level security;
create policy "Families read submissions" on public.transfer_submissions for select to authenticated using(public.can_read_invoice(invoice_id));
create policy "Families read selected concepts" on public.transfer_submission_items for select to authenticated using(exists(select 1 from public.transfer_submissions s where s.id=submission_id));
create policy "Families read associated receipts" on public.transfer_receipts for select to authenticated using(exists(select 1 from public.transfer_submissions s where s.id=submission_id));
grant select on public.transfer_submissions,public.transfer_submission_items,public.transfer_receipts to authenticated;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('transfer-receipts','transfer-receipts',false,5242880,array['application/pdf','image/jpeg','image/png']) on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
create policy "Families upload private receipts" on storage.objects for insert to authenticated with check(bucket_id='transfer-receipts' and (storage.foldername(name))[1]=auth.uid()::text and exists(select 1 from public.profiles where id=auth.uid() and is_active and account_status='active' and role::text in ('parent','guardian')));
create policy "Families read own private receipt files" on storage.objects for select to authenticated using(bucket_id='transfer-receipts' and (storage.foldername(name))[1]=auth.uid()::text);
create or replace function public.submit_transfer(p_invoice uuid,p_items uuid[],p_amount bigint,p_reference text,p_path text,p_filename text) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare result uuid; outstanding bigint; item_count integer; existing public.transfer_submissions;
begin
 if not public.can_read_invoice(p_invoice) or not exists(select 1 from public.profiles where id=auth.uid() and role::text in ('parent','guardian') and is_active and account_status='active') then raise exception 'Invoice access denied' using errcode='42501'; end if;
 perform 1 from public.invoices where id=p_invoice for update;
 select * into existing from public.transfer_submissions where guardian_id=auth.uid() and reference=btrim(p_reference);
 if existing.id is not null then
  if existing.invoice_id=p_invoice and existing.amount_cents=p_amount
   and (select array_agg(item_id order by item_id) from public.transfer_submission_items where submission_id=existing.id)=(select array_agg(x order by x) from unnest(p_items) x)
   and exists(select 1 from public.transfer_receipts where submission_id=existing.id and storage_path=p_path and filename=p_filename)
  then return existing.id; end if;
  raise exception 'Transfer reference already belongs to a different operation';
 end if;
 if p_items is null or cardinality(p_items)=0 or cardinality(p_items)<>(select count(distinct x) from unnest(p_items) x) then raise exception 'Select distinct pending concepts'; end if;
 select count(*),sum(amount_cents-paid_cents) into item_count,outstanding from public.invoice_items where invoice_id=p_invoice and id=any(p_items) and amount_cents>paid_cents;
 if item_count<>cardinality(p_items) or p_amount is null or p_amount<=0 or p_amount>outstanding then raise exception 'Invalid selected concepts or amount'; end if;
 if exists(select 1 from public.transfer_submission_items si join public.transfer_submissions s on s.id=si.submission_id where si.item_id=any(p_items) and s.status='pending') then raise exception 'Selected concepts already have a pending transfer'; end if;
 if p_reference is null or length(btrim(p_reference)) not between 1 and 100 then raise exception 'Invalid transfer reference'; end if;
 if p_path is null or split_part(p_path,'/',1)<>auth.uid()::text or not exists(select 1 from storage.objects where bucket_id='transfer-receipts' and name=p_path and owner_id=auth.uid()::text) then raise exception 'Upload a receipt owned by the current user'; end if;
 if p_filename is null or length(p_filename) not between 1 and 200 then raise exception 'Invalid receipt filename'; end if;
 insert into public.transfer_submissions(invoice_id,guardian_id,reference,amount_cents) values(p_invoice,auth.uid(),btrim(p_reference),p_amount) returning id into result;
 insert into public.transfer_submission_items select result,unnest(p_items);
 insert into public.transfer_receipts(submission_id,storage_path,filename) values(result,p_path,p_filename);
 return result;
end; $$;
create or replace function public.attach_transfer_receipt(p_submission uuid,p_path text,p_filename text) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare result uuid; invoice_value uuid; existing public.transfer_receipts;
begin
 select invoice_id into invoice_value from public.transfer_submissions where id=p_submission and guardian_id=auth.uid();
 if invoice_value is null then raise exception 'Submission access denied' using errcode='42501';end if;
 perform 1 from public.invoices where id=invoice_value for update;
 perform 1 from public.transfer_submissions where id=p_submission for update;
 if not exists(select 1 from public.transfer_submissions where id=p_submission and guardian_id=auth.uid() and status='pending' and public.can_read_invoice(invoice_id)) then raise exception 'Submission access denied' using errcode='42501'; end if;
 if split_part(p_path,'/',1)<>auth.uid()::text or not exists(select 1 from storage.objects where bucket_id='transfer-receipts' and name=p_path and owner_id=auth.uid()::text) then raise exception 'Invalid receipt ownership'; end if;
 if p_filename is null or length(p_filename) not between 1 and 200 then raise exception 'Invalid receipt filename';end if;
 select * into existing from public.transfer_receipts where storage_path=p_path;
 if existing.id is not null then if existing.submission_id=p_submission and existing.filename=p_filename then return existing.id;end if;raise exception 'Receipt is already associated with another operation or filename';end if;
 insert into public.transfer_receipts(submission_id,storage_path,filename) values(p_submission,p_path,p_filename) returning id into result; return result;
end; $$;
revoke all on function public.submit_transfer(uuid,uuid[],bigint,text,text,text),public.attach_transfer_receipt(uuid,text,text) from public;
grant execute on function public.submit_transfer(uuid,uuid[],bigint,text,text,text),public.attach_transfer_receipt(uuid,text,text) to authenticated;

-- Source: 20261008120000_billing_review.sql

alter table public.transfer_submissions add column reviewed_at timestamptz;
create unique index billing_values_tuition_effective_idx on public.billing_values(concept,effective_from) where service_id is null;
alter table public.billing_values add constraint billing_values_safe_amount check(amount_cents<=9007199254740991);
alter table public.invoice_items add constraint invoice_items_safe_amount check(amount_cents<=9007199254740991);
alter table public.transfer_submissions add constraint transfers_safe_amount check(amount_cents<=9007199254740991);
create or replace function public.review_transfer(p_submission uuid,p_approve boolean) returns void language plpgsql security definer set search_path=pg_catalog,public as $$
declare submission public.transfer_submissions; item public.invoice_items; remaining bigint; allocation bigint;
begin
 if not public.is_billing_admin() then raise exception 'Administrator required' using errcode='42501'; end if;
 select * into submission from public.transfer_submissions where id=p_submission;
 if submission.id is null then raise exception 'Transfer not found'; end if;
 perform 1 from public.invoices where id=submission.invoice_id for update;
 select * into submission from public.transfer_submissions where id=p_submission for update;
 if submission.status<>'pending' then raise exception 'Transfer already reviewed'; end if;
 if p_approve is null then raise exception 'Review decision required'; end if;
 if p_approve then
  remaining=submission.amount_cents;
  if remaining>(select sum(i.amount_cents-i.paid_cents) from public.invoice_items i join public.transfer_submission_items si on si.item_id=i.id where si.submission_id=p_submission) then raise exception 'Transfer exceeds outstanding selected items'; end if;
  for item in select i.* from public.invoice_items i join public.transfer_submission_items si on si.item_id=i.id where si.submission_id=p_submission order by i.id for update of i loop
   allocation=least(remaining,item.amount_cents-item.paid_cents);
   update public.invoice_items set paid_cents=paid_cents+allocation where id=item.id;
   remaining=remaining-allocation;
  end loop;
  if remaining<>0 then raise exception 'Amount could not be allocated'; end if;
 end if;
 update public.transfer_submissions set reviewed_at=now(),status=case when p_approve then 'approved' else 'rejected' end where id=p_submission;
end;$$;
create or replace function public.issue_monthly_invoice(p_student uuid,p_period date,p_due date) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare result uuid;
begin
 if not public.is_billing_admin() then raise exception 'Administrator required' using errcode='42501'; end if;
 if p_period<>date_trunc('month',p_period)::date then raise exception 'Period must be the first day of a month'; end if;
 if not exists(select 1 from public.students where id=p_student and is_active) then raise exception 'Active student required'; end if;
 if not exists(select 1 from public.billing_values where concept='tuition' and service_id is null and effective_from<=p_period) then raise exception 'Configure tuition before issuing invoices'; end if;
 if exists(select 1 from (
  select 'sport' concept,sport_group_id service_id from public.student_sport_enrollments where student_id=p_student and is_active and academic_year=extract(year from p_period)
  union all select 'transport',route_id from public.student_transport_enrollments where student_id=p_student and is_active and academic_year=extract(year from p_period)
  union all select 'dining',dining_service_id from public.student_dining_enrollments where student_id=p_student and is_active and academic_year=extract(year from p_period)
 ) enrolled where not exists(select 1 from public.billing_values price where price.concept=enrolled.concept and price.service_id=enrolled.service_id and price.effective_from<=p_period)) then raise exception 'Configure all enrolled service prices before issuing invoices';end if;
 insert into public.invoices(student_id,period,due_date) values(p_student,p_period,p_due) returning id into result;
 insert into public.invoice_items(invoice_id,concept,service_id,label,amount_cents)
 select result,chosen.concept,chosen.service_id,chosen.label,chosen.amount_cents from (
  select distinct on (concept,service_id) * from public.billing_values v where effective_from<=p_period and (
   concept='tuition' and service_id is null
   or concept='sport' and exists(select 1 from public.student_sport_enrollments e where e.student_id=p_student and e.is_active and e.academic_year=extract(year from p_period) and e.sport_group_id=v.service_id)
   or concept='transport' and exists(select 1 from public.student_transport_enrollments e where e.student_id=p_student and e.is_active and e.academic_year=extract(year from p_period) and e.route_id=v.service_id)
   or concept='dining' and exists(select 1 from public.student_dining_enrollments e where e.student_id=p_student and e.is_active and e.academic_year=extract(year from p_period) and e.dining_service_id=v.service_id)
  ) order by concept,service_id,effective_from desc
 ) chosen;
 return result;
end;$$;
revoke all on function public.review_transfer(uuid,boolean),public.issue_monthly_invoice(uuid,date,date) from public;
grant execute on function public.review_transfer(uuid,boolean),public.issue_monthly_invoice(uuid,date,date) to authenticated;

-- Source: 20261008130000_billing_reports.sql

create or replace function public.billing_report(p_start date,p_end date) returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public as $$
declare result jsonb;
begin
 if not public.is_billing_admin() then raise exception 'Administrator required' using errcode='42501'; end if;
 if p_start is null or p_end is null or p_start>p_end then raise exception 'Invalid period'; end if;
 select jsonb_build_object(
 'income',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'student_id',i.student_id,'reference',t.reference,'amount_cents',t.amount_cents,'paid_at',t.reviewed_at)) from public.transfer_submissions t join public.invoices i on i.id=t.invoice_id where t.status='approved' and (t.reviewed_at at time zone 'America/Argentina/Buenos_Aires')::date between p_start and p_end),'[]'::jsonb),
 'invoices',coalesce((select jsonb_agg(row_to_json(summary)) from(select i.id,i.student_id,p.first_name||' '||p.last_name student_name,i.period,i.due_date,sum(it.amount_cents) total_cents,sum(it.paid_cents) paid_cents,case when sum(it.amount_cents)=sum(it.paid_cents) then 'complete' else 'incomplete' end status from public.invoices i join public.students s on s.id=i.student_id join public.people p on p.id=s.person_id join public.invoice_items it on it.invoice_id=i.id where i.period between p_start and p_end group by i.id,p.first_name,p.last_name) summary),'[]'::jsonb),
 'services',coalesce((select jsonb_agg(row_to_json(details)) from(select i.student_id,it.label,it.concept,it.amount_cents,it.paid_cents,sg.name group_name,sp.name sport,el.name level,teacher.first_name||' '||teacher.last_name teacher,tr.name route,(select jsonb_agg(jsonb_build_object('day',day_of_week,'start',starts_at,'end',ends_at)) from public.sport_group_schedules where sport_group_id=sg.id and is_active) schedules from public.invoice_items it join public.invoices i on i.id=it.invoice_id left join public.sport_groups sg on it.concept='sport' and sg.id=it.service_id left join public.sports sp on sp.id=sg.sport_id left join public.educational_levels el on el.id=sg.educational_level_id left join public.teachers t on t.id=sg.teacher_id left join public.people teacher on teacher.id=t.person_id left join public.transport_routes tr on it.concept='transport' and tr.id=it.service_id where i.period between p_start and p_end and it.concept in ('sport','transport')) details),'[]'::jsonb)
 ) into result;return result;
end;$$;
revoke all on function public.billing_report(date,date) from public;
grant execute on function public.billing_report(date,date) to authenticated;

-- Source: 20261008140000_billing_reminders.sql

create table public.billing_non_business_days(day date primary key,label text not null);
alter table public.billing_non_business_days enable row level security;
create policy "Admins maintain billing calendar" on public.billing_non_business_days for all to authenticated using(public.is_billing_admin()) with check(public.is_billing_admin());
grant select,insert,update,delete on public.billing_non_business_days to authenticated;
create table public.billing_reminders (
 id uuid primary key default gen_random_uuid(), guardian_id uuid not null references public.profiles(id), kind text not null check(kind in ('month_end','debt')),
 reminder_date date not null, recipient text not null, payload jsonb not null, status text not null default 'ready' check(status in ('ready','sending','sent','failed')),
 provider_id text, created_at timestamptz not null default now(), unique(guardian_id,kind,reminder_date)
);
alter table public.billing_reminders enable row level security;
create policy "Billing admins read reminder outcomes" on public.billing_reminders for select to authenticated using(public.is_billing_admin());
grant select on public.billing_reminders to authenticated;
create or replace function public.prepare_billing_reminders(p_date date) returns integer language plpgsql security definer set search_path=pg_catalog,public as $$
declare last_business date; reminder_kind text; affected integer;
begin
 if auth.role() is distinct from 'service_role' then raise exception 'Server service role required' using errcode='42501'; end if;
 last_business=(date_trunc('month',p_date)+interval '1 month - 1 day')::date;
 while extract(isodow from last_business)>5 or exists(select 1 from public.billing_non_business_days where day=last_business) loop last_business=last_business-1; end loop;
 reminder_kind=case when p_date=last_business then 'month_end' when extract(day from p_date)=20 then 'debt' else null end;
 if reminder_kind is null then return 0; end if;
 insert into public.billing_reminders(guardian_id,kind,reminder_date,recipient,payload)
 select profile.id,reminder_kind,p_date,profile.email,jsonb_build_object('name',profile.full_name,'total_cents',sum(item.amount_cents-item.paid_cents),'items',jsonb_agg(jsonb_build_object('invoice_id',invoice.id,'student_id',invoice.student_id,'period',invoice.period,'due_date',invoice.due_date,'student_name',student_person.first_name||' '||student_person.last_name,'label',item.label,'amount_cents',item.amount_cents,'paid_cents',item.paid_cents)))
 from public.profiles profile join public.people person on person.profile_id=profile.id join (select distinct guardian_person_id,student_id from public.student_guardians where is_active) relationship on relationship.guardian_person_id=person.id join public.students student on student.id=relationship.student_id and student.is_active join public.people student_person on student_person.id=student.person_id join public.invoices invoice on invoice.student_id=student.id join public.invoice_items item on item.invoice_id=invoice.id
 where profile.is_active and profile.account_status='active' and profile.role::text in ('parent','guardian') and person.is_active and exists(select 1 from public.invoice_items unpaid where unpaid.invoice_id=invoice.id and unpaid.amount_cents>unpaid.paid_cents) and invoice.period<=p_date
 group by profile.id having sum(item.amount_cents-item.paid_cents)>0 on conflict(guardian_id,kind,reminder_date) do nothing;
 get diagnostics affected=row_count;return affected;
end;$$;
revoke all on function public.prepare_billing_reminders(date) from public,authenticated;
grant execute on function public.prepare_billing_reminders(date) to service_role;

-- Source: 20261008150000_billing_safety.sql

create policy "Billing admins inspect associated receipt files" on storage.objects for select to authenticated using(bucket_id='transfer-receipts' and public.is_billing_admin() and exists(select 1 from public.transfer_receipts r where r.storage_path=name));
create policy "Families remove unattached receipt uploads" on storage.objects for delete to authenticated using(bucket_id='transfer-receipts' and (storage.foldername(name))[1]=auth.uid()::text and not exists(select 1 from public.transfer_receipts r where r.storage_path=name));
create or replace function public.validate_billing_service() returns trigger language plpgsql set search_path=pg_catalog,public as $$
begin
 if new.concept='tuition' and new.service_id is not null or new.concept<>'tuition' and new.service_id is null then raise exception 'Service reference does not match billing concept'; end if;
 if new.concept='sport' and not exists(select 1 from public.sport_groups where id=new.service_id and is_active) or new.concept='transport' and not exists(select 1 from public.transport_routes where id=new.service_id and is_active) or new.concept='dining' and not exists(select 1 from public.dining_services where id=new.service_id and is_active) then raise exception 'Active billing service required'; end if;return new;
end;$$;
create trigger billing_values_service before insert or update on public.billing_values for each row execute function public.validate_billing_service();

-- Source: 20261008160000_receipt_evidence_safety.sql

create or replace function public.can_delete_unattached_receipt(p_path text) returns boolean language sql stable security definer set search_path=pg_catalog,public as $$
 select exists(select 1 from public.profiles where id=auth.uid() and is_active and account_status='active' and role::text in ('parent','guardian'))
 and split_part(p_path,'/',1)=auth.uid()::text
 and exists(select 1 from storage.objects where bucket_id='transfer-receipts' and name=p_path and owner_id=auth.uid()::text)
 and not exists(select 1 from public.transfer_receipts where storage_path=p_path);
$$;
revoke all on function public.can_delete_unattached_receipt(text) from public;
grant execute on function public.can_delete_unattached_receipt(text) to authenticated;
drop policy "Families remove unattached receipt uploads" on storage.objects;
create policy "Families remove unattached receipt uploads" on storage.objects for delete to authenticated using(bucket_id='transfer-receipts' and public.can_delete_unattached_receipt(name));

-- Source: 20261008170000_invoice_total_integrity.sql

create or replace function public.validate_invoice_total() returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
begin
 perform 1 from public.invoices where id=new.invoice_id for update;
 if (select coalesce(sum(amount_cents),0) from public.invoice_items where invoice_id=new.invoice_id)>9007199254740991 then raise exception 'Invoice total exceeds safe monetary range' using errcode='23514';end if;return new;
end;$$;
create trigger invoice_items_total after insert or update on public.invoice_items for each row execute function public.validate_invoice_total();

$module$;
 elsif present <> 8 then
   raise exception 'Partial module detected; inspect its catalog before recovery';
 end if;
end $recovery$;

notify pgrst, 'reload schema';
