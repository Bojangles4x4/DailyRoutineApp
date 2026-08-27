create table if not exists public.routine_documents (
  owner_id uuid primary key references auth.users(id) on delete cascade,
  schema_version integer not null default 1 check (schema_version > 0),
  revision bigint not null default 1 check (revision > 0),
  document jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by text not null default '' check (char_length(updated_by) <= 100)
);

alter table public.routine_documents enable row level security;

revoke all on table public.routine_documents from anon, authenticated;
grant select, insert, update, delete on table public.routine_documents to authenticated;

drop policy if exists "Owners can read their routine document" on public.routine_documents;
create policy "Owners can read their routine document"
on public.routine_documents for select
to authenticated
using ((select auth.uid()) = owner_id);

drop policy if exists "Owners can create their routine document" on public.routine_documents;
create policy "Owners can create their routine document"
on public.routine_documents for insert
to authenticated
with check ((select auth.uid()) = owner_id);

drop policy if exists "Owners can update their routine document" on public.routine_documents;
create policy "Owners can update their routine document"
on public.routine_documents for update
to authenticated
using ((select auth.uid()) = owner_id)
with check ((select auth.uid()) = owner_id);

drop policy if exists "Owners can delete their routine document" on public.routine_documents;
create policy "Owners can delete their routine document"
on public.routine_documents for delete
to authenticated
using ((select auth.uid()) = owner_id);

create or replace function public.advance_routine_document_revision()
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

drop trigger if exists routine_documents_advance_revision on public.routine_documents;
create trigger routine_documents_advance_revision
before update on public.routine_documents
for each row execute function public.advance_routine_document_revision();

comment on table public.routine_documents is
  'One private, versioned routine document per authenticated owner. Partner access is intentionally not enabled in the sync foundation.';
