begin;
CREATE OR REPLACE FUNCTION sacco_private.validate_staging_draft(p_kind text, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_member uuid; v_member_text text; v_loan uuid; v_amount numeric; v_day date; v_date_text text;
 v_month text; v_duplicate_count integer:=0; v_warnings jsonb:='[]'::jsonb;
 v_interest_rule text; v_note text;
begin
 if p_kind not in ('CONTRIBUTION','LOAN','REPAYMENT','EXPENSE','INVESTMENT','CASH_IN','MEMBERSHIP_FEE','WAIVER') then
  return pg_catalog.jsonb_build_object('valid',false,'error','Unsupported transaction type');
 end if;
 if p_payload is null or pg_catalog.jsonb_typeof(p_payload)<>'object' then
  return pg_catalog.jsonb_build_object('valid',false,'error','Invalid transaction data');
 end if;
 v_member_text:=p_payload->>'member_id';
 if v_member_text is null or v_member_text !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
  return pg_catalog.jsonb_build_object('valid',false,'error','Choose a valid SACCO member');
 end if;
 v_member:=v_member_text::uuid;
 if not exists(select 1 from public.sacco_members where id=v_member) then
  return pg_catalog.jsonb_build_object('valid',false,'error','Member does not exist');
 end if;
 v_date_text:=p_payload->>'entry_on';
 if v_date_text is null or v_date_text !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
  return pg_catalog.jsonb_build_object('valid',false,'error','Choose a valid transaction date');
 end if;
 begin
  v_day:=v_date_text::date;
 exception when others then
  return pg_catalog.jsonb_build_object('valid',false,'error','Transaction date is invalid');
 end;
 if v_day < '2024-01-01'::date or v_day > (current_date + 31) then
  return pg_catalog.jsonb_build_object('valid',false,'error','Transaction date outside supported range');
 end if;
 if p_kind <> 'WAIVER' then
  if pg_catalog.jsonb_typeof(p_payload->'amount') <> 'number' then
   return pg_catalog.jsonb_build_object('valid',false,'error','Amount must be a number');
  end if;
  v_amount:=(p_payload->>'amount')::numeric;
  if v_amount <= 0 or v_amount > 10000000000 or pg_catalog.round(v_amount,2)<>v_amount then
   return pg_catalog.jsonb_build_object('valid',false,'error','Amount must be positive UGX with at most two decimals');
  end if;
 else
  v_amount:=0;
 end if;
 v_note:=pg_catalog.btrim(coalesce(p_payload->>'note',''));
 if pg_catalog.length(v_note)>300 then
  return pg_catalog.jsonb_build_object('valid',false,'error','Description is too long');
 end if;
 if p_kind in ('EXPENSE','WAIVER') and pg_catalog.length(v_note)<5 then
  return pg_catalog.jsonb_build_object('valid',false,'error','Provide a reason of at least five characters');
 end if;
 if p_kind in ('CONTRIBUTION','WAIVER') then
  v_month:=p_payload->>'month';
  if v_month is null or v_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' or v_month < '2024-02' then
   return pg_catalog.jsonb_build_object('valid',false,'error','Contribution month is invalid');
  end if;
  if v_month > pg_catalog.to_char(current_date + interval '1 month','YYYY-MM') then
   return pg_catalog.jsonb_build_object('valid',false,'error','Contribution month is too far in the future');
  end if;
  if p_kind='CONTRIBUTION' then
   select count(*) into v_duplicate_count from public.sacco_contributions c
   where c.member_id=v_member and c.contribution_month=(v_month||'-01')::date and c.amount=v_amount;
  else
   select count(*) into v_duplicate_count from public.sacco_waivers w
   where w.member_id=v_member and w.contribution_month=(v_month||'-01')::date;
  end if;
 elsif p_kind='REPAYMENT' then
  if coalesce(p_payload->>'loan_id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
   return pg_catalog.jsonb_build_object('valid',false,'error','Select a valid loan for repayment');
  end if;
  v_loan:=(p_payload->>'loan_id')::uuid;
  if not exists(select 1 from public.sacco_loans where id=v_loan and member_id=v_member) then
   return pg_catalog.jsonb_build_object('valid',false,'error','Loan does not belong to the selected member');
  end if;
  select count(*) into v_duplicate_count from public.sacco_repayments r
  where r.loan_id=v_loan and r.paid_on=v_day and r.amount=v_amount;
 elsif p_kind='LOAN' then
  select count(*) into v_duplicate_count from public.sacco_loans l
  where l.member_id=v_member and l.issued_on=v_day and l.principal=v_amount;
  if v_amount>1000000 then
   v_warnings:=v_warnings || pg_catalog.jsonb_build_array('Principal exceeds the usual UGX 1,000,000 regular-loan limit; verify SACCO authorization');
  end if;
 end if;
 if v_duplicate_count>0 then
  v_warnings:=v_warnings || pg_catalog.jsonb_build_array('Possible duplicate: matches '||v_duplicate_count||' imported transaction(s)');
 end if;
 if v_day>current_date then
  v_warnings:=v_warnings || pg_catalog.jsonb_build_array('Transaction date is in the future');
 end if;
 v_interest_rule:=case when p_kind='LOAN' then
   case when v_day>='2026-07-01' then '5% flat monthly' else '5% compounded monthly' end
   else null end;
 return pg_catalog.jsonb_build_object(
  'valid',true,'action_kind',p_kind,'member_id',v_member,
  'amount_ugx',v_amount,'entry_on',v_day,'loan_id',v_loan,
  'contribution_month',v_month,'interest_rule',v_interest_rule,
  'duplicate_count',v_duplicate_count,'warnings',v_warnings,
  'mode','STAGING_REVIEW_ONLY'
 );
end$function$
;
commit;