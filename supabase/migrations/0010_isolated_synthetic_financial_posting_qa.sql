-- Isolated write-capable QA ledger. Synthetic TEST_A / TEST_B only.
-- Separate from all sacco_* financial tables; original website and imported books are untouched.
begin;
create table public.sacco_qa_entries(
 id uuid primary key default gen_random_uuid(),
 actor_user_id uuid not null references auth.users(id),
 request_key uuid not null,
 kind text not null check(kind in('CONTRIBUTION','LOAN','REPAYMENT','EXPENSE','CASH_IN','INVESTMENT','REVERSAL')),
 member_code text not null check(member_code in('TEST_A','TEST_B')),
 entry_on date not null,
 amount numeric(16,2) not null check(amount>0),
 loan_id uuid references public.sacco_qa_entries(id),
 contribution_month date,
 note text not null default '' check(char_length(note)<=300),
 reverses_id uuid unique references public.sacco_qa_entries(id),
 created_at timestamptz not null default now(),
 unique(actor_user_id,request_key),
 constraint qa_links check(
  (kind='REPAYMENT' and loan_id is not null and reverses_id is null and contribution_month is null)
  or (kind='REVERSAL' and reverses_id is not null and loan_id is null and contribution_month is null)
  or (kind='CONTRIBUTION' and contribution_month is not null and loan_id is null and reverses_id is null)
  or (kind not in('REPAYMENT','REVERSAL','CONTRIBUTION') and loan_id is null and reverses_id is null and contribution_month is null)
 )
);
alter table public.sacco_qa_entries enable row level security;
revoke all on public.sacco_qa_entries from public,anon,authenticated;
grant select on public.sacco_qa_entries to authenticated;
create policy sacco_qa_entries_admin_read on public.sacco_qa_entries
 for select to authenticated using(
 actor_user_id=(select auth.uid()) and (select sacco_private.is_sacco_admin()));
create index sacco_qa_entries_actor_at on public.sacco_qa_entries(actor_user_id,created_at desc);

create table public.sacco_qa_audit(
 id uuid primary key default gen_random_uuid(),
 actor_user_id uuid not null references auth.users(id),
 entry_id uuid not null references public.sacco_qa_entries(id),
 event_kind text not null check(event_kind in('QA_POST','QA_REVERSAL')),
 event_data jsonb not null,
 created_at timestamptz not null default now()
);
alter table public.sacco_qa_audit enable row level security;
revoke all on public.sacco_qa_audit from public,anon,authenticated;
grant select on public.sacco_qa_audit to authenticated;
create policy sacco_qa_audit_admin_read on public.sacco_qa_audit
 for select to authenticated using(
 actor_user_id=(select auth.uid()) and (select sacco_private.is_sacco_admin()));

create function sacco_private.qa_post(
 p_request_key uuid,p_kind text,p_member_code text,p_entry_on date,p_amount numeric,
 p_loan_id uuid default null,p_contribution_month text default null,p_note text default ''
) returns jsonb language plpgsql volatile security definer set search_path='' as $$
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
end$$;
revoke all on function sacco_private.qa_post(uuid,text,text,date,numeric,uuid,text,text) from public,anon,authenticated;
grant execute on function sacco_private.qa_post(uuid,text,text,date,numeric,uuid,text,text) to authenticated;

create function sacco_private.qa_reverse(p_request_key uuid,p_entry_id uuid,p_reason text)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare v_actor uuid;v_original public.sacco_qa_entries%rowtype;v_seen public.sacco_qa_entries%rowtype;
 v_new public.sacco_qa_entries%rowtype;v_reason text;
begin
 v_actor:=(select auth.uid());
 if v_actor is null or not (select sacco_private.is_sacco_admin()) then
  raise exception 'Verified administrator required' using errcode='42501';
 end if;
 if p_request_key is null or p_entry_id is null then raise exception 'Provide transaction and request identifiers' using errcode='22023'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_actor::text,2026));
 select * into v_seen from public.sacco_qa_entries
 where actor_user_id=v_actor and request_key=p_request_key;
 if found then
  if v_seen.kind<>'REVERSAL' or v_seen.reverses_id<>p_entry_id then
   raise exception 'Request key was already used for a different reversal' using errcode='23505';
  end if;
  return pg_catalog.jsonb_build_object('receipt_id',v_seen.id,'already_posted',true,'qa_only',true);
 end if;
 select * into v_original from public.sacco_qa_entries
 where id=p_entry_id and actor_user_id=v_actor and kind<>'REVERSAL';
 if not found then raise exception 'Test transaction not found or already a reversal' using errcode='22023'; end if;
 if exists(select 1 from public.sacco_qa_entries where reverses_id=v_original.id) then
  raise exception 'Test transaction has already been reversed' using errcode='23505';
 end if;
 v_reason:=pg_catalog.btrim(coalesce(p_reason,''));
 if char_length(v_reason)<5 or char_length(v_reason)>300 then
  raise exception 'Give a reversal reason of 5-300 characters' using errcode='22023';
 end if;
 if v_original.kind='LOAN' and exists(
  select 1 from public.sacco_qa_entries rp
  where rp.loan_id=v_original.id and rp.kind='REPAYMENT'
   and not exists(select 1 from public.sacco_qa_entries rv where rv.reverses_id=rp.id)
 ) then
  raise exception 'Reverse associated test repayments before reversing a test loan' using errcode='22023';
 end if;
 insert into public.sacco_qa_entries(actor_user_id,request_key,kind,member_code,
   entry_on,amount,reverses_id,note)
 values(v_actor,p_request_key,'REVERSAL',v_original.member_code,current_date,
   v_original.amount,v_original.id,v_reason)
 returning * into v_new;
 insert into public.sacco_qa_audit(actor_user_id,entry_id,event_kind,event_data)
 values(v_actor,v_new.id,'QA_REVERSAL',
  pg_catalog.jsonb_build_object('original_id',v_original.id,'original_kind',v_original.kind,
   'reason',v_reason,'qa_only',true));
 return pg_catalog.jsonb_build_object('receipt_id',v_new.id,'reversed_id',v_original.id,
  'already_posted',false,'qa_only',true);
end$$;
revoke all on function sacco_private.qa_reverse(uuid,uuid,text) from public,anon,authenticated;
grant execute on function sacco_private.qa_reverse(uuid,uuid,text) to authenticated;

-- Public invoker wrappers expose only the narrow test action while private definer
-- implementation enforces SACCO administrator identity and synthetic TEST_A/TEST_B data.
create function public.sacco_qa_post(p_request_key uuid,p_kind text,p_member_code text,p_entry_on date,p_amount numeric,
 p_loan_id uuid default null,p_contribution_month text default null,p_note text default '')
returns jsonb language sql volatile security invoker set search_path='' as $$
 select sacco_private.qa_post(p_request_key,p_kind,p_member_code,p_entry_on,p_amount,
   p_loan_id,p_contribution_month,p_note)
$$;
revoke all on function public.sacco_qa_post(uuid,text,text,date,numeric,uuid,text,text) from public,anon;
grant execute on function public.sacco_qa_post(uuid,text,text,date,numeric,uuid,text,text) to authenticated;

create function public.sacco_qa_reverse(p_request_key uuid,p_entry_id uuid,p_reason text)
returns jsonb language sql volatile security invoker set search_path='' as $$
 select sacco_private.qa_reverse(p_request_key,p_entry_id,p_reason)
$$;
revoke all on function public.sacco_qa_reverse(uuid,uuid,text) from public,anon;
grant execute on function public.sacco_qa_reverse(uuid,uuid,text) to authenticated;
commit;