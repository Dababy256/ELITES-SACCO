# Elites SACCO — SMTP email delivery setup (Brevo)

**Status: NOT CONNECTED.** This document is a setup checklist, not evidence that Brevo or Supabase custom SMTP has been configured.

## Service recommendation

Brevo Free has 300 email sends/day according to its published plan documentation (November 2026). New users may need to complete account verification and transactional SMTP activation before the relay works. Free tier terms/limits can change.

Official documentation:
- Supabase: https://supabase.com/docs/guides/auth/auth-smtp
- Supabase Rate limits: https://supabase.com/docs/guides/auth/rate-limits
- Brevo SMTP setup: https://help.brevo.com/hc/en-us/articles/7924908994450-Send-transactional-emails-using-Brevo-SMTP
- Brevo SMTP key setup: https://help.brevo.com/hc/en-us/articles/7959631848850-Create-and-manage-your-SMTP-keys
- Brevo sender verification: https://help.brevo.com/hc/en-us/articles/208836149-Create-a-new-sender-From-name-and-From-email

## Account setup — action required from SACCO administrator

1. Create or log in to a free Brevo account at https://www.brevo.com . Complete Brevo account verification.
2. Under **Settings → Senders, Domains, IPs → Senders**, register and verify a sending address for Elites SACCO. **Sender name:** Elites SACCO. Use a sending address controlled by the administrator, not any member's personal address. Ideally use a domain registered for the SACCO and authenticate it with DKIM/SPF/DMARC. For testing only, Brevo may allow verified free-mail senders but can rewrite the From address for Gmail/Yahoo/Microsoft compliance; check delivery before inviting anyone.
3. Under **Settings → SMTP & API → SMTP**, enable transactional emails (if activation is required, request it from Brevo support). Create a dedicated SMTP key named **Elites SACCO Supabase Auth**.
4. Open project-scoped Supabase SMTP settings: https://supabase.com/dashboard/project/vcdswucekgrnonffvrva/auth/smtp
5. Enter the fields:

| Supabase field | Value |
|---|---|
| Enable custom SMTP | On |
| Sender email | Your verified Brevo sending address |
| Sender name | Elites SACCO |
| Host | smtp-relay.brevo.com |
| Port | 587 (STARTTLS) |
| Username | The exact SMTP login Brevo displays (not necessarily account email) |
| Password | The **SMTP key** generated in Brevo (NOT Brevo account password or HTTP API key) |

6. Save and send **one** password recovery test email to the verified administrator address.
7. Verify project **Authentication → URL Configuration**:
   - Site URL: https://elites-sacco-auth-preview.vercel.app/
   - Additional Redirect URL: https://elites-sacco-auth-preview.vercel.app/
8. Review Supabase **Authentication → Rate Limits**: https://supabase.com/dashboard/project/vcdswucekgrnonffvrva/auth/rate-limits . When custom SMTP is enabled Supabase initially allows approximately **30 messages/hour**; this is already adequate for the five members. Keep throttling and email confirmation enabled; do NOT disable verification to bypass quotas.
9. Check the received email and complete the reset workflow. If it fails, inspect Brevo's transactional email event logs for rejection, unverified sender or pending SMTP activation. Then invite the other SACCO members after confirming the complete flow.

## Credentials: strict handling

- Do not share any SMTP key, password, password-reset URL, OTP, or Supabase Management API token in chat.
- Do not commit SMTP credentials to GitHub, public HTML, source code, or a Vercel client environment variable.
- Enter secrets only in the authenticated Supabase dashboard; rotate immediately if accidentally disclosed.
- This project is **Elites SACCO**; do not alter the other hospital-management Supabase project.

## Operator acceptance checklist

- [ ] Brevo account created and confirmed
- [ ] Sender verified and transactional email sending activated
- [ ] Dedicated SMTP key securely stored
- [ ] Supabase custom SMTP enabled and saved on the SACCO project
- [ ] Auth rate limit reviewed
- [ ] Password reset received and redirected to the HTTPS preview
- [ ] Admin successfully signs in with a new password
- [ ] Other members onboarded individually with least-privilege access

**Production cutover remains blocked** pending verified login, role testing, ledger parity and reconciled live JSONBin changes.
