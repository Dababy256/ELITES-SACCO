-- Source evidence manifest. No sensitive backup JSON, PINs or media are stored here.
-- The chairperson confirms no new entries after the original 2026-11-06 export.
-- This attestation is NOT a technical lock on the original JSONBin site.
begin;
create table if not exists public.sacco_source_manifest (
 singleton boolean primary key default true check(singleton),
 backup_sha256 text not null check(backup_sha256 ~ '^[0-9a-f]{64}$'),
 backup_label text not null,
 snapshot_date date not null,
 attested_unchanged_date date not null,
 member_count integer not null,
 contribution_count integer not null,
 loan_count integer not null,
 repayment_count integer not null,
 legacy_edit_count integer not null,
 profile_photo_count integer not null,
 original_logo_hash text not null check(original_logo_hash ~ '^[0-9a-f]{32}$'),
 status text not null check(status='USER_ATTESTED_UNCHANGED'),
 attestation_note text not null,
 recorded_at timestamptz not null default now()
);
alter table public.sacco_source_manifest enable row level security;
revoke all on public.sacco_source_manifest from public,anon,authenticated;
grant select on public.sacco_source_manifest to authenticated;
drop policy if exists sacco_source_manifest_admin_read on public.sacco_source_manifest;
create policy sacco_source_manifest_admin_read
 on public.sacco_source_manifest for select to authenticated
 using((select sacco_private.is_sacco_admin()));
insert into public.sacco_source_manifest(
 singleton,backup_sha256,backup_label,snapshot_date,attested_unchanged_date,
 member_count,contribution_count,loan_count,repayment_count,
 legacy_edit_count,profile_photo_count,original_logo_hash,status,attestation_note
) values(
 true,'b4b200618f2e74c1ebdc3a567c2eb5ac1a33b6ee58994d4913dcae86f5ee8837',
 'elites_sacco_backup_2026-11-06.json','2026-11-06','2026-11-09',
 5,133,28,27,13,1,'01c6e2af1eb508a2a62ea8c50c222637',
 'USER_ATTESTED_UNCHANGED',
 'Chairperson confirmed no additional entries since the November 6 export; technical write-lock on old site not asserted'
) on conflict(singleton) do nothing;
commit;
