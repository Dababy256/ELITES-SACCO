-- Regression test: existing loan REPAYMENT validations, no inserts.
-- Must report bad_date_valid=false, correct_date_valid=true.
with candidate as (
 select id, member_id, issued_on from public.sacco_loans
 where issued_on > '2024-01-01'
 order by issued_on desc limit 1
), checked as (
 select
  sacco_private.validate_staging_draft('REPAYMENT',jsonb_build_object(
    'member_id',member_id,'loan_id',id,'amount',1234,
    'entry_on',to_char(issued_on - 1,'YYYY-MM-DD'),'note','qa_only'
  )) as bad_date,
  sacco_private.validate_staging_draft('REPAYMENT',jsonb_build_object(
    'member_id',member_id,'loan_id',id,'amount',1234,
    'entry_on',to_char(issued_on,'YYYY-MM-DD'),'note','qa_only'
  )) as correct_date
 from candidate
)
select
 (bad_date->>'valid')::boolean bad_date_valid,
 bad_date->>'error' bad_date_error,
 (correct_date->>'valid')::boolean correct_date_valid
from checked;
