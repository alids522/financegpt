begin;
create function financegpt.save_agent_policy(p_connection_id uuid,payload jsonb,idempotency_key text)returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();cached financegpt.idempotency_records;conn financegpt.agent_connections;entry record;ids uuid[];allow_key text;begin
 if not finance_private.trusted(uid)then raise exception 'Access denied';end if;
 if length(idempotency_key)<8 then raise exception 'Idempotency key required';end if;
 perform pg_advisory_xact_lock(hashtextextended(uid||':policy:'||idempotency_key,0));
 select *into cached from financegpt.idempotency_records where user_id=uid and operation='agent_policy'and key=idempotency_key;
 if found then if cached.request_hash<>md5(jsonb_build_object('id',p_connection_id,'payload',payload)::text)then raise exception 'Conflict: policy request changed';end if;return cached.response_ref;end if;
 select *into conn from financegpt.agent_connections where id=p_connection_id and user_id=uid for update;
 if not found or conn.status='revoked'then raise exception 'Agent unavailable';end if;
 for entry in select *from jsonb_each(coalesce(payload->'permissions','{}'))loop
  if entry.key not in('accounts:read','transactions:read','transactions:create','transactions:update','transactions:delete','categories:read','categories:write','budgets:read','budgets:write','forecasts:read','forecasts:simulate','analytics:read','reports:export','transactions:import','recurring:write')or jsonb_typeof(entry.value)<>'boolean'then raise exception 'Invalid permission';end if;
 end loop;
 for entry in select *from jsonb_each(coalesce(payload->'limits','{}'))loop
  if entry.key not in('create_limit','edit_limit','daily_cap','hourly_cap','backdate_days')or jsonb_typeof(entry.value)<>'number'or(entry.value#>>'{}')!~'^[0-9]+$'or(entry.value#>>'{}')::numeric>9000000000000000 then raise exception 'Limits must be nonnegative safe integers';end if;
 end loop;
 foreach allow_key in array array['account_allowlist','category_allowlist']loop
  select coalesce(array_agg(x::uuid),'{}')into ids from jsonb_array_elements_text(coalesce(payload->allow_key,'[]'))x;
  if allow_key='account_allowlist'and exists(select 1 from unnest(ids)x where not exists(select 1 from financegpt.accounts where id=x and user_id=uid))then raise exception 'Account unavailable';end if;
  if allow_key='category_allowlist'and exists(select 1 from unnest(ids)x where not exists(select 1 from financegpt.categories where id=x and user_id=uid))then raise exception 'Category unavailable';end if;
 end loop;
 for entry in select *from jsonb_each(coalesce(payload->'permissions','{}'))loop
  insert into financegpt.agent_permissions(user_id,connection_id,permission,enabled)values(uid,conn.id,entry.key,entry.value::boolean)on conflict(connection_id,permission)do update set enabled=excluded.enabled,updated_at=now();
 end loop;
 insert into financegpt.agent_policies(user_id,connection_id,limits_json,account_allowlist,category_allowlist,approval_mode)values(uid,conn.id,coalesce(payload->'limits','{}'),array(select x::uuid from jsonb_array_elements_text(coalesce(payload->'account_allowlist','[]'))x),array(select x::uuid from jsonb_array_elements_text(coalesce(payload->'category_allowlist','[]'))x),case when payload->>'approval_mode'='always'then'always'else'risk'end)
 on conflict(connection_id)do update set limits_json=excluded.limits_json,account_allowlist=excluded.account_allowlist,category_allowlist=excluded.category_allowlist,approval_mode=excluded.approval_mode;
 insert into financegpt.idempotency_records(user_id,operation,key,request_hash,response_ref)values(uid,'agent_policy',idempotency_key,md5(jsonb_build_object('id',conn.id,'payload',payload)::text),'{}');
 return '{}'::jsonb;end $$;
revoke all on function financegpt.save_agent_policy(uuid,jsonb,text)from public,anon;
grant execute on function financegpt.save_agent_policy(uuid,jsonb,text)to authenticated;
notify pgrst,'reload schema';
commit;
