-- Lock native financial postings from alteration, including before reversal.
-- Same reversal request key with different reason must not be treated as a valid retry.
begin;
CREATE OR REPLACE FUNCTION sacco_private.guard_native_financial_history()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_before jsonb; v_after jsonb;
begin
 if tg_op='DELETE' then
  if old.voided_at is not null or old.legacy_key like 'native:%' then
   raise exception 'Native or reversed SACCO transactions are immutable; use the audited reversal workflow'
     using errcode='42501';
  end if;
  return old;
 end if;
 if old.voided_at is not null then
  raise exception 'A reversed financial entry is immutable' using errcode='42501';
 end if;
 if old.legacy_key like 'native:%' and new.voided_at is null and
  pg_catalog.to_jsonb(new) <> pg_catalog.to_jsonb(old) then
  raise exception 'A native posted entry cannot be edited; reverse and repost instead'
   using errcode='42501';
 end if;
 if new.voided_at is not null then
  if old.legacy_key not like 'native:%' then
   raise exception 'Imported historical records cannot be reversed using native posting workflow'
     using errcode='42501';
  end if;
  if new.voided_by is null or char_length(btrim(coalesce(new.void_reason,'')))<15 then
   raise exception 'Native reversal requires actor and documented reason' using errcode='42501';
  end if;
  v_before:=pg_catalog.to_jsonb(old)-'voided_at'-'voided_by'-'void_reason';
  v_after:=pg_catalog.to_jsonb(new)-'voided_at'-'voided_by'-'void_reason';
  if v_before<>v_after then
   raise exception 'A reversal cannot silently alter the original financial transaction'
     using errcode='42501';
  end if;
 end if;
 return new;
