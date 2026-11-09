-- Lock imported historical books for the staging phase.
-- Browser users must create proposals in sacco_staging_drafts instead.
-- The existing SELECT privileges and RLS read policies remain unchanged.
begin;
revoke insert,update,delete on
 public.sacco_contributions,
 public.sacco_loans,
 public.sacco_repayments,
 public.sacco_financial_entries,
 public.sacco_membership_fees,
 public.sacco_waivers,
 public.sacco_settings,
 public.sacco_minutes
 from authenticated;
commit;
