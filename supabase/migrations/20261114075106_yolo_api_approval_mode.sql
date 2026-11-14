begin;
alter table financegpt.agent_policies add constraint approval_mode_valid check(approval_mode in('risk','always','yolo'));

-- A replay explicitly resubmits an existing pending request. Merely enabling
-- YOLO does not execute any queued proposal, rejected request or expired action.
create function finance_private.execute_yolo_pending(uid uuid,client text,action_id uuid)returns jsonb language plpgsql security definer set search_path='' as $$
declare a financegpt.agent_pending_actions;conn financegpt.agent_connections;pol financegpt.agent_policies;result jsonb;total bigint;hourly bigint;begin
 perform pg_advisory_xact_lock(hashtextextended(uid||':agent',0));
 select *into a from financegpt.agent_pending_actions where id=action_id and user_id=uid for update;
 if not found then raise exception 'not_found';end if;
 conn:=finance_private.agent_authorize(uid,client,a.operation);
 if a.connection_id<>conn.id then raise exception 'permission_denied';end if;
 select *into pol from financegpt.agent_policies where connection_id=conn.id and user_id=uid;
 if pol.approval_mode is distinct from 'yolo'then raise exception 'permission_denied: YOLO is not enabled';end if;
 if a.status='executed'then
  select execution_result-'request_hash'into result from financegpt.agent_executions where action_id=a.id and connection_id=conn.id and user_id=uid;
  return coalesce(result,jsonb_build_object('status','executed','action_id',a.id));
 end if;
 if a.status<>'pending'then return jsonb_build_object('status',a.status,'action_id',a.id);end if;
 if a.expires_at<now()then update financegpt.agent_pending_actions set status='expired'where id=a.id;return jsonb_build_object('status','expired','action_id',a.id);end if;
 if a.payload_json?'resource'then
  perform finance_private.check_managed_policy(conn,a.payload_json);
  select count(*)into hourly from financegpt.agent_audit_logs where connection_id=conn.id and event_type='agent.execute'and occurred_at>now()-interval'1 hour';
 else
  select coalesce(sum((execution_result->'data'->>'amount')::bigint),0)into total from financegpt.agent_executions where connection_id=conn.id and executed_at>=date_trunc('day',now());
  if total+coalesce((a.payload_json->>'amount')::bigint,0)>coalesce((pol.limits_json->>'daily_cap')::bigint,5000000)then raise exception 'rate_limited: daily cap';end if;
  select count(*)into hourly from financegpt.agent_executions where connection_id=conn.id and executed_at>now()-interval'1 hour';
 end if;
 if hourly>=coalesce((pol.limits_json->>'hourly_cap')::bigint,30)then raise exception 'rate_limited: hourly cap';end if;
 result:=finance_private.agent_execute(uid,conn,a.operation,a.payload_json,a.idempotency_key);
 insert into financegpt.agent_executions(user_id,connection_id,action_id,idempotency_key,execution_result)values(uid,conn.id,a.id,a.idempotency_key,result||jsonb_build_object('request_hash',a.payload_hash));
 update financegpt.agent_pending_actions set status='executed'where id=a.id;
 insert into financegpt.agent_audit_logs(user_id,connection_id,event_type,actor,tool,outcome,safe_diff_json)values(uid,conn.id,'agent.yolo.execute','agent',a.operation,'ok','{"approval_mode":"yolo","resubmitted":true}');
 return result;end $$;
revoke all on function finance_private.execute_yolo_pending(uuid,text,uuid)from public,anon,authenticated;

