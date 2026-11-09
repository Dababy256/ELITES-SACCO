-- Verified-user, append-only SELF-ATTESTED browser acceptance receipts.
-- Not a financial posting, and not an automatic production release authorization.
begin;
create table public.sacco_member_readiness_signoffs (
 id uuid primary key default gen_random_uuid(),
 member_id uuid not null references public.sacco_members(id) on delete restrict,
 auth_user_id uuid not null references auth.users(id) on delete restrict,
 checks_passed integer not null check (checks_passed=8),
 checks_total integer not null check (checks_total=8),
 checks_version text not null default 'member-browser-v1' check (checks_version='member-browser-v1'),
 attestation text not null check (
  attestation='I personally ran and passed all eight checks in my signed-in browser.'
 ),
 accepted_at timestamptz not null default now()
);
create index sacco_readiness_signoffs_recent
on public.sacco_member_readiness_signoffs(member_id,accepted_at desc);
alter table public.sacco_member_readiness_signoffs enable row level security;
revoke all on public.sacco_member_readiness_signoffs from public,anon,authenticated;
grant select,insert on public.sacco_member_readiness_signoffs to authenticated;
create policy sacco_readiness_signoffs_own_and_admin_read
on public.sacco_member_readiness_signoffs for select to authenticated
using (
 auth_user_id=(select auth.uid())
 or (select sacco_private.is_sacco_admin())
);
create policy sacco_readiness_signoffs_member_self_report
on public.sacco_member_readiness_signoffs for insert to authenticated
with check (
 auth_user_id=(select auth.uid()) and
 exists(select 1 from public.sacco_members m
  where m.id=member_id
  and m.auth_user_id=(select auth.uid()))
);
commit;