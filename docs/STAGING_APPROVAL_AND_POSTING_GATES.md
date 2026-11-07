# Elites SACCO — approval and locked posting stage
**Prepared:** 7 November 2026  
**Status:** Staging review usable; real ledger posting intentionally disabled.

## Changes delivered
- Database migration `0004_staging_review_workflow.sql`: append-only staging review table with unique `draft_id`, administrator-only RLS read access, server-side validation for member, amount, dates, linked loan, contribution month and probable duplicate transactions.
- Approval functions `sacco_preview_draft` and `sacco_review_draft` check the authenticated SACCO administrator inside privileged code; blank or inadequate rejection reasons are rejected. Approved or rejected decisions are immutable and written to the central audit ledger.
- Duplicate approval requests for the **same** draft are idempotent; a conflicting later decision is not allowed. Approval blocks when a matching historical contribution, loan, repayment or waiver is detected.
- The staging dashboard now offers **Draft approvals (sandbox)** with a preview step, approval/rejection decisions and a permanent indication that no money is posted.
- Database migration `0007_dormant_atomic_posting_engine.sql` prepared the later actual posting implementation for contributions, loans, repayments, expenses, investments, cash-ins, membership fees and waivers. It uses atomic transactions, authorizing administrator identity, linked approved review, validated data, per-member locking, a unique draft receipt and financial audit events.
- The **posting engine is OFF**. The private `sacco_private.posting_control` gate is set to `enabled=false`, no source reconciliation is recorded, and `authenticated` plus `anon` roles lack EXECUTE permission on `sacco_post_approved_draft`. Turning on posting requires an explicit future controlled cutover.
- Follow-up SQL compatibility fixes for the review functions are captured in migrations `0005_fix_review_validator.sql` and `0006_fix_review_rpc.sql`.

## Tests completed
- The administrator can preview and approve a valid draft in a transaction that rolls back after testing.
- The same approval request is idempotent: the review row count stays at one.
- A known historical contribution is detected as a potential duplicate.
- A rejection creates an appropriate staging review record in a test transaction.
- The unlinked-account RPC attempt was denied with `42501 Administrator membership required`.
- Anonymous accounts have no EXECUTE privilege on staging review RPCs.
- Supabase security advisor highlights staging review functions as callable SECURITY DEFINER functions. This is intentional and **must remain subject to further security audit**; the functions check membership, and an unlinked account was denied in a direct RPC test.
- Supabase also warns that leaked-password protection is disabled; review Auth settings before full-member rollout.
- **Actual posting engine execution has NOT been acceptance-tested**. A rollback-only attempt to temporarily enable its gate was blocked by the execution tool's safety checks; no bypass was attempted.
- Final database counts unchanged: 5 members, 133 contributions, 28 loans, 27 repayments, zero permanent staging review rows, zero permanent posting receipts.
- Latest test portal deploy reports READY and is aliased at https://elites-sacco-auth-preview.vercel.app/.

## How the administrator can test the UI without financial risk
1. Sign in to https://elites-sacco-auth-preview.vercel.app/ (not demo mode).
2. Select **Draft approvals (sandbox)** from the account navigation.
3. Create a test draft using a SACCO member and plausible transaction data; do not use this as a payment receipt.
4. Open the draft in the queue and select **Preview validation**.
5. Use **Approve in sandbox** or **Reject draft**. The review is stored permanently as a staging record, while all financial balances remain unchanged.
6. Verify the staging-only status is visible. **Approved does not mean posted**.

## Do not release or merge yet
- Reconcile the original JSONBin source for every transaction made after the 6 Nov 2026 backup snapshot; resolve double-entry conflicts.
- Verify the posting routine against synthetic transactions and concurrency/replay scenarios in an isolated test environment. A failed test or unavailable test facility is **not** a pass.
- Establish a production approval policy, including handling of errors, reversals, overpayments and financial close-out.
- Authenticate and link the other four SACCO members and test cross-member isolation.
- Review data-access lints and turn on leaked-password protection if available.
- Rotate exposed JSONBin credentials and remove old client secrets only at production cutover.
- Explicit authorization is required before granting browser EXECUTE privileges or enabling the private posting gate.

**Current position: protected staging, not a production accounting system.**
