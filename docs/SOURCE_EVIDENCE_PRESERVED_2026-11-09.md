# The Elites SACCO — final historical source and evidence preservation
**Checkpoint:** 9 November 2026  
**System:** Existing Supabase Free staging project; separate Vercel preview  
**Legacy website:** Original GitHub Pages/JSONBin `main` unchanged

## Authoritative source attestation
The chairperson explicitly confirmed that **no new transactions or data were entered after the original 6 November 2026 JSON export**. The backup was verified locally and its SHA-256 fingerprint recorded in an administrator-only `sacco_source_manifest` table.

This is a **user attestation of unchanged contents**, **not** a technical read-only lock on the legacy website. The original website should no longer be used to enter transactions once a formal cutover is approved. A saved copy of the original source should be retained offline.

The manifest stores only the original file fingerprint, dates, baseline record counts and evidence inventory. **It does not store raw JSON, PINs or secret keys.** The migration is `supabase/migrations/0023_source_manifest_nov6_user_attested.sql`.

## Confidential historical media and audit preservation — COMPLETE
The earlier evidence inventory initially described these items as pending; further database inspection established that **the member profile photo and all loan-edit events had already been imported**. No duplicate copies were created.

| Original evidence | Original backup | Protected Supabase record | Integrity |
|---|---:|---|---|
| Official logo | 1 | 1 row in `sacco_branding` (member-accessible through RLS) | Exact match |
| Member profile photos | 1 | 1 image in `sacco_members.photo_data` | Exact match |
| Historical loan/repayment adjustment log | 13 | 13 `LEGACY_LOG` records in `sacco_audit_entries` | All 13 exact matches |

The original logo was restored from the private source JSON into `public.sacco_branding`, a *read-only to browser users* RLS-protected table. The schema is in `supabase/migrations/0022_private_branding_table.sql`; the raw image data is **not** committed to GitHub or deployed as a public image. Verified linked members can read the logo; unlinked users cannot. The private photo is available only through the existing member-level RLS access rules.

Comparison used the entire original image data and all seven original edit-log fields (timestamp, operator, action, category, member, before, after). The profile photo and logo were separately fingerprinted. No legacy PIN was added to the new portal.

## Repeatable tests
The read-only `supabase/tests/final_source_assets_and_ledger_readonly.sql` test returns:
- `user_attested_source_recorded=true`
- `edit_logs_exact_match=true`
- `photo_exact_match=true`
- `logo_exact_match=true`
- `financial_import_stable=true`
- `production_writes_still_locked=true`

Source baseline remains 5 historical member records (2 linked email-confirmed Auth identities), 133 contributions totaling UGX 13,965,000, 28 loans and 27 repayments. Historical source-equivalent net cash remains UGX 1,776,412.

## Portal improvements
The new Vercel staging version `dpl_41p2zWnkcw29Kcbc2n3FvHgUwUw7` was **READY** and verified at https://elites-sacco-auth-preview.vercel.app/ .

- Linked members see the real original logo after signing in and their own profile photo if available.
- **Reconcile backup** performs an in-browser check of historical source transactions, original repayment loan links, settings, member photo, logo and all edit-log contents.
- It also computes SHA-256 on the selected local file and compares it to the administrator-only recorded fingerprint of the chairperson-attested 6 November export.
- File contents and raw PINs stay in the administrator's browser. Imported data already stored in Supabase is fetched read-only for comparison; none of the newly selected local file contents are uploaded.
- The linked ordinary member can use their own **Readiness checks** tab independently.

## Access and finance safeguards
- Core historical financial tables still reject browser role direct INSERT/UPDATE/DELETE.
- Native posting and native reversal functions remain uncallable by ordinary browser roles.
- Native posting control is `enabled=false`; zero new real posting receipts and zero real reversals.
- Source `main/index.html` remains unchanged.
- Supabase Free has a known Pro-only leaked-password warning; avoid treating paid upgrade as a precondition for this stage.

## Remaining before active finance cutover
1. Have **both currently linked accounts** independently sign in and run **Readiness checks**, reporting any FAIL results. The linked ordinary member must personally confirm they cannot view another member's ledger.
2. Confirm a working password reset/recovery from a real mailbox.
3. Decide and communicate a **single effective cutover time**. After that moment, make the original JSONBin website read-only or archive it, to prevent split-brain posting. Do not rotate its credentials while members still rely on it.
4. In a short controlled go-live window, verify source checksum, preview reports and cashbook, enable exactly the audited server posting/reversal roles and user interface under administrator approval, complete a small first real transaction and verify the receipt/cash impact, then announce the new URL.
5. Retain the original full confidential JSON export and old website code for rollback and audit. **Do not restore by overwriting later genuine new transactions.**

**Current status: source preservation complete, staged portal available, but real financial posting and original-site retirement are NOT yet authorized.**
