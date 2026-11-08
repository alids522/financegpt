begin;
alter table financegpt.export_jobs add column requested_by_connection_id uuid references financegpt.agent_connections(id),add column attempts int default 0,add column error_code text;
create trigger owned_export_connection before insert or update on financegpt.export_jobs for each row execute function finance_private.owned_links('requested_by_connection_id','agent_connections');
create function financegpt.claim_export_job(job_id uuid)returns jsonb language plpgsql security definer set search_path='' as $$declare job financegpt.export_jobs;begin
 update financegpt.export_jobs set status='processing',attempts=attempts+1 where id=job_id and status in('pending','approved','failed')and attempts<3 returning * into job;
 return case when found then to_jsonb(job)else null end;end $$;
create function financegpt.create_export(payload jsonb,idempotency_key text)returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();cached financegpt.idempotency_records;job financegpt.export_jobs;begin
 if not finance_private.trusted(uid)then raise exception 'Access denied';end if;
 if payload->>'format'not in('csv','pdf')or coalesce(payload->>'type','transactions')not in('transactions','budget','forecast')then raise exception 'Invalid export format or dataset';end if;
 if length(idempotency_key)<8 then raise exception 'Idempotency key required';end if;
 perform pg_advisory_xact_lock(hashtextextended(uid||':export:'||idempotency_key,0));
 select * into cached from financegpt.idempotency_records where user_id=uid and operation='export'and key=idempotency_key;
 if found then if cached.request_hash<>md5(payload::text)then raise exception 'Idempotency conflict';end if;return cached.response_ref;end if;
 insert into financegpt.export_jobs(user_id,type,format,filter_snapshot,status)values(uid,coalesce(payload->>'type','transactions'),payload->>'format',coalesce(payload->'filter_snapshot','{}'),'pending')returning * into job;
 insert into financegpt.idempotency_records(user_id,operation,key,request_hash,response_ref)values(uid,'export',idempotency_key,md5(payload::text),to_jsonb(job));return to_jsonb(job);end $$;
do $$declare body text;begin
 select pg_get_functiondef('finance_private.agent_execute(uuid,financegpt.agent_connections,text,jsonb,text)'::regprocedure)into body;
 body:=replace(body,'else raise exception ''Unsupported operation'';end if;',E'elsif op=''reports:export'' then\n  if p->>''format'' not in(''csv'',''pdf'')then raise exception ''Invalid report format'';end if;\n  insert into financegpt.export_jobs(user_id,requested_by_connection_id,type,format,filter_snapshot,status)values(uid,conn.id,coalesce(p->>''type'',''transactions''),p->>''format'',coalesce(p->''filter_snapshot'',''{}''),''approved'')returning to_jsonb(export_jobs.*)into result;\n else raise exception ''Unsupported operation'';end if;');execute body;
 select pg_get_functiondef('financegpt.agent_mutate(uuid,text,text,jsonb,text)'::regprocedure)into body;
 body:=replace(body,'operation in (''transactions:delete'',''budgets:write'')','operation in (''transactions:delete'',''budgets:write'',''reports:export'')');
 body:=replace(body,'if operation<>''budgets:write'' then','if operation not in(''budgets:write'',''reports:export'')then');
 execute body;
end $$;
create function financegpt.maintenance_tick()returns jsonb language plpgsql security definer set search_path='' as $$declare expired int;begin
 update financegpt.agent_pending_actions set status='expired'where status='pending'and expires_at<now();get diagnostics expired=row_count;
 delete from finance_private.rate_limits where window_start<now()-interval '2 days';
 delete from financegpt.agent_audit_logs where occurred_at<now()-interval '365 days';
 return jsonb_build_object('expired_actions',expired);end $$;
revoke all on function financegpt.claim_export_job(uuid),financegpt.create_export(jsonb,text),financegpt.maintenance_tick()from public,anon,authenticated;
grant execute on function financegpt.create_export(jsonb,text)to authenticated;
grant execute on function financegpt.claim_export_job(uuid),financegpt.maintenance_tick()to service_role;
notify pgrst,'reload schema';
commit;
