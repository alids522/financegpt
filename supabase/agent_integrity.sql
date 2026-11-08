begin;
-- Re-check current policy at execution, including proposals approved after policy edits.
create function finance_private.check_agent_payload(conn financegpt.agent_connections,op text,p jsonb)returns jsonb language plpgsql security definer set search_path='' as $$
declare pol financegpt.agent_policies;b financegpt.budgets;key text;ids uuid[];item jsonb;begin
 select * into pol from financegpt.agent_policies where connection_id=conn.id;
 if not found then raise exception 'permission_denied: policy unavailable';end if;
 if op='reports:export'then
  if coalesce(p->>'type','transactions')not in('transactions','budget','forecast')then raise exception 'validation_error: unsupported report dataset';end if;
  foreach key in array array['account_ids','category_ids']loop
   ids:=case key when'account_ids'then pol.account_allowlist else pol.category_allowlist end;
   if cardinality(ids)>0 then
    if exists(select 1 from jsonb_array_elements_text(coalesce(p->'filter_snapshot'->key,'[]'))x where not(x::uuid=any(ids)))then raise exception 'permission_denied: report policy changed';end if;
    if jsonb_array_length(coalesce(p->'filter_snapshot'->key,'[]'))=0 then p:=jsonb_set(p,'{filter_snapshot}',coalesce(p->'filter_snapshot','{}')||jsonb_build_object(key,to_jsonb(ids)));end if;
   end if;
  end loop;
 elsif op='budgets:write'then
  select * into b from financegpt.budgets where id=(p->>'id')::uuid and user_id=conn.user_id;
  if not found or(cardinality(pol.account_allowlist)>0 and(b.account_id is null or not(b.account_id=any(pol.account_allowlist))))or(cardinality(pol.category_allowlist)>0 and(b.category_id is null or not(b.category_id=any(pol.category_allowlist))))then raise exception 'permission_denied: budget restriction';end if;
  if b.row_version is distinct from(p->>'expected_version')::int then raise exception 'conflict: budget version required';end if;
 else
  if cardinality(pol.account_allowlist)>0 and(not((p->>'account_id')::uuid=any(pol.account_allowlist))or(p->>'destination_account_id'is not null and not((p->>'destination_account_id')::uuid=any(pol.account_allowlist))))then raise exception 'permission_denied: account restriction';end if;
  if cardinality(pol.category_allowlist)>0 then
   if p->>'category_id'is not null and not((p->>'category_id')::uuid=any(pol.category_allowlist))then raise exception 'permission_denied: category restriction';end if;
   if exists(select 1 from jsonb_array_elements(coalesce(p->'splits','[]'))x where not((x->>'category_id')::uuid=any(pol.category_allowlist)))then raise exception 'permission_denied: split category restriction';end if;
   if not(p?'splits')and p->>'id'is not null and exists(select 1 from financegpt.transaction_splits where transaction_id=(p->>'id')::uuid and not(category_id=any(pol.category_allowlist)))then raise exception 'permission_denied: existing split restriction';end if;
  end if;
 end if;
 return p;end $$;
do $$declare body text;begin
 select pg_get_functiondef('finance_private.agent_execute(uuid,financegpt.agent_connections,text,jsonb,text)'::regprocedure)into body;
 body:=replace(body,'declare result jsonb;b financegpt.budgets;begin','declare result jsonb;b financegpt.budgets;begin p:=finance_private.check_agent_payload(conn,op,p);');
 execute body;
end $$;
revoke all on function finance_private.check_agent_payload(financegpt.agent_connections,text,jsonb)from public,anon,authenticated;
-- A worker crash makes a claim retryable after five minutes, with at most three attempts.
alter table financegpt.export_jobs add column started_at timestamptz;
create or replace function financegpt.claim_export_job(job_id uuid)returns jsonb language plpgsql security definer set search_path='' as $$declare job financegpt.export_jobs;begin
 update financegpt.export_jobs set status='processing',started_at=now(),attempts=attempts+1 where id=job_id and(status in('pending','approved')or(status='processing'and started_at<now()-interval'5 minutes'))and attempts<3 returning *into job;
 return case when found then to_jsonb(job)else null end;end $$;
revoke all on function financegpt.claim_export_job(uuid)from public,anon,authenticated;
grant execute on function financegpt.claim_export_job(uuid)to service_role;
notify pgrst,'reload schema';
commit;
