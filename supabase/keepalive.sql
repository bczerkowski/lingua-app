-- Keepalive table for .github/workflows/keepalive.yml.
-- Run once in Supabase → SQL Editor (project "lexicon").
-- The workflow upserts row id=1 every ~2 days so the free-tier project
-- registers real database writes and is not auto-paused.

create table if not exists public.keepalive (
  id        int primary key,
  pinged_at timestamptz not null default now()
);

alter table public.keepalive enable row level security;

-- anon may only read/write the single row id=1; nothing else in the DB.
drop policy if exists "keepalive anon" on public.keepalive;
create policy "keepalive anon" on public.keepalive
  for all to anon
  using (id = 1)
  with check (id = 1);

grant select, insert, update on public.keepalive to anon;

insert into public.keepalive (id) values (1) on conflict (id) do nothing;
