-- Repeatable read-only privileged API and ordinary-member authorization preflight.
-- Uses the actual linked ordinary member's identity for transaction-local RLS simulation.
-- No records are created, modified or deleted. All claim changes are rolled back.
begin;
do $verify$
declare n int;
begin
 select count(*) into n from pg_proc p join pg_namespace s on p.pronamespace=s.oid
 where s.nspname='public' and p.prosecdef and
 p.proname in ('sacco_preview_draft','sacco_request_access',
 'sacco_review_access_request','sacco_review_draft');
 if n<>0 then raise exception 'Public privileged RPC exposure remains: %',n;end if;
 if has_function_privilege('anon','public.sacco_review_draft(uuid,text,text)','EXECUTE')
 or has_function_privilege('anon','public.sacco_request_access()','EXECUTE')
 or has_function_privilege('authenticated','public.sacco_post_approved_draft(uuid)','EXECUTE')
 or has_function_privilege('authenticated','public.sacco_reverse_posted_entry(uuid,uuid,text,text)','EXECUTE')
 then raise exception 'Unexpected anonymous or real ledger posting/reversal privilege';end if;
 if (select enabled from sacco_private.posting_control where singleton) then
  raise exception 'Real financial posting gate is unexpectedly ON';end if;
end$verify$;
select set_config('request.jwt.claim.sub',
 (select auth_user_id::text from public.sacco_members
 where member_role='member' and auth_user_id is not null order by created_at limit 1),true);
set local role authenticated;
do $member$
declare denied boolean;
begin
 if (select count(*) from public.sacco_members)<>1 then
  raise exception 'Linked ordinary member can read other member identities';end if;
 if (select count(*) from public.sacco_posting_receipts)<>0
 or (select count(*) from public.sacco_posting_reversals)<>0 then
  raise exception 'Ordinary member can view private posting or reversal records';end if;
 denied:=false;
 begin
  perform public.sacco_preview_draft('00000000-0000-4000-8000-000000000111'::uuid);
 exception when insufficient_privilege then denied:=true;
 end;
 if not denied then raise exception 'Ordinary member gained preview access';end if;
 denied:=false;
 begin
  perform public.sacco_review_draft('00000000-0000-4000-8000-000000000111'::uuid,
    'APPROVED','Unauthorized attempt');
 exception when insufficient_privilege then denied:=true;
 end;
 if not denied then raise exception 'Ordinary member gained draft approval';end if;
 denied:=false;
 begin
  perform public.sacco_review_access_request('00000000-0000-4000-8000-000000000111'::uuid,
    'APPROVED',null,'Unauthorized attempt to change member identity','I VERIFIED THIS PERSON');
 exception when insufficient_privilege then denied:=true;
 end;
 if not denied then raise exception 'Ordinary member gained identity approval';end if;
 if (public.sacco_request_access()->>'status')<>'LINKED' then
  raise exception 'Linked ordinary member cannot reach legitimate access status';end if;
end$member$;
select 'PASS - no public definer API, member action boundaries and posting gate preserved' as result;
rollback;