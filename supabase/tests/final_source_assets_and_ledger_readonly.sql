-- Final historical-source archive preflight, read-only.
-- Operates on private imported evidence; never returns PINs, photos or log contents.
with log_hashes as (
 select md5(
  coalesce(source_record->>'when','') || chr(31) ||
  coalesce(source_record->>'by','') || chr(31) ||
  coalesce(source_record->>'action','') || chr(31) ||
  coalesce(source_record->>'category','') || chr(31) ||
  coalesce(source_record->>'member','') || chr(31) ||
  coalesce(source_record->>'before','') || chr(31) ||
  coalesce(source_record->>'after','')
 ) as item_hash
 from public.sacco_audit_entries where event_kind='LEGACY_LOG'
), evidence as (
 select
  (select md5(string_agg(item_hash,E'\n' order by item_hash)) from log_hashes) as edit_log_bundle_md5,
  (select count(*) from log_hashes) as edit_log_count,
  (select md5(photo_data) from public.sacco_members where photo_data is not null limit 1) as member_photo_md5,
  (select count(*) from public.sacco_members where photo_data is not null) as photo_count,
  (select md5(logo_data) from public.sacco_branding where singleton) as imported_logo_md5
), finance as (
 select
  (select count(*) from public.sacco_members) as members,
  (select count(*) from public.sacco_members where auth_user_id is not null) as linked,
  (select count(*) from public.sacco_contributions) as contributions,
  (select coalesce(sum(amount),0) from public.sacco_contributions) as contributed_ugx,
  (select count(*) from public.sacco_loans) as loans,
  (select count(*) from public.sacco_repayments) as repayments,
  (select count(*) from public.sacco_posting_receipts) as native_posts,
  (select count(*) from public.sacco_posting_reversals) as native_reversals,
  (select enabled from sacco_private.posting_control where singleton) as native_posting_enabled
), source as (
 select m.backup_sha256,m.status,m.member_count,m.contribution_count,
 m.loan_count,m.repayment_count,m.legacy_edit_count,m.profile_photo_count,
 m.original_logo_hash
 from public.sacco_source_manifest m where singleton
)
select
 (source.backup_sha256='b4b200618f2e74c1ebdc3a567c2eb5ac1a33b6ee58994d4913dcae86f5ee8837'
  and source.status='USER_ATTESTED_UNCHANGED') as user_attested_source_recorded,
 (evidence.edit_log_count=source.legacy_edit_count and
  evidence.edit_log_bundle_md5='29d3e89ee870b0cf6d951f9620e8ee0b') as edit_logs_exact_match,
 (evidence.photo_count=source.profile_photo_count and
  evidence.member_photo_md5='0f4c13b17bda8d98177e92cc28ec9de0') as photo_exact_match,
 (evidence.imported_logo_md5=source.original_logo_hash
  and evidence.imported_logo_md5='01c6e2af1eb508a2a62ea8c50c222637') as logo_exact_match,
 (finance.members=source.member_count and finance.contributions=source.contribution_count
  and finance.loans=source.loan_count and finance.repayments=source.repayment_count
  and finance.contributed_ugx=13965000) as financial_import_stable,
 (finance.native_posts=0 and finance.native_reversals=0
  and not finance.native_posting_enabled
  and not has_function_privilege('authenticated','public.sacco_post_approved_draft(uuid)','EXECUTE')
  and not has_function_privilege('authenticated','public.sacco_reverse_posted_entry(uuid,uuid,text,text)','EXECUTE')) as production_writes_still_locked,
 finance.linked as linked_accounts,
 'Browser acceptance and legacy-site retirement remain manual release gates' as remaining_release_gate
from evidence cross join finance cross join source;
