# Elites SACCO — Free-plan native transaction concurrency acceptance
**Verified:** 9 November 2026  
**Database:** Existing dedicated Elites SACCO Supabase Free project; **no paid branch or new project**  
**Original GitHub Pages / JSONBin website:** Unmodified

## Scope
Use a separate, private, short-lived `sacco_parallel_qa` schema **inside the existing Free project**. This is a schema containing only fictional members and cloned ledger tables. It is not in the exposed Data API schemas; roles `anon` and `authenticated` have no schema or function grants.

The functions tested were copied **at runtime from the current dormant native functions** using `pg_get_functiondef`, remapping ledger-table and private-function references to the fictional schema. A corresponding clone of `posting_control` was temporarily enabled; the real `sacco_private.posting_control` stayed **disabled** throughout. Existing original finance records were never copied into the clone.

## Tests performed with two independent SQL sessions
1. **Two approved drafts, same member/month/amount/date; different draft IDs.** Two overlapping requests to the actual cloned `post_approved_draft` routine:
   - One produced a new contribution receipt.
   - The other returned `23505 Possible duplicate financial posting blocked`.
   - Exactly one fictional contribution and one receipt recorded.
2. **Two concurrent retries of the SAME approved draft.**
   - Both returned the SAME original receipt ID with `already_posted=true`.
   - No second posting created.
3. **Two concurrent reversals using the SAME receipt and SAME reversal request key/reason.**
   - One returned a new reversal ID with `already_reversed=false`.
   - The other returned the SAME reversal ID with `already_reversed=true`.
4. **Second reversal with DIFFERENT request key.**
   - Rejected with `23505 This financial posting was already reversed; no second reversal allowed`.
5. **Final fictional clone assertions.**
   - One contribution ledger row retained for audit, **zero active contribution rows** after reversal, one posting receipt, one reversal receipt and one native-reversal audit event.
6. **Cleanup.**
   - The temporary `sacco_parallel_qa` schema was **dropped** (verified absent).
   - Verified live imports unchanged: **133 contributions (UGX 13,965,000), 28 loans, 27 repayments**.
   - **Zero real native posting receipts and zero real reversals**; real posting switch `enabled=false`; browser `EXECUTE` privilege still revoked.

## Repeatable test fixture
The disposable setup script is available at [`supabase/tests/free_plan_parallel_native_clone_setup.sql`](../supabase/tests/free_plan_parallel_native_clone_setup.sql). It requires a privileged SQL session and should **never** be executed with changed schema prefixes or as part of automatic production migrations. It creates a short-lived schema for manual acceptance testing, not an application schema.

Once the fixture has been created, run these through **two separate SQL connections concurrently** (replace `PARALLEL_A` with `PARALLEL_B` for the second connection):

```sql
begin;
select set_config('request.jwt.claim.sub',
 (select auth_user_id::text from sacco_parallel_qa.sacco_members
  where legacy_name='TEST_A'),true);
select sacco_parallel_qa.post_approved_draft(
 (select id from sacco_parallel_qa.sacco_staging_drafts
  where payload->>'note'='PARALLEL_A')
);
commit;
```

To verify idempotency, run the successful draft twice concurrently. To test reversals, call `sacco_parallel_qa.sacco_reverse_posted_entry` with the successful fictional posting receipt, the same unique request key and a descriptive reason of 15+ characters.

**Crucial:** This test remains a limited concurrency acceptance test. It does not cover high-load concurrent postings, every financial type, member-browser sign-in, interrupted network recovery, live backups, or cashbook accounting across a complete cutover. The actual posting engine stays locked.

## Safe teardown
Before production launch or ending the test session, check that the clone contains only fictional data; then remove it:

```sql
drop schema sacco_parallel_qa cascade;
```

The tested teardown also verified the cloned row counts and real gate state before removing the schema. Do not accidentally substitute `public` or `sacco_private` into this command.

## Free-plan password security
The Supabase adviser still reports `auth_leaked_password_protection`. Current Supabase documentation states this particular feature is **Pro-plan and above**. On Free, do **not** claim that this warning can be cleared without changing plan. Do **not** upgrade to unblock this staging test.

Security mitigations in place: email verification before onboarding, individual sign-ins, administrator identity approval, RLS isolation, 12-character signup prompt, security-invoker public RPC wrappers, and non-executable native financial posting/reversal functions. The 12-character check is client-side; set an equivalent server-side minimum in the Supabase Email Auth settings if offered on Free.

Official documentation: https://supabase.com/docs/guides/auth/password-security

## Remaining before authorizing cutover
1. **Final source write freeze** and fresh original-site JSON export after all real financial activity stops; rerun the private browser-local zero-difference check, manually inspect repayment-loan mapping, evidence and settings.
2. Full member-browser acceptance with the administrator and ordinary-member accounts (real sign-in and RLS behaviour, error messages, recovery, reviews and reports). Other three members may join later if the rollout has a documented policy.
3. Test business logic across loan issue dates/repayment events, expenses, savings arrears and reversals in a controlled integration test; current 84/84 loan-history parity and rollback-only suite are earlier passed checks.
4. Audit that all ordinary contributions/loan balances/reports ignore reversed entries. One common operational risk remains a still-running old JSONBin site that may receive activity after the final export.
5. Rotate the exposed old JSONBin credentials and remove old PIN/master-key paths **only at user-authorized final cutover**.

**Release gate remains CLOSED. This report does not authorize production merging or posting.**
