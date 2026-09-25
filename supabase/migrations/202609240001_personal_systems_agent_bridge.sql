create table if not exists public.agent_snapshots (
  owner_id uuid primary key references auth.users(id) on delete cascade,
  schema_version integer not null default 1 check (schema_version > 0),
  revision bigint not null default 1 check (revision > 0),
  payload jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by text not null default '' check (char_length(updated_by) <= 100)
);

alter table public.agent_snapshots enable row level security;

revoke all on table public.agent_snapshots from anon, authenticated;
grant select, insert, update, delete on table public.agent_snapshots to authenticated;

drop policy if exists "Owners read their agent snapshot" on public.agent_snapshots;
create policy "Owners read their agent snapshot"
on public.agent_snapshots for select
to authenticated
using ((select auth.uid()) = owner_id);

drop policy if exists "Owners create their agent snapshot" on public.agent_snapshots;
create policy "Owners create their agent snapshot"
on public.agent_snapshots for insert
to authenticated
with check ((select auth.uid()) = owner_id);

drop policy if exists "Owners update their agent snapshot" on public.agent_snapshots;
create policy "Owners update their agent snapshot"
on public.agent_snapshots for update
to authenticated
using ((select auth.uid()) = owner_id)
with check ((select auth.uid()) = owner_id);

drop policy if exists "Owners delete their agent snapshot" on public.agent_snapshots;
create policy "Owners delete their agent snapshot"
on public.agent_snapshots for delete
to authenticated
using ((select auth.uid()) = owner_id);

create or replace function public.advance_agent_snapshot_revision()
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

drop trigger if exists agent_snapshots_advance_revision on public.agent_snapshots;
create trigger agent_snapshots_advance_revision
before update on public.agent_snapshots
for each row execute function public.advance_agent_snapshot_revision();

comment on table public.agent_snapshots is
  'One owner-only, privacy-minimized routine snapshot for the Personal Systems Agent. It excludes notes, memories, raw Health values, medication details, and text responses.';
