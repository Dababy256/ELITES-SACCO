-- Administrator-only read-only native posting state.
-- This does NOT grant posting rights or enable the financial writing gate.
begin;
create function sacco_private.sacco_release_status()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_control sacco_private.posting_control%rowtype;
begin
 if (select auth.uid()) is null or not (select sacco_private.is_sacco_admin()) then
  raise exception 'Verified SACCO administrator required' using errcode='42501';
 end if;
 select * into v_control from sacco_private.posting_control where singleton;
 if not found then raise exception 'Financial posting control record missing' using errcode='42501';end if;
 return pg_catalog.jsonb_build_object(
  'posting_gate_enabled',v_control.enabled,
  'posting_rpc_enabled',pg_catalog.has_function_privilege('authenticated','public.sacco_post_approved_draft(uuid)','EXECUTE'),
  'reversal_rpc_enabled',pg_catalog.has_function_privilege('authenticated','public.sacco_reverse_posted_entry(uuid,uuid,text,text)','EXECUTE'),
  'cutover_reference',v_control.cutover_reference,
  'cutover_at',v_control.source_reconciled_at,
  'native_posting_receipts',(select count(*) from public.sacco_posting_receipts),
  'native_reversal_receipts',(select count(*) from public.sacco_posting_reversals),
  'approved_review_count',(select count(*) from public.sacco_staging_reviews where decision='APPROVED'),
  'admin_signoffs',(select count(*) from public.sacco_member_readiness_signoffs s join public.sacco_members m on m.id=s.member_id where m.member_role='admin'),
  'ordinary_signoffs',(select count(*) from public.sacco_member_readiness_signoffs s join public.sacco_members m on m.id=s.member_id where m.member_role='member'),
  'linked_members',(select count(*) from public.sacco_members where auth_user_id is not null),
  'historical_evidence_manifest',(select count(*) from public.sacco_source_manifest),
  'operational',v_control.enabled and v_control.source_reconciled_at is not null and
   nullif(btrim(coalesce(v_control.cutover_reference,'')),'') is not null and
   pg_catalog.has_function_privilege('authenticated','public.sacco_post_approved_draft(uuid)','EXECUTE')
 );
end$$;
revoke all on function sacco_private.sacco_release_status() from public,anon,authenticated,service_role;
grant execute on function sacco_private.sacco_release_status() to authenticated;
create function public.sacco_release_status()
returns jsonb language sql stable security invoker set search_path='' as $$
 select sacco_private.sacco_release_status();
$$;
revoke all on function public.sacco_release_status() from public,anon,authenticated,service_role;
grant execute on function public.sacco_release_status() to authenticated;
commit;