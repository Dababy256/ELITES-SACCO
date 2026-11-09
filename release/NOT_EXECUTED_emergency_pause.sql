-- EMERGENCY FINANCIAL POSTING PAUSE — NOT EXECUTED
-- Stops new native posts and reversals. Keeps ALL ledger/history rows intact.
-- WARNING: this does NOT automatically reactivate old JSONBin writes.
begin;
update sacco_private.posting_control
 set enabled=false,updated_at=clock_timestamp()
 where singleton=true;
revoke execute on function sacco_private.sacco_post_approved_draft(uuid) from authenticated;
revoke execute on function public.sacco_post_approved_draft(uuid) from authenticated;
revoke execute on function sacco_private.sacco_reverse_posted_entry(uuid,uuid,text,text) from authenticated;
revoke execute on function public.sacco_reverse_posted_entry(uuid,uuid,text,text) from authenticated;
do $verify$
begin
 if (select enabled from sacco_private.posting_control where singleton)
 or pg_catalog.has_function_privilege('authenticated','public.sacco_post_approved_draft(uuid)','EXECUTE')
 or pg_catalog.has_function_privilege('authenticated','public.sacco_reverse_posted_entry(uuid,uuid,text,text)','EXECUTE')
 then raise exception 'Emergency pause did not disable native financial posting' using errcode='42501';
 end if;
end$verify$;
commit;
-- After any genuine new posting, DO NOT restore stale JSON backups over later transactions.
-- Reconcile forward or use a formally audited reversal; keep the old website read-only.
