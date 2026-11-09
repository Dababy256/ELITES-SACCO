# Elites SACCO — Audited reversal workflow checkpoint
**Date:** 8 November 2026  
**Scope:** Isolated Supabase staging project and Vercel test portal. Original GitHub Pages / JSONBin website is not modified.

## What is now implemented
- Migrations `0017_dormant_audited_reversal.sql`, `0018_active_ledger_excludes_reversals.sql`, `0019_protect_native_history.sql`, and `0020_native_entry_immutability_and_replay.sql` add a locked, audited **native-transaction reversal** engine.
- The six monetary/waiver ledger tables have nullable `voided_at`, `voided_by` and `void_reason` columns. Existing imported historical rows all remain active; no financial amount was modified.
- The `sacco_posting_reversals` journal uniquely links to an original `sacco_posting_receipts` row, retains the original transaction snapshot, records reason, administrator and timestamp, and prevents a second reversal.
- The original transaction row is **not deleted**; a valid reversal marks it voided. Financial reports, contributions, repayments, loan eligibility and the server loan-interest calculation ignore voided rows.
- A loan disbursement cannot be reversed while unvoided repayments still belong to it. The repayments must be reversed first.
- Requests require a verified SACCO administrator, explicit text confirmation `REVERSE POSTED TRANSACTION`, a 15–500 character justification and unique idempotency key. A same-key retry returns the original reversal receipt; a changed reason or different receipt fails.
- Database history guards prevent deletion of native postings, modification of an already reversed entry, edits to native postings before reversal, and modification of imported legacy entries through the new native reversal procedure.
- The same private posting gate protects **both** native writes and native reversals. The gate is still **disabled**, and `anon` and `authenticated` roles have **no EXECUTE** privilege on the native reversal or posting functions. No live posting or reversal UI controls have been enabled.
- The staged web portal filters reversed native financial entries from active calculations and has an administrator-only, read-only **Posting & reversal journal** tab. The **Financial posting lab** remains separate for actual persisted fictional test entries.

## Acceptance tests (transaction rolled back)
The existing `supabase/tests/clone_real_posting_rollback.sql` copies the **actual locked posting and reversal function definitions** into temporary fictional financial tables inside a database transaction. Tests run against the clone only, then drop everything with `ROLLBACK`.

The following assertions passed:
1. Seven fictional native post receipts covering a loan, same-day partial repayment, savings, expense, membership fee, and administrator-approved exception loans.
2. Same-day UGX 1,000,000 loan and UGX 200,000 repayment: balance UGX 850,000 with immediate first-month interest.
3. Reversing the repayment restored outstanding to UGX 1,050,000 according to the original policy.
4. Reversal of a loan with an active repayment was rejected.
5. After the repayment was reversed, loan reversal succeeded and the reversed loan no longer contributed to the active balance.
6. The two reversal receipts and corresponding audit events existed; the seven original posting receipts and native records remained stored.
7. Same-key reversal retries were idempotent, a different reversal key was blocked, and reusing the same key with a changed justification was blocked.
8. Editing an existing native posting, editing a reversed repayment, and deleting a native loan were all rejected.

**These are transaction-scoped database regression tests. They are not yet a complete independently hosted multi-user acceptance test, nor a test of a production browser reversal flow.**

## Current data and deployment
- Staging site: https://elites-sacco-auth-preview.vercel.app/
- Vercel deployment: `dpl_4sojZBj4tBC68QaL9TEkBeu86MKU` — READY; stable preview alias confirmed.
- Original GitHub `main/index.html` remained at SHA `c0825d30bbd254130b4dea64fc8ce42629b91937`.
- 5 SACCO members, 2 linked Auth logins.
- 133 original contributions (UGX 13,965,000); 28 historical loans; 27 repayments.
- 0 actual native posting receipts; 0 native reversals; native posting/reversal gate disabled; browser EXECUTE revoked.
- The fictional QA ledger had 5 entries at last check, from separate user testing. Those rows were not altered.

## Outstanding release gates
1. Full, independent end-to-end reversal acceptance in a separate branch/project (including concurrent operations, missed/replayed requests and role isolation). Creating a new Supabase branch can incur usage charges; do not create one without cost authorization.
2. Final historical backup after a **write freeze** of the old JSONBin website, and manual reconciliation of linked loan identifiers, evidentiary attachments and settings beyond the browser comparator's scope.
3. Supabase security adviser still flags 4 authenticated-callable `SECURITY DEFINER` functions (their internal auth checks need formal audit) and disabled leaked-password protection. Address before real release.
4. Three remaining members may enroll later, but real cutover requires a deliberate roll-out plan, support, and explicit user authorization.
5. Rotate the exposed original JSONBin credentials and eliminate old client PIN/master-key paths at cutover.

**Current decision: Native financial posting and reversal REMAIN LOCKED. Original SACCO website stays the system of record.**
