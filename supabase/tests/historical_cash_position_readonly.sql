-- Read-only source-formula financial position from active (nonvoided) ledger rows.
-- The historical baseline is from the original 2026-11-06 JSON backup.
with loans as (
 select l.id,l.principal,coalesce(sum(r.amount),0) repaid
 from public.sacco_loans l
 left join public.sacco_repayments r on r.loan_id=l.id and r.voided_at is null
 where l.voided_at is null
 group by l.id,l.principal
), loan_summary as (
 select coalesce(sum(principal),0) as principal_issued,
 coalesce(sum(repaid),0) as repayments_received,
 coalesce(sum(greatest(0,repaid-least(principal,repaid))),0) as interest_collected,
 coalesce(sum(greatest(0,principal-least(principal,repaid))),0) as active_loan_principal
 from loans
), base as (
 select
 (select coalesce(sum(amount),0) from public.sacco_contributions where voided_at is null) as gross_savings,
 (select coalesce(sum(amount),0) from public.sacco_membership_fees where voided_at is null) as membership_fees,
 (select coalesce(sum(amount),0) from public.sacco_financial_entries where entry_kind='cash_in' and voided_at is null) as other_cash_in,
 (select coalesce(sum(amount),0) from public.sacco_financial_entries where entry_kind='expense' and voided_at is null) as expenses,
 (select coalesce(sum(amount),0) from public.sacco_financial_entries where entry_kind='investment' and voided_at is null) as investments
)
select b.*,l.principal_issued,l.repayments_received,l.interest_collected,l.active_loan_principal,
(b.gross_savings+l.interest_collected+b.other_cash_in+b.membership_fees-
 (b.expenses+l.active_loan_principal+b.investments)) as original_formula_net_cash,
(b.gross_savings+l.repayments_received+b.other_cash_in+b.membership_fees-
 (b.expenses+l.principal_issued+b.investments)) as direct_cashflow_net_cash,
(b.gross_savings+l.interest_collected+b.other_cash_in+b.membership_fees-
 (b.expenses+l.active_loan_principal+b.investments))=
(b.gross_savings+l.repayments_received+b.other_cash_in+b.membership_fees-
 (b.expenses+l.principal_issued+b.investments)) as calculation_equivalence,
(b.gross_savings=13965000 and l.principal_issued=19230000 and
 l.repayments_received=14638631 and b.other_cash_in=227781 and
 b.membership_fees=100000 and b.expenses=825000 and b.investments=7100000 and
 (b.gross_savings+l.repayments_received+b.other_cash_in+b.membership_fees-
 (b.expenses+l.principal_issued+b.investments))=1776412) as original_nov6_snapshot_matches
from base b cross join loan_summary l;