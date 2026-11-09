# The Elites SACCO — pre-launch browser acceptance and deep backup reconciliation
**Checkpoint date:** 9 November 2026  
**Cost/plan:** Existing Supabase Free project; no paid Supabase branch or upgrade  
**Production:** Original GitHub Pages / JSONBin website unchanged, still authoritative

## New browser features prepared on migration branch
- `staging/supabase-readonly.html` now includes a **Readiness checks** tab for all signed-in, approved members.
- The tab performs fresh, read-only database queries under the current member's actual authenticated session: verified account linkage, five-member roster (admin) or one-member roster (ordinary account), cross-member savings/loans/repayment RLS isolation, repayment-to-loan integrity, member-approval privacy, private audit/QA record visibility, and zero real native posting/reversal history. An ordinary-member session also calls the admin draft-preview RPC with a nonexistent draft ID to verify role denial; this is read-only and cannot post finances.
- An administrator additionally checks the imported November 6 financial baseline: **133 contributions totalling UGX 13,965,000, 28 loans, 27 repayments**.
- The tab contains explicit manual **cutover blockers**: source write freeze, fresh backup, detailed reconciliation, real member-browser login test, evidence/photos and password recovery, and old-key rotation.
- This is a local display. The results are not persisted to Supabase. A logged-in member must run the test in their own session; database simulations alone are not a substitute.
- The source code passed JavaScript syntax parsing. **Vercel deployment `dpl_54RFgLBhBc8CewtDksVuQEsh4Rwt` is READY** and the stable staging alias `https://elites-sacco-auth-preview.vercel.app/` was verified. The new tab is deployed but each member must still run browser acceptance using their own sign-in.

## Browser-local backup comparison now covers more than amounts
Previously the private browser comparison showed 0 unmatched records but did not differentiate the links between repayments and their original loans.

The upgraded browser comparator now checks:
- Original sequential **loan number** by member (not only principal/date).
- Every repayment's source `loanId` compared to the imported loan's `loan_number`.
- Each loan's original `loanType`, `purpose`, frozen total and manual completion flag (when provided).
- Policy settings: monthly contribution target, membership fee, monthly overrides and payment information, compared entirely in browser without exposing private values in CSV/detail text.
- Previously supported member roster, savings, investment, cash-in, expense, membership-fee, minute and waiver categories.
- The comparator **does not** compare private PINs, photos/logo, physical evidence/receipts or unstructured edit history. It also cannot prove whether the selected file is the latest production export.

Synthetic JavaScript regression checks:
- Matching member, loan, repayment and settings → **0 unmatched**.
- Incorrect original repayment `loanId` → **2 unmatched comparison rows**.
- Incorrect monthly contribution target → **2 unmatched comparison rows**.

## Independent historical import checks against the saved November 6 backup
The November 6 original-site JSON backup was available locally in the execution environment. It was examined **without uploading it or committing its contents, PINs, photos or credentials**.

The backup's relevant policy fields are:
- Monthly contribution target: UGX 150,000
- Membership fee: UGX 50,000
- Special monthly target overrides: none
- Payment information text: blank

The existing Supabase import matches those fields.

Database check [`supabase/tests/historical_loan_links_and_policy_readonly.sql`](../supabase/tests/historical_loan_links_and_policy_readonly.sql) **PASSED**:
- 28 loans and 27 repayments.
- **27 of 27** repayments matched the original stored `loanId` to their linked imported loan number.
- Zero repayments linked to a different member or dated before the loan issuance.
- Zero missing source loan numbers.
- Zero mismatches for original loan types or frozen totals.
- Savings target, membership fee, overrides and payment-information blankness all matched the original.
- Import settings are compared only for the November 6 snapshot, not against the ongoing original site after that date.

No financial records were updated.

## User acceptance instructions
**Administrator:** Visit the separate test portal when the updated deployment is READY, sign in, select **Readiness checks**, click **Run read-only checks now**, and inspect the results. As of this baseline, eight automated checks should pass. Use **Reconcile backup** locally only with an original-site JSON export; do not share a PIN-bearing backup.

**Ordinary member (already approved):** Sign in on their own device and account, select **Readiness checks** and run the same tests. Expect the ordinary member to see their own financial records and no other member's records. Their eight checks include a read-only denial of a privileged operation.

**Neither sign-in test authorizes production changes.** The original website should remain operational until explicitly frozen.

## Financial safeguards reverified
- Supabase: 5 members; 2 linked accounts; 133 original contributions (UGX 13,965,000); 28 loans; 27 repayments.
- 0 native real posting receipts; 0 real reversal receipts.
- `sacco_private.posting_control.enabled=false`.
- Browser-authenticated role has no native posting or reversal EXECUTE permission.
- Source GitHub Pages application is not modified.
- Remaining Supabase Auth advisory: leaked-password protection; currently available on Pro and above, so not required for staging on Free. Prefer a server-enforced strong-password minimum where the Free dashboard supports it.

## Remaining launch blockers
1. After choosing a cutover date, **freeze** original-site writes, export the fresh authoritative backup, and repeat the upgraded comparison. Do not freeze it prematurely.
2. Independently verify logo, photos, evidence attachments and historical edit/audit data where relevant, as these are outside structured reconciliation.
3. Have both linked identities perform real-browser acceptance, including ordinary member financial privacy; record a reproducible failure report if a test fails.
4. Test recovery email and operational support instructions. The other 3 member accounts can onboard later with a rollout plan.
5. Rotate exposed legacy JSONBin credentials, retire old PIN handling and explicitly authorize the cutover **only after** the preceding checks.

**No merge, no production deployment, no native posting.**
