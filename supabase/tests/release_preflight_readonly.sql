-- Elites SACCO release preflight, read-only.
-- Run against the dedicated staging Supabase project; never enables posting or changes data.
-- Does NOT replace the original-site JSON reconciliation or posting acceptance tests.
with checks as (
 select
 (select count(*) from public.sacco_members) as member_count,
 (select count(*) from public.sacco_members where auth_user_id is not null) as linked_members,
 (select count(*) from public.sacco_contributions) as contribution_count,
 (select coalesce(sum(amount),0) from public.sacco_contributions) as contributions_ugx,
 (select count(*) from public.sacco_loans) as loan_count,
 (select count(*) from public.sacco_repayments) as repayment_count,
 (select count(*) from public.sacco_posting_receipts) as posting_receipts,
 (select enabled from sacco_private.posting_control where singleton) as posting_enabled,
 has_function_privilege('authenticated','public.sacco_post_approved_draft(uuid)','EXECUTE') as authenticated_can_post,
 has_function_privilege('anon','public.sacco_post_approved_draft(uuid)','EXECUTE') as anonymous_can_post,
 (select count(*) from public.sacco_repayments r left join public.sacco_loans l
   on l.id=r.loan_id and l.member_id=r.member_id where l.id is null) as orphaned_repayments,
 (select count(*) from public.sacco_repayments r join public.sacco_loans l
   on l.id=r.loan_id where r.paid_on<l.issued_on) as repayments_before_issuance,
 (select count(*) from public.sacco_contributions where amount<=0 or paid_on is null) as invalid_contributions,
 (select count(*) from public.sacco_loans where principal<=0) as invalid_loans,
 (select count(*) from public.sacco_repayments where amount<=0) as invalid_repayments,
 (select count(*) from (select member_id,issued_on,principal from public.sacco_loans
   group by member_id,issued_on,principal having count(*)>1) dup) as potential_duplicate_loans,
 (select count(*) from (select loan_id,paid_on,amount from public.sacco_repayments
   group by loan_id,paid_on,amount having count(*)>1) dup) as potential_duplicate_repayments,
 (select count(*) from (select member_id,contribution_month,paid_on,amount from public.sacco_contributions
   group by member_id,contribution_month,paid_on,amount having count(*)>1) dup) as potential_duplicate_contributions
)
select
 member_count,linked_members,contribution_count,contributions_ugx,loan_count,repayment_count,
 posting_receipts,posting_enabled,authenticated_can_post,anonymous_can_post,
 orphaned_repayments,repayments_before_issuance,invalid_contributions,invalid_loans,
 invalid_repayments,potential_duplicate_loans,potential_duplicate_repayments,potential_duplicate_contributions,
 (orphaned_repayments=0 and repayments_before_issuance=0 and
  invalid_contributions=0 and invalid_loans=0 and invalid_repayments=0 and
  potential_duplicate_loans=0 and potential_duplicate_repayments=0 and potential_duplicate_contributions=0)
  as basic_record_integrity_pass,
 (not posting_enabled and not authenticated_can_post and not anonymous_can_post and posting_receipts=0)
  as posting_gate_closed,
 (linked_members=member_count) as membership_onboarding_complete
from checks;