end$function$
;
CREATE OR REPLACE FUNCTION public.sacco_reverse_posted_entry(p_receipt_id uuid, p_request_key uuid, p_reason text, p_confirmation text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_actor uuid;
 v_control sacco_private.posting_control%rowtype;
 v_receipt public.sacco_posting_receipts%rowtype;
 v_reverse public.sacco_posting_reversals%rowtype;
 v_reason text;
 v_record jsonb;
 v_modified_rows integer;
begin
 v_actor:=(select auth.uid());
 if v_actor is null or not (select sacco_private.is_sacco_admin()) then
  raise exception 'Verified SACCO administrator required' using errcode='42501';
 end if;
 if p_receipt_id is null or p_request_key is null then
  raise exception 'Posting receipt and unique reversal request id required' using errcode='22023';
 end if;
 if p_confirmation is distinct from 'REVERSE POSTED TRANSACTION' then
  raise exception 'Explicit typed confirmation required' using errcode='42501';
 end if;
 v_reason:=pg_catalog.btrim(coalesce(p_reason,''));
 if pg_catalog.char_length(v_reason)<15 or pg_catalog.char_length(v_reason)>500 then
  raise exception 'A specific reversal reason of 15-500 characters is mandatory' using errcode='22023';
 end if;
 -- Same gate is locked by both normal posting and reversals, serializing all writes.
 select * into v_control from sacco_private.posting_control where singleton=true for update;
 if not found or not v_control.enabled or v_control.source_reconciled_at is null
     or nullif(pg_catalog.btrim(v_control.cutover_reference),'') is null then
  raise exception 'Real transaction reversal remains disabled until cutover' using errcode='42501';
 end if;
 select * into v_receipt from public.sacco_posting_receipts where id=p_receipt_id for update;
 if not found then raise exception 'Only a posted native transaction receipt may be reversed' using errcode='22023';end if;
 select * into v_reverse from public.sacco_posting_reversals where request_key=p_request_key;
 if found and v_reverse.posting_receipt_id<>p_receipt_id then
  raise exception 'Reversal request key already used for another receipt' using errcode='23505';
 end if;
 select * into v_reverse from public.sacco_posting_reversals where posting_receipt_id=p_receipt_id;
 if found then
  if v_reverse.request_key<>p_request_key then
   raise exception 'This financial posting was already reversed; no second reversal allowed' using errcode='23505';
  end if;
  if v_reverse.reason<>v_reason then
   raise exception 'Reversal replay has a different justification from the original request'
    using errcode='23505';
  end if;
  return pg_catalog.jsonb_build_object('reversal_id',v_reverse.id,'receipt_id',v_receipt.id,
   'already_reversed',true,'ledger_table',v_receipt.ledger_table);
 end if;
 -- Native provenance prevents modifying any imported legacy transactions.
 if v_receipt.ledger_table not in (
  'sacco_contributions','sacco_loans','sacco_repayments',
  'sacco_financial_entries','sacco_membership_fees','sacco_waivers'
 ) then raise exception 'Unsupported ledger record for reversal' using errcode='22023';end if;
 case v_receipt.ledger_table
 when 'sacco_contributions' then
  update public.sacco_contributions x set voided_at=now(),voided_by=v_actor,void_reason=v_reason
  where x.id=v_receipt.posted_record_id and x.legacy_key='native:'||v_receipt.draft_id::text and x.voided_at is null
  returning pg_catalog.to_jsonb(x) into v_record;
 when 'sacco_loans' then
  if exists(select 1 from public.sacco_repayments p where p.loan_id=v_receipt.posted_record_id
    and p.voided_at is null) then
   raise exception 'Reverse all active repayments against this loan before reversing the loan' using errcode='22023';
  end if;
  update public.sacco_loans x set voided_at=now(),voided_by=v_actor,void_reason=v_reason
  where x.id=v_receipt.posted_record_id and x.legacy_key='native:'||v_receipt.draft_id::text and x.voided_at is null
  returning pg_catalog.to_jsonb(x) into v_record;
 when 'sacco_repayments' then
  update public.sacco_repayments x set voided_at=now(),voided_by=v_actor,void_reason=v_reason
  where x.id=v_receipt.posted_record_id and x.legacy_key='native:'||v_receipt.draft_id::text and x.voided_at is null
  returning pg_catalog.to_jsonb(x) into v_record;
 when 'sacco_financial_entries' then
  update public.sacco_financial_entries x set voided_at=now(),voided_by=v_actor,void_reason=v_reason
  where x.id=v_receipt.posted_record_id and x.legacy_key='native:'||v_receipt.draft_id::text and x.voided_at is null
  returning pg_catalog.to_jsonb(x) into v_record;
 when 'sacco_membership_fees' then
  update public.sacco_membership_fees x set voided_at=now(),voided_by=v_actor,void_reason=v_reason
  where x.id=v_receipt.posted_record_id and x.legacy_key='native:'||v_receipt.draft_id::text and x.voided_at is null
  returning pg_catalog.to_jsonb(x) into v_record;
 when 'sacco_waivers' then
  update public.sacco_waivers x set voided_at=now(),voided_by=v_actor,void_reason=v_reason
  where x.id=v_receipt.posted_record_id and x.legacy_key='native:'||v_receipt.draft_id::text and x.voided_at is null
  returning pg_catalog.to_jsonb(x) into v_record;
 end case;
 get diagnostics v_modified_rows=row_count;
 if v_modified_rows<>1 then
  raise exception 'Native ledger record missing, modified or previously voided; reversal refused'
    using errcode='23505';
 end if;
 -- BEFORE snapshot omits void fields to preserve original financial record clearly.
 insert into public.sacco_posting_reversals(
  posting_receipt_id,request_key,ledger_table,posted_record_id,reversed_by,reason,before_record
 ) values (
  p_receipt_id,p_request_key,v_receipt.ledger_table,v_receipt.posted_record_id,v_actor,v_reason,
  v_record - 'voided_at' - 'voided_by' - 'void_reason'
 ) returning * into v_reverse;
 insert into public.sacco_audit_entries(
  actor_user_id,event_kind,entity_table,entity_id,before_record,after_record
 ) values (
  v_actor,'NATIVE_REVERSAL',v_receipt.ledger_table,v_receipt.posted_record_id::text,
  v_reverse.before_record,
  pg_catalog.jsonb_build_object('posting_receipt_id',v_receipt.id,
   'reversal_id',v_reverse.id,'reason',v_reason,'reversed_by',v_actor,
   'cutover_reference',v_control.cutover_reference)
 );
 return pg_catalog.jsonb_build_object('reversal_id',v_reverse.id,'receipt_id',v_receipt.id,
  'already_reversed',false,'ledger_table',v_receipt.ledger_table,
  'posted_record_id',v_receipt.posted_record_id);
end$function$
;
revoke all on function sacco_private.guard_native_financial_history() from public,anon,authenticated,service_role;
revoke all on function public.sacco_reverse_posted_entry(uuid,uuid,text,text) from public,anon,authenticated,service_role;
commit;