do $$declare b text;old text;begin
 select pg_get_functiondef('financegpt.agent_mutate(uuid,text,text,jsonb,text)'::regprocedure)into b;
 old:=b;
 b:=replace(b,'if needs then','if needs and coalesce(pol.approval_mode,''risk'')<>''yolo'' then');
 if b=old then raise exception 'Missing financial approval branch';end if;
 old:=b;
 b:=replace(b,'return jsonb_build_object(''status'',case when pending.expires_at',E'if exists(select 1 from financegpt.agent_policies where connection_id=conn.id and user_id=uid and approval_mode=''yolo'')then return finance_private.execute_yolo_pending(uid,client,pending.id);end if;\n  return jsonb_build_object(''status'',case when pending.expires_at');
 if b=old then raise exception 'Missing pending financial replay branch';end if;
 execute b;

 select pg_get_functiondef('financegpt.manage_resource(uuid,text,text,text,jsonb,uuid,text)'::regprocedure)into b;
 old:=b;
 b:=replace(b,'if pol.approval_mode=''always''or method=''DELETE''or resource in(''debt_payments'',''goal_allocations'')or(resource=''recurring_rules''and coalesce(payload->>''mode'',''auto-post'')=''auto-post'')then','if coalesce(pol.approval_mode,''risk'')<>''yolo''and(pol.approval_mode=''always''or method=''DELETE''or resource in(''debt_payments'',''goal_allocations'')or(resource=''recurring_rules''and coalesce(payload->>''mode'',''auto-post'')=''auto-post''))then');
 if b=old then raise exception 'Missing resource approval branch';end if;
 old:=b;
 b:=replace(b,'p:=jsonb_build_object(''resource'',resource',E'if client is not null then conn:=finance_private.agent_authorize(uid,client,scope);end if;\n p:=jsonb_build_object(''resource'',resource');
 if b=old then raise exception 'Missing resource authorization branch';end if;
 old:=b;
 b:=replace(b,'return cached.response_ref;end if;',E'if client is not null and cached.response_ref->>''status''=''pending_approval''and exists(select 1 from financegpt.agent_policies where connection_id=conn.id and approval_mode=''yolo'')then\n result:=finance_private.execute_yolo_pending(uid,client,(cached.response_ref->>''action_id'')::uuid);\n update financegpt.idempotency_records set response_ref=result where id=cached.id;return result;end if;return cached.response_ref;end if;');
 if b=old then raise exception 'Missing resource replay branch';end if;
 -- Record successful automatic resource writes for rate limits and traceability.
 b:=replace(b,'else result:=finance_private.agent_execute(uid,conn,scope,p,idempotency_key);end if;',E'else result:=finance_private.agent_execute(uid,conn,scope,p,idempotency_key);\n insert into financegpt.agent_executions(user_id,connection_id,idempotency_key,execution_result)values(uid,conn.id,idempotency_key,result||jsonb_build_object(''request_hash'',md5(p::text)));end if;');
 execute b;

 select pg_get_functiondef('financegpt.save_agent_policy(uuid,jsonb,text)'::regprocedure)into b;
 old:=b;
 b:=replace(b,'case when payload->>''approval_mode''=''always''then''always''else''risk''end','coalesce(payload->>''approval_mode'',(select approval_mode from financegpt.agent_policies where connection_id=conn.id and user_id=uid),''risk'')');
 if b=old then raise exception 'Missing policy approval-mode editor';end if;
 b:=replace(b,'if length(idempotency_key)<8 then',E'if payload?''approval_mode''and(payload->>''approval_mode''is null or payload->>''approval_mode''not in(''risk'',''always'',''yolo''))then raise exception ''Invalid approval mode'';end if;\n if length(idempotency_key)<8 then');
 execute b;

 select pg_get_functiondef('financegpt.generate_personal_token(text,integer)'::regprocedure)into b;
 old:=b;
 b:=replace(b,'insert into financegpt.agent_policies(user_id,connection_id)values(uid,conn);',E'insert into financegpt.agent_policies(user_id,connection_id,approval_mode)values(uid,conn,case when(select settings_json->>''api_approval_mode''from financegpt.profiles where user_id=uid)=''yolo''then''yolo''else''risk''end);');
 if b=old then raise exception 'Missing personal token policy default';end if;
 execute b;
end $$;
notify pgrst,'reload schema';
commit;
