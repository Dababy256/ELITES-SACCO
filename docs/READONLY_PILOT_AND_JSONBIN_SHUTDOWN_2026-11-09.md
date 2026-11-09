# The Elites SACCO — read-only pilot and legacy JSONBin write shutdown
**Checkpoint:** 9 November 2026, Juba local time  
**Mode:** The Supabase member pilot is live for viewing, while actual finance posting is locked.

## Delivered in this stage
- Deployed a **clean read-only member pilot** to the previously used isolated Vercel project: https://elites-sacco-auth-preview.vercel.app/
- Deployment `dpl_7Mceg334jRiSvJvRZPsCP9qnR2y2` confirmed READY and its original preview alias verified.
- Member pilot has individual login, personal financial books, secure branding, private profile pictures, readiness checks and administrator-only launch status. It hides visible financial QA and legacy backup reconciliation menus.
- Candidate source: `release/secure_readonly_member_pilot_2026-11-09.html` on the migration-only branch.
- Prepared **credential-free GitHub Pages handover page** `release/legacy_github_pages_handover_NOT_DEPLOYED.html`; not published. This page cannot post to, or read data from, JSONBin and contains NO legacy key or PIN.
- Original `main/index.html` SHA remains `c0825d30bbd254130b4dea64fc8ce42629b91937`. No original GitHub Pages site changes; no JSONBin changes.

## Critical discovered legacy key vulnerability
The existing original public HTML source contains a `MASTER_KEY` constant used in client-side `fetch` requests with the **`X-Master-Key`** JSONBin header. The old app's `saveData()` function uses an authenticated JSONBin PUT method. The original page also registers a service worker, so a cached, older script may remain operational after a public-page replacement.

**A GitHub Pages HTML rewrite, banner or redirect does NOT revoke the exposed JSONBin master key, nor does it reliably block already-open or cached old application copies.** The key may have been copied. The original source is also present in public git history, so merely removing today's script does not erase the exposure. The original JSONBin account should be treated as potentially exposed until the provider invalidates the master key or the archived old bin and account access are retired.

JSONBin documentation:
- Master key FAQ: https://jsonbin.io/support/tags/access-keys-api — describes default master key's broad access, and that it cannot be deleted or its permissions modified like a scoped access key.
- https://jsonbin.io/api-reference/bins/update — JSON bin updates accept X-Master-Key.
- https://jsonbin.io/api-reference/access-keys/get-started — access keys are scoped and can be deleted separately from the master key.

## What owner must do before any new financial postings
1. **Retain securely** the complete November 6 original JSON backup, including images and audit history; do not upload the PIN-bearing JSON to public GitHub.
2. **Inside JSONBin account administration**, look for a supported master-key regeneration/rotation control. If none, **contact JSONBin support** to invalidate the exposed master key. The FAQ says an ordinary Access Key deletion does not eliminate a published Master Key.
3. If provider cannot revoke it, plan to **retire the old JSONBin bin or account only after explicitly authorizing a destructive retirement and verifying your private full backup.** Do not delete the bin as an automatic cutover step.
4. Confirm old app can no longer write to the original bin, including from an already-open browser tab. A denied old update does not require risking a new real financial entry; coordinate a provider-side revocation verification.
5. Only then, with the single-site cutover approved, replace original GitHub Pages with the prepared handover page and activate Supabase financial posting through the guarded release procedure.
6. Keep old write path off permanently. If any new native transactions occur, do not overwrite them by restoring the older November 6 snapshot.

## Current source & safety verification
- Three linked, email-verified accounts; one administrator has persistently recorded 8/8 readiness.
- 133 contributions totaling UGX 13,965,000, 28 loans, 27 repayments.
- Zero actual native posting and reversal receipts.
- `sacco_private.posting_control.enabled=false`.
- Both public and private native finance-write functions have no authenticated `EXECUTE` rights.
- Free Supabase tier, no paid upgrade.

## Release boundary
This stage authorizes a read-only pilot **ONLY**. It neither replaces the legacy site nor starts new financial transactions. Closing the security gap on the old JSONBin master key is the next external dependency.
