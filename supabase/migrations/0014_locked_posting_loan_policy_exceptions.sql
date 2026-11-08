-- Correct locked posting routine to require documented administrator approval for original SACCO loan exceptions.
-- No GRANT, gate change, or financial mutation occurs in this migration.
begin;
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
   where prev.member_id=v_member and prev.issued_on<=v_when
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
   where f.entry_kind=lower(v_draft.action_kind) and f.entry_on=v_when
   and f.amount=v_amount and lower(coalesce(f.narrative,''))=lower(coalesce(v_draft.payload->>'note',''))) then
    raise exception 'Matching cashbook entry already exists' using errcode='23505';
  end if;
  insert into public.sacco_financial_entries(entry_kind,entry_on,amount,narrative,legacy_key,source_record)
  values(lower(v_draft.action_kind),v_when,v_amount,
   nullif(pg_catalog.btrim(coalesce(v_draft.payload->>'note','')),''),
   'native:'||p_draft_id::text,v_source)
  returning id into v_posted;v_ledger:='sacco_financial_entries';
 when 'MEMBERSHIP_FEE' then
  if exists(select 1 from public.sacco_membership_fees f where f.member_id=v_member and f.paid_on=v_when and f.amount=v_amount) then
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
revoke all on function public.sacco_post_approved_draft(uuid) from public,anon,authenticated,service_role;
commit;