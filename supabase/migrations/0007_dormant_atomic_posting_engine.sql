-- Stage 5: dormant atomic posting engine. MUST remain disabled until post-backup reconciliation.
-- Not callable by browser roles. Review approval does not post or enable this function.
begin;
create table sacco_private.posting_control(
 singleton boolean primary key default true check(singleton),
 enabled boolean not null default false,
 source_reconciled_at timestamptz,
 cutover_reference text,
 updated_at timestamptz not null default now()
);
insert into sacco_private.posting_control(singleton,enabled) values(true,false);
revoke all on sacco_private.posting_control from public,anon,authenticated,service_role;

create table public.sacco_posting_receipts(
 id uuid primary key default gen_random_uuid(),
 draft_id uuid not null unique references public.sacco_staging_drafts(id) on delete restrict,
 review_id uuid not null references public.sacco_staging_reviews(id),
 ledger_table text not null check(ledger_table in(
  'sacco_contributions','sacco_loans','sacco_repayments','sacco_financial_entries',
  'sacco_membership_fees','sacco_waivers')),
 posted_record_id uuid not null,
 posted_by uuid not null references auth.users(id),
 posting_data jsonb not null,
 posted_at timestamptz not null default now()
);
alter table public.sacco_posting_receipts enable row level security;
revoke all on public.sacco_posting_receipts from public,anon,authenticated;
grant select on public.sacco_posting_receipts to authenticated;
grant select,insert,update,delete on public.sacco_posting_receipts to service_role;
create policy sacco_posting_receipts_admin_read on public.sacco_posting_receipts
 for select to authenticated using((select sacco_private.is_sacco_admin()));
create index sacco_posting_receipts_at_idx on public.sacco_posting_receipts(posted_at desc);

create function public.sacco_post_approved_draft(p_draft_id uuid)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
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
  if v_amount>1000000 then
   raise exception 'Regular loan over UGX 1,000,000 requires a separate approved policy' using errcode='22023';
  end if;
  select coalesce(max(loan_number),0)+1 into v_number from public.sacco_loans where member_id=v_member;
  insert into public.sacco_loans(member_id,loan_number,issued_on,principal,loan_type,legacy_key,source_record)
  values(v_member,v_number,v_when,v_amount,'REGULAR','native:'||p_draft_id::text,v_source)
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
end$$;
-- Intentionally inaccessible to both anonymous and signed-in browser users.
-- A separately reviewed, explicit future cutover must GRANT EXECUTE and set the
-- private posting gate after all original JSONBin movements are reconciled.
revoke all on function public.sacco_post_approved_draft(uuid) from public,anon,authenticated,service_role;
commit;