# Elites SACCO — read-only backup reconciliation (8 November 2026)

**Staging URL:** https://elites-sacco-auth-preview.vercel.app/  
**Status:** Administrator reconciliation UI deployed; **NOT reconciled against an up-to-date original-site export yet.**

## What has been built
- A new administrator-only **Reconcile backup** dashboard tab.
- The administrator chooses a JSON backup file with a browser-local file picker. It is parsed and compared **in the browser** against already-authenticated, RLS-protected Supabase data. The original backup is not uploaded to Supabase, Brevo, GitHub or Vercel by this code.
- Compares multisets of records (including duplicate identical entries) rather than totals alone. Categories: member roster, dated contributions and months, dated loans and frozen totals, dated repayments, expenses, investments, cash received, membership fees, minutes, and recognized waiver records.
- Reports record counts on both sides, entries present only in the selected export or only in the Supabase import, and a CSV of discrepancies without credentials or photos.
- Uses member-name normalization to handle duplicate empty legacy aliases or differences in letter case without merging unrelated members.
- Uploaded JSON is capped at 10 MB and read only after a user file selection.
- **No backup data, member PINs or original passwords are committed to this GitHub branch.**

## Steps to reconcile the original SACCO site
1. **On the original SACCO website**, sign in as administrator, go to **Admin → Settings → Download Backup (JSON)**, and save a **fresh** export. Keep that downloaded file private (it can include member PINs, evidence screenshots, personal data and financial transactions).
2. Visit the **separate test portal** https://elites-sacco-auth-preview.vercel.app/ , sign in as administrator and open **Reconcile backup**.
3. Select the freshly exported JSON from the local file picker. Neither the original full JSON nor its PINs leave the browser through this workflow.
4. Inspect counts and CSV discrepancies. **Only in uploaded backup** usually indicates an original-site transaction absent from Supabase; **Only in Supabase** may indicate an edited or deleted original transaction, changed event metadata, or a mismatch in normalization.
5. If differences are found, investigate them before requesting any new ledger postings. A changed transaction may yield two entries in the difference report (old representation missing; new representation added).
6. If differences show zero, check that the file was actually exported *after* the last transaction on the original website. Uploading the old 6 November snapshot will not establish that the source stayed unchanged.
7. Preserve both the 6 November original import backup and the fresh export securely and reconcile any gaps before user-authorized cutover.

## Limitations and required independent checks
- This is a comparison, **not** an importer or posting engine. It never updates Supabase financial records and never enables private posting.
- The report compares member/date/month/amount and selected additional fields, but it does **not** fully reconcile repayment-to-loan links, payment evidence attachments, every free-text field, PINs or membership policy settings. Those require additional manual or purpose-built checks before cutover.
- Equality alone cannot prove no data was changed at the original site after the export. Stop using or freeze the original site before final cutover to avoid a race between backup and migration.
- Any prior failed or partial mutation should be investigated using the audit log and original system of record before applying changes.
- Reported timestamps come from the locally selected file's modification time; file modification time is not cryptographic evidence of when the backup was exported.
- New financial posting remains disabled until finance-specific acceptance tests, source reconciliation, legacy credential rotation and a deliberate migration authorization.

## Verification performed
- Pure calculation test: matching synthetic records across five record categories reported 0 discrepancies.
- Changing one contribution from 150,000 to 152,000 UGX reported exactly two unmatched representations (one export-only, one Supabase-only).
- A casing-only alias of a legacy member did not create false duplicates in the synthetic test.
- Both scripts in the updated browser HTML passed JavaScript syntax checks.
- Vercel deployment `dpl_EeZmUKx6uaRnn6EiWQeeJcoemWq2` returned READY; stable domain alias confirmed.
- Read-only Supabase check: 5 members, 133 contributions totaling 13,965,000 UGX, 28 loans, 27 repayments, 0 posting receipts, posting gate disabled and no authenticated browser execution rights to the posting routine.

**No claim is made that the live JSONBin data has been reconciled since 6 November 2026.**
