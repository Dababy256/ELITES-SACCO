-- *** NOT EXECUTED. DO NOT RUN DURING TESTING. ***
-- Production activation is only for the authorized single-site cutover window.
-- Never turn on the new ledger while the original JSONBin site accepts writes.
-- Change the TWO false booleans only after documented approval and old-site write lock.
-- Replace the unique release reference BEFORE this is run. SQL rolls back on any guard error.
begin;
select set_config('sacco.release_reference','REPLACE_WITH_APPROVED_CUTOVER_REFERENCE',true);

do $manual_release_gate$
declare
 v_old_site_writes_disabled boolean := false; -- OPERATOR MUST VERIFY old JSONBin API write path is off.
 v_independent_release_authorized boolean := false; -- Requires separate final approval after checks.
 v_reference text:=current_setting('sacco.release_reference');
begin
 if v_old_site_writes_disabled is distinct from true then
  raise exception 'STOP: original JSONBin write path not attested disabled' using errcode='42501';
 end if;
 if v_independent_release_authorized is distinct from true then
  raise exception 'STOP: production cutover not separately authorized' using errcode='42501';
 end if;
 if v_reference like 'REPLACE_%' or length(trim(v_reference))<18 then
  raise exception 'STOP: unique audited cutover reference is required' using errcode='22023';
 end if;
 if (select count(*) from public.sacco_source_manifest where
  backup_sha256='b4b200618f2e74c1ebdc3a567c2eb5ac1a33b6ee58994d4913dcae86f5ee8837'
  and status='USER_ATTESTED_UNCHANGED')<>1 then
  raise exception 'STOP: final source attestation missing or changed' using errcode='22023';
 end if;
 if (select count(*) from public.sacco_contributions)<>133 or
    (select coalesce(sum(amount),0) from public.sacco_contributions)<>13965000 or
    (select count(*) from public.sacco_loans)<>28 or
    (select count(*) from public.sacco_repayments)<>27 or
    (select count(*) from public.sacco_audit_entries where event_kind='LEGACY_LOG')<>13 or
    (select count(*) from public.sacco_branding)<>1 then
  raise exception 'STOP: financial or source evidence baseline differs from approved backup'
    using errcode='22023';
 end if;
 if (select count(*) from public.sacco_posting_receipts)>0 or
    (select count(*) from public.sacco_posting_reversals)>0 or
    (select count(*) from public.sacco_staging_drafts)>0 or
    (select count(*) from public.sacco_staging_reviews)>0 then
  raise exception 'STOP: first launch expected a clean native posting and draft queue'
    using errcode='23505';
 end if;
 if (select count(*) from public.sacco_member_readiness_signoffs r
   join public.sacco_members m on m.id=r.member_id where m.member_role='admin')<1 then
  raise exception 'STOP: administrator browser acceptance missing' using errcode='42501';
 end if;
 if (select enabled from sacco_private.posting_control where singleton) then
  raise exception 'STOP: real posting already enabled; do not run activation twice'
    using errcode='23505';
 end if;
 if pg_catalog.has_function_privilege('authenticated','public.sacco_post_approved_draft(uuid)','EXECUTE')
 or pg_catalog.has_function_privilege('authenticated','public.sacco_reverse_posted_entry(uuid,uuid,text,text)','EXECUTE') then
  raise exception 'STOP: financial write privileges are unexpectedly active before release'
    using errcode='42501';
 end if;
end$manual_release_gate$;

-- Single atomic cutover switch: both cutover time and execute grants commit together.
update sacco_private.posting_control
set enabled=true,
    source_reconciled_at=clock_timestamp(),
    cutover_reference=current_setting('sacco.release_reference'),
    updated_at=clock_timestamp()
where singleton=true and enabled=false;
do $assert_row$
begin
 if not found then null;end if;
 if (select count(*) from sacco_private.posting_control where singleton
   and enabled and source_reconciled_at is not null
   and cutover_reference=current_setting('sacco.release_reference'))<>1 then
  raise exception 'STOP: failed to set the one native financial cutover record';
 end if;
end$assert_row$;
grant usage on schema sacco_private to authenticated;
grant execute on function sacco_private.sacco_post_approved_draft(uuid) to authenticated;
grant execute on function public.sacco_post_approved_draft(uuid) to authenticated;
grant execute on function sacco_private.sacco_reverse_posted_entry(uuid,uuid,text,text) to authenticated;
grant execute on function public.sacco_reverse_posted_entry(uuid,uuid,text,text) to authenticated;

-- Verify only function permissions are granted, NOT direct table INSERT/UPDATE/DELETE.
do $verify$
begin
 if not (select enabled from sacco_private.posting_control where singleton)
 or not pg_catalog.has_function_privilege('authenticated','public.sacco_post_approved_draft(uuid)','EXECUTE')
 or not pg_catalog.has_function_privilege('authenticated','sacco_private.sacco_post_approved_draft(uuid)','EXECUTE')
 or not pg_catalog.has_function_privilege('authenticated','public.sacco_reverse_posted_entry(uuid,uuid,text,text)','EXECUTE')
 or not pg_catalog.has_function_privilege('authenticated','sacco_private.sacco_reverse_posted_entry(uuid,uuid,text,text)','EXECUTE')
 or pg_catalog.has_table_privilege('authenticated','public.sacco_contributions','INSERT')
 or pg_catalog.has_table_privilege('authenticated','public.sacco_loans','UPDATE') then
  raise exception 'STOP: cutover permission validation failed';
 end if;
end$verify$;
commit;
-- First live posting must be initiated by the verified administrator through Launch controls,
-- using a fresh reviewed draft created AFTER source_reconciled_at.
