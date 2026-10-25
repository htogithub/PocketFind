-- PocketFind - Supabase setup
-- Run this whole file once in Supabase > SQL Editor.
-- It is safe to run again: every object is created or replaced.
-- All objects are prefixed with pf_ so they can live next to other apps
-- in the same Supabase project.

-- ---------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------

create table if not exists public.pf_profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  name        text not null check (char_length(name) between 1 and 24),
  code        text not null unique,
  color       text not null default '#2D5BFF' check (color ~ '^#[0-9A-Fa-f]{6}$'),
  created_at  timestamptz not null default now()
);

create table if not exists public.pf_friends (
  user_id     uuid not null references public.pf_profiles(id) on delete cascade,
  friend_id   uuid not null references public.pf_profiles(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (user_id, friend_id),
  check (user_id <> friend_id)
);
create index if not exists pf_friends_friend_idx on public.pf_friends(friend_id);

-- One row per person: their last known position.
-- lat/lng are null while the person is in ghost mode.
create table if not exists public.pf_locations (
  user_id     uuid primary key references public.pf_profiles(id) on delete cascade,
  lat         double precision,
  lng         double precision,
  accuracy    real,
  ghost       boolean not null default false,
  updated_at  timestamptz not null default now()
);

-- The server clock decides when a position was sent.
create or replace function public.pf_touch()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists pf_locations_touch on public.pf_locations;
create trigger pf_locations_touch
  before insert or update on public.pf_locations
  for each row execute function public.pf_touch();

-- ---------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------

alter table public.pf_profiles  enable row level security;
alter table public.pf_friends   enable row level security;
alter table public.pf_locations enable row level security;

create or replace function public.pf_is_friend(other uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.pf_friends
    where user_id = auth.uid() and friend_id = other
  );
$$;

drop policy if exists pf_profiles_select on public.pf_profiles;
create policy pf_profiles_select on public.pf_profiles
  for select to authenticated
  using (id = auth.uid() or public.pf_is_friend(id));

drop policy if exists pf_profiles_update on public.pf_profiles;
create policy pf_profiles_update on public.pf_profiles
  for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- Only the name and the colour can be changed by the app; the code is fixed.
revoke update on public.pf_profiles from authenticated, anon;
grant  update (name, color) on public.pf_profiles to authenticated;

drop policy if exists pf_friends_select on public.pf_friends;
create policy pf_friends_select on public.pf_friends
  for select to authenticated
  using (user_id = auth.uid());

drop policy if exists pf_locations_select on public.pf_locations;
create policy pf_locations_select on public.pf_locations
  for select to authenticated
  using (user_id = auth.uid() or public.pf_is_friend(user_id));

drop policy if exists pf_locations_insert on public.pf_locations;
create policy pf_locations_insert on public.pf_locations
  for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists pf_locations_update on public.pf_locations;
create policy pf_locations_update on public.pf_locations
  for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------------------------------------------------------------
-- Functions called by the app
-- ---------------------------------------------------------------

-- Creates the caller's profile with a unique 6-character code
-- (or renames it if it already exists).
create or replace function public.pf_create_profile(p_name text, p_color text default '#2D5BFF')
returns public.pf_profiles
language plpgsql security definer set search_path = public as $$
declare
  v_row   public.pf_profiles;
  v_code  text;
  v_abc   text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  i       int;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;

  select * into v_row from public.pf_profiles where id = auth.uid();
  if found then
    update public.pf_profiles
       set name = left(btrim(p_name), 24), color = p_color
     where id = auth.uid()
     returning * into v_row;
    return v_row;
  end if;

  loop
    v_code := '';
    for i in 1..6 loop
      v_code := v_code || substr(v_abc, 1 + floor(random() * length(v_abc))::int, 1);
    end loop;
    exit when not exists (select 1 from public.pf_profiles where code = v_code);
  end loop;

  insert into public.pf_profiles (id, name, code, color)
  values (auth.uid(), left(btrim(p_name), 24), v_code, p_color)
  returning * into v_row;
  return v_row;
end;
$$;

-- Adds someone by their code. Both people become friends at once.
create or replace function public.pf_add_friend(p_code text)
returns json
language plpgsql security definer set search_path = public as $$
declare
  v_friend public.pf_profiles;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;

  select * into v_friend from public.pf_profiles
   where code = upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  if not found then
    raise exception 'code_not_found';
  end if;
  if v_friend.id = auth.uid() then
    raise exception 'own_code';
  end if;

  insert into public.pf_friends (user_id, friend_id)
  values (auth.uid(), v_friend.id), (v_friend.id, auth.uid())
  on conflict do nothing;

  return json_build_object('id', v_friend.id, 'name', v_friend.name, 'color', v_friend.color);
end;
$$;

-- Removes a friend in both directions.
create or replace function public.pf_remove_friend(p_friend uuid)
returns void
language sql security definer set search_path = public as $$
  delete from public.pf_friends
   where (user_id = auth.uid() and friend_id = p_friend)
      or (user_id = p_friend and friend_id = auth.uid());
$$;

-- Deletes the caller's account and everything attached to it.
create or replace function public.pf_delete_me()
returns void
language sql security definer set search_path = public, auth as $$
  delete from auth.users where id = auth.uid();
$$;

revoke execute on function public.pf_create_profile(text, text) from public, anon;
revoke execute on function public.pf_add_friend(text)           from public, anon;
revoke execute on function public.pf_remove_friend(uuid)        from public, anon;
revoke execute on function public.pf_delete_me()                from public, anon;
grant  execute on function public.pf_create_profile(text, text) to authenticated;
grant  execute on function public.pf_add_friend(text)           to authenticated;
grant  execute on function public.pf_remove_friend(uuid)        to authenticated;
grant  execute on function public.pf_delete_me()                to authenticated;

-- ---------------------------------------------------------------
-- Realtime
-- ---------------------------------------------------------------

do $$
begin
  alter publication supabase_realtime add table public.pf_locations;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.pf_friends;
exception when duplicate_object then null;
end $$;
