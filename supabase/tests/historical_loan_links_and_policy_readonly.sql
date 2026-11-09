-- Read-only historical source metadata parity (9 November 2026).
-- This does not verify freshness of the original website or upload its JSON backup.
with loan_meta as (
 select
  count(*) as loan_count,
  count(*) filter(where l.loan_number<=0) as bad_numbers,
  count(*) filter(where l.loan_type is distinct from
    coalesce(nullif(l.source_record->>'loanType',''),'REGULAR')) as changed_loan_types,
  count(*) filter(where coalesce(l.frozen_total,0)
    <>coalesce(nullif(l.source_record->>'frozenTotal','')::numeric,0)) as changed_frozen_totals
 from public.sacco_loans l
), repay_meta as (
 select
  count(*) as repayment_count,
  count(*) filter(where l.id is null) as orphaned_repayment_links,
  count(*) filter(where l.id is not null and r.member_id<>l.member_id) as cross_member_repayments,
  count(*) filter(where l.id is not null and r.paid_on<l.issued_on) as repayments_predating_issue,
  count(*) filter(where coalesce(r.source_record->>'loanId','') <>
     coalesce(l.loan_number::text,'')) as source_loan_number_mismatches,
  count(*) filter(where coalesce(r.source_record->>'loanId','')='') as source_loan_number_missing
 from public.sacco_repayments r
 left join public.sacco_loans l on r.loan_id=l.id
), settings as (
 select
 count(*) as settings_row_count,
 bool_and(value->>'monthlyTarget'='150000') as target_is_150k,
 bool_and(value->>'membershipFee'='50000') as membership_is_50k,
 bool_and(value->'targetOverrides'='{}'::jsonb) as no_special_overrides,
 bool_and(coalesce(value->>'paymentInfo','')='') as blank_payment_info
 from public.sacco_settings
)
select loan_count,repayment_count,
 orphaned_repayment_links,cross_member_repayments,
 repayments_predating_issue,source_loan_number_mismatches,
 source_loan_number_missing,changed_loan_types,
 changed_frozen_totals,bad_numbers,
 settings_row_count,target_is_150k,membership_is_50k,
 no_special_overrides,blank_payment_info,
 (loan_count=28 and repayment_count=27 and
  orphaned_repayment_links=0 and cross_member_repayments=0 and
  repayments_predating_issue=0 and source_loan_number_mismatches=0 and
  source_loan_number_missing=0 and changed_loan_types=0 and
  changed_frozen_totals=0 and bad_numbers=0 and
  settings_row_count=1 and target_is_150k and membership_is_50k and
  no_special_overrides and blank_payment_info) as nov6_import_metadata_check
from loan_meta cross join repay_meta cross join settings;
