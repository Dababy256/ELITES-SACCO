-- ELITES SACCO: safe migration foundation
-- Run on an empty, verified Supabase project; do not run against an unknown populated DB.
-- Contains no historical financial data and does not modify JSONBin.
create table if not exists public.sacco_members (
 id uuid primary key default gen_random_uuid(),
 legacy_name text not null unique,
 display_name text not null,
 auth_user_id uuid unique references auth.users(id) on delete set null,
 member_role text not null default 'member' check (member_role in ('member','admin')),
 photo_data text,
 created_at timestamptz not null default now()
);
create table if not exists public.sacco_settings (
 singleton_id boolean primary key default true check (singleton_id),
 value jsonb not null default '{}'::jsonb,
 updated_at timestamptz not null default now()
);
create table if not exists public.sacco_import_runs (
 id uuid primary key default gen_random_uuid(),
 backup_sha256 text not null unique,
 totals jsonb not null,
 imported_at timestamptz not null default now()
);
-- RLS is on from the start. Never create an "allow all" policy.
alter table public.sacco_members enable row level security;
alter table public.sacco_settings enable row level security;
alter table public.sacco_import_runs enable row level security;
revoke all on public.sacco_members, public.sacco_settings, public.sacco_import_runs from public, anon, authenticated;
grant select, insert, update, delete on public.sacco_members, public.sacco_settings, public.sacco_import_runs to service_role;
-- Role check lives in a non-API-exposed schema to avoid recursive RLS.
create schema if not exists sacco_private;
revoke all on schema sacco_private from public;
grant usage on schema sacco_private to authenticated;
create or replace function sacco_private.is_admin() returns boolean
language sql stable security definer set search_path=''
as $$ select (select auth.uid()) is not null and exists
 (select 1 from public.sacco_members m
  where m.auth_user_id=(select auth.uid()) and m.member_role='admin') $$;
revoke all on function sacco_private.is_admin() from public, anon;
grant execute on function sacco_private.is_admin() to authenticated;
grant select on public.sacco_members, public.sacco_settings to authenticated;
create policy sacco_members_select on public.sacco_members
 for select to authenticated
 using (auth_user_id=(select auth.uid()) or (select sacco_private.is_admin()));
create policy sacco_settings_select on public.sacco_settings
 for select to authenticated using (true);
-- RLS defaults to DENY for other operations. Only trusted service-role
-- import/onboarding code can set admin rights and link auth identities.
