# The Elites SACCO — controlled launch runbook (PREPARED, NOT EXECUTED)
**Checkpoint:** 9 November 2026  
**Current plan:** Supabase Free; separate authenticated Vercel member portal; original GitHub Pages/JSONBin financial application is still authoritative  
**Go-live status:** NOT APPROVED. Do not infer release authorization from approval to continue testing.

## Verified starting position
- Five historical member records; **three email-confirmed linked accounts** (one administrator and two ordinary members). Two other historical members can register later after identity approval.
- **Administrator's own 8/8 browser acceptance is persistently recorded**. Ordinary-member signoff register currently has **zero completed receipts**. One earlier unassigned 8/8 report was not fabricated into a separate account's result.
- Original source backup `elites_sacco_backup_2026-11-06.json` was user-attested unchanged since November 6. Source checksum is retained privately. No subsequent entries were reported, but the old JSONBin write path is **not technically disabled**.
- Original financial baseline: 133 contributions, UGX 13,965,000; 28 loans, 27 repayments; net source-formula cash position **UGX 1,776,412**. All historical loan links, original logo, photo and 13 edit-log events verified.
- Zero native live posting or reversal receipts, zero outstanding staging drafts/reviews; financial gate `enabled=false`. The public API functions and private financial implementation functions are all **non-executable by authenticated and anonymous users**.

## Additional cutover protection completed
1. `0026_native_posting_cutover_boundary_guard.sql`: server rejects a draft CREATED before financial cutover, a REVIEW APPROVAL created before cutover, and any transaction whose date predates the **Africa/Juba-local** cutover day. This prevents an old test approval or a backdated imported entry from being silently reposted as new money.
2. `0027_admin_release_status_readonly.sql`: administrator-only `public.sacco_release_status()` reports gate and API state, source readiness and receipts. Verified ordinary members cannot call it; no ability to change the control.
3. `0028_private_native_write_invoker_endpoints.sql`: move posting and reversal `SECURITY DEFINER` implementations to `sacco_private`. Public routes become `SECURITY INVOKER` wrappers with no EXECUTE grants before cutover. The actual cloned posting-and-reversal logic passed the complete rollback-only regression, including **seven fictional posts, two reversals and three stale-entry rejection tests**.
4. Administrator-only **Launch controls** tab is installed on the isolated staging URL. While the server gate is disabled it displays only status, receipts, signoff counts and checklists. Live posting and reversal buttons remain HIDDEN.
5. After a separately authorized activation, the console is prepared to show newly created, reviewed drafts for individual native posting with explicit typed confirmation and to perform documented audited reversals. The functions recheck administrator identity, source cutoff and server gate and are idempotent. This is code-level/database rehearsal, **not yet a live operational acceptance test**.
6. Member readiness checks now validate the immutable historical subset even after subsequent native postings, allowing delayed onboarding and test acceptance by remaining members.

## Required pre-launch human and external service checks
- **Check A — old writing site**: The JSONBin write path in the original web application must be explicitly disabled or its exposed write credential rotated/revoked. Merely saying "no entries since November 6" does NOT technically prevent a late original-site submission or a still-open browser tab.
- **Check B — recovery**: Administrator and, preferably, one ordinary member should verify a real password reset link delivered by Supabase Auth to a mailbox (without sharing credentials or links with an assistant).
- **Check C — original evidence**: Retain an independent, confidential, offline copy of the original entire JSON export and an archive of the old site code. Compare its SHA-256 to `sacco_source_manifest`. The old backup includes private PINs and cannot be published.
- **Check D — member browser privacy**: Have at least one ordinary member independently run the actual `Readiness checks` and verify they see only their own books. The remaining members need not all be onboarded before a phased pilot; later signup and verification will remain enabled.
- **Check E — final release approval**: Obtain a specific cutover date/time and explicit approval for activating the new financial ledger. Nothing here should infer those from earlier "proceed" requests.

## Once those checks pass: controlled cutover sequence
1. Announce a short write-freeze window to members. Stop old financial entries; disable old JSONBin writing (including already-open tabs) and confirm the final backup remains unchanged.
2. Publish `release/secure_member_portal_candidate_NOT_DEPLOYED.html` to the **same isolated Vercel project** only after a final code/UI check. This is a separate production candidate without visible QA and local-reconciliation menu items. The original GitHub Pages `main` is not modified by this Vercel deployment.
3. Review `supabase/tests/controlled_cutover_preflight_readonly.sql`. The source, media, account and privileged-function technical checks should all pass. It deliberately lists manual old-write lock, recovery and authorization as **not independently verified**.
4. With the old write path off and final approval documented, use `release/NOT_EXECUTED_cutover_activate.sql` as the operator activation checklist. Its two critical boolean acknowledgments default to **false**, and its cutover reference is a nonfunctional placeholder. They must be reviewed and explicitly edited only in the authorized cutover. The script then atomically sets the server posting gate, source cutoff time and authenticated invocation grants on both private and public posting/reversal APIs. It DOES NOT grant direct financial table INSERT/UPDATE/DELETE to members.
5. Verify `Launch controls` displays active status, cutover timestamp and release reference. Keep all previous sandbox drafts ineligible: only fresh, post-cutover reviewed drafts may post. Do not attempt to import the existing financial snapshot again.
6. Enter one real, independently evidenced **small** transaction through Draft reviews; preview it, approve it and use the explicit posting control. Confirm exactly **one native receipt**, the corresponding ledger row and audit entry, and the new balance delta. Use the transaction's real amount and actual payment evidence—not a synthetic QA amount.
7. Have an ordinary member confirm the corresponding private ledger view reflects their own new transaction and no other member information; check administrator cashbook and the historical baseline. Announce the new member URL only after successful reconciliation.
8. Retain the original website as **read-only historic archive**; never allow it and the new native ledger to accept new financial entries simultaneously. Remove old JSONBin public write keys and retired PIN pathways only after the new site is operating correctly.

## Emergency pause — without destroying data
- `release/NOT_EXECUTED_emergency_pause.sql` disables the posting gate and revokes both private and public posting/reversal EXECUTE rights in one transaction.
- It does **not** delete, undo, overwrite or roll back any genuine native ledger transaction and does NOT restart old JSONBin writes.
- If any genuine native postings already exist, never restore the November 6 backup over them. Reconcile forward with audited reversals, or suspend operations until the discrepancies are resolved.
- Keep a written incident log including affected members, expected/actual balances, timestamps and receipt IDs; do not place member PINs or passwords in the log.

## Source locations / current status
- Staging portal: https://elites-sacco-auth-preview.vercel.app/ (native posting LOCKED)
- Prepared but **NOT deployed production candidate**: `release/secure_member_portal_candidate_NOT_DEPLOYED.html`
- Prepared but **NOT executed** activation: `release/NOT_EXECUTED_cutover_activate.sql`
- Prepared but **NOT executed** emergency pause: `release/NOT_EXECUTED_emergency_pause.sql`
- Read-only database preflight: `supabase/tests/controlled_cutover_preflight_readonly.sql`
- Rollback-only engine regression: `supabase/tests/clone_real_posting_rollback.sql`

**Nothing in this runbook is final cutover approval or permission to alter the original website.**
