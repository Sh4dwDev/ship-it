-- Ship It database setup.
-- Paste this whole file into Supabase: SQL Editor -> New query -> Run.
-- Safe to run again; it won't delete data.

-- ---------- tables ----------
create table if not exists public.profiles (
  id uuid primary key references auth.users on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 40),
  role text not null default 'member' check (role in ('admin', 'member')),
  created_at timestamptz not null default now()
);

create table if not exists public.members (
  id uuid primary key references public.profiles on delete cascade,
  data jsonb not null default '{}',
  updated_at timestamptz not null default now()
);

create table if not exists public.boards (
  id uuid primary key references public.profiles on delete cascade,
  data jsonb not null default '{}',
  updated_at timestamptz not null default now()
);

create table if not exists public.cheers (
  id uuid primary key references public.profiles on delete cascade,
  given jsonb not null default '{}',
  updated_at timestamptz not null default now()
);

create table if not exists public.settings (
  id int primary key default 1 check (id = 1),
  data jsonb not null default '{}',
  updated_at timestamptz not null default now()
);

create table if not exists public.invites (
  code text primary key,
  note text,
  created_by uuid references public.profiles on delete set null,
  created_at timestamptz not null default now(),
  expires_at timestamptz,
  used_by uuid references public.profiles on delete set null,
  used_at timestamptz
);

-- ---------- helper checks ----------
create or replace function public.is_member() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid());
$$;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and role = 'admin');
$$;

-- True until someone has claimed admin. The site uses it to let the first person in without a code.
create or replace function public.needs_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select not exists (select 1 from profiles where role = 'admin');
$$;

-- Turns a signed-in account into a member, using an invite code.
-- The very first person to join becomes admin and needs no code.
create or replace function public.redeem_invite(p_code text, p_name text) returns text
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_name text := btrim(coalesce(p_name, ''));
  v_used text;
begin
  if v_uid is null then raise exception 'Sign in first.'; end if;
  if exists (select 1 from profiles where id = v_uid) then return 'already'; end if;
  if char_length(v_name) < 1 or char_length(v_name) > 40 then raise exception 'Pick a name between 1 and 40 characters.'; end if;

  perform pg_advisory_xact_lock(4242);
  if not exists (select 1 from profiles where role = 'admin') then
    insert into profiles (id, display_name, role) values (v_uid, v_name, 'admin');
    insert into members (id) values (v_uid) on conflict do nothing;
    return 'admin';
  end if;

  insert into profiles (id, display_name, role) values (v_uid, v_name, 'member');
  update invites set used_by = v_uid, used_at = now()
    where code = upper(btrim(coalesce(p_code, ''))) and used_by is null
      and (expires_at is null or expires_at > now())
    returning code into v_used;
  if v_used is null then raise exception 'That invite code is wrong, used or expired.'; end if;
  insert into members (id) values (v_uid) on conflict do nothing;
  return 'member';
end;
$$;

create or replace function public.set_display_name(p_name text) returns void
language plpgsql security definer set search_path = public as $$
declare v_name text := btrim(coalesce(p_name, ''));
begin
  if char_length(v_name) < 1 or char_length(v_name) > 40 then raise exception 'Pick a name between 1 and 40 characters.'; end if;
  update profiles set display_name = v_name where id = auth.uid();
end;
$$;

revoke all on function public.redeem_invite(text, text) from public, anon;
revoke all on function public.set_display_name(text) from public, anon;
grant execute on function public.redeem_invite(text, text) to authenticated;
grant execute on function public.set_display_name(text) to authenticated;
grant execute on function public.needs_admin() to anon, authenticated;
grant execute on function public.is_member() to authenticated;
grant execute on function public.is_admin() to authenticated;

-- ---------- row level security ----------
alter table public.profiles enable row level security;
alter table public.members  enable row level security;
alter table public.boards   enable row level security;
alter table public.cheers   enable row level security;
alter table public.settings enable row level security;
alter table public.invites  enable row level security;

grant select, insert, update, delete on public.profiles, public.members, public.boards, public.cheers, public.settings, public.invites to authenticated;
revoke all on public.profiles, public.members, public.boards, public.cheers, public.settings, public.invites from anon;

-- profiles: members see each other; only admins change roles or remove people (never themselves).
drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles for select to authenticated using (public.is_member());
drop policy if exists profiles_admin_update on public.profiles;
create policy profiles_admin_update on public.profiles for update to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists profiles_admin_delete on public.profiles;
create policy profiles_admin_delete on public.profiles for delete to authenticated using (public.is_admin() and id <> auth.uid());

-- members: public stats card. Everyone in the group reads; you write your own; admins can clear any.
drop policy if exists members_read on public.members;
create policy members_read on public.members for select to authenticated using (public.is_member());
drop policy if exists members_insert on public.members;
create policy members_insert on public.members for insert to authenticated with check (id = auth.uid() and public.is_member());
drop policy if exists members_update on public.members;
create policy members_update on public.members for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
drop policy if exists members_delete on public.members;
create policy members_delete on public.members for delete to authenticated using (id = auth.uid() or public.is_admin());

-- boards: your private quest board. Only you.
drop policy if exists boards_own on public.boards;
create policy boards_own on public.boards for all to authenticated using (id = auth.uid()) with check (id = auth.uid() and public.is_member());

-- cheers: high-fives. Everyone reads; you write your own.
drop policy if exists cheers_read on public.cheers;
create policy cheers_read on public.cheers for select to authenticated using (public.is_member());
drop policy if exists cheers_insert on public.cheers;
create policy cheers_insert on public.cheers for insert to authenticated with check (id = auth.uid() and public.is_member());
drop policy if exists cheers_update on public.cheers;
create policy cheers_update on public.cheers for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
drop policy if exists cheers_delete on public.cheers;
create policy cheers_delete on public.cheers for delete to authenticated using (id = auth.uid() or public.is_admin());

-- settings: announcements, challenge, group goal. Everyone reads; admins write.
drop policy if exists settings_read on public.settings;
create policy settings_read on public.settings for select to authenticated using (public.is_member());
drop policy if exists settings_admin_insert on public.settings;
create policy settings_admin_insert on public.settings for insert to authenticated with check (public.is_admin());
drop policy if exists settings_admin_update on public.settings;
create policy settings_admin_update on public.settings for update to authenticated using (public.is_admin()) with check (public.is_admin());

-- invites: admins only.
drop policy if exists invites_admin on public.invites;
create policy invites_admin on public.invites for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ---------- live updates ----------
do $$
declare t text;
begin
  foreach t in array array['profiles', 'members', 'cheers', 'settings'] loop
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
