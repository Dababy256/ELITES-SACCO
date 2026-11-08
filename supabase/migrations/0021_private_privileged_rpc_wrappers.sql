-- Move privileged SACCO actions out of the exposed public schema.
-- Public RPC signatures stay stable as SECURITY INVOKER forwarding wrappers.
-- All underlying SECURITY DEFINER implementations retain strict auth.uid/admin checks.
-- No historical financial changes and no live posting activation.
begin;
do $copy$
declare f regprocedure; src text;
begin
 foreach f in array array[
  'public.sacco_preview_draft(uuid)'::regprocedure,
  'public.sacco_request_access()'::regprocedure,
  'public.sacco_review_access_request(uuid,text,uuid,text,text)'::regprocedure,
  'public.sacco_review_draft(uuid,text,text)'::regprocedure
 ] loop
  src:=pg_catalog.pg_get_functiondef(f);
  src:=replace(src,'FUNCTION public.sacco_','FUNCTION sacco_private.sacco_');
  execute src;
 end loop;
end$copy$;
revoke all on function sacco_private.sacco_preview_draft(uuid) from public,anon;
revoke all on function sacco_private.sacco_request_access() from public,anon;
revoke all on function sacco_private.sacco_review_access_request(uuid,text,uuid,text,text) from public,anon;
revoke all on function sacco_private.sacco_review_draft(uuid,text,text) from public,anon;
grant usage on schema sacco_private to authenticated;
grant execute on function sacco_private.sacco_preview_draft(uuid) to authenticated;
grant execute on function sacco_private.sacco_request_access() to authenticated;
grant execute on function sacco_private.sacco_review_access_request(uuid,text,uuid,text,text) to authenticated;
grant execute on function sacco_private.sacco_review_draft(uuid,text,text) to authenticated;

create or replace function public.sacco_preview_draft(p_draft_id uuid)
returns jsonb language sql volatile security invoker set search_path='' as $$
 select sacco_private.sacco_preview_draft(p_draft_id);
$$;
create or replace function public.sacco_request_access()
returns jsonb language sql volatile security invoker set search_path='' as $$
 select sacco_private.sacco_request_access();
$$;
create or replace function public.sacco_review_access_request(
 p_request_id uuid, p_decision text, p_member_id uuid default null,
 p_verification_note text default '', p_confirmation text default ''
) returns jsonb language sql volatile security invoker set search_path='' as $$
 select sacco_private.sacco_review_access_request(
  p_request_id,p_decision,p_member_id,p_verification_note,p_confirmation);
$$;
create or replace function public.sacco_review_draft(
 p_draft_id uuid,p_decision text,p_note text default ''
) returns jsonb language sql volatile security invoker set search_path='' as $$
 select sacco_private.sacco_review_draft(p_draft_id,p_decision,p_note);
$$;
revoke all on function public.sacco_preview_draft(uuid) from public,anon;
revoke all on function public.sacco_request_access() from public,anon;
revoke all on function public.sacco_review_access_request(uuid,text,uuid,text,text) from public,anon;
revoke all on function public.sacco_review_draft(uuid,text,text) from public,anon;
grant execute on function public.sacco_preview_draft(uuid) to authenticated;
grant execute on function public.sacco_request_access() to authenticated;
grant execute on function public.sacco_review_access_request(uuid,text,uuid,text,text) to authenticated;
grant execute on function public.sacco_review_draft(uuid,text,text) to authenticated;
commit;