-- Elites SACCO: verified member access onboarding. No changes to the financial ledger.
begin;
create table public.sacco_access_requests (
 id uuid primary key default gen_random_uuid(),
 auth_user_id uuid not null unique references auth.users(id) on delete cascade,
 verified_email text not null,
 status text not null default 'PENDING' check(status in ('PENDING','APPROVED','REJECTED')),
 requested_at timestamptz not null default now(),
 target_member_id uuid unique references public.sacco_members(id) on delete restrict,
 reviewed_by uuid references auth.users(id),
 reviewed_at timestamptz,
 verification_note text,
 constraint sacco_access_decision_consistency check(
  (status='PENDING' and reviewed_by is null and reviewed_at is null and target_member_id is null and verification_note is null)
  or (status='APPROVED' and reviewed_by is not null and reviewed_at is not null and target_member_id is not null and verification_note is not null)
  or (status='REJECTED' and reviewed_by is not null and reviewed_at is not null and target_member_id is null and verification_note is not null)
 )
);
alter table public.sacco_access_requests enable row level security;
revoke all on public.sacco_access_requests from public,anon,authenticated;
grant select on public.sacco_access_requests to authenticated;
grant select,insert,update,delete on public.sacco_access_requests to service_role;
create policy sacco_access_requests_owner_or_admin_read on public.sacco_access_requests
 for select to authenticated
 using (auth_user_id=(select auth.uid()) or (select sacco_private.is_sacco_admin()));
create index sacco_access_requests_queue_idx on public.sacco_access_requests(status,requested_at desc);

create function public.sacco_request_access()
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare
 v_user uuid; v_email text; v_confirmed timestamptz; v_req public.sacco_access_requests%rowtype;
begin
 v_user:=(select auth.uid());
 if v_user is null then
  raise exception 'Sign in to request SACCO access' using errcode='42501';
 end if;
 if exists(select 1 from public.sacco_members where auth_user_id=v_user) then
  return pg_catalog.jsonb_build_object('status','LINKED','created',false);
 end if;
 select u.email,u.email_confirmed_at into v_email,v_confirmed from auth.users u where u.id=v_user;
 if v_email is null or v_confirmed is null then
  raise exception 'Verify your email address before requesting access' using errcode='42501';
 end if;
 select * into v_req from public.sacco_access_requests where auth_user_id=v_user for update;
 if found then
  return pg_catalog.jsonb_build_object('status',v_req.status,'created',false);
 end if;
 insert into public.sacco_access_requests(auth_user_id,verified_email)
 values(v_user,pg_catalog.lower(pg_catalog.btrim(v_email)))
 returning * into v_req;
 return pg_catalog.jsonb_build_object('status',v_req.status,'created',true);
end$$;
revoke all on function public.sacco_request_access() from public,anon;
grant execute on function public.sacco_request_access() to authenticated;

create function public.sacco_review_access_request(
 p_request_id uuid,
 p_decision text,
 p_member_id uuid default null,
 p_verification_note text default '',
 p_confirmation text default ''
)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare
 v_admin uuid; v_req public.sacco_access_requests%rowtype;
 v_member public.sacco_members%rowtype; v_note text;
 v_email text; v_confirmed timestamptz; v_phrase text;
begin
 v_admin:=(select auth.uid());
 if v_admin is null or not (select sacco_private.is_sacco_admin()) then
  raise exception 'Administrator membership required' using errcode='42501';
 end if;
 if p_decision is null or p_decision not in ('APPROVED','REJECTED') then
  raise exception 'Invalid access decision' using errcode='22023';
 end if;
 select * into v_req from public.sacco_access_requests where id=p_request_id for update;
 if not found then
  raise exception 'Access request not found' using errcode='22023';
 end if;
 if v_req.status<>'PENDING' then
  if v_req.status=p_decision and v_req.target_member_id is not distinct from
   (case when p_decision='APPROVED' then p_member_id else null end) then
   return pg_catalog.jsonb_build_object('status',v_req.status,'request_id',v_req.id,'already_reviewed',true);
  end if;
  raise exception 'This access request has already been decided' using errcode='23505';
 end if;
 v_note:=pg_catalog.btrim(coalesce(p_verification_note,''));
 if pg_catalog.char_length(v_note)<15 or pg_catalog.char_length(v_note)>500 then
  raise exception 'Enter 15-500 characters describing how identity was independently verified' using errcode='22023';
 end if;
 if p_decision='REJECTED' then
  update public.sacco_access_requests
    set status='REJECTED',reviewed_by=v_admin,reviewed_at=now(),verification_note=v_note
   where id=v_req.id;
  insert into public.sacco_audit_entries(actor_user_id,event_kind,entity_table,entity_id,after_record)
  values(v_admin,'ACCESS_REJECTED','sacco_access_requests',v_req.id::text,
   pg_catalog.jsonb_build_object('auth_user_id',v_req.auth_user_id,'decision','REJECTED'));
  return pg_catalog.jsonb_build_object('status','REJECTED','request_id',v_req.id,'already_reviewed',false);
 end if;
 if p_member_id is null then
  raise exception 'Choose the verified existing SACCO member' using errcode='22023';
 end if;
 select * into v_member from public.sacco_members where id=p_member_id for update;
 if not found or v_member.auth_user_id is not null then
  raise exception 'Member is missing or already linked to a login' using errcode='23505';
 end if;
 v_phrase:=case when v_member.member_role='admin' then 'AUTHORIZE ADMIN ACCESS'
                else 'I VERIFIED THIS PERSON' end;
 if coalesce(p_confirmation,'')<>v_phrase then
  raise exception 'You must explicitly confirm the verified member role' using errcode='42501';
 end if;
 if exists(select 1 from public.sacco_members where auth_user_id=v_req.auth_user_id) then
  raise exception 'This account is already linked to a member' using errcode='23505';
 end if;
 select u.email,u.email_confirmed_at into v_email,v_confirmed
  from auth.users u where u.id=v_req.auth_user_id;
 if v_email is null or v_confirmed is null or
    pg_catalog.lower(pg_catalog.btrim(v_email))<>v_req.verified_email then
  raise exception 'Email confirmation or address has changed: request cannot be approved' using errcode='42501';
 end if;
 update public.sacco_members set auth_user_id=v_req.auth_user_id where id=v_member.id;
 update public.sacco_access_requests
 set status='APPROVED',target_member_id=v_member.id,reviewed_by=v_admin,
     reviewed_at=now(),verification_note=v_note where id=v_req.id;
 insert into public.sacco_audit_entries(actor_user_id,event_kind,entity_table,entity_id,after_record)
 values(v_admin,'ACCESS_APPROVED','sacco_access_requests',v_req.id::text,
  pg_catalog.jsonb_build_object('auth_user_id',v_req.auth_user_id,'member_id',v_member.id,
   'existing_member_role',v_member.member_role,'approval_at',now()));
 return pg_catalog.jsonb_build_object(
   'status','APPROVED','request_id',v_req.id,'member_role',v_member.member_role,
   'member_id',v_member.id,'already_reviewed',false);
end$$;
revoke all on function public.sacco_review_access_request(uuid,text,uuid,text,text) from public,anon;
grant execute on function public.sacco_review_access_request(uuid,text,uuid,text,text) to authenticated;
commit;