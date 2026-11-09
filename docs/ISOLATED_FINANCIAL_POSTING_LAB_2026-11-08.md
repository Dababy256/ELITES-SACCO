# Elites SACCO — isolated financial posting lab (8 November 2026)

**Separate test portal:** https://elites-sacco-auth-preview.vercel.app/  
**Tab:** `Financial posting lab` (administrator only)  
**Status:** Works with a *different, synthetic* ledger. This is not a production posting cutover.

## Why this is safe
- The original website on GitHub Pages / JSONBin has **not been edited** and remains the authoritative financial source.
- The 6 November financial import in Supabase is **not modified** by this lab.
- New, isolated tables `public.sacco_qa_entries` and `public.sacco_qa_audit` hold only fictional test member codes `TEST_A` and `TEST_B`.
- Supabase enforces RLS and only authenticated verified SACCO administrators can invoke the narrow QA posting and reversal functions. Ordinary members cannot see or insert QA records, and direct QA table INSERT/UPDATE/DELETE privileges are revoked.
- The actual posting engine `sacco_post_approved_draft` remains disabled and browser-inaccessible.
- The QA tables accept REAL database transactions only in the *synthetic* ledger, not financial credits/debits to SACCO members.
- Test audit and reversal events are append-only, and each posting has a unique request identifier to prevent accidental duplicate retries.

## Source-of-truth loan rules confirmed in `main/index.html`
- The **repayment may be made at any time on or after loan issuance**, including the same day. No mandatory one-month waiting period exists in the source.
- First 5% interest applies immediately to a new loan.
- For loans issued **1 July 2026 onward**, interest is **5% flat per month on original principal**. Second month's interest starts on the day *after* the first monthly anniversary, and subsequent months likewise. Repayments reduce outstanding but not the fixed monthly interest charge. Interest stops after the loan is cleared under the original implementation.
- For loans issued **before 1 July 2026**, interest compounds **5% monthly** subject to repayment dates.
- Frozen loans use their frozen total less repayments. A manual `COMPLETE` override sets the calculated outstanding to zero.
- The original source **warns** about ordinary loans above UGX 1,000,000 or starting another loan with an outstanding balance, and offers explicit admin override. It does not impose an unconditional hard block. Test UI mirrors those warnings.
- Staging validator was updated to warn about a repayment against a manually completed loan instead of imposing an extra hard prohibition.
- The QA lab calculates outstanding balances using the existing staging `loanBalance` function already compared against original `calcLoanBalance` across all 28 historical loans at checked dates. This is a UI calculation; no automatic *interest posting* to real books happens.

## How to test
1. Sign in as the administrator at https://elites-sacco-auth-preview.vercel.app/ and select **Financial posting lab**. Do **not** use demo mode.
2. Choose `Issue test loan`, `Fictional TEST_A`, today's date and **UGX 1,000,000**; choose **POST TEST TRANSACTION**. Confirm explicitly. This creates a REAL database row only in `sacco_qa_entries`. You will see a posting receipt.
3. Select `Post test repayment`, `Fictional TEST_A`, the same date, the newly created fictional loan and **UGX 200,000**. Post and confirm.
4. Under **Fictional loan balances**, the loan should show **UGX 850,000** outstanding (1,000,000 + immediate 5% of principal − 200,000).
5. Select **Verify idempotent retry of last posting**. The same receipt should be returned with a message indicating that no second row was created.
6. Test an additional partial repayment using a different amount or date; outstanding should decrease according to the original interest rules. A repayment dated before loan issuance should be rejected.
7. Select **Reverse test transaction** against one of the fictional repayments. Provide a reason. The repayment should remain visible in history as **REVERSED**, and the calculated outstanding should increase again.
8. Test reversing the test loan itself. The server should reject that while unreversed repayments remain linked; reverse those first. After reversal, the loan disappears from active balances but remains in immutable test history.
9. Optional: test a savings contribution, expense, investment and cash-in using fictional TEST_B. Verify the synthetic cash-flow summary updates.
10. Reopen the original SACCO website. Its real balances and transaction counts must remain unchanged.

## Tests already performed programmatically
- A synthetic UGX 1,000,000 loan and UGX 200,000 **same-day** repayment were posted in a rolled-back SQL transaction, with the expected UGX 850,000 policy balance.
- Repeating an identical request with its original idempotency identifier created only one loan/repayment row.
- Reversing a repayment wrote one QA reversal event and an audit entry; replay of the reversal did not duplicate it.
- A repayment dated **before issuance** was rejected.
- Attempting to reverse a loan with an active repayment was rejected. Reversing the repayment first then the loan succeeded.
- Ordinary member RLS read simulation returned zero private QA rows.
- The SQL test transaction was rolled back; current QA ledger starts with zero events.
- Historical financial ledgers remain 133 contributions, 28 loans and 27 repayments; original posting gate remains disabled and browser users lack posting privilege.

## Limits and remaining release work
- QA functions are separate from and are **not the same as the dormant actual member posting function**, so passing QA does not certify production posting.
- The dormant production posting function still needs a policy alignment review (notably exception handling for regular-loan cap and unpaid-loan eligibility), isolated clone-data execution, reversals, concurrency and accounting reconciliation tests.
- Repeated posting with a **new** request identifier but identical amount, date, kind and member is blocked as a possible duplicate in QA; exceptional legitimate duplicate payments need a documented override workflow in production.
- There is no automated validation of cash availability, signed approval minutes or evidentiary receipts in QA; these are separate controls for real operations.
- The administrator reported zero unmatched records when comparing a backup; final original-site write freeze and refreshed comparison must still happen at cutover.
- Remaining member onboarding and outstanding Supabase Auth security advisories remain separate release tasks.
- No site migration or real financial posting is authorized by testing this lab.
