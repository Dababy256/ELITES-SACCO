-- RLS smoke test for any linked ordinary member. READ-ONLY; transaction rolls back.
-- Intended to be executed as an administrator via the dedicated Supabase SQL editor.
-- Note: intentionally impersonates only the *database request claims* for RLS testing;
-- it does not create a real session or establish end-to-end browser authorization.
begin;
select set_config('request.jwt.claim.sub',(
 select auth_user_id::text from public.sacco_members
 where member_role='member' and auth_user_id is not null
 order by created_at limit 1),true);
set local role authenticated;
with self as (select id from public.sacco_members where auth_user_id=(select auth.uid()))
select
 (select count(*) from public.sacco_members) visible_member_records,
 (select count(*) from public.sacco_members where id not in (select id from self)) other_member_records,
 (select count(*) from public.sacco_contributions where member_id not in (select id from self)) other_contributions,
 (select count(*) from public.sacco_loans where member_id not in (select id from self)) other_loans,
 (select count(*) from public.sacco_repayments where member_id not in (select id from self)) other_repayments,
 (select count(*) from public.sacco_financial_entries) private_cashbook_records,
 (select count(*) from public.sacco_audit_entries) private_audit_records,
 (select count(*) from public.sacco_staging_drafts) private_drafts,
 (select count(*) from public.sacco_staging_reviews) private_draft_reviews,
 has_table_privilege('public.sacco_loans','INSERT') direct_loan_insert,
 has_function_privilege('public.sacco_post_approved_draft(uuid)','EXECUTE') can_post_to_ledger;
rollback;
