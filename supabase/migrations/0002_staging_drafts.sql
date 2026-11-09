-- Elites SACCO staging-only transaction proposals.
-- Financial balances remain derived exclusively from the immutable imported ledger.
begin;
create table if not exists public.sacco_staging_drafts (
 id uuid primary key default gen_random_uuid(),
 created_by uuid not null references auth.users(id) default auth.uid(),
 action_kind text not null check (action_kind in ('CONTRIBUTION','LOAN','REPAYMENT','EXPENSE','INVESTMENT','CASH_IN','MEMBERSHIP_FEE','WAIVER')),
 payload jsonb not null check (jsonb_typeof(payload)='object' and octet_length(payload::text)<=8192),
 created_at timestamptz not null default now()
);
alter table public.sacco_staging_drafts enable row level security;
revoke all on public.sacco_staging_drafts from public,anon,authenticated;
grant select,insert on public.sacco_staging_drafts to authenticated;
grant select,insert,update,delete on public.sacco_staging_drafts to service_role;
create policy sacco_staging_drafts_admin_select on public.sacco_staging_drafts
 for select to authenticated using ((select sacco_private.is_sacco_admin()));
create policy sacco_staging_drafts_admin_insert on public.sacco_staging_drafts
 for insert to authenticated with check(
 created_by=(select auth.uid()) and (select sacco_private.is_sacco_admin())
);
create index sacco_staging_drafts_created_idx on public.sacco_staging_drafts(created_at desc);
-- Disallow mutation of approved historical ledger via client API while testing.
-- Historical records remain intact; new entries are still blocked from the test UI.
revoke update,delete on public.sacco_contributions,public.sacco_loans,public.sacco_repayments,
 public.sacco_financial_entries,public.sacco_membership_fees,public.sacco_waivers from authenticated;
commit;
