# Elites SACCO — verified member access onboarding
**Date:** 8 November 2026  
**Environment:** Separate Supabase / Vercel staging project, not the original JSONBin site.

## Deployed
- SQL migration: `supabase/migrations/0008_verified_member_access.sql`.
- Administrator and newly registered user screens added to `staging/supabase-readonly.html`, deployed at https://elites-sacco-auth-preview.vercel.app/ .
- `sacco_access_requests` stores a verified Supabase Auth email, request status, and reviewed identity link. Row-level security allows applicants to view only their own request and SACCO administrators to view the request queue.
- New users can use `sacco_request_access()` only after email confirmation; repeated submissions return the existing request.
- New users **cannot** choose their SACCO member account or role.
- Administrators use `sacco_review_access_request(...)` to link a verified new login to an existing unlinked member **after independently verifying identity**.
- Every approval or rejection is audited. Decisions are irreversible in this stage and duplicate/conflicting re-reviews are rejected. Email must still be confirmed and unchanged at approval.
- Target member records with existing logins are protected against relinking.
- Assigning an account to an existing member whose `member_role='admin'` requires an additional, explicit administrator-privilege confirmation. Existing roles are not changed.

## Test procedure
1. Each of the four remaining members opens the **test portal** and selects **Create account instead**.
2. Each member uses an individual email address they control and chooses a strong unique password; each confirms their email using the private message from Supabase/Brevo.
3. Once signed in, a not-yet-linked member sees **Account awaiting activation** and selects **Request membership review**. No savings or other financial records are displayed before linking.
4. The existing linked administrator signs in separately, selects **Member access**, and reviews each applicant's verified email.
5. Independently verify the applicant by calling or otherwise contacting the member through the SACCO's existing trusted channel, **not merely by trusting the submitted email address**.
6. Select the exact existing member; explicitly confirm identity and (only if appropriate) administrator privileges; enter how verification was performed; approve.
7. The member refreshes the portal using **Check status again**, then verifies they can see only their own contributions, loans and repayments.
8. Test that a newly registered but **unapproved** account sees no financial data. The administrator confirms the audit record.
9. Never ask any member to send a password, OTP, recovery link, email login token or Supabase/Brevo SMTP secret via chat.

## Verified automated checks (8 November)
- An existing linked administrator invoking `sacco_request_access()` returns `LINKED` without creating a duplicate access request.
- Unlinked/unknown account denied administrator approval with `42501 Administrator membership required`.
- Unlinked account lacking a verified email denied access request with `42501 Verify your email address before requesting access`.
- RLS simulation for unlinked account returned zero visible requests.
- Anonymous `EXECUTE` privileges on both onboarding RPC functions are revoked. Signed-in access is intentionally permitted but the functions re-check the actual authenticated user's identity/role on the server.
- Direct browser `INSERT`/`UPDATE` privileges on the access request table are revoked.
- Latest Vercel deployment `dpl_8R8axU5T7L7p5ZqiaB8BmTvZtLHg` is READY and resolves at the stable staging alias.
- Database post-check: 5 members, 1 linked account, **0 access requests**, 133 contributions, 28 loans, 27 repayments, **0 posted receipts**. Posting gate remains `enabled=false` and browser roles cannot execute real posting.
- **Still untested:** actual new member sign-up, confirmation, request and approval in a browser, because the other four members have not registered yet.

## Outstanding release blockers
- The November 8 locally run **Reconcile backup** screen does not upload its results to the database. Ask the administrator to confirm the number of **Unmatched records**. Do not assume that completing the upload means zero discrepancies.
- Source of truth is still the original website until fresh backup reconciliation and explicit cutover.
- Full testing of the dormant atomic posting engine and reversals remains incomplete.
- Enable/leverage leaked-password protection if available in Supabase Auth; the security advisor currently warns that this feature is off.
- Supabase security advisor flags publicly exposed, authenticated `SECURITY DEFINER` RPCs; internal role checks are present, but a formal security review is still required before production.
- Rotate/revoke exposed legacy JSONBin credentials only as part of a controlled cutover after verified backups.

**Production release not authorized. Do not merge migration PR yet.**
