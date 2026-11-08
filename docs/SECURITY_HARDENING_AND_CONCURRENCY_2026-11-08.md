# Elites SACCO — privileged API hardening and duplicate-submission tests
**Date:** 8 November 2026  
**Status:** Protected staging; original SACCO website and imported books unchanged.

## Admin API hardening
- Migration `0021_private_privileged_rpc_wrappers.sql` moved four privileged database operations into the unexposed `sacco_private` schema: `sacco_preview_draft`, `sacco_review_draft`, `sacco_request_access`, and `sacco_review_access_request`.
- The four `public` RPC endpoints now use **SECURITY INVOKER** SQL wrappers preserving the same names, arguments, and portal behavior. The private implementations retain the existing `auth.uid()` identity and role guards.
- No anonymous role can invoke these endpoints; signed-in members can request their own access status, but cannot approve membership or financial drafts.
- A transaction-scoped dry-run tested an administrator approval, linked account access, and unauthorized ordinary-member calls. After applying migration, a repeatable read-only regression passed: [`supabase/tests/privileged_invoker_api_security.sql`](../supabase/tests/privileged_invoker_api_security.sql).
- The project security advisor previously reported **four** signed-in-user-executable public `SECURITY DEFINER` RPCs. After the migration it reports **zero** such warnings.
- Moving the privileged implementation to a private schema reduces accidental REST exposure; it does **not** eliminate the importance of internal authorization checks. Those guards were kept and tested.
- Live posting and reversal functions remain *entirely non-executable* by both anonymous and signed-in web users.

## Two-request concurrency checks (fictional QA tables only)
Two independent DB requests were issued concurrently in the **separate** `sacco_qa_entries` ledger with fictional `TEST_A` / `TEST_B` member codes.

1. **Same key + same payload:** One request inserted a fictional cash-in entry. The other returned the *same* receipt with `already_posted=true`. Verified exactly **one posting**. Reversed it using the separate QA reversal function.
2. **Different keys + identical payment details:** One request was accepted; the other failed with `23505 Possible duplicate test posting already exists`. Verified exactly **one posting**. Reversed it.
3. The tests produced two QA posting entries, two QA reversal entries and their append-only audit events. After reversal, neither test posting contributes to active fictional cash totals.
4. **No real SACCO posting or reversal function was executed.** Tests do not yet establish high-load, production engine or independent browser acceptance.

## Signup password UX
- Updated the staging signup form to require a **12-character minimum** and remind members not to share credentials; existing account sign-in requirements are unchanged.
- This is a client-side quality safeguard and does not replace server-side Auth password policy.
- The staging Vercel deployment `dpl_CbWCH4pYFfuGBMBesDvjrpwXqgwt` reports READY at https://elites-sacco-auth-preview.vercel.app/ .

## Remaining security warning
The current Supabase security advisor now reports only `auth_leaked_password_protection`: disabled. Supabase's current documentation states that this feature is available on **Pro plan and above** and is configured in the project's Authentication → Providers → Email settings.

Administrator action (if available on the project's plan): visit
https://supabase.com/dashboard/project/vcdswucekgrnonffvrva/auth/providers?provider=Email
and turn on **Leaked password protection**; ideally enforce a server-side minimum password length of at least 12. The model did **not** change or verify that setting.

Reference: https://supabase.com/docs/guides/auth/password-security

## Final integrity and release status
- Historical records: 5 members, 2 linked logins; 133 contributions totaling UGX 13,965,000; 28 loans and 27 repayments.
- **0** native posting receipts and **0** native reversal receipts; private posting switch remains `enabled=false`.
- The independent synthetic QA ledger contains **9 entries** in total, including the existing user's tests and the newly posted/reversed concurrency tests. Do not confuse them with real member transactions.
- Original GitHub Pages `main/index.html` remains SHA `c0825d30bbd254130b4dea64fc8ce42629b91937`.
- No Supabase development branch was created, no new paid compute authorized, and no merge/cutover performed.

## Next acceptance milestones
1. Independently test the **actual** locked native posting/reversal engine with simultaneous real database transactions in a separate isolated, funded test branch or cloned project, after any required cost authorization. Rollback-clone and QA-only concurrency tests are good preliminary evidence, not a substitute for multi-session native posting tests.
2. Complete final original-site write freeze and fresh source backup; verify all linked repayment records, attachments and settings that the browser reconciliation tool does not compare.
3. Review real browser/member login and administrator workflows end to end, including password recovery, request approval, financial reports and rejected access attempts.
4. Set the available server-side Auth password protections, and rotate/remove exposed legacy JSONBin credentials only at authorized cutover.
5. Keep posting and reversal gates locked until explicit production approval.

**This stage is complete; production release is not authorized.**
