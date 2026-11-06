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
