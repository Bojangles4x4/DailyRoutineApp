create table if not exists public.accountability_relationships (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  owner_display_name text not null default '' check (char_length(owner_display_name) <= 80),
  partner_id uuid references auth.users(id) on delete set null,
  partner_email text not null check (char_length(partner_email) between 3 and 320),
  partner_display_name text not null default '' check (char_length(partner_display_name) <= 80),
  status text not null default 'pending' check (status in ('pending', 'active', 'paused', 'revoked')),
  permissions jsonb not null default '{"progressTotals":true,"routineNames":true,"checkins":false,"steps":false,"medication":false}'::jsonb,
  invited_at timestamptz not null default now(),
  accepted_at timestamptz,
  updated_at timestamptz not null default now(),
  revoked_at timestamptz
);

create unique index if not exists accountability_relationships_active_email_idx
on public.accountability_relationships (owner_id, lower(partner_email))
where status <> 'revoked';

create index if not exists accountability_relationships_partner_idx
on public.accountability_relationships (partner_id, status);

create table if not exists public.accountability_snapshots (
  relationship_id uuid primary key references public.accountability_relationships(id) on delete cascade,
  owner_id uuid not null references auth.users(id) on delete cascade,
  schema_version integer not null default 1 check (schema_version > 0),
  revision bigint not null default 1 check (revision > 0),
  payload jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.accountability_relationships enable row level security;
alter table public.accountability_snapshots enable row level security;

revoke all on table public.accountability_relationships from anon, authenticated;
revoke all on table public.accountability_snapshots from anon, authenticated;
grant select, insert, update, delete on table public.accountability_relationships to authenticated;
grant select, insert, update, delete on table public.accountability_snapshots to authenticated;

drop policy if exists "Owners read accountability relationships" on public.accountability_relationships;
create policy "Owners read accountability relationships"
on public.accountability_relationships
for select to authenticated
using ((select auth.uid()) = owner_id);

drop policy if exists "Owners create pending accountability relationships" on public.accountability_relationships;
create policy "Owners create pending accountability relationships"
on public.accountability_relationships
for insert to authenticated
with check ((select auth.uid()) = owner_id and partner_id is null and status = 'pending');

drop policy if exists "Owners update accountability relationships" on public.accountability_relationships;
create policy "Owners update accountability relationships"
on public.accountability_relationships
for update to authenticated
using ((select auth.uid()) = owner_id)
with check ((select auth.uid()) = owner_id);

drop policy if exists "Owners delete accountability relationships" on public.accountability_relationships;
create policy "Owners delete accountability relationships"
on public.accountability_relationships
for delete to authenticated
using ((select auth.uid()) = owner_id);

drop policy if exists "Active partners read their relationships" on public.accountability_relationships;
create policy "Active partners read their relationships"
on public.accountability_relationships
for select to authenticated
using ((select auth.uid()) = partner_id and status = 'active');

create or replace function public.protect_accountability_acceptance_fields()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if (select auth.uid()) = old.owner_id
    and (new.partner_id is distinct from old.partner_id or new.accepted_at is distinct from old.accepted_at) then
    raise exception 'Invitation acceptance fields can only be changed by the invited partner.' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists accountability_relationships_protect_acceptance on public.accountability_relationships;
create trigger accountability_relationships_protect_acceptance
before update on public.accountability_relationships
for each row execute function public.protect_accountability_acceptance_fields();

drop policy if exists "Owners manage accountability snapshots" on public.accountability_snapshots;
create policy "Owners manage accountability snapshots"
on public.accountability_snapshots
for all to authenticated
using ((select auth.uid()) = owner_id)
with check (
  (select auth.uid()) = owner_id
  and exists (
    select 1 from public.accountability_relationships relationship
    where relationship.id = relationship_id
      and relationship.owner_id = (select auth.uid())
  )
);

drop policy if exists "Active partners read shared snapshots" on public.accountability_snapshots;
create policy "Active partners read shared snapshots"
on public.accountability_snapshots
for select to authenticated
using (
  exists (
    select 1 from public.accountability_relationships relationship
    where relationship.id = relationship_id
      and relationship.partner_id = (select auth.uid())
      and relationship.status = 'active'
  )
);

create or replace function public.advance_accountability_snapshot_revision()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.revision := old.revision + 1;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists accountability_snapshots_advance_revision on public.accountability_snapshots;
create trigger accountability_snapshots_advance_revision
before update on public.accountability_snapshots
for each row execute function public.advance_accountability_snapshot_revision();

create or replace function public.accept_accountability_invitation(invitation_id uuid)
returns public.accountability_relationships
language plpgsql
security definer
set search_path = ''
as $$
declare
  invitation public.accountability_relationships;
  signed_in_email text;
begin
  if (select auth.uid()) is null then
    raise exception 'Sign in before accepting an invitation.' using errcode = '42501';
  end if;

  signed_in_email := lower(coalesce((select auth.jwt()) ->> 'email', ''));

  update public.accountability_relationships
  set partner_id = (select auth.uid()),
      status = 'active',
      accepted_at = coalesce(accepted_at, now()),
      updated_at = now()
  where id = invitation_id
    and status = 'pending'
    and lower(partner_email) = signed_in_email
  returning * into invitation;

  if invitation.id is null then
    raise exception 'This invitation is unavailable or belongs to another email address.' using errcode = '42501';
  end if;

  return invitation;
end;
$$;

revoke all on function public.accept_accountability_invitation(uuid) from public, anon;
grant execute on function public.accept_accountability_invitation(uuid) to authenticated;

comment on table public.accountability_relationships is
  'Owner-controlled accountability connections. Each relationship has independent permissions and lifecycle status.';

comment on table public.accountability_snapshots is
  'Privacy-filtered progress only. Full routine documents, notes, prayer text, medication names/times, and raw Health data are never stored here.';
