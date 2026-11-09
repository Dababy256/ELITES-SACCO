-- Hide highly privileged native financial write implementations in sacco_private.
-- Preserve public RPC argument/return API through SECURITY INVOKER wrappers.
-- Both private and public EXECUTE rights remain REVOKED until separately approved cutover.
begin;
do $clone_native$
declare source_code text; func_name text; signature text;
begin
 foreach func_name in array array['sacco_post_approved_draft','sacco_reverse_posted_entry'] loop
  signature:=case when func_name='sacco_post_approved_draft'
   then 'public.sacco_post_approved_draft(uuid)'
   else 'public.sacco_reverse_posted_entry(uuid,uuid,text,text)' end;
  source_code:=pg_catalog.pg_get_functiondef(signature::regprocedure);
  if source_code not like '%SECURITY DEFINER%' then
   raise exception 'Refusing to move unexpected non-privileged function %',signature;
  end if;
  source_code:=pg_catalog.replace(source_code,
   'FUNCTION public.'||func_name,'FUNCTION sacco_private.'||func_name);
  execute source_code;
 end loop;
end$clone_native$;

create or replace function public.sacco_post_approved_draft(p_draft_id uuid)
returns jsonb language sql volatile security invoker set search_path='' as $$
 select sacco_private.sacco_post_approved_draft(p_draft_id);
$$;
create or replace function public.sacco_reverse_posted_entry(
 p_receipt_id uuid,p_request_key uuid,p_reason text,p_confirmation text)
returns jsonb language sql volatile security invoker set search_path='' as $$
 select sacco_private.sacco_reverse_posted_entry(
  p_receipt_id,p_request_key,p_reason,p_confirmation);
$$;
revoke all on function sacco_private.sacco_post_approved_draft(uuid) from public,anon,authenticated,service_role;
revoke all on function sacco_private.sacco_reverse_posted_entry(uuid,uuid,text,text) from public,anon,authenticated,service_role;
revoke all on function public.sacco_post_approved_draft(uuid) from public,anon,authenticated,service_role;
revoke all on function public.sacco_reverse_posted_entry(uuid,uuid,text,text) from public,anon,authenticated,service_role;
commit;