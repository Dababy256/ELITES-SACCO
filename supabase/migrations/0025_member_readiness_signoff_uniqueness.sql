-- One self-reported successful 8/8 acceptance receipt per member per test version.
-- Cannot be edited or deleted by any browser account.
begin;
create unique index sacco_readiness_signoff_once_per_version
on public.sacco_member_readiness_signoffs(member_id,checks_version);
commit;