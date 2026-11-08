-- Isolated transactional clone of the CURRENT locked production posting function.
-- All clone tables and test writes are rolled back; NO real sacco_* rows can be written.
-- Never grant the cloned functions to API roles and NEVER change public posting_control.
begin;
create schema sacco_validation_clone;
revoke all on schema sacco_validation_clone from public,anon,authenticated;
-- Keep a close column/index replica of all tables the posting path accesses.
create table sacco_validation_clone.sacco_members (like public.sacco_members including all);
create table sacco_validation_clone.sacco_staging_drafts (like public.sacco_staging_drafts including all);
create table sacco_validation_clone.sacco_staging_reviews (like public.sacco_staging_reviews including all);
create table sacco_validation_clone.sacco_posting_receipts (like public.sacco_posting_receipts including all);
create table sacco_validation_clone.sacco_loans (like public.sacco_loans including all);
create table sacco_validation_clone.sacco_repayments (like public.sacco_repayments including all);
create table sacco_validation_clone.sacco_contributions (like public.sacco_contributions including all);
create table sacco_validation_clone.sacco_waivers (like public.sacco_waivers including all);
create table sacco_validation_clone.sacco_financial_entries (like public.sacco_financial_entries including all);
create table sacco_validation_clone.sacco_membership_fees (like public.sacco_membership_fees including all);
create table sacco_validation_clone.sacco_audit_entries (like public.sacco_audit_entries including all);
create table sacco_validation_clone.posting_control (like sacco_private.posting_control including all);

-- Clone function DEFINITIONS from Postgres, modifying only schema-qualified references.
-- This tests the exact current procedural logic, not the unrelated QA posting lab code.
do $clone$
declare s text; fn regprocedure;
begin
 foreach fn in array array[
   'sacco_private.is_sacco_admin()'::regprocedure,
   'sacco_private.validate_staging_draft(text,jsonb)'::regprocedure,
   'public.sacco_post_approved_draft(uuid)'::regprocedure
 ] loop
  s:=pg_catalog.pg_get_functiondef(fn);
  s:=replace(s,'public.sacco_','sacco_validation_clone.sacco_');
  s:=replace(s,'sacco_private.is_sacco_admin','sacco_validation_clone.is_sacco_admin');
  s:=replace(s,'sacco_private.validate_staging_draft','sacco_validation_clone.validate_staging_draft');
  s:=replace(s,'sacco_private.posting_control','sacco_validation_clone.posting_control');
  s:=replace(s,'sacco_validation_clone.sacco_post_approved_draft','sacco_validation_clone.post_approved_draft');
  execute s;
 end loop;
end$clone$;
revoke all on all functions in schema sacco_validation_clone from public,anon,authenticated;

do $test$
declare
 actor uuid; member_a uuid; member_b uuid;
 loan_draft uuid; loan_id uuid; repayment_draft uuid; repayment_id uuid;
 saving_draft uuid; expense_draft uuid; fee_draft uuid; cash_draft uuid;
 a jsonb; b jsonb; v_count integer; v_errors integer:=0;
