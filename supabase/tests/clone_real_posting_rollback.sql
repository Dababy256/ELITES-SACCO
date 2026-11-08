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
create table sacco_validation_clone.sacco_posting_reversals (like public.sacco_posting_reversals including all);
create table sacco_validation_clone.sacco_loans (like public.sacco_loans including all);
create table sacco_validation_clone.sacco_repayments (like public.sacco_repayments including all);
create table sacco_validation_clone.sacco_contributions (like public.sacco_contributions including all);
create table sacco_validation_clone.sacco_waivers (like public.sacco_waivers including all);
create table sacco_validation_clone.sacco_financial_entries (like public.sacco_financial_entries including all);
create table sacco_validation_clone.sacco_membership_fees (like public.sacco_membership_fees including all);
create table sacco_validation_clone.sacco_audit_entries (like public.sacco_audit_entries including all);
create table sacco_validation_clone.posting_control (like sacco_private.posting_control including all);

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
    on sacco_validation_clone.%I
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
  s:=replace(s,'public.sacco_','sacco_validation_clone.sacco_');
  s:=replace(s,'sacco_private.is_sacco_admin','sacco_validation_clone.is_sacco_admin');
  s:=replace(s,'sacco_private.validate_staging_draft','sacco_validation_clone.validate_staging_draft');
  s:=replace(s,'sacco_private.loan_due_as_of','sacco_validation_clone.loan_due_as_of');
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
 extra_draft uuid; denied_draft uuid; cap_draft uuid; cap_denied_draft uuid;
 a jsonb; b jsonb; rev_a jsonb; rev_b jsonb; native_loan_receipt uuid; native_repayment_receipt uuid;
 v_count integer; v_errors integer:=0;
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
 select id into native_loan_receipt from sacco_validation_clone.sacco_posting_receipts where draft_id=loan_draft;
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
 select id into native_repayment_receipt from sacco_validation_clone.sacco_posting_receipts where draft_id=repayment_draft;
 select id into repayment_id from sacco_validation_clone.sacco_repayments where legacy_key='native:'||repayment_draft::text;
 if repayment_id is null then raise exception 'Same-day repayment not written'; end if;
 -- 5% flat interest immediately => 1,000,000 + 50,000 - 200,000 = 850,000 due.
 if (select l.principal from sacco_validation_clone.sacco_loans l where l.id=loan_id)*1.05 -
    (select sum(r.amount) from sacco_validation_clone.sacco_repayments r where r.loan_id=(select l.id from sacco_validation_clone.sacco_loans l where l.legacy_key='native:'||loan_draft::text))<>850000 then
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
 -- Original source allows exceptions to unpaid-loan policy, but ONLY with explicit approval.
 insert into sacco_validation_clone.sacco_staging_drafts(created_by,action_kind,payload)
 values(actor,'LOAN',jsonb_build_object('member_id',member_a,'amount',400000,'entry_on','2026-11-08','note','Unapproved second loan'))
 returning id into denied_draft;
 insert into sacco_validation_clone.sacco_staging_reviews(draft_id,decision,reviewed_by,validation_snapshot)
 values(denied_draft,'APPROVED',actor,'{}'::jsonb);
 begin
  perform sacco_validation_clone.post_approved_draft(denied_draft);
  raise exception 'FAILED: unsettled loan exception was not blocked';
 exception when others then
  if sqlerrm not like '%unsettled loan%' then raise; end if;
 end;
 insert into sacco_validation_clone.sacco_staging_drafts(created_by,action_kind,payload)
 values(actor,'LOAN',jsonb_build_object('member_id',member_a,'amount',400000,'entry_on','2026-11-08',
  'override_unsettled_loan',true,'note','Approved second loan exception'))
 returning id into extra_draft;
 insert into sacco_validation_clone.sacco_staging_reviews(draft_id,decision,reviewed_by,review_note,validation_snapshot)
 values(extra_draft,'APPROVED',actor,'Approved exception after checking unpaid loan and documenting rationale','{}'::jsonb);
 a:=sacco_validation_clone.post_approved_draft(extra_draft);
 if (select loan_number from sacco_validation_clone.sacco_loans where legacy_key='native:'||extra_draft::text)<>2 then
  raise exception 'Sequential numbering for explicitly overridden second loan failed';
 end if;
 -- Regular-loan cap: unapproved >1m is blocked; approved exception is recorded.
 insert into sacco_validation_clone.sacco_staging_drafts(created_by,action_kind,payload)
 values(actor,'LOAN',jsonb_build_object('member_id',member_b,'amount',1200000,'entry_on','2026-11-08','note','Unapproved cap override'))
 returning id into cap_denied_draft;
 insert into sacco_validation_clone.sacco_staging_reviews(draft_id,decision,reviewed_by,validation_snapshot)
 values(cap_denied_draft,'APPROVED',actor,'{}'::jsonb);
 begin
  perform sacco_validation_clone.post_approved_draft(cap_denied_draft);
  raise exception 'FAILED: regular loan cap exception was not blocked';
 exception when others then
  if sqlerrm not like '%Regular loan exceeds%' then raise; end if;
 end;
 insert into sacco_validation_clone.sacco_staging_drafts(created_by,action_kind,payload)
 values(actor,'LOAN',jsonb_build_object('member_id',member_b,'amount',1200000,'entry_on','2026-11-08',
  'loan_type','REGULAR','override_regular_cap',true,'note','Approved regular loan cap exception'))
 returning id into cap_draft;
 insert into sacco_validation_clone.sacco_staging_reviews(draft_id,decision,reviewed_by,review_note,validation_snapshot)
 values(cap_draft,'APPROVED',actor,'Approved exceptional regular loan above policy cap at committee review','{}'::jsonb);
 a:=sacco_validation_clone.post_approved_draft(cap_draft);
 if (select source_record->'policy_override'->>'regular_cap'
  from sacco_validation_clone.sacco_loans where legacy_key='native:'||cap_draft::text)<>'true' then
  raise exception 'Approved cap override was not audited in source record';end if;
 if (select count(*) from sacco_validation_clone.sacco_posting_receipts)<>7 then
  raise exception 'Incorrect receipt count after seven distinct synthetic postings';end if;
 if (select count(*) from sacco_validation_clone.sacco_audit_entries where event_kind='NATIVE_POST')<>7 then
  raise exception 'Explicit posting audit trail incomplete';end if;

 -- Reversal must fail while a loan has an unvoided repayment.
 begin
  perform sacco_validation_clone.sacco_reverse_posted_entry(
   native_loan_receipt,'a0000000-0000-4000-8000-000000000001'::uuid,
   'Correcting original test loan after reconciliation','REVERSE POSTED TRANSACTION');
  raise exception 'FAILED: loan reversal was allowed with an active repayment';
 exception when others then
  if sqlerrm not like '%Reverse all active repayments%' then raise;end if;
 end;
 -- A repayment reversal restores the full loan balance; original records remain.
 rev_a:=sacco_validation_clone.sacco_reverse_posted_entry(
  native_repayment_receipt,'a0000000-0000-4000-8000-000000000002'::uuid,
  'Wrong repayment amount was received on the test receipt','REVERSE POSTED TRANSACTION');
 rev_b:=sacco_validation_clone.sacco_reverse_posted_entry(
  native_repayment_receipt,'a0000000-0000-4000-8000-000000000002'::uuid,
  'Wrong repayment amount was received on the test receipt','REVERSE POSTED TRANSACTION');
 if (rev_a->>'already_reversed')::boolean is distinct from false
   or (rev_b->>'already_reversed')::boolean is distinct from true
   or rev_a->>'reversal_id'<>rev_b->>'reversal_id' then
    raise exception 'FAILED: reversal retry was not idempotent';
 end if;
 if (select count(*) from sacco_validation_clone.sacco_repayments where id=repayment_id)<>1
    or (select count(*) from sacco_validation_clone.sacco_repayments where id=repayment_id and voided_at is not null)<>1 then
  raise exception 'FAILED: reversal deleted a repayment or failed to mark it voided';
 end if;
 if sacco_validation_clone.loan_due_as_of(loan_id,'2026-11-08')<>1050000 then
  raise exception 'FAILED: reversing repayment did not restore original principal plus interest';
 end if;
 begin
  perform sacco_validation_clone.sacco_reverse_posted_entry(
   native_repayment_receipt,'a0000000-0000-4000-8000-000000000003'::uuid,
   'Attempt a different reversal key for the same receipt','REVERSE POSTED TRANSACTION');
  raise exception 'FAILED: second reversal accepted';
 exception when others then
  if sqlerrm not like '%already reversed%' then raise;end if;
 end;
 -- Once active repayments are reversed, a native loan can also be reversed.
 rev_a:=sacco_validation_clone.sacco_reverse_posted_entry(
  native_loan_receipt,'a0000000-0000-4000-8000-000000000004'::uuid,
  'Void mistaken disbursement after all linked repayments reversed','REVERSE POSTED TRANSACTION');
 if (select count(*) from sacco_validation_clone.sacco_loans where id=loan_id)<>1
    or (select count(*) from sacco_validation_clone.sacco_loans where id=loan_id and voided_at is not null)<>1
    or sacco_validation_clone.loan_due_as_of(loan_id,'2026-11-08')<>0 then
  raise exception 'FAILED: reversed loan not preserved or still affects balance';
 end if;
 if (select count(*) from sacco_validation_clone.sacco_posting_reversals)<>2
    or (select count(*) from sacco_validation_clone.sacco_audit_entries where event_kind='NATIVE_REVERSAL')<>2
    or (select count(*) from sacco_validation_clone.sacco_posting_receipts)<>7 then
  raise exception 'FAILED: reversal audit or original posting receipt history incomplete';
 end if;
 -- Once voided, the original transaction may not be silently edited or deleted.
 begin
  update sacco_validation_clone.sacco_repayments set amount=1 where id=repayment_id;
  raise exception 'FAILED: editing a reversed repayment was permitted';
 exception when others then
  if sqlerrm not like '%reversed financial entry is immutable%' then raise;end if;
 end;
 begin
  delete from sacco_validation_clone.sacco_loans where id=loan_id;
  raise exception 'FAILED: deleting a native loan was permitted';
 exception when others then
  if sqlerrm not like '%Native or reversed SACCO transactions are immutable%' then raise;end if;
 end;
 raise notice 'PASS: 7 original postings, 2 audited reversals, correct balance, duplicate prevention, source history immutable';

 -- All synthetic entries plus cloned schema are discarded below.
end$test$;
rollback;
