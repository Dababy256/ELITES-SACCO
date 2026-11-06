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
3. Apply the **complete** relational schema from the migration package supplied in this ChatGPT conversation. The SQL in this branch is an **identity/RLS foundation only**, not the full data model.
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

## Status

GitHub write access verified and migration branch opened. The existing Supabase project has been restored but contains unrelated hospital-management tables. The SACCO backup dry-run passed with five members, 133 contribution entries, 28 loans, 27 repayments, three meeting minutes and 13 legacy audit entries; no unmatched loan references. One empty legacy member alias was detected and explicitly skipped. The exported backup also has a logo and one member photo, both handled by the revised offline migration package. PINs are never imported. No financial data has been written to Supabase. A separate SACCO project and Auth-enabled frontend are still required.