begin
 select auth_user_id into actor from public.sacco_members
 where member_role='admin' and auth_user_id is not null order by created_at limit 1;
 if actor is null then raise exception 'Missing linked admin to exercise authorization'; end if;
 insert into sacco_validation_clone.sacco_members(legacy_name,display_name,auth_user_id,member_role)
 values('TEST_A','Fictional member A',actor,'admin') returning id into member_a;
 insert into sacco_validation_clone.sacco_members(legacy_name,display_name,member_role)
 values('TEST_B','Fictional member B','member') returning id into member_b;
 insert into sacco_validation_clone.posting_control(singleton,enabled,source_reconciled_at,cutover_reference)
 values(true,true,now(),'ROLLBACK_CLONE_TEST_ONLY');
 perform pg_catalog.set_config('request.jwt.claim.sub',actor::text,true);
 -- Issue a fictional loan on 8 November 2026.
 insert into sacco_validation_clone.sacco_staging_drafts(created_by,action_kind,payload)
 values(actor,'LOAN',jsonb_build_object('member_id',member_a,'amount',1000000,'entry_on','2026-11-08','note','synthetic test loan'))
 returning id into loan_draft;
 insert into sacco_validation_clone.sacco_staging_reviews(draft_id,decision,reviewed_by,validation_snapshot)
 values(loan_draft,'APPROVED',actor,'{}'::jsonb);
 a:=sacco_validation_clone.post_approved_draft(loan_draft);
 b:=sacco_validation_clone.post_approved_draft(loan_draft);
 if (a->>'already_posted')::boolean is distinct from false
    or (b->>'already_posted')::boolean is distinct from true
    or a->>'receipt_id' <> b->>'receipt_id' then
  raise exception 'Loan replay was not idempotent';
 end if;
 select id into loan_id from sacco_validation_clone.sacco_loans where legacy_key='native:'||loan_draft::text;
 if loan_id is null then raise exception 'Fictional loan row not created'; end if;
 -- Same-day partial payment (no one-month waiting requirement).
 insert into sacco_validation_clone.sacco_staging_drafts(created_by,action_kind,payload)
 values(actor,'REPAYMENT',jsonb_build_object('member_id',member_a,'loan_id',loan_id,
  'amount',200000,'entry_on','2026-11-08','note','same-day synthetic repayment'))
 returning id into repayment_draft;
 insert into sacco_validation_clone.sacco_staging_reviews(draft_id,decision,reviewed_by,validation_snapshot)
 values(repayment_draft,'APPROVED',actor,'{}'::jsonb);
 a:=sacco_validation_clone.post_approved_draft(repayment_draft);
 select id into repayment_id from sacco_validation_clone.sacco_repayments where legacy_key='native:'||repayment_draft::text;
 if repayment_id is null then raise exception 'Same-day repayment not written'; end if;
 -- 5% flat interest immediately => 1,000,000 + 50,000 - 200,000 = 850,000 due.
 if (select principal from sacco_validation_clone.sacco_loans where id=loan_id)*1.05 -
    (select sum(amount) from sacco_validation_clone.sacco_repayments where loan_id=loan_id)<>850000 then
  raise exception 'Same-day flat interest regression failed'; end if;
 -- Contribution, cashbook expense and membership fee using same production code.
 insert into sacco_validation_clone.sacco_staging_drafts(created_by,action_kind,payload)
 values(actor,'CONTRIBUTION',jsonb_build_object('member_id',member_a,'amount',150000,'month','2026-11','entry_on','2026-11-08'))
 returning id into saving_draft;
 insert into sacco_validation_clone.sacco_staging_reviews(draft_id,decision,reviewed_by,validation_snapshot)
 values(saving_draft,'APPROVED',actor,'{}'::jsonb);
 a:=sacco_validation_clone.post_approved_draft(saving_draft);
 if (select count(*) from sacco_validation_clone.sacco_contributions)<>1 then
  raise exception 'Contribution posting failed';end if;
 insert into sacco_validation_clone.sacco_staging_drafts(created_by,action_kind,payload)
 values(actor,'EXPENSE',jsonb_build_object('member_id',member_a,'amount',25000,'entry_on','2026-11-08','note','Fictional stationery'))
 returning id into expense_draft;
 insert into sacco_validation_clone.sacco_staging_reviews(draft_id,decision,reviewed_by,validation_snapshot)
 values(expense_draft,'APPROVED',actor,'{}'::jsonb);
 a:=sacco_validation_clone.post_approved_draft(expense_draft);
 if (select count(*) from sacco_validation_clone.sacco_financial_entries where entry_kind='expense')<>1 then
  raise exception 'Expense posting failed';end if;
 insert into sacco_validation_clone.sacco_staging_drafts(created_by,action_kind,payload)
 values(actor,'MEMBERSHIP_FEE',jsonb_build_object('member_id',member_b,'amount',50000,'entry_on','2026-11-08'))
 returning id into fee_draft;
 insert into sacco_validation_clone.sacco_staging_reviews(draft_id,decision,reviewed_by,validation_snapshot)
 values(fee_draft,'APPROVED',actor,'{}'::jsonb);
 a:=sacco_validation_clone.post_approved_draft(fee_draft);
 if (select count(*) from sacco_validation_clone.sacco_membership_fees)<>1 then
  raise exception 'Membership fee posting failed';end if;
 if (select count(*) from sacco_validation_clone.sacco_posting_receipts)<>5 then
  raise exception 'Incorrect number of receipts after five unique drafts';end if;
 if (select count(*) from sacco_validation_clone.sacco_audit_entries where event_kind='NATIVE_POST')<>5 then
  raise exception 'Explicit posting audit trail incomplete';end if;
 raise notice 'PASS: loan issue, same-day repayment, savings, expense, membership fee, 5 unique receipts, replay idempotence, 5 explicit audit rows';
 -- All synthetic entries plus cloned schema are discarded below.
end$test$;
rollback;
