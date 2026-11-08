-- Active accounting rules: reversed native entries stay in history but are ignored in balances and duplicate detection.
-- Existing imported data has no void marker and is not changed.
begin;
CREATE OR REPLACE FUNCTION sacco_private.loan_due_as_of(p_loan_id uuid, p_as_of date)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 l public.sacco_loans%rowtype;
 v_total numeric:=0;v_balance numeric;v_prev date;v_anniv date;
 v_n integer:=1;v_months integer:=1;v_clear_month integer;
 v_r record;v_paid numeric:=0;v_this_months integer;
begin
 if p_loan_id is null or p_as_of is null then
  raise exception 'Loan id and as-of date are required' using errcode='22023';
 end if;
 select * into l from public.sacco_loans where id=p_loan_id;
 if not found then raise exception 'Loan not found' using errcode='22023';end if;
 if l.voided_at is not null then return 0;end if;
 if p_as_of<l.issued_on then return 0;end if;
 select coalesce(sum(amount),0) into v_total from public.sacco_repayments
  where loan_id=p_loan_id and voided_at is null and paid_on<=p_as_of;
 if l.manual_status='COMPLETE' then return 0;end if;
 if coalesce(l.frozen_total,0)>0 then
  return greatest(0,round(l.frozen_total-v_total));
 end if;
 if l.issued_on>='2026-07-01'::date then
  loop
   v_anniv:=(l.issued_on+pg_catalog.make_interval(months=>v_months))::date;
   exit when v_anniv+1>p_as_of or v_months>1200;
   v_months:=v_months+1;
  end loop;
  for v_r in select paid_on,amount from public.sacco_repayments
   where loan_id=p_loan_id and voided_at is null and paid_on<=p_as_of order by paid_on,id loop
   v_paid:=v_paid+v_r.amount;
   v_this_months:=1;
   loop
    v_anniv:=(l.issued_on+pg_catalog.make_interval(months=>v_this_months))::date;
    exit when v_anniv+1>v_r.paid_on or v_this_months>1200;
    v_this_months:=v_this_months+1;
   end loop;
   if v_paid>=l.principal*(1+0.05*v_this_months)-0.5 then
    v_clear_month:=v_this_months;
    exit;
   end if;
  end loop;
  return greatest(0,round(l.principal*(1+0.05*coalesce(v_clear_month,v_months))-v_total));
 end if;
 v_balance:=l.principal*1.05;
 select v_balance-coalesce(sum(amount),0) into v_balance from public.sacco_repayments
   where loan_id=p_loan_id and voided_at is null and paid_on<=l.issued_on and paid_on<=p_as_of;
 if v_balance<=0 then return 0;end if;
 v_n:=1;
 loop
  v_anniv:=(l.issued_on+pg_catalog.make_interval(months=>v_n))::date;
  exit when v_anniv>p_as_of or v_n>1200;
  v_prev:=(l.issued_on+pg_catalog.make_interval(months=>v_n-1))::date;
  select v_balance-coalesce(sum(amount),0) into v_balance from public.sacco_repayments
   where loan_id=p_loan_id and voided_at is null and paid_on>v_prev and paid_on<=v_anniv;
  if v_balance<=0 then v_balance:=0;exit;end if;
  v_balance:=v_balance*1.05;
  v_n:=v_n+1;
 end loop;
 v_prev:=(l.issued_on+pg_catalog.make_interval(months=>v_n-1))::date;
 select v_balance-coalesce(sum(amount),0) into v_balance from public.sacco_repayments
  where loan_id=p_loan_id and voided_at is null and paid_on>v_prev and paid_on<=p_as_of;
 return greatest(0,round(v_balance));
