# Elites SACCO — secure member onboarding

This document applies to the **dedicated Elites SACCO Supabase project**. It is not the former JSONBin member-PIN system.

## First administrator account

1. Open the dedicated Supabase project's **Authentication → Users** dashboard.
2. Invite or create an Auth user using the administrator's real, verified email address. Never type or transmit a password through ChatGPT or GitHub.
3. Confirm the identity and email address in Supabase. Use the SQL editor (privileged dashboard only) to link the account to the exact legacy member:

```sql
update public.sacco_members as m
set auth_user_id = a.id
from auth.users as a
where lower(a.email) = lower('REPLACE_WITH_VERIFIED_ADMIN_EMAIL')
  and a.email_confirmed_at is not null
  and m.legacy_name = 'Apule Gerald Humble'
  and m.auth_user_id is null
returning m.legacy_name, m.member_role, m.auth_user_id;
```

**Expected outcome:** exactly one row updated. If zero rows are returned, verify email confirmation, account identity and member spelling. **Never** grant an administrative role based only on a user-entered display name or `user_metadata`.

## Remaining members

Invite each member at their verified email. Repeat the same SQL with the intended exact `legacy_name`. Existing admin roles are limited to the preconfigured SACCO officers; do not let members change their own role. Confirm that each registered Auth ID is linked to exactly one SACCO member.

## Access tests

- Unauthenticated visitors cannot query any SACCO financial table.
- A registered but unlinked user sees no financial or member data.
- A normal linked member can read their own contribution, loan and request records, but not other members' private records.
- An administrator can read all member records and financial entries.
- Normal members cannot post/alter contributions, loan balances or fees; requests can be submitted only in PENDING state.
- Every authorized financial change is audited.

## Preview and production

`staging/supabase-readonly.html` contains **only a publishable key** and is **read-only**. It has not been deployed to the production website. Do not replace the current login with unverified PIN checks.

All accounting write workflows, full historical-interest parity and concurrent-update protections require acceptance testing before any production cutover. After the cutover, revoke/rotate the publicly exposed JSONBin master key and remove it from all deployed assets. Export and reconcile any JSONBin transactions recorded after the 6 November 2026 migration snapshot.
