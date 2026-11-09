-- Pure read-only loan balance calculation for policy enforcement.
-- Repayments may occur on the issue date (no one-month waiting period).
-- Never changes historical loan or repayment records.
begin;
create or replace function sacco_private.loan_due_as_of(p_loan_id uuid,p_as_of date)
returns numeric language plpgsql stable security definer set search_path='' as $$
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
 if p_as_of<l.issued_on then return 0;end if;
 select coalesce(sum(amount),0) into v_total from public.sacco_repayments
  where loan_id=p_loan_id and paid_on<=p_as_of;
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
   where loan_id=p_loan_id and paid_on<=p_as_of order by paid_on,id loop
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
   where loan_id=p_loan_id and paid_on<=l.issued_on and paid_on<=p_as_of;
 if v_balance<=0 then return 0;end if;
 v_n:=1;
 loop
  v_anniv:=(l.issued_on+pg_catalog.make_interval(months=>v_n))::date;
  exit when v_anniv>p_as_of or v_n>1200;
  v_prev:=(l.issued_on+pg_catalog.make_interval(months=>v_n-1))::date;
  select v_balance-coalesce(sum(amount),0) into v_balance from public.sacco_repayments
   where loan_id=p_loan_id and paid_on>v_prev and paid_on<=v_anniv;
  if v_balance<=0 then v_balance:=0;exit;end if;
  v_balance:=v_balance*1.05;
  v_n:=v_n+1;
 end loop;
 v_prev:=(l.issued_on+pg_catalog.make_interval(months=>v_n-1))::date;
 select v_balance-coalesce(sum(amount),0) into v_balance from public.sacco_repayments
  where loan_id=p_loan_id and paid_on>v_prev and paid_on<=p_as_of;
 return greatest(0,round(v_balance));
end$$;
revoke all on function sacco_private.loan_due_as_of(uuid,date) from public,anon,authenticated,service_role;
commit;