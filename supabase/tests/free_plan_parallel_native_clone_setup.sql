-- Isolated transactional clone of the CURRENT locked production posting function.
-- All clone tables and test writes are rolled back; NO real sacco_* rows can be written.
-- Never grant the cloned functions to API roles and NEVER change public posting_control.
begin;
create schema sacco_parallel_qa;
revoke all on schema sacco_parallel_qa from public,anon,authenticated;
-- Keep a close column/index replica of all tables the posting path accesses.
create table sacco_parallel_qa.sacco_members (like public.sacco_members including all);
create table sacco_parallel_qa.sacco_staging_drafts (like public.sacco_staging_drafts including all);
create table sacco_parallel_qa.sacco_staging_reviews (like public.sacco_staging_reviews including all);
create table sacco_parallel_qa.sacco_posting_receipts (like public.sacco_posting_receipts including all);
create table sacco_parallel_qa.sacco_posting_reversals (like public.sacco_posting_reversals including all);
create table sacco_parallel_qa.sacco_loans (like public.sacco_loans including all);
create table sacco_parallel_qa.sacco_repayments (like public.sacco_repayments including all);
create table sacco_parallel_qa.sacco_contributions (like public.sacco_contributions including all);
create table sacco_parallel_qa.sacco_waivers (like public.sacco_waivers including all);
create table sacco_parallel_qa.sacco_financial_entries (like public.sacco_financial_entries including all);
create table sacco_parallel_qa.sacco_membership_fees (like public.sacco_membership_fees including all);
create table sacco_parallel_qa.sacco_audit_entries (like public.sacco_audit_entries including all);
create table sacco_parallel_qa.posting_control (like sacco_private.posting_control including all);

-- Mirror live immutable-history triggers on fictional tables.
do $clone_guard$
declare t text;
begin
 foreach t in array array[
 'sacco_contributions','sacco_loans','sacco_repayments',
 'sacco_financial_entries','sacco_membership_fees','sacco_waivers'
 ] loop
  execute pg_catalog.format(
   'create trigger sacco_guard_native_history before update or delete
    on sacco_parallel_qa.%I
    for each row execute function sacco_private.guard_native_financial_history()',t
  );
 end loop;
end$clone_guard$;

-- Clone function DEFINITIONS from Postgres, modifying only schema-qualified references.
-- This tests the exact current procedural logic, not the unrelated QA posting lab code.
do $clone$
declare s text; fn regprocedure;
begin
 foreach fn in array array[
   'sacco_private.is_sacco_admin()'::regprocedure,
   'sacco_private.validate_staging_draft(text,jsonb)'::regprocedure,
   'sacco_private.loan_due_as_of(uuid,date)'::regprocedure,
   'public.sacco_post_approved_draft(uuid)'::regprocedure,
   'public.sacco_reverse_posted_entry(uuid,uuid,text,text)'::regprocedure
 ] loop
  s:=pg_catalog.pg_get_functiondef(fn);
  s:=replace(s,'public.sacco_','sacco_parallel_qa.sacco_');
  s:=replace(s,'sacco_private.is_sacco_admin','sacco_parallel_qa.is_sacco_admin');
  s:=replace(s,'sacco_private.validate_staging_draft','sacco_parallel_qa.validate_staging_draft');
  s:=replace(s,'sacco_private.loan_due_as_of','sacco_parallel_qa.loan_due_as_of');
  s:=replace(s,'sacco_private.posting_control','sacco_parallel_qa.posting_control');
  s:=replace(s,'sacco_parallel_qa.sacco_post_approved_draft','sacco_parallel_qa.post_approved_draft');
  execute s;
 end loop;
end$clone$;
revoke all on all functions in schema sacco_parallel_qa from public,anon,authenticated;

insert into sacco_parallel_qa.sacco_members(legacy_name,display_name,auth_user_id,member_role)
select 'TEST_A','Fictional QA A',auth_user_id,'admin'
from public.sacco_members where member_role='admin' and auth_user_id is not null
order by created_at limit 1;
insert into sacco_parallel_qa.posting_control(singleton,enabled,source_reconciled_at,cutover_reference)
values(true,true,now(),'FICTIONAL_PARALLEL_CLONE_QA');
with tester as (select id as member_id,auth_user_id from sacco_parallel_qa.sacco_members limit 1)
insert into sacco_parallel_qa.sacco_staging_drafts(created_by,action_kind,payload)
select t.auth_user_id,'CONTRIBUTION',pg_catalog.jsonb_build_object(
 'member_id',t.member_id,'amount',111117,'month','2026-11',
 'entry_on','2026-11-09','note','PARALLEL_'||g.s)
from tester t cross join (values('A'),('B')) g(s);
insert into sacco_parallel_qa.sacco_staging_reviews(draft_id,decision,reviewed_by,review_note,validation_snapshot)
select d.id,'APPROVED',d.created_by,'Approved for fictional concurrency only','{}'::jsonb
from sacco_parallel_qa.sacco_staging_drafts d;
commit;
