-- Transactional, fictitious self-attestation acceptance regression.
-- All inserts are rolled back. No finance postings, passwords or member data changed.
begin;
select set_config('qa.accept_actor_a',(select auth_user_id::text
 from public.sacco_members where member_role='member' and auth_user_id is not null
 order by created_at limit 1),true);
select set_config('qa.accept_actor_b',(select auth_user_id::text
 from public.sacco_members where member_role='member' and auth_user_id is not null
 and auth_user_id::text<>current_setting('qa.accept_actor_a')
 order by created_at limit 1),true);
select set_config('qa.accept_member_a',(select id::text from public.sacco_members
 where auth_user_id::text=current_setting('qa.accept_actor_a')),true);
select set_config('qa.accept_actor_admin',(select auth_user_id::text from public.sacco_members
 where member_role='admin' and auth_user_id is not null limit 1),true);
select set_config('request.jwt.claim.sub',current_setting('qa.accept_actor_a'),true);
set local role authenticated;
insert into public.sacco_member_readiness_signoffs
(member_id,auth_user_id,checks_passed,checks_total,attestation)
select id,auth_user_id,8,8,
 'I personally ran and passed all eight checks in my signed-in browser.'
from public.sacco_members where auth_user_id=auth.uid();

do $tests$ declare rejected boolean;
begin
 if (select count(*) from public.sacco_member_readiness_signoffs)<>1
  then raise exception 'Member A cannot view own acceptance receipt';end if;
 rejected:=false;
 begin
  insert into public.sacco_member_readiness_signoffs
   (member_id,auth_user_id,checks_passed,checks_total,attestation)
  select id,auth_user_id,8,8,
   'I personally ran and passed all eight checks in my signed-in browser.'
  from public.sacco_members where auth_user_id=auth.uid();
 exception when unique_violation then rejected:=true;
 end;
 if not rejected then raise exception 'Duplicate signed-off acceptance was allowed';end if;
 rejected:=false;
 begin
  insert into public.sacco_member_readiness_signoffs
   (member_id,auth_user_id,checks_passed,checks_total,attestation)
  select id,auth_user_id,7,8,
   'I personally ran and passed all eight checks in my signed-in browser.'
  from public.sacco_members where auth_user_id=auth.uid();
 exception when check_violation then rejected:=true;
 end;
 if not rejected then raise exception 'Partial 7/8 acceptance was allowed';end if;
end$tests$;
select set_config('request.jwt.claim.sub',current_setting('qa.accept_actor_b'),true);
do $tests$ declare blocked boolean:=false;
begin
 if (select count(*) from public.sacco_member_readiness_signoffs)<>0 then
  raise exception 'Member B can see another member signoff';end if;
 begin
  insert into public.sacco_member_readiness_signoffs
   (member_id,auth_user_id,checks_passed,checks_total,attestation)
  values(current_setting('qa.accept_member_a')::uuid,auth.uid(),8,8,
   'I personally ran and passed all eight checks in my signed-in browser.');
 exception when insufficient_privilege then blocked:=true;
 end;
 if not blocked then raise exception 'Member B forged member A acceptance';end if;
end$tests$;
select set_config('request.jwt.claim.sub',current_setting('qa.accept_actor_admin'),true);
do $tests$ begin
 if (select count(*) from public.sacco_member_readiness_signoffs)<>1 then
  raise exception 'Administrator cannot read acceptance register';end if;
 if has_table_privilege('authenticated','public.sacco_member_readiness_signoffs','UPDATE')
 or has_table_privilege('authenticated','public.sacco_member_readiness_signoffs','DELETE')
 then raise exception 'Readiness signoff is not append-only';end if;
 if has_table_privilege('anon','public.sacco_member_readiness_signoffs','SELECT') then
  raise exception 'Anonymous account can read readiness register';end if;
end$tests$;
select 'PASS: signed-in self-attestation, privacy, duplicate, forging and 7/8 protection' as result;
rollback;