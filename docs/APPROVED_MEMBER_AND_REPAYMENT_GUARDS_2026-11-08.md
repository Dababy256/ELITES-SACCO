# Elites SACCO — approved ordinary-member access and repayment validation checkpoint
**Date:** 8 November 2026  
**Scope:** Dedicated Supabase staging project, no real financial posting.

## Verified account onboarding
- 2 of the 5 historical members now have email-confirmed Auth accounts linked to their SACCO records.
- The newly linked ordinary member is **Okullo David Laurence**. An approved `sacco_access_requests` row exists, with review recorded in the staging system.
- The remaining three historical member profiles remain in the database, with no linked sign-in. Their later onboarding does not block continued **read-only and sandbox testing**.

## Real-member RLS regression
Using the approved ordinary member's Auth identity **in a transaction-scoped database RLS simulation**, results were:
- Exactly **one** member profile accessible; **zero** other member rows.
- The account's own data is visible: **27 contribution entries**, **5 loans**, **4 repayments**.
- **Zero** other members' contribution, loan or repayment records visible.
- **Zero** administrator cashbook, audit, staging drafts or reviews visible.
- No `INSERT` privilege on historical loan rows and no `EXECUTE` privilege on actual posting engine.
- The one accessible membership access request was that member's own.
- Note: The test verifies database role permissions using the approved user's Auth ID; it is **not** a full member-browser acceptance test.
- Reproducible SQL committed as [`supabase/tests/member_rls_smoke_readonly.sql`](../supabase/tests/member_rls_smoke_readonly.sql).

## Repayment validation tightened
- Migration [`0009_repayment_date_guards.sql`](../supabase/migrations/0009_repayment_date_guards.sql) now rejects a repayment with a date **before the loan was issued**.
- It also stops processing a new repayment against a loan with a manual `COMPLETE` override until review.
- Read-only regression with an existing historical loan showed `bad_date_valid=false` and `correct_date_valid=true`, with expected error text.
- Reproducible SQL in [`supabase/tests/repayment_validator_readonly.sql`](../supabase/tests/repayment_validator_readonly.sql).
- Existing imported repayment rows were **not** changed.

## Full release preflight (re-run)
- Members: **5**; linked: **2**; 133 contributions (UGX 13,965,000); 28 loans; 27 repayments.
- **0** orphaned repayments, early repayment dates, invalid amounts or exact duplicate date/amount record combinations.
- **0** actual posting receipts.
- Private posting switch **disabled**; authenticated and anonymous browser roles **cannot execute** the posting function.
- **Core record integrity: PASS; posting gate: CLOSED.**
- Member onboarding: INCOMPLETE (3 members can enroll later).

## Release decision / remaining work
- The administrator separately reported **0 unmatched records** using the browser-local backup reconciliation tool. The file, timestamp and detailed comparator output were not transmitted for independent checking.
- An actual **isolated and synthetic posting transaction acceptance test** remains necessary, including retries, overpayment, reversals, rollback, audit trail and loan interest boundary cases. The dormant posting engine was not executed in this stage.
- The server currently cannot enable leaked-password screening through the available Supabase connector. See Supabase Auth security settings; its advisor still reports this option disabled.
- Four publicly exposed `SECURITY DEFINER` API functions have internal authorization checks but remain security-advisor warnings, requiring review before full release.
- Completing registration for all remaining members is **not a prerequisite for read-only pilot testing**. It is a membership access rollout task for later.
- **Do not merge or switch production yet.** The original JSONBin site stays authoritative until final source freeze and explicit migration approval.