end$function$
;
CREATE OR REPLACE FUNCTION sacco_private.validate_staging_draft(p_kind text, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_member uuid; v_member_text text; v_loan uuid; v_amount numeric; v_day date; v_date_text text;
 v_month text; v_duplicate_count integer:=0; v_warnings jsonb:='[]'::jsonb;
 v_interest_rule text; v_note text; v_loan_type text; v_unsettled integer:=0;
 v_issue_on date; v_manual_status text;
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
   where c.voided_at is null and c.member_id=v_member and c.contribution_month=(v_month||'-01')::date and c.amount=v_amount;
  else
   select count(*) into v_duplicate_count from public.sacco_waivers w
   where w.voided_at is null and w.member_id=v_member and w.contribution_month=(v_month||'-01')::date;
  end if;
 elsif p_kind='REPAYMENT' then
  if coalesce(p_payload->>'loan_id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
   return pg_catalog.jsonb_build_object('valid',false,'error','Select a valid loan for repayment');
  end if;
  v_loan:=(p_payload->>'loan_id')::uuid;
  select l.issued_on,l.manual_status into v_issue_on,v_manual_status
   from public.sacco_loans l where l.id=v_loan and l.member_id=v_member and l.voided_at is null;
  if not found then
   return pg_catalog.jsonb_build_object('valid',false,'error','Loan does not belong to the selected member');
  end if;
  if v_day < v_issue_on then
   return pg_catalog.jsonb_build_object('valid',false,'error','Repayment date precedes the loan issue date');
  end if;
  if v_manual_status='COMPLETE' then
   v_warnings:=v_warnings || pg_catalog.jsonb_build_array(
    'Loan is manually marked complete. Original source still permits recording a repayment; independently verify amount and avoid unintended overpayment.'
   );
  end if;
  select count(*) into v_duplicate_count from public.sacco_repayments r
  where r.voided_at is null and r.loan_id=v_loan and r.paid_on=v_day and r.amount=v_amount;
 elsif p_kind='LOAN' then
  v_loan_type:=coalesce(nullif(pg_catalog.btrim(p_payload->>'loan_type'),''),'REGULAR');
  if v_loan_type not in ('REGULAR','DEVELOPMENTAL') then
   return pg_catalog.jsonb_build_object('valid',false,'error','Loan type must be regular or developmental');
  end if;
  select count(*) into v_duplicate_count from public.sacco_loans l
  where l.voided_at is null and l.member_id=v_member and l.issued_on=v_day and l.principal=v_amount;
  select count(*) into v_unsettled from public.sacco_loans prev
  where prev.voided_at is null and prev.member_id=v_member and prev.issued_on<=v_day
    and sacco_private.loan_due_as_of(prev.id,v_day)>0;
  if v_loan_type='REGULAR' and v_amount>1000000 then
   v_warnings:=v_warnings || pg_catalog.jsonb_build_array('Regular loan exceeds UGX 1,000,000; administrator approval and a documented override reason required');
  end if;
  if v_unsettled>0 then
   v_warnings:=v_warnings || pg_catalog.jsonb_build_array(
    v_unsettled||' unpaid existing loan(s) identified; administrator approval and a documented override reason required'
   );
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
  'loan_type',v_loan_type,'prior_unsettled_count',v_unsettled,
  'cap_override_requested',(p_payload->>'override_regular_cap'='true'),
  'unsettled_override_requested',(p_payload->>'override_unsettled_loan'='true'),
  'mode','STAGING_REVIEW_ONLY'
 );
end$function$
;
CREATE OR REPLACE FUNCTION public.sacco_post_approved_draft(p_draft_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_actor uuid;
 v_ctl sacco_private.posting_control%rowtype;
 v_draft public.sacco_staging_drafts%rowtype;
 v_review public.sacco_staging_reviews%rowtype;
 v_receipt public.sacco_posting_receipts%rowtype;
 v_checked jsonb;
 v_amount numeric;
 v_when date;
 v_month date;
 v_member uuid;
 v_loan uuid;
 v_number integer;
 v_ledger text;
 v_posted uuid;
 v_source jsonb;
 v_loan_type text;
 v_unpaid_prior integer;
 v_exception_reason text;
begin
 v_actor:=(select auth.uid());
 if v_actor is null or not (select sacco_private.is_sacco_admin()) then
  raise exception 'Verified administrator membership required' using errcode='42501';
 end if;
 -- No one can turn posting on through a public API or staging UI.
 select * into v_ctl from sacco_private.posting_control where singleton=true for update;
 if not found or not v_ctl.enabled or v_ctl.source_reconciled_at is null
    or nullif(pg_catalog.btrim(v_ctl.cutover_reference),'') is null then
  raise exception 'Real ledger posting disabled until cutover and source reconciliation' using errcode='42501';
 end if;
 select * into v_draft from public.sacco_staging_drafts where id=p_draft_id for update;
 if not found then raise exception 'Draft not found' using errcode='22023'; end if;
 -- Idempotency: a previously-posted draft returns exactly the existing receipt.
 select * into v_receipt from public.sacco_posting_receipts where draft_id=p_draft_id;
 if found then
  return pg_catalog.jsonb_build_object('receipt_id',v_receipt.id,'draft_id',p_draft_id,
   'ledger_table',v_receipt.ledger_table,'record_id',v_receipt.posted_record_id,
   'already_posted',true);
 end if;
 select * into v_review from public.sacco_staging_reviews
 where draft_id=p_draft_id and decision='APPROVED';
 if not found then raise exception 'Draft must have an approved staging review' using errcode='42501'; end if;
 -- Lock the member to serialize postings for that member and avoid concurrent loan numbering
 -- or separate drafts that look distinct before the first one is committed.
 v_member:=(v_draft.payload->>'member_id')::uuid;
 perform 1 from public.sacco_members where id=v_member for update;
 if not found then raise exception 'Member record missing' using errcode='22023'; end if;
 v_checked:=sacco_private.validate_staging_draft(v_draft.action_kind,v_draft.payload);
 if (v_checked->>'valid')::boolean is distinct from true then
  raise exception 'Draft failed revalidation: %',v_checked->>'error' using errcode='22023';
 end if;
 if coalesce((v_checked->>'duplicate_count')::integer,0)>0 then
  raise exception 'Possible duplicate financial posting blocked' using errcode='23505';
 end if;
 v_amount:=(v_checked->>'amount_ugx')::numeric;
 v_when:=(v_checked->>'entry_on')::date;
 v_month:=case when v_draft.action_kind in ('CONTRIBUTION','WAIVER')
  then ((v_checked->>'contribution_month')||'-01')::date else null end;
 v_loan:=nullif(v_checked->>'loan_id','')::uuid;
 v_source:=pg_catalog.jsonb_build_object('source','supabase_native',
  'draft_id',p_draft_id,'review_id',v_review.id,
  'posted_by',v_actor,'note',coalesce(v_draft.payload->>'note',''));
 case v_draft.action_kind
 when 'CONTRIBUTION' then
  insert into public.sacco_contributions(member_id,contribution_month,paid_on,amount,legacy_key,source_record)
  values(v_member,v_month,v_when,v_amount,'native:'||p_draft_id::text,v_source)
  returning id into v_posted;v_ledger:='sacco_contributions';
 when 'LOAN' then
  v_loan_type:=coalesce(nullif(pg_catalog.btrim(v_draft.payload->>'loan_type'),''),'REGULAR');
  if v_loan_type not in ('REGULAR','DEVELOPMENTAL') then
   raise exception 'Unsupported loan type' using errcode='22023';
  end if;
  v_exception_reason:=pg_catalog.btrim(coalesce(v_review.review_note,''));
  -- Original site presents an administrator confirmation rather than a universal ban.
  if v_loan_type='REGULAR' and v_amount>1000000 and not (
    v_draft.payload->>'override_regular_cap'='true'
    and char_length(v_exception_reason)>=15
  ) then
   raise exception 'Regular loan exceeds UGX 1,000,000; an explicitly approved override and documented reason are required'
   using errcode='22023';
  end if;
  select count(*) into v_unpaid_prior
   from public.sacco_loans prev
   where prev.voided_at is null and prev.member_id=v_member and prev.issued_on<=v_when
     and sacco_private.loan_due_as_of(prev.id,v_when)>0;
  if v_unpaid_prior>0 and not (
   v_draft.payload->>'override_unsettled_loan'='true'
   and char_length(v_exception_reason)>=15
  ) then
   raise exception 'Member already has % unsettled loan(s); explicitly approved override and a documented reason required',v_unpaid_prior
   using errcode='22023';
  end if;
  if v_loan_type='REGULAR' and v_amount>1000000 or v_unpaid_prior>0 then
   v_source:=v_source || pg_catalog.jsonb_build_object(
    'policy_override',pg_catalog.jsonb_build_object(
     'regular_cap',v_loan_type='REGULAR' and v_amount>1000000,
     'unsettled_loans',v_unpaid_prior,'authorization_note',v_exception_reason,
     'authorized_by',v_review.reviewed_by
    )
   );
  end if;
  select coalesce(max(loan_number),0)+1 into v_number from public.sacco_loans where member_id=v_member;
  insert into public.sacco_loans(member_id,loan_number,issued_on,principal,loan_type,legacy_key,source_record)
  values(v_member,v_number,v_when,v_amount,v_loan_type,'native:'||p_draft_id::text,v_source)
  returning id into v_posted;v_ledger:='sacco_loans';
 when 'REPAYMENT' then
  insert into public.sacco_repayments(member_id,loan_id,paid_on,amount,legacy_key,source_record)
  values(v_member,v_loan,v_when,v_amount,'native:'||p_draft_id::text,v_source)
  returning id into v_posted;v_ledger:='sacco_repayments';
 when 'EXPENSE','INVESTMENT','CASH_IN' then
  if exists(select 1 from public.sacco_financial_entries f
   where f.voided_at is null and f.entry_kind=lower(v_draft.action_kind) and f.entry_on=v_when
   and f.amount=v_amount and lower(coalesce(f.narrative,''))=lower(coalesce(v_draft.payload->>'note',''))) then
    raise exception 'Matching cashbook entry already exists' using errcode='23505';
  end if;
  insert into public.sacco_financial_entries(entry_kind,entry_on,amount,narrative,legacy_key,source_record)
  values(lower(v_draft.action_kind),v_when,v_amount,
   nullif(pg_catalog.btrim(coalesce(v_draft.payload->>'note','')),''),
   'native:'||p_draft_id::text,v_source)
  returning id into v_posted;v_ledger:='sacco_financial_entries';
 when 'MEMBERSHIP_FEE' then
  if exists(select 1 from public.sacco_membership_fees f where f.voided_at is null and f.member_id=v_member and f.paid_on=v_when and f.amount=v_amount) then
   raise exception 'Matching membership fee already exists' using errcode='23505';
  end if;
  insert into public.sacco_membership_fees(member_id,paid_on,amount,legacy_key,source_record)
  values(v_member,v_when,v_amount,'native:'||p_draft_id::text,v_source)
  returning id into v_posted;v_ledger:='sacco_membership_fees';
 when 'WAIVER' then
  insert into public.sacco_waivers(member_id,contribution_month,legacy_key,source_record)
  values(v_member,v_month,'native:'||p_draft_id::text,v_source)
  returning id into v_posted;v_ledger:='sacco_waivers';
 else
  raise exception 'Unsupported posting kind' using errcode='22023';
 end case;
 insert into public.sacco_posting_receipts(draft_id,review_id,ledger_table,posted_record_id,posted_by,posting_data)
 values(p_draft_id,v_review.id,v_ledger,v_posted,v_actor,v_checked)
 returning * into v_receipt;
 insert into public.sacco_audit_entries(actor_user_id,event_kind,entity_table,entity_id,after_record)
 values(v_actor,'NATIVE_POST',v_ledger,v_posted::text,
  pg_catalog.jsonb_build_object('receipt_id',v_receipt.id,'draft_id',p_draft_id,
   'review_id',v_review.id,'cutover_reference',v_ctl.cutover_reference));
 return pg_catalog.jsonb_build_object('receipt_id',v_receipt.id,'draft_id',p_draft_id,
  'ledger_table',v_ledger,'record_id',v_posted,'already_posted',false);
end$function$
;
revoke all on function sacco_private.loan_due_as_of(uuid,date) from public,anon,authenticated,service_role;
revoke all on function sacco_private.validate_staging_draft(text,jsonb) from public,anon,authenticated;
revoke all on function public.sacco_post_approved_draft(uuid) from public,anon,authenticated,service_role;
commit;
