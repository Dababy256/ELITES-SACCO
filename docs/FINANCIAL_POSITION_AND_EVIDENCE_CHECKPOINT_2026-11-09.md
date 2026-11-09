**CORRECTION — 9 November 2026:** Subsequent exact integrity checks confirm the historical profile photo and all 13 original loan/repayment edit events **had already been imported** into member/audit tables; the logo has now been restored privately in `sacco_branding`. All match the original source. See [verified source evidence archive](SOURCE_EVIDENCE_PRESERVED_2026-11-09.md). Previous statements below about evidence not being migrated reflect the earlier provisional inventory, not the verified final state.

# The Elites SACCO — Financial position acceptance & historical evidence inventory
**Checkpoint:** 9 November 2026  
**Plan:** Supabase Free; isolated Vercel staging project  
**Release status:** Staging deployed; original SACCO GitHub Pages/JSONBin untouched; real financial posting locked

## Source-equivalent cash reconciliation — PASSED
Confirmed original `getGlobalStats()` accounting calculation in the original site:
```
Net cash = Savings + Membership fees + Collected loan interest + Other cash received
           - Expenses - Principal still circulating - Investments
```
This equals the direct cashflow identity:
```
Net cash = Savings + ALL loan repayments + Membership fees + Other cash received
           - ALL loans disbursed - Expenses - Investments
```
Both approaches give the same result for the November 6 historical import. **Neither proves the actual bank/cash holdings.**

| Original accounting component | UGX |
|---|---:|
| Gross savings (133 entries) | 13,965,000 |
| Membership fees (2 entries) | 100,000 |
| Collected interest on repayments | 958,631 |
| Other cash received (2 entries) | 227,781 |
| Expenses (3 entries) | 825,000 |
| Loan principal circulating | 5,550,000 |
| Investments (3 entries) | 7,100,000 |
| **NET CASH POSITION** | **1,776,412** |

Direct cashflow verification:
- Loan principal issued: UGX **19,230,000** over **28 loans**.
- Loan repayments actually received: UGX **14,638,631** over **27 repayments**.
- All category counts and sums matched the original 6 November 2026 JSON backup.
- Both formulas produced **UGX 1,776,412**, exact match.

A repeatable, non-mutating database test was added at [`supabase/tests/historical_cash_position_readonly.sql`](../supabase/tests/historical_cash_position_readonly.sql). Output `calculation_equivalence=true`, `original_nov6_snapshot_matches=true`.

## Cashbook portal upgrade
- Staging administrator **Cashbook** tab now shows ledger net cash, collected interest, principal circulating and membership fees; a detailed seven-category cashflow breakdown and a downloadable sanitized position CSV.
- The report derives figures from current **nonvoided** financial records and uses the original accounting formula.
- It warns if the source-formula and direct-cashflow figures ever diverge (e.g. owing to orphaned repayments).
- The report is not shown to ordinary members. No posting controls are enabled.
- Staging Vercel deployment: `dpl_F5uLHk2v4pfyNcnsFGUXL8RhXd93` READY, confirmed stable alias https://elites-sacco-auth-preview.vercel.app/.
- Tested JavaScript compilation, and a synthetic fixture produced the expected cash net. The complete original-source category totals and financial formula were independently validated by the read-only SQL query.

## Evidence archive inventory (not yet migrated)
The Nov 6 original export includes:
- **1 SACCO logo**.
- **1 member profile photo entry**.
- **13 history edit-log events**, all tagged `Loan/Repayment`.
- A separate legacy PIN field in member records.

These nonledger elements were **NOT** uploaded to GitHub, Vercel, Supabase Storage or a public website. The existing import is NOT a complete replacement for their secure preservation. The browser-only `Reconcile backup` screen now counts their presence without sending the content to a service.

Before switching off the original site, confirm a secure archive of complete original backup and independent plan to preserve or migrate images and adjustment evidence. Do not publish the member photo or copy raw PINs to the new app.

## Role / security verification
- `authenticated` role has NO direct INSERT/UPDATE/DELETE privileges on core contribution, loan, repayment, cashbook, membership fee, waiver, minutes or settings tables. Administrative transactions remain mediated by dedicated authorized RPCs.
- Native posting `sacco_post_approved_draft` and reversal `sacco_reverse_posted_entry` remain non-executable by browser roles.
- Current native posting gate `enabled=false`, **0** native posted transactions, **0** native reversals.
- Members 5; linked, email-confirmed accounts 2; remaining 3 can be onboarded under a controlled rollout.
- No changes to original GitHub Pages `main/index.html` (sha `c0825d30bbd254130b4dea64fc8ce42629b91937`).

## User approval versus final cutover
The administrator stated **"APPROVAL DONE. PROCEED"** in conversation. This authorizes moving through the remaining safe acceptance work; it does not establish the timestamp of the last transaction on the old site, the source write freeze, or a new final export. Do not assume those are complete.

**Required before go-live:**
1. Decide a time to stop all financial writes to the original site; announce it to all affected members.
2. After the final old-site transaction, export a **fresh full JSON backup** and keep a second confidential offline copy. Do not post raw JSON with PINs into GitHub or public Vercel files.
3. Run the upgraded local **Reconcile backup** against the frozen source and investigate every mismatch, including loan associations and policy settings. The currently checked source snapshot is dated **6 November**, and may already be outdated.
4. Confirm restoration of logo/profile photos and historical adjustment evidence privately; do not treat 0 financial mismatches as media archive parity.
5. Have administrator and already linked ordinary member each independently perform signed-in browser **Readiness checks** and document their PASS count; verify recovery emails and member privacy.
6. After deliberate go-live authorization, finalize ledger posting permissions, legacy credential rotation, old PIN retirement and read-only archive instructions. Have a controlled rollback/forward-fix plan if transactions have begun in the new ledger.

**Do NOT merge the migration PR or activate native financial writes until final fresh source evidence is in hand and the release gates pass.**
