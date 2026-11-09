-- Elites SACCO read-only pre-cutover gate, 9 November 2026.
-- NO ledger writes, no auth changes, no release activation.
with counts as (
 select
  (select count(*) from public.sacco_members) members,
  (select count(*) from public.sacco_members where auth_user_id is not null) linked_accounts,
  (select count(*) from public.sacco_members m join auth.users u on m.auth_user_id=u.id where u.email_confirmed_at is not null) verified_accounts,
  (select count(*) from public.sacco_member_readiness_signoffs s
   join public.sacco_members m on m.id=s.member_id where m.member_role='admin') admin_signoffs,
  (select count(*) from public.sacco_member_readiness_signoffs s
   join public.sacco_members m on m.id=s.member_id where m.member_role='member') ordinary_signoffs,
  (select count(*) from public.sacco_contributions) contributions,
  (select coalesce(sum(amount),0) from public.sacco_contributions) savings_ugx,
  (select count(*) from public.sacco_loans) loans,
  (select count(*) from public.sacco_repayments) repayments,
  (select count(*) from public.sacco_repayments r
   join public.sacco_loans l on l.id=r.loan_id and l.member_id=r.member_id
   where r.source_record->>'loanId'=l.loan_number::text and r.paid_on>=l.issued_on) verified_repayment_links,
  (select count(*) from public.sacco_posting_receipts) native_postings,
  (select count(*) from public.sacco_posting_reversals) native_reversals,
  (select count(*) from public.sacco_staging_drafts) lingering_drafts,
  (select count(*) from public.sacco_staging_reviews) lingering_reviews,
  (select count(*) from public.sacco_branding) branding_rows,
  (select count(*) from public.sacco_members where photo_data is not null) private_photos,
  (select count(*) from public.sacco_audit_entries where event_kind='LEGACY_LOG') historical_edits,
  (select count(*) from public.sacco_source_manifest
    where backup_sha256='b4b200618f2e74c1ebdc3a567c2eb5ac1a33b6ee58994d4913dcae86f5ee8837'
    and status='USER_ATTESTED_UNCHANGED') original_source_manifest
), permission_state as (
 select
  (select enabled from sacco_private.posting_control where singleton) posting_gate,
  has_function_privilege('authenticated','public.sacco_post_approved_draft(uuid)','EXECUTE') public_post_call,
  has_function_privilege('authenticated','sacco_private.sacco_post_approved_draft(uuid)','EXECUTE') private_post_call,
  has_function_privilege('authenticated','public.sacco_reverse_posted_entry(uuid,uuid,text,text)','EXECUTE') public_reverse_call,
  has_function_privilege('authenticated','sacco_private.sacco_reverse_posted_entry(uuid,uuid,text,text)','EXECUTE') private_reverse_call,
  (select count(*) from pg_proc p join pg_namespace n on p.pronamespace=n.oid
   where n.nspname='public'
   and p.proname in ('sacco_post_approved_draft','sacco_reverse_posted_entry')
   and p.prosecdef) public_definer_count
)
select
 c.members,c.linked_accounts,c.verified_accounts,
 c.admin_signoffs,c.ordinary_signoffs,
 (c.original_source_manifest=1 and c.contributions=133 and c.savings_ugx=13965000
  and c.loans=28 and c.repayments=27 and c.verified_repayment_links=27) source_finances_verified,
 (c.branding_rows=1 and c.private_photos=1 and c.historical_edits=13) evidence_preserved,
 (c.lingering_drafts=0 and c.lingering_reviews=0) no_old_approved_drafts,
 (c.native_postings=0 and c.native_reversals=0 and not p.posting_gate
  and not p.public_post_call and not p.private_post_call
  and not p.public_reverse_call and not p.private_reverse_call) financial_posting_locked,
 (p.public_definer_count=0) privileged_public_apis_eliminated,
 (c.admin_signoffs>=1) administrator_acceptance_recorded,
 (c.ordinary_signoffs>=1) ordinary_member_acceptance_recorded,
 false as legacy_jsonbin_writes_technically_disabled_not_yet_confirmed,
 false as password_recovery_real_mailbox_test_not_yet_confirmed,
 false as final_cutover_separately_authorized,
 'READY FOR CONTROLLED RELEASE PLANNING ONLY; DO NOT START NATIVE POSTING' as conclusion
from counts c cross join permission_state p;