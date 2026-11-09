-- Protect documented SACCO loan-policy exceptions in staging review decisions.
-- Staging approvals never create ledger entries.
begin;
CREATE OR REPLACE FUNCTION public.sacco_review_draft(p_draft_id uuid, p_decision text, p_note text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare d public.sacco_staging_drafts%rowtype; v_review public.sacco_staging_reviews%rowtype;
 v_check jsonb; v_reviewer uuid; v_note text;
begin
 v_reviewer:=(select auth.uid());
 if v_reviewer is null or not (select sacco_private.is_sacco_admin()) then
  raise exception 'Administrator membership required' using errcode='42501';
 end if;
 if p_decision not in ('APPROVED','REJECTED') or p_decision is null then
  raise exception 'Invalid decision' using errcode='22023';
 end if;
 v_note:=pg_catalog.btrim(coalesce(p_note,''));
 if pg_catalog.length(v_note)>500 then raise exception 'Review note is too long' using errcode='22023'; end if;
 if p_decision='REJECTED' and pg_catalog.length(v_note)<5 then
  raise exception 'A rejection reason of at least five characters is required' using errcode='22023';
 end if;
 -- Locks the draft before looking at the unique review row. Concurrent review requests serialize.
 select * into d from public.sacco_staging_drafts where id=p_draft_id for update;
 if not found then raise exception 'Draft not found' using errcode='22023'; end if;
 select * into v_review from public.sacco_staging_reviews where draft_id=d.id;
 if found then
  if v_review.decision<>p_decision then
   raise exception 'Draft already reviewed; conflicting decision rejected' using errcode='23505';
  end if;
  return pg_catalog.jsonb_build_object('review_id',v_review.id,'decision',v_review.decision,
    'already_reviewed',true,'posted_to_financial_ledger',false);
 end if;
 v_check:=sacco_private.validate_staging_draft(d.action_kind,d.payload);
 if p_decision='APPROVED' and (v_check->>'valid')::boolean is distinct from true then
  raise exception 'Draft validation failed: %', v_check->>'error' using errcode='22023';
 end if;
 if p_decision='APPROVED' and coalesce((v_check->>'duplicate_count')::integer,0)>0 then
  raise exception 'Possible duplicate. Approving blocked pending duplicate reconciliation' using errcode='23505';
 end if;
 if p_decision='APPROVED' and d.action_kind='LOAN' then
  if v_check->>'loan_type'='REGULAR' and (v_check->>'amount_ugx')::numeric>1000000 and
    (v_check->>'cap_override_requested')::boolean is distinct from true then
   raise exception 'Regular loan above UGX 1,000,000 requires an explicit policy override' using errcode='22023';
  end if;
  if coalesce((v_check->>'prior_unsettled_count')::integer,0)>0 and
    (v_check->>'unsettled_override_requested')::boolean is distinct from true then
   raise exception 'Existing unpaid loan requires an explicit approval override' using errcode='22023';
  end if;
  if (v_check->>'cap_override_requested')::boolean is true
   or (v_check->>'unsettled_override_requested')::boolean is true then
   if char_length(v_note)<15 then
    raise exception 'Loan policy override requires a reviewer justification of at least 15 characters' using errcode='22023';
   end if;
  end if;
 end if;
 insert into public.sacco_staging_reviews(draft_id,decision,reviewed_by,review_note,validation_snapshot)
 values(d.id,p_decision,v_reviewer,v_note,v_check)
 returning * into v_review;
 insert into public.sacco_audit_entries(actor_user_id,event_kind,entity_table,entity_id,after_record)
 values(v_reviewer,'STAGING_'||p_decision,'sacco_staging_drafts',d.id::text,
  pg_catalog.jsonb_build_object('review_id',v_review.id,'kind',d.action_kind,
    'decision',p_decision,'note',v_note,'mode','STAGING_REVIEW_ONLY'));
 return pg_catalog.jsonb_build_object('review_id',v_review.id,'decision',v_review.decision,
  'already_reviewed',false,'posted_to_financial_ledger',false);
end$function$
;
revoke all on function public.sacco_review_draft(uuid,text,text) from public,anon;
grant execute on function public.sacco_review_draft(uuid,text,text) to authenticated;
commit;