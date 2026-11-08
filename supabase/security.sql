begin;
create table finance_private.rate_limits(key text primary key,window_start timestamptz not null default now(),attempts int not null default 1);
revoke all on finance_private.rate_limits from public,anon,authenticated;
create function financegpt.check_rate_limit(bucket text,max_attempts int,window_seconds int) returns boolean language plpgsql security definer set search_path='' as $$
declare r finance_private.rate_limits; begin
 insert into finance_private.rate_limits(key) values(bucket) on conflict(key) do update set
 attempts=case when finance_private.rate_limits.window_start<now()-make_interval(secs=>window_seconds) then 1 else finance_private.rate_limits.attempts+1 end,
 window_start=case when finance_private.rate_limits.window_start<now()-make_interval(secs=>window_seconds) then now() else finance_private.rate_limits.window_start end returning * into r;
 return r.attempts<=max_attempts; end $$;
create function financegpt.lookup_login(identifier text) returns text language sql security definer set search_path='' as $$
 select u.email from auth.users u join financegpt.profiles p on p.user_id=u.id where p.username_normalized=lower(identifier) and p.status='active' limit 1
$$;
create function financegpt.service_context(uid uuid,sid uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare p financegpt.profiles; begin
 select * into p from financegpt.profiles where user_id=uid and status='active';
 if not found or not exists(select 1 from auth.sessions where id=sid and user_id=uid) then raise exception 'Session revoked or account inactive'; end if;
 return to_jsonb(p)||jsonb_build_object('role',(select role from financegpt.user_roles where user_id=uid)); end $$;

-- Prevent ownership mismatches on all auxiliary entities, including agent policy links.
create function finance_private.owned_links() returns trigger language plpgsql security definer set search_path='' as $$
declare i int; ref_table text; col text; ref uuid; valid boolean; begin
 for i in 0..tg_nargs/2-1 loop
  col:=tg_argv[i*2];ref_table:=tg_argv[i*2+1];ref:=nullif(to_jsonb(new)->>col,'')::uuid;
  if ref is not null then execute format('select exists(select 1 from financegpt.%I where id=$1 and user_id=$2)',ref_table) into valid using ref,new.user_id;
   if not valid then raise exception 'Related record not found'; end if;
  end if;
 end loop;return new; end $$;
create trigger owned_agent_permission before insert or update on financegpt.agent_permissions for each row execute function finance_private.owned_links('connection_id','agent_connections');
create trigger owned_agent_policy before insert or update on financegpt.agent_policies for each row execute function finance_private.owned_links('connection_id','agent_connections');
create trigger owned_budget_period before insert or update on financegpt.budget_periods for each row execute function finance_private.owned_links('budget_id','budgets');
create trigger owned_import_row before insert or update on financegpt.import_rows for each row execute function finance_private.owned_links('job_id','import_jobs');
create trigger owned_forecast_point before insert or update on financegpt.forecast_points for each row execute function finance_private.owned_links('run_id','forecast_runs');
create trigger owned_forecast_scenario before insert or update on financegpt.forecast_scenarios for each row execute function finance_private.owned_links('base_run_id','forecast_runs');

create function finance_private.agent_authorize(uid uuid,client text,scope text) returns financegpt.agent_connections language plpgsql security definer set search_path='' as $$
declare conn financegpt.agent_connections; begin
 select * into conn from financegpt.agent_connections where user_id=uid and oauth_client_id=client for update;
 if not found or conn.status<>'active' then raise exception 'revoked: agent connection unavailable'; end if;
 if not exists(select 1 from financegpt.profiles where user_id=uid and status='active' and not must_change_password) then raise exception 'permission_denied: account unavailable'; end if;
 if scope like 'admin:%' or scope='agent_permissions:write' or not exists(select 1 from financegpt.agent_permissions where connection_id=conn.id and permission=scope and enabled) then raise exception 'permission_denied: scope unavailable'; end if;
 return conn;end $$;
create function financegpt.authorize_agent(uid uuid,client text,scope text) returns jsonb language plpgsql security definer set search_path='' as $$ declare conn financegpt.agent_connections;begin
 conn:=finance_private.agent_authorize(uid,client,scope);
 insert into financegpt.agent_audit_logs(user_id,connection_id,event_type,actor,tool,outcome) values(uid,conn.id,'agent.read','agent',scope,'ok');
 return to_jsonb(conn);end $$;

create function finance_private.agent_execute(uid uuid,conn financegpt.agent_connections,op text,p jsonb,idem text) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;b financegpt.budgets;begin
 if op in ('transactions:create','transactions:update','transactions:delete') then
  if op='transactions:delete' then p:=p||jsonb_build_object('status','voided'); end if;
  result:=finance_private.post_transaction(uid,p,idem,'agent');
 elsif op='budgets:write' then
  select * into b from financegpt.budgets where id=(p->>'id')::uuid and user_id=uid for update;
  if not found then raise exception 'Budget not found';end if;
  if b.row_version<>(p->>'expected_version')::int then raise exception 'conflict: budget changed';end if;
  update financegpt.budgets set amount=(p->>'amount')::bigint,row_version=row_version+1,updated_at=now() where id=b.id returning to_jsonb(budgets.*) into result;
 else raise exception 'Unsupported operation';end if;
 insert into financegpt.agent_audit_logs(user_id,connection_id,event_type,actor,tool,safe_diff_json,outcome) values(uid,conn.id,'agent.execute','agent',op,jsonb_build_object('id',result->>'id','amount',p->'amount'),'ok');
 return jsonb_build_object('status','ok','data',result);end $$;

create function financegpt.agent_mutate(uid uuid,client text,operation text,payload jsonb,idempotency_key text) returns jsonb language plpgsql security definer set search_path='' as $$
declare conn financegpt.agent_connections;pol financegpt.agent_policies;old financegpt.transactions;pending financegpt.agent_pending_actions;done financegpt.agent_executions;p jsonb:=payload;needs boolean:=false;result jsonb;hourly int;daily bigint;begin
 if length(idempotency_key)<8 then raise exception 'validation_error: idempotency key required';end if;
 perform pg_advisory_xact_lock(hashtextextended(uid||':agent',0));
 conn:=finance_private.agent_authorize(uid,client,operation);
 select * into done from financegpt.agent_executions where connection_id=conn.id and agent_executions.idempotency_key=agent_mutate.idempotency_key;
 if found then
  if done.execution_result->>'request_hash'<>md5(payload::text) then raise exception 'conflict: idempotency payload changed'; end if;
  return done.execution_result-'request_hash';end if;
 select * into pending from financegpt.agent_pending_actions where connection_id=conn.id and agent_pending_actions.idempotency_key=agent_mutate.idempotency_key;
 if found then
  if pending.payload_hash<>md5(payload::text) or pending.operation<>operation then raise exception 'conflict: proposal changed';end if;
  return jsonb_build_object('status',case when pending.expires_at<now() then 'expired' else pending.status end,'action_id',pending.id);end if;
 select * into pol from financegpt.agent_policies where connection_id=conn.id;
 if not found then raise exception 'permission_denied: no policy';end if;
 if operation<>'budgets:write' then
  if operation<>'transactions:create' then
   select * into old from financegpt.transactions where id=(p->>'id')::uuid and user_id=uid;
   if not found then raise exception 'not_found';end if;
   p:=to_jsonb(old)||p;
   if (p->>'expected_version')::int is distinct from old.row_version then raise exception 'conflict: version required';end if;
  end if;
  if (p->>'amount')::bigint<=0 then raise exception 'validation_error: amount must be positive';end if;
  if cardinality(pol.account_allowlist)>0 and (not ((p->>'account_id')::uuid=any(pol.account_allowlist)) or (p->>'destination_account_id' is not null and not ((p->>'destination_account_id')::uuid=any(pol.account_allowlist)))) then raise exception 'permission_denied: account restriction';end if;
  if cardinality(pol.category_allowlist)>0 and p->>'category_id' is not null and not ((p->>'category_id')::uuid=any(pol.category_allowlist)) then raise exception 'permission_denied: category restriction';end if;
  if (p->>'effective_at')::timestamptz<now()-make_interval(days=>coalesce((pol.limits_json->>'backdate_days')::int,365)) then needs:=true;end if;
 end if;
 select count(*),coalesce(sum((execution_result->'data'->>'amount')::bigint),0) into hourly,daily from financegpt.agent_executions where connection_id=conn.id and executed_at>=date_trunc('day',now());
 if daily+coalesce((p->>'amount')::bigint,0)>coalesce((pol.limits_json->>'daily_cap')::bigint,5000000) then raise exception 'rate_limited: daily cap';end if;
 select count(*) into hourly from financegpt.agent_executions where connection_id=conn.id and executed_at>now()-interval '1 hour';
 if hourly>=coalesce((pol.limits_json->>'hourly_cap')::int,30) then raise exception 'rate_limited: hourly cap';end if;
 needs:=needs or pol.approval_mode='always' or operation in ('transactions:delete','budgets:write') or p->>'type' in ('transfer','adjustment') or coalesce(p->>'currency','IDR')<>'IDR';
 if operation='transactions:create' then needs:=needs or (p->>'amount')::bigint>coalesce((pol.limits_json->>'create_limit')::bigint,1000000);end if;
 if operation='transactions:update' then needs:=needs or abs((p->>'amount')::bigint-old.amount)>coalesce((pol.limits_json->>'edit_limit')::bigint,250000) or p->>'account_id'<>old.account_id::text or p->>'type'<>old.type or p->>'currency'<>old.currency;end if;
 if needs then
  insert into financegpt.agent_pending_actions(connection_id,user_id,operation,payload_hash,payload_json,idempotency_key,expected_version) values(conn.id,uid,operation,md5(payload::text),p,idempotency_key,(p->>'expected_version')::int) returning * into pending;
  insert into financegpt.agent_audit_logs(user_id,connection_id,event_type,actor,tool,outcome)values(uid,conn.id,'agent.proposal','agent',operation,'pending_approval');
  return jsonb_build_object('status','pending_approval','action_id',pending.id,'expires_at',pending.expires_at);
 end if;
 result:=finance_private.agent_execute(uid,conn,operation,p,idempotency_key);
 insert into financegpt.agent_executions(user_id,connection_id,idempotency_key,execution_result)values(uid,conn.id,idempotency_key,result||jsonb_build_object('request_hash',md5(payload::text)));
 return result;
end $$;

create function financegpt.resolve_approval(action_id uuid,approve boolean) returns jsonb language plpgsql security definer set search_path='' as $$
declare a financegpt.agent_pending_actions;conn financegpt.agent_connections;pol financegpt.agent_policies;result jsonb;total bigint;begin
 if not finance_private.trusted(auth.uid()) then raise exception 'Trusted user session required';end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()||':agent',0));
 select * into a from financegpt.agent_pending_actions where id=action_id and user_id=auth.uid() for update;
 if not found then raise exception 'Action not found';end if;
 if a.status<>'pending' then return jsonb_build_object('status',a.status);end if;
 if a.expires_at<now() then update financegpt.agent_pending_actions set status='expired' where id=a.id;return jsonb_build_object('status','expired');end if;
 if not approve then update financegpt.agent_pending_actions set status='rejected' where id=a.id;return jsonb_build_object('status','rejected');end if;
 select * into conn from financegpt.agent_connections where id=a.connection_id;
 conn:=finance_private.agent_authorize(a.user_id,conn.oauth_client_id,a.operation);
 select * into pol from financegpt.agent_policies where connection_id=conn.id;
 if cardinality(pol.account_allowlist)>0 and not ((a.payload_json->>'account_id')::uuid=any(pol.account_allowlist)) then raise exception 'Account policy changed';end if;
 if cardinality(pol.category_allowlist)>0 and a.payload_json->>'category_id' is not null and not ((a.payload_json->>'category_id')::uuid=any(pol.category_allowlist)) then raise exception 'Category policy changed';end if;
 select coalesce(sum((execution_result->'data'->>'amount')::bigint),0) into total from financegpt.agent_executions where connection_id=conn.id and executed_at>=date_trunc('day',now());
 if total+coalesce((a.payload_json->>'amount')::bigint,0)>coalesce((pol.limits_json->>'daily_cap')::bigint,5000000) then raise exception 'Daily cap exceeded';end if;
 result:=finance_private.agent_execute(a.user_id,conn,a.operation,a.payload_json,a.idempotency_key);
 insert into financegpt.agent_executions(user_id,connection_id,action_id,idempotency_key,execution_result)values(a.user_id,conn.id,a.id,a.idempotency_key,result||jsonb_build_object('request_hash',a.payload_hash));
 update financegpt.agent_pending_actions set status='executed' where id=a.id;
 insert into financegpt.agent_audit_logs(user_id,connection_id,event_type,actor,outcome)values(a.user_id,conn.id,'approval.executed','self','ok');
 return result;end $$;

