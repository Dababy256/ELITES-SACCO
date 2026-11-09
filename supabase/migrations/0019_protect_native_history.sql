-- Stage 19: preserve every native entry after posting or reversal.
-- Guard against deleting native rows and editing already-voided history.
begin;
create function sacco_private.guard_native_financial_history()
returns trigger language plpgsql set search_path='' as $$
declare v_before jsonb; v_after jsonb;
begin
 if tg_op='DELETE' then
  if old.voided_at is not null or old.legacy_key like 'native:%' then
   raise exception 'Native or reversed SACCO transactions are immutable; use the audited reversal workflow'
     using errcode='42501';
  end if;
  return old;
 end if;
 if old.voided_at is not null then
  raise exception 'A reversed financial entry is immutable' using errcode='42501';
 end if;
 if new.voided_at is not null then
  if old.legacy_key not like 'native:%' then
   raise exception 'Imported historical records cannot be reversed using native posting workflow'
     using errcode='42501';
  end if;
  if new.voided_by is null or char_length(btrim(coalesce(new.void_reason,'')))<15 then
   raise exception 'Native reversal requires actor and documented reason' using errcode='42501';
  end if;
  v_before:=pg_catalog.to_jsonb(old)-'voided_at'-'voided_by'-'void_reason';
  v_after:=pg_catalog.to_jsonb(new)-'voided_at'-'voided_by'-'void_reason';
  if v_before<>v_after then
   raise exception 'A reversal cannot silently alter the original financial transaction'
     using errcode='42501';
  end if;
 end if;
 return new;
end$$;
revoke all on function sacco_private.guard_native_financial_history() from public,anon,authenticated,service_role;

do $create_guards$
declare tabname text;
begin
 foreach tabname in array array[
 'sacco_contributions','sacco_loans','sacco_repayments',
 'sacco_financial_entries','sacco_membership_fees','sacco_waivers'
 ] loop
  execute pg_catalog.format(
   'alter table public.%I add constraint %I check (
      (voided_at is null and voided_by is null and void_reason is null)
      or (voided_at is not null and voided_by is not null and char_length(btrim(void_reason)) between 15 and 500)
    )', tabname,tabname||'_void_consistent'
  );
  execute pg_catalog.format(
   'create trigger sacco_guard_native_history before update or delete on public.%I
     for each row execute function sacco_private.guard_native_financial_history()',tabname
  );
 end loop;
end$create_guards$;
commit;