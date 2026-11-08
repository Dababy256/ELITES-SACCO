# Elites SACCO — Supabase migration (staging branch)

**Production safety:** This branch intentionally leaves `index.html` and JSONBin unchanged. Do **not** merge as a finished cutover. The legacy HTML publicly contains a JSONBin master key and checks plaintext PINs in browser code. Rotate the JSONBin key after making a verified backup, then remove the secret from all deployed assets and Git history.

## What is verified

- The current site consists of a single `index.html` file using JSONBin read and whole-record PUT.
- Contribution targets are historical: 80,000 UGX Feb–Jul 2024, 100,000 Aug 2024–Jun 2026, 150,000 from Jul 2026 (unless overridden).
- Pre–July 2026 loans use compounded 5% interest; later loans use monthly flat 5% with existing repayment and freeze rules.
- There are member requests, loans/repayments, savings, expenses, investments, fees, waivers, meeting minutes, photos, and edit logs.

## Migration sequencing

1. **Export backup** from the existing site's Admin → Settings → Download Backup (JSON). Keep the export private: it contains financial records, evidence screenshots, and possibly member PINs.
2. Verify the Supabase project is active, belongs to the SACCO, and is empty or compatible. Never run schema changes against an unverified project.
3. Apply the **complete** relational schema from the migration package supplied in this ChatGPT conversation. The SQL on this branch now describes the **complete 12-table RLS-protected relational schema** and has been applied to the dedicated project.
4. Run the package's backup importer **in dry-run mode first**. Resolve all errors and reconcile exact per-member contribution totals, loan principal, repayments, fees, cash inflows/outflows, and record counts.
5. Import with a **server-only** Supabase service-role key held in a local environment file, never in GitHub or browser code. Record the backup checksum and refuse repeated imports.
6. Create Supabase Auth users and link identities to imported members. Old plaintext PINs must **not** be migrated.
7. Rewrite the application's login, reads, and writes against RLS-protected Supabase tables and scoped APIs. Never just replace JSONBin URLs with Supabase keys while continuing whole-record client-side writes.
8. Test user roles, admin permissions, loan calculations, duplicate saves, concurrent edits, audit logging, and full rollback before moving production traffic.
9. After production cutover and validated backups, disable old JSONBin writes, rotate/revoke exposed credentials, and scrub repository history as appropriate.

## Security

- Do not put `service_role`, secret keys, member PINs, or actual backup JSON in the repository.
- Frontend may use only a Supabase publishable key with correctly enforced RLS.
- Preserve the original HTML as a rollback reference; no forced deploy from this branch.

## Status — 6 November 2026

- Dedicated **Elites SACCO** Supabase project created on the Free plan, in eu-west-1, separate from the hospital application.
- Full 12-table RLS-protected schema has been applied successfully to that dedicated project.
- Sanitized 6 November JSONBin backup imported successfully into that project. Imported: 5 members, 133 contributions, 28 loans, 27 repayments, 8 financial entries, 2 fees, 3 meeting minutes, 13 historical audit entries; 0 active requests/waivers in the source.
- Independently reconciled aggregate amounts and record counts; 0 broken loan links; 1 preserved frozen loan; 1 member photo and SACCO logo preserved. Imported source-record PIN/credential fields: 0.
- All 12 tables have RLS enabled; Supabase security advisor reported no findings.
- No Auth users are linked to member records yet. The original PIN-based HTML remains deployed, continues using JSONBin, and is **not** suitable for production use with Supabase.
- Do not merge until the new authenticated frontend, server-authorized write flows, and role-based acceptance tests are complete. Do not commit the private backup or any service-role credentials.

## Staging dashboard and safe testing — 7 Nov 2026

- New Vercel project `elites-sacco-auth-preview` serves the staging dashboard at <https://elites-sacco-auth-preview.vercel.app/>. This is separate from the existing GitHub Pages/JSONBin application.
- The login page includes a sample-data **Explore demo without a password** option. The demo uses fictitious financial numbers and does not query Supabase.
- For authenticated members, added real Supabase-backed savings and arrears, historical policy-based loan balances, loan exports, cashbook (admin), members, minutes and transaction **drafts** (admin only). These remain under testing and are not authoritative statements.
- Added `supabase/migrations/0002_staging_drafts.sql`. Admins can write only to RLS-restricted test drafts. Drafts never post to the imported financial ledger; historical browser write/delete privileges were removed.
- Browser scripts parsed without syntax errors. Supabase administrator role test allowed creating a test draft within a rolled-back transaction; unlinked user query returned zero visible drafts. No test transaction remained committed.
- Remaining: validate exact loan math against all historic loans and edge cases, invite and link remaining verified members, verify all auth redirects and actual browser login, build audited production posting workflows, reconcile post-backup changes and rotate exposed JSONBin credentials.
- Supabase security advisor currently warns that leaked-password protection is disabled; review Auth security settings before onboarding all members.

