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
