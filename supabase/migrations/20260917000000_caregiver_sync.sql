-- Baby Feed: shared feeding log for several caregivers.
-- One "baby" row, any number of members. Feeds and weights are synced rows
-- keyed by the client-generated UUID; deletes are soft so they propagate.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------- tables

create table public.babies (
  id uuid primary key,
  name text not null default '',
  birth_date timestamptz,
  created_by uuid not null references auth.users(id) on delete cascade,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now()
);

create table public.baby_members (
  baby_id uuid not null references public.babies(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'caregiver' check (role in ('owner', 'caregiver')),
  display_name text not null default '',
  joined_at timestamptz not null default now(),
  primary key (baby_id, user_id)
);

create table public.baby_invites (
  code text primary key,
  baby_id uuid not null references public.babies(id) on delete cascade,
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '7 days',
  max_uses int not null default 20,
  uses int not null default 0
);

create table public.feeds (
  id uuid primary key,
  baby_id uuid not null references public.babies(id) on delete cascade,
  start_time timestamptz not null,
  kind text not null,
  amount_ml double precision,
  duration_minutes int,
  side text,
  note text not null default '',
  logged_by uuid references auth.users(id) on delete set null,
  logged_by_name text not null default '',
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now()
);
create index feeds_baby_server_updated_idx on public.feeds (baby_id, server_updated_at);

create table public.weights (
  id uuid primary key,
  baby_id uuid not null references public.babies(id) on delete cascade,
  date timestamptz not null,
  grams double precision not null,
  note text not null default '',
  logged_by uuid references auth.users(id) on delete set null,
  logged_by_name text not null default '',
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now()
);
create index weights_baby_server_updated_idx on public.weights (baby_id, server_updated_at);

-- ---------------------------------------------------------------- triggers

-- server_updated_at is the server's clock; clients pull "everything since"
-- by it, and merge by the client-side updated_at.
create or replace function public.touch_server_updated_at()
returns trigger language plpgsql as $$
begin
  new.server_updated_at := now();
  return new;
end $$;

create trigger babies_touch before insert or update on public.babies
  for each row execute function public.touch_server_updated_at();
create trigger feeds_touch before insert or update on public.feeds
  for each row execute function public.touch_server_updated_at();
create trigger weights_touch before insert or update on public.weights
  for each row execute function public.touch_server_updated_at();

-- Whoever creates a baby is its owner.
create or replace function public.add_owner_membership()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.baby_members (baby_id, user_id, role)
  values (new.id, new.created_by, 'owner')
  on conflict do nothing;
  return new;
end $$;

create trigger babies_add_owner after insert on public.babies
  for each row execute function public.add_owner_membership();

-- ---------------------------------------------------------------- helpers

create or replace function public.is_baby_member(p_baby_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.baby_members m
    where m.baby_id = p_baby_id and m.user_id = auth.uid()
  );
$$;

create or replace function public.is_baby_owner(p_baby_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.baby_members m
    where m.baby_id = p_baby_id and m.user_id = auth.uid() and m.role = 'owner'
  );
$$;

-- ---------------------------------------------------------------- RLS

alter table public.babies enable row level security;
alter table public.baby_members enable row level security;
alter table public.baby_invites enable row level security;
alter table public.feeds enable row level security;
alter table public.weights enable row level security;

create policy "members read babies" on public.babies
  for select using (public.is_baby_member(id));
create policy "signed-in users create babies" on public.babies
  for insert with check (auth.uid() = created_by);
create policy "members update babies" on public.babies
  for update using (public.is_baby_member(id)) with check (public.is_baby_member(id));

create policy "members read members" on public.baby_members
  for select using (public.is_baby_member(baby_id));
create policy "members update own row" on public.baby_members
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "self or owner removes members" on public.baby_members
  for delete using (user_id = auth.uid() or public.is_baby_owner(baby_id));
-- Inserts happen only through join_baby() and the owner trigger.

create policy "members read invites" on public.baby_invites
  for select using (public.is_baby_member(baby_id));
create policy "members revoke invites" on public.baby_invites
  for delete using (public.is_baby_member(baby_id));
-- Inserts happen only through create_invite().

create policy "members read feeds" on public.feeds
  for select using (public.is_baby_member(baby_id));
create policy "members add feeds" on public.feeds
  for insert with check (public.is_baby_member(baby_id));
create policy "members update feeds" on public.feeds
  for update using (public.is_baby_member(baby_id)) with check (public.is_baby_member(baby_id));

create policy "members read weights" on public.weights
  for select using (public.is_baby_member(baby_id));
create policy "members add weights" on public.weights
  for insert with check (public.is_baby_member(baby_id));
create policy "members update weights" on public.weights
  for update using (public.is_baby_member(baby_id)) with check (public.is_baby_member(baby_id));

-- ---------------------------------------------------------------- RPCs

-- Returns a fresh 6-character invite code for a baby the caller belongs to.
create or replace function public.create_invite(p_baby_id uuid)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_code text;
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; -- no 0/O/1/I
  i int;
begin
  if auth.uid() is null then
    raise exception 'Sign in first';
  end if;
  if not public.is_baby_member(p_baby_id) then
    raise exception 'You are not a caregiver of this baby';
  end if;

  loop
    v_code := '';
    for i in 1..6 loop
      v_code := v_code || substr(v_alphabet, 1 + floor(random() * length(v_alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from public.baby_invites where code = v_code);
  end loop;

  insert into public.baby_invites (code, baby_id, created_by)
  values (v_code, p_baby_id, auth.uid());

  return v_code;
end $$;

-- Redeems an invite code and returns the baby row the caller just joined.
create or replace function public.join_baby(p_code text, p_display_name text default '')
returns setof public.babies language plpgsql security definer set search_path = public as $$
declare
  v_invite public.baby_invites%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Sign in first';
  end if;

  select * into v_invite
  from public.baby_invites
  where code = upper(regexp_replace(p_code, '[^A-Za-z0-9]', '', 'g'))
  for update;

  if not found then
    raise exception 'That code is not valid';
  end if;
  if v_invite.expires_at < now() then
    raise exception 'That code has expired. Ask for a new one.';
  end if;
  if v_invite.uses >= v_invite.max_uses then
    raise exception 'That code has been used too many times. Ask for a new one.';
  end if;

  insert into public.baby_members (baby_id, user_id, role, display_name)
  values (v_invite.baby_id, auth.uid(), 'caregiver', coalesce(p_display_name, ''))
  on conflict (baby_id, user_id) do update
    set display_name = case
      when excluded.display_name <> '' then excluded.display_name
      else public.baby_members.display_name
    end;

  update public.baby_invites set uses = uses + 1 where code = v_invite.code;

  return query select * from public.babies where id = v_invite.baby_id;
end $$;

grant execute on function public.create_invite(uuid) to authenticated;
grant execute on function public.join_baby(text, text) to authenticated;

-- ---------------------------------------------------------------- realtime

alter publication supabase_realtime add table public.feeds, public.weights, public.babies, public.baby_members;
