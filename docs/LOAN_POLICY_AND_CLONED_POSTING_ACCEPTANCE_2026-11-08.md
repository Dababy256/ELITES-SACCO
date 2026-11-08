# Elites SACCO — loan-policy alignment and cloned posting acceptance checkpoint
**Test date:** 8 November 2026
**Environment:** Dedicated Supabase staging project, standalone Vercel preview, original GitHub Pages/JSONBin site unchanged.

## Source policy verified from the original `main/index.html`
- Repayments may be made on the issue date or later. There is no mandatory monthly waiting period.
- A 5% charge applies immediately.
- Loans dated from 1 July 2026 use 5% flat interest on principal, added on the day after each monthly anniversary; interest stops after repayment reaches the amount due under the original calculation.
- Earlier loans compound at 5% monthly, applying repayments by their dates.
- A frozen loan uses its fixed frozen total minus repayments. Manual completion overrides the computed balance.
- The original website supports **REGULAR** and **DEVELOPMENTAL** loan types. For a regular loan above UGX 1,000,000 or a new loan while an earlier one is outstanding, it shows an administrator warning and allows explicit administrator confirmation. These are not unconditional prohibitions.

## Completed release-candidate changes
1. **Read-only server interest function:** `sacco_private.loan_due_as_of(uuid,date)` now implements source-policy interest and time-bound repayments. It is not callable through the public browser Data API.
2. **Historical parity:** compared the original site's JavaScript calculation against the server routine on all 28 imported loans at **8 Nov 2026, 31 Dec 2026 and 1 Feb 2027**: **84 of 84 matches**, zero differences.
3. **Locked real posting function:** still disabled and not executable by anonymous or signed-in browser roles. Internal branch for loans now distinguishes REGULAR and DEVELOPMENTAL and requires BOTH a requested exception flag and a documented administrator-review note (15+ characters) for a regular loan above UGX 1,000,000 or an unpaid earlier loan. The approved exception is recorded in the posted transaction source/audit metadata. Actual posting is not active.
4. **Staging draft review:** server validator reports existing outstanding loans, loan type and over-cap warnings; staging approval rejects unapproved exceptions or undocumented authorizations. Both successful and blocked review flows were tested in rolled-back SQL transactions.
5. **Administrator interface:** the **Draft approvals (sandbox)** tab now includes loan-type choice, over-cap and unsettled-loan exception flags, and a mandatory written approval justification on flagged loans.
6. **Actual locked posting logic tested in a fictional clone:** the versioned `supabase/tests/clone_real_posting_rollback.sql` uses `pg_get_functiondef` to copy the current server function and its dependencies into temporary, isolated, empty cloned tables inside one database transaction. Synthetic data cover a loan issue, immediate same-day partial repayment, contribution, expense, membership fee, idempotent retry, seven audit receipts, rejected over-cap/unpaid-loan exceptions and permitted overrides with reviewer justification. All assertions completed; `ROLLBACK` removed the entire clone and its data.

## Deployment and account checks
- Staging site: https://elites-sacco-auth-preview.vercel.app/
- READY deployment: `dpl_J5siqSoYxQ1GFetY9pe2GKL58fWw`; stable alias confirmed.
- Live old GitHub `main/index.html` unchanged, SHA `c0825d30bbd254130b4dea64fc8ce42629b91937`.
- Imported financial books unchanged: 133 contributions totaling UGX 13,965,000; 28 loans; 27 repayments.
- Two of five member identities linked; the remaining three may enroll later.
- **0 actual financial posting receipts**, **posting_enabled=false**, and anonymous/authenticated roles **cannot call** `sacco_post_approved_draft`.
- Two persistent, fictional QA lab events were present after user testing; they are isolated from the real books. Do not erase them without user request.
- Supabase security advisor still reports four signed-in-callable SECURITY DEFINER functions, guarded internally, and disabled leaked-password screening.

## Safe manual test of loan exception review
1. Sign in as administrator on the **test portal**, select **Draft approvals (sandbox)**, and choose **Loan disbursement**.
2. Choose a member with an existing loan; select REGULAR or DEVELOPMENTAL; choose a test amount. For a regular loan above UGX 1,000,000, select the special cap exception. For any existing unsettled loan, select that exception too.
3. Save the staging draft, then open it in the queue and choose **Preview validation**. Read the real-data loan-policy warnings.
4. If any exception is requested/required, provide **a specific review justification of at least 15 characters** and approve. This approves a staging record only, **not a real loan or payment**.
5. The isolated **Financial posting lab** remains available for actual writes into fictional `TEST_A` and `TEST_B` accounts. It cannot alter the real financial ledger.

## Remaining before production launch
- The **real posting engine has no completed production-grade reversal design/acceptance test**. The QA lab has reversals, but it is a separate implementation and does not certify production reversals.
- An independent staging database/project branch would be useful for full end-to-end deployment tests and concurrency; creating one may incur extra Supabase charges. The current rollback clone is not a replacement for all integration tests.
- Confirm final original-site write freeze, latest backup and fields not included in the zero-difference comparator, including original repayment associations, payment screenshots, policy settings and requests.
- Review privileged RPCs, leaked-password protection and old JSONBin credential rotation.
- Explicit cutover decision is still required; **do not merge** the migration PR or enable actual financial posting.

**Status: accounting migration staging improved; original production still authoritative.**
