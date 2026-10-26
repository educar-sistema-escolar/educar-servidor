-- Use separate statements for the different trigger record shapes.
create or replace function public.set_forum_vote_identity()
returns trigger language plpgsql security definer set search_path = pg_catalog, public as $$
begin
 if not public.is_active_forum_student() then
  raise exception 'Active student account required' using errcode = '42501';
 end if;
 if tg_op = 'UPDATE' then
  if new.voter_id is distinct from old.voter_id then
   raise exception 'Forum vote identity is immutable' using errcode = '42501';
  end if;
  if tg_table_name = 'forum_discussion_votes' then
   if new.discussion_id is distinct from old.discussion_id then
    raise exception 'Forum vote identity is immutable' using errcode = '42501';
   end if;
  elsif tg_table_name = 'forum_reply_votes' then
   if new.reply_id is distinct from old.reply_id then
    raise exception 'Forum vote identity is immutable' using errcode = '42501';
   end if;
  end if;
 else
  new.voter_id := auth.uid();
  new.created_at := now();
 end if;
 return new;
end; $$;
revoke all on function public.set_forum_vote_identity() from public, anon, authenticated;
