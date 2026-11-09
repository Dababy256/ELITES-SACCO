begin;
CREATE OR REPLACE FUNCTION sacco_private.qa_post(p_request_key uuid, p_kind text, p_member_code text, p_entry_on date, p_amount numeric, p_loan_id uuid DEFAULT NULL::uuid, p_contribution_month text DEFAULT NULL::text, p_note text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_actor uuid;v_existing public.sacco_qa_entries%rowtype;v_post public.sacco_qa_entries%rowtype;
 v_loan public.sacco_qa_entries%rowtype;v_month date;v_note text;
begin
 v_actor:=(select auth.uid());
 if v_actor is null or not (select sacco_private.is_sacco_admin()) then
  raise exception 'Verified SACCO administrator required' using errcode='42501';
 end if;
 if p_request_key is null then raise exception 'Request idempotency key is required' using errcode='22023'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_actor::text,2026));
 select * into v_existing from public.sacco_qa_entries
 where actor_user_id=v_actor and request_key=p_request_key;
 if found then
  if v_existing.kind<>p_kind or v_existing.member_code<>p_member_code or
     v_existing.entry_on is distinct from p_entry_on or v_existing.amount is distinct from p_amount or
     v_existing.loan_id is distinct from p_loan_id or
     coalesce(pg_catalog.to_char(v_existing.contribution_month,'YYYY-MM'),'')
       <>coalesce(p_contribution_month,'') then
    raise exception 'Idempotency key already used for another transaction' using errcode='23505';
  end if;
  return pg_catalog.jsonb_build_object('receipt_id',v_existing.id,'already_posted',true,'qa_only',true);
 end if;
 if p_kind is null or p_kind not in ('CONTRIBUTION','LOAN','REPAYMENT','EXPENSE','CASH_IN','INVESTMENT') then
  raise exception 'Unsupported test transaction type' using errcode='22023';
 end if;
 if p_member_code is null or p_member_code not in ('TEST_A','TEST_B') then
  raise exception 'Only fictional TEST_A and TEST_B may be used' using errcode='22023';
 end if;
 if p_entry_on is null or p_entry_on<'2024-01-01' or p_entry_on>current_date+31 then
  raise exception 'Invalid test transaction date' using errcode='22023';
 end if;
 if p_amount is null or p_amount<=0 or p_amount>10000000000
    or round(p_amount,2)<>p_amount then
  raise exception 'Enter a positive amount with no more than two decimals' using errcode='22023';
 end if;
 v_note:=pg_catalog.btrim(coalesce(p_note,''));
 if char_length(v_note)>300 then raise exception 'Description is too long' using errcode='22023'; end if;
 if p_kind in ('EXPENSE','INVESTMENT','CASH_IN') and char_length(v_note)<5 then
  raise exception 'A reason of at least five characters is required' using errcode='22023';
 end if;
 if p_kind='CONTRIBUTION' then
  if p_contribution_month is null or
     p_contribution_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
   raise exception 'Select a valid contribution month' using errcode='22023';
  end if;
  v_month:=(p_contribution_month||'-01')::date;
  if v_month<'2024-02-01' or v_month>date_trunc('month',current_date+interval '1 month')::date then
   raise exception 'Contribution month is outside supported range' using errcode='22023';
  end if;
 elsif p_contribution_month is not null and p_contribution_month<>'' then
  raise exception 'Contribution month belongs only to savings' using errcode='22023';
 end if;
 if p_kind='REPAYMENT' then
  if p_loan_id is null then raise exception 'Select a test loan' using errcode='22023'; end if;
  select * into v_loan from public.sacco_qa_entries
   where id=p_loan_id and actor_user_id=v_actor and kind='LOAN' and member_code=p_member_code;
  if not found then raise exception 'Test loan not found for this fictional member' using errcode='22023'; end if;
  if exists(select 1 from public.sacco_qa_entries z where z.reverses_id=v_loan.id) then
   raise exception 'Test loan has been reversed' using errcode='22023';
  end if;
  if p_entry_on<v_loan.entry_on then
   raise exception 'Payment cannot be recorded before loan issue' using errcode='22023';
  end if;
 elsif p_loan_id is not null then
  raise exception 'Only a repayment may select a loan' using errcode='22023';
 end if;
 -- Detect identical test entries. Different partial payments remain valid.
 if exists(select 1 from public.sacco_qa_entries e
 where e.actor_user_id=v_actor and e.kind=p_kind and e.member_code=p_member_code
 and e.entry_on=p_entry_on and e.amount=p_amount
 and e.loan_id is not distinct from p_loan_id
 and e.contribution_month is not distinct from v_month
 and not exists(select 1 from public.sacco_qa_entries rev where rev.reverses_id=e.id)) then
  raise exception 'Possible duplicate test posting already exists; review or reverse it first'
  using errcode='23505';
 end if;
 insert into public.sacco_qa_entries(
 actor_user_id,request_key,kind,member_code,entry_on,amount,loan_id,contribution_month,note)
 values(v_actor,p_request_key,p_kind,p_member_code,p_entry_on,p_amount,p_loan_id,v_month,v_note)
 returning * into v_post;
 insert into public.sacco_qa_audit(actor_user_id,entry_id,event_kind,event_data)
 values(v_actor,v_post.id,'QA_POST',
  pg_catalog.jsonb_build_object('kind',p_kind,'member_code',p_member_code,'amount',p_amount,
   'entry_on',p_entry_on,'loan_id',p_loan_id,'qa_only',true));
 return pg_catalog.jsonb_build_object('receipt_id',v_post.id,'already_posted',false,'qa_only',true);
end$function$
;
commit;