create function financegpt.admin_list_users(admin_id uuid,search_text text default '') returns jsonb language plpgsql security definer set search_path='' as $$ begin
 if not exists(select 1 from financegpt.user_roles r join financegpt.profiles p using(user_id) where r.user_id=admin_id and r.role='admin' and p.status='active' and not p.must_change_password)then raise exception 'Admin required';end if;
 return (select coalesce(jsonb_agg(t),'[]') from(select p.user_id,p.username_normalized,p.status,p.created_at,r.role,u.email,u.last_sign_in_at from financegpt.profiles p join auth.users u on u.id=p.user_id join financegpt.user_roles r on r.user_id=p.user_id where p.username_normalized ilike '%'||search_text||'%' or u.email ilike '%'||search_text||'%' order by p.created_at desc limit 100)t);end $$;
create function financegpt.admin_action(admin_id uuid,target_id uuid,action text,reason text,new_role text default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare old financegpt.profiles;begin
 if not exists(select 1 from financegpt.user_roles r join financegpt.profiles p using(user_id) where r.user_id=admin_id and r.role='admin' and p.status='active' and not p.must_change_password)then raise exception 'Admin required';end if;
 if length(trim(reason))<3 then raise exception 'Reason required';end if;
 perform pg_advisory_xact_lock(hashtextextended('finance-admin-actions',0));
 select * into old from financegpt.profiles where user_id=target_id for update;
 if not found then raise exception 'User not found';end if;
 if action in ('suspend','change-role') and exists(select 1 from financegpt.user_roles where user_id=target_id and role='admin') and (select count(*) from financegpt.user_roles r join financegpt.profiles p using(user_id)where r.role='admin' and p.status='active')<=1 and (action='suspend' or new_role<>'admin') then raise exception 'Cannot remove the last active admin';end if;
 if action='suspend' then update financegpt.profiles set status='suspended' where user_id=target_id;delete from auth.sessions where user_id=target_id;
 elsif action='reactivate' then update financegpt.profiles set status='active' where user_id=target_id;
 elsif action='change-role' then update financegpt.user_roles set role=new_role,created_by=admin_id where user_id=target_id;
 elsif action='force-logout' then delete from auth.sessions where user_id=target_id;
 elsif action='reset-password' then update financegpt.profiles set must_change_password=true where user_id=target_id;delete from auth.sessions where user_id=target_id;
 else raise exception 'Unsupported admin action';end if;
 insert into financegpt.admin_audit_logs(admin_user_id,target_user_id,action,reason,result)values(admin_id,target_id,action,reason,jsonb_build_object('status','ok','previous_status',old.status,'new_role',new_role));
 return jsonb_build_object('status','ok');end $$;
create function financegpt.scheduled_tick() returns int language plpgsql security definer set search_path='' as $$
declare r financegpt.recurring_rules;payload jsonb;amount int:=0;local_next timestamp;zone text;begin
 for r in select rr.* from financegpt.recurring_rules rr join financegpt.profiles p on p.user_id=rr.user_id where active and next_at<=now() and p.status='active' and not p.must_change_password and (end_at is null or end_at>=next_at) for update of rr skip locked loop
  payload:=r.payload_json||jsonb_build_object('effective_at',r.next_at,'status',case when r.mode='auto-post' then 'posted' else r.mode end);
  perform finance_private.post_transaction(r.user_id,payload,'recurring:'||r.id||':'||r.next_at,'recurring');
  select timezone into zone from financegpt.profiles where user_id=r.user_id;local_next:=r.next_at at time zone zone;
  update financegpt.recurring_rules set next_at=(local_next+case cadence when 'daily' then interval '1 day' when 'weekly' then interval '1 week' when 'yearly' then interval '1 year' else interval '1 month' end)at time zone zone where id=r.id;
  amount:=amount+1;
 end loop;return amount;end $$;

-- Revoke broad defaults after creating the new RPCs, then grant the intended entrypoints.
revoke all on all functions in schema financegpt from public,anon,authenticated;
grant execute on function financegpt.initialize_profile(),financegpt.create_account(jsonb,text),financegpt.save_transaction(jsonb,text),financegpt.confirm_import(jsonb,text),financegpt.resolve_approval(uuid,boolean) to authenticated;
grant execute on all functions in schema financegpt to service_role;
revoke all on all functions in schema finance_private from public,anon,authenticated;
grant execute on function finance_private.trusted(uuid) to authenticated;
notify pgrst,'reload schema';
commit;