## Auth email provider — activated for administrator (7 Nov 2026)

The user configured Brevo SMTP directly in the provider dashboard, corrected the sending-IP restrictions, received a Supabase password recovery email and set a password successfully. Supabase logs subsequently confirmed a successful password sign-in. Keep SMTP credentials private. New-member confirmation delivery remains to be tested. See [Brevo SMTP guide](docs/SMTP_SETUP_BREVO.md).

## Staging approval and dormant posting engine

See [review / posting gate safety report](docs/STAGING_APPROVAL_AND_POSTING_GATES.md). The administrator-only draft approval queue has been deployed. Actual ledger posting remains disabled and browser-inaccessible; do not merge or enable before live source reconciliation and end-to-end posting tests.

## Read-only source reconciliation — 8 November 2026

The secure staging portal now has a browser-local **Reconcile backup** tab for the administrator. Instructions and limitations: [backup reconciliation guide](docs/BACKUP_RECONCILIATION_2026-11-08.md). **Awaiting a fresh original-site JSON export.** Current Supabase records are still the November 6 backup import and are not authoritative for later changes. Real posting remains disabled.

## Verified member access — 8 November 2026

The test portal now has an email-confirmed **Request membership review** flow and an administrator-only **Member access** approval queue. Approval requires independent identity verification; any existing administrator role requires an additional explicit confirmation. See [member onboarding runbook](docs/MEMBER_ONBOARDING_2026-11-08.md). Only one of five member accounts is currently linked. Four others must enroll and be approved individually. Do not treat a confirmed email as verified SACCO membership; do not enable financial posting until backup reconciliation and release tests pass.

## Release readiness checkpoint — 8 November 2026

Administrator reported **0 unmatched records** from browser-local backup reconciliation. This is a user-reported result, not a verified source freeze or final reconciliation of every loan link/evidence field. Automated read-only integrity checks passed but four other members remain unlinked, real posting acceptance tests remain incomplete, and posting is still disabled. See [release readiness checkpoint](docs/RELEASE_READINESS_CHECKPOINT_2026-11-08.md) and [repeatable preflight SQL](supabase/tests/release_preflight_readonly.sql). Do not merge or cut over yet.

## Linked member and repayment QA — 8 November 2026

Two of five members now have linked, email-confirmed logins. Verified the newly approved ordinary member's data isolation with repeatable RLS tests, strengthened repayment validation to reject pre-issuance dates, and reran the financial preflight successfully. Three members can enroll later while testing proceeds. **Real transaction posting and reversals remain untested and locked.** See [member privacy and repayment validation checkpoint](docs/APPROVED_MEMBER_AND_REPAYMENT_GUARDS_2026-11-08.md).

## Isolated transaction posting lab — 8 November 2026

Administrators can now test **real SQL writes and reversals in a separate fictional QA ledger** through the staging portal's **Financial posting lab** tab. This does not mutate the original website, any imported real SACCO financial tables, or the still-locked live posting switch. Same-day and partial loan repayments follow the source-code interest rules. Details and step-by-step tests: [isolated posting lab runbook](docs/ISOLATED_FINANCIAL_POSTING_LAB_2026-11-08.md).

## Source-policy loan alignment and cloned real posting tests — 8 Nov 2026

Implemented server-side interest parity with the original code (84/84 checks), documented regular/developmental and unpaid-loan exceptions with mandatory audit reasons, and published the **Draft approvals (sandbox)** loan-policy controls. Exercised the actual *locked* posting routine copied into an ephemeral fictional schema with all data rolled back, including same-day repayment and documented exception cases. Financial posting on real SACCO tables is **still disabled**; real reversal design and full cutover acceptance are not yet complete. Details: [loan policy and cloned posting acceptance](docs/LOAN_POLICY_AND_CLONED_POSTING_ACCEPTANCE_2026-11-08.md).

## Audited reversal workflow — 8 November 2026

A locked native-transaction reversal engine is now in place. Originals remain stored; cancelled entries no longer affect member balances and are visible in an administrator-only, read-only audit journal. The actual posting and reversal functions passed a fictional, transaction-rolled-back integration regression including same-day repayment recovery, reversal dependency ordering, immutable history and duplicate-request safeguards. **Real financial posting and reversal remain disabled**; separate production browser and security acceptance tests still required. See [native reversal acceptance report](docs/NATIVE_REVERSAL_ACCEPTANCE_2026-11-08.md).
