# The Elites SACCO — member readiness acceptance register
**Checkpoint:** 9 November 2026
**Environment:** Existing Supabase Free project and isolated Vercel staging portal
**Status:** Three linked, email-confirmed accounts; one 8/8 pass reported verbally, no account-specific receipts until members sign off in the app.

## Why this stage
The chairperson reported that **one person had passed all 8 browser checks**, but did not identify which account. The database has now advanced to **three linked Auth identities**: one administrator and two ordinary members, with two historical members not yet linked. It would be misleading to mark a particular account as accepted or assume all members passed.

We therefore created a **signed-in member acceptance register**. A member can run Readiness checks on their own session and, **only when all eight checks pass**, click **Record my successful 8/8 check**. A confirmation prompt explains that it creates a non-financial self-attestation, not a go-live authorization.

The administrator sees the five-member roster, whether each account is linked, and the recorded 8/8 status/date. Ordinary members can view only their own signoff. Existing reported results are intentionally **not automatically attributed** to any account.

## Database implementation
- `supabase/migrations/0024_member_browser_readiness_signoffs.sql`: RLS-protected `public.sacco_member_readiness_signoffs`. Receipts are append-only, bound to the currently authenticated user's linked member ID.
- `supabase/migrations/0025_member_readiness_signoff_uniqueness.sql`: unique acceptance per member per version (`member-browser-v1`), with attempts to duplicate blocked.
- Checks are constrained to **8 of 8**; 7 of 8 fails a database CHECK constraint.
- A member may insert only a record for their own verified account, cannot inspect another member's record, and cannot update/delete a signoff. Anonymous users have no read access. An administrator can read the register but cannot impersonate another member's signoff.
- **Important evidence distinction:** this is a **member self-attestation** coupled with the frontend's eight read-only checks, not an independent server proof of completed browser interaction. A caller able to use browser developer tools could submit a self-attestation without clicking through all UI checks, so it is not sufficient alone to authorize financial cutover.

## Tests
- `supabase/tests/member_readiness_signoff_rls_rollback.sql` passed against two linked ordinary members and the administrator in transaction-scoped identity simulations:
  1. Ordinary member A inserts and sees own signoff.
  2. Duplicate 8/8 submission blocked by unique constraint.
  3. A 7/8 submission blocked by database constraint.
  4. Ordinary member B cannot see member A's signoff.
  5. Ordinary member B cannot forge member A's signoff.
  6. Administrator sees the register, but browser users cannot update/delete receipts and anonymous users have no SELECT grant.
- All test inserts were rolled back. At deployment verification there were **0 persisted signoffs**.
- JavaScript passed syntax validation; real-browser acceptance is still member-dependent.

## Staging deployment
- URL: https://elites-sacco-auth-preview.vercel.app/
- Deployment: `dpl_E22GmKGiomEhczR7TDGScSwvSZXx` — READY, stable domain confirmed.
- No changes to original GitHub Pages `main/index.html`; unchanged SHA `c0825d30bbd254130b4dea64fc8ce42629b91937`.

## Current financial security
- 5 member records, 3 linked accounts (one administrator, two ordinary members).
- 133 contributions, 28 loans, 27 repayments; 0 native posting receipts, 0 native reversal receipts.
- Native posting control still **disabled**, and browser `authenticated` role cannot execute native posting or reversal functions.
- Supabase Free plan retained; sole security advisor warning remains the unavailable-on-Free leaked-password protection feature.

## Next acceptance actions
1. The member who already reported 8/8 should sign in again, open **Readiness checks**, run the checks, then click **Record my successful 8/8 check**. This attributes their acceptance to the correct account.
2. The other two linked members (including the administrator) should run and record their own 8/8 checks from their own browsers. Only 3 of 5 historical members are currently linked; onboarding the remaining two can be planned separately.
3. An administrator should inspect the acceptance register and verify its status, confirm password recovery from a real mailbox, and check the original source backup remains the authoritative unchanged record.
4. Only then plan the operational cutover date, old-site read-only status, controlled first financial transaction and safe fallback. **Do not enable real posting or retire the original website based on self-attestations alone.**

**No production merge, no old-site modifications, no real financial posting activated.**
