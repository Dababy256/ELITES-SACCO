-- Private verified-member SACCO branding for the original imported logo.
-- The actual logo data is restored from the *confidential* original backup, NOT committed.
begin;
create table if not exists public.sacco_branding (
 singleton boolean primary key default true check(singleton),
 logo_data text not null check(
 char_length(logo_data) between 100 and 200000 and logo_data like 'data:image/%;base64,%'
 ),
 created_at timestamptz not null default now()
);
alter table public.sacco_branding enable row level security;
revoke all on public.sacco_branding from public,anon,authenticated;
grant select on public.sacco_branding to authenticated;
drop policy if exists sacco_branding_verified_members on public.sacco_branding;
create policy sacco_branding_verified_members
 on public.sacco_branding for select to authenticated
 using(exists (
  select 1 from public.sacco_members m
  where m.auth_user_id=(select auth.uid())
 ));
commit;
