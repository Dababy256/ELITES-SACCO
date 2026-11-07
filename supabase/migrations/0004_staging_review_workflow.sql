-- Stage 4: immutable review workflow. Approval is a SANDBOX decision, never a financial posting.
begin;

create table public.sacco_staging_reviews (
 id uuid primary key default gen_random_uuid(),
 draft_id uuid not null unique references public.sacco_staging_drafts(id) on delete restrict,
 decision text not null check(decision in ('APPROVED','REJECTED')),
 reviewed_by uuid not null references auth.users(id),
 review_note text not null default '' check(char_length(review_note)<=500),
 validation_snapshot jsonb not null,
 reviewed_at timestamptz not null default now()
);
alter table public.sacco_staging_reviews enable row level security;
revoke all on public.sacco_staging_reviews from public,anon,authenticated;
grant select on public.sacco_staging_reviews to authenticated;
grant select,insert,update,delete on public.sacco_staging_reviews to service_role;
create policy sacco_staging_reviews_admin_read on public.sacco_staging_reviews
 for select to authenticated using ((select sacco_private.is_sacco_admin()));
create index sacco_staging_reviews_recent_idx on public.sacco_staging_reviews(reviewed_at desc);

create function sacco_private.validate_staging_draft(p_kind text, p_payload jsonb)
returns jsonb language plpgsql stable security definer set search_path='' as $$
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
end$$;
revoke all on function sacco_private.validate_staging_draft(text,jsonb) from public,anon,authenticated;
grant execute on function sacco_private.validate_staging_draft(text,jsonb) to service_role;

create function public.sacco_preview_draft(p_draft_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare d public.sacco_staging_drafts%rowtype; v_result jsonb; v_review public.sacco_staging_reviews%rowtype;
begin
 if (select auth.uid()) is null or not (select sacco_private.is_sacco_admin()) then
  raise exception 'Administrator membership required' using errcode='42501';
 end if;
 select * into d from public.sacco_staging_drafts where id=p_draft_id;
 if not found then raise exception 'Draft not found' using errcode='22023'; end if;
 v_result:=sacco_private.validate_staging_draft(d.action_kind,d.payload);
 select * into v_review from public.sacco_staging_reviews where draft_id=d.id;
 return pg_catalog.jsonb_build_object(
  'draft_id',d.id,'validation',v_result,'review_status',
  case when v_review.id is null then 'PENDING' else v_review.decision end,
  'posted_to_financial_ledger',false
 );
end$$;
revoke all on function public.sacco_preview_draft(uuid) from public,anon;
grant execute on function public.sacco_preview_draft(uuid) to authenticated;

create function public.sacco_review_draft(p_draft_id uuid,p_decision text,p_note text default '')
returns jsonb language plpgsql security definer set search_path='' as $$
declare d public.sacco_staging_drafts%rowtype; v_review public.sacco_staging_reviews%rowtype;
 v_check jsonb; v_reviewer uuid; v_note text;
begin
 v_reviewer:=(select auth.uid());
 if v_reviewer is null or not (select sacco_private.is_sacco_admin()) then
  raise exception 'Administrator membership required' using errcode='42501';
 end if;
 if p_decision not in ('APPROVED','REJECTED') or p_decision is null then
  raise exception 'Invalid decision' using errcode='22023';
 end if;
 v_note:=pg_catalog.btrim(coalesce(p_note,''));
 if pg_catalog.length(v_note)>500 then raise exception 'Review note is too long' using errcode='22023'; end if;
 if p_decision='REJECTED' and pg_catalog.length(v_note)<5 then
  raise exception 'A rejection reason of at least five characters is required' using errcode='22023';
 end if;
 -- Locks the draft before looking at the unique review row. Concurrent review requests serialize.
 select * into d from public.sacco_staging_drafts where id=p_draft_id for update;
 if not found then raise exception 'Draft not found' using errcode='22023'; end if;
 select * into v_review from public.sacco_staging_reviews where draft_id=d.id;
 if found then
  if v_review.decision<>p_decision then
   raise exception 'Draft already reviewed; conflicting decision rejected' using errcode='23505';
  end if;
  return pg_catalog.jsonb_build_object('review_id',v_review.id,'decision',v_review.decision,
    'already_reviewed',true,'posted_to_financial_ledger',false);
 end if;
 v_check:=sacco_private.validate_staging_draft(d.action_kind,d.payload);
 if p_decision='APPROVED' and (v_check->>'valid')::boolean is distinct from true then
  raise exception 'Draft validation failed: %', v_check->>'error' using errcode='22023';
 end if;
 if p_decision='APPROVED' and coalesce((v_check->>'duplicate_count')::integer,0)>0 then
  raise exception 'Possible duplicate. Approving blocked pending duplicate reconciliation' using errcode='23505';
 end if;
 insert into public.sacco_staging_reviews(draft_id,decision,reviewed_by,review_note,validation_snapshot)
 values(d.id,p_decision,v_reviewer,v_note,v_check)
 returning * into v_review;
 insert into public.sacco_audit_entries(actor_user_id,event_kind,entity_table,entity_id,after_record)
 values(v_reviewer,'STAGING_'||p_decision,'sacco_staging_drafts',d.id::text,
  pg_catalog.jsonb_build_object('review_id',v_review.id,'kind',d.action_kind,
    'decision',p_decision,'note',v_note,'mode','STAGING_REVIEW_ONLY'));
 return pg_catalog.jsonb_build_object('review_id',v_review.id,'decision',v_review.decision,
  'already_reviewed',false,'posted_to_financial_ledger',false);
end$$;
revoke all on function public.sacco_review_draft(uuid,text,text) from public,anon;
grant execute on function public.sacco_review_draft(uuid,text,text) to authenticated;

-- No function created in this migration may post to actual financial tables.
-- Live entries will require a separate audited cutover migration after reconciliation.
commit;