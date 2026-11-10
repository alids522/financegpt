begin;
-- Resource mutations share the existing agent permission, approval and audit boundary.
do $$declare t text;begin
 foreach t in array array['categories','transaction_templates','recurring_rules','savings_goals','goal_allocations','debts','debt_payments']loop
 execute format('alter table financegpt.%I add column if not exists row_version integer not null default 1',t);
 end loop;
end $$;
create function finance_private.managed_resource(uid uuid,r text,method text,p jsonb,rid uuid)returns jsonb language plpgsql security definer set search_path='' as $$
declare allowed text[];data jsonb:=p-'expected_version';old jsonb;result jsonb;cols text;nested jsonb;link text;parent uuid;begin
 allowed:=case r
 when 'categories'then array['name','type','parent_id','color','icon','archived','sort_order','default_budget']
 when 'transaction_templates'then array['name','payload_json','favourite','sort_order']
 when 'recurring_rules'then array['name','next_at','cadence','payload_json','mode','active','end_at']
 when 'savings_goals'then array['name','target_amount','target_date','account_id','currency']
 when 'goal_allocations'then array['goal_id','amount','notes']
 when 'debts'then array['name','counterparty','kind','principal','rate','due','currency']
 when 'debt_payments'then array['debt_id','transaction_id','principal_paid','interest_paid'] else null end;
 if allowed is null or method not in('POST','PATCH','DELETE')or jsonb_typeof(p)<>'object'or exists(select 1 from jsonb_object_keys(data)k where not(k=any(allowed)))then raise exception 'validation_error: invalid resource fields';end if;
 if rid is not null then
  execute format('select to_jsonb(t)from financegpt.%I t where id=$1 and user_id=$2 for update',r)into old using rid,uid;
  if old is null then raise exception 'not_found';end if;
  if (p->>'expected_version')::int is distinct from(old->>'row_version')::int then raise exception 'conflict: expected_version required';end if;
 elsif method<>'POST'then raise exception 'validation_error: record id required';end if;
 if method='DELETE'then
  if r='categories'then update financegpt.categories set archived=true,row_version=row_version+1 where id=rid and user_id=uid returning to_jsonb(categories.*)into result;
  elsif r='recurring_rules'then update financegpt.recurring_rules set active=false,row_version=row_version+1 where id=rid and user_id=uid returning to_jsonb(recurring_rules.*)into result;
  else execute format('delete from financegpt.%I t where id=$1 and user_id=$2 returning to_jsonb(t)',r)into result using rid,uid;end if;
  return jsonb_build_object('data',result,'deleted',r not in('categories','recurring_rules'),'archived',r='categories','disabled',r='recurring_rules');
 end if;
 nested:=coalesce(data->'payload_json',old->'payload_json');
 if r in('transaction_templates','recurring_rules')then
  if jsonb_typeof(nested)<>'object'or nested?'user_id' or nested?'id' then raise exception 'validation_error: invalid transaction payload';end if;
  foreach link in array array['account_id','destination_account_id']loop
   if nested->>link is not null and not exists(select 1 from financegpt.accounts where id=(nested->>link)::uuid and user_id=uid)then raise exception 'permission_denied: foreign account';end if;
  end loop;
  if nested->>'category_id'is not null and not exists(select 1 from financegpt.categories where id=(nested->>'category_id')::uuid and user_id=uid)then raise exception 'permission_denied: foreign category';end if;
  if exists(select 1 from jsonb_array_elements(coalesce(nested->'splits','[]'))x where not exists(select 1 from financegpt.categories where id=(x->>'category_id')::uuid and user_id=uid))then raise exception 'permission_denied: foreign split';end if;
  if r='recurring_rules'and(coalesce(nested->>'type','')not in('income','expense','transfer')or nested->>'account_id'is null or coalesce((nested->>'amount')::bigint,0)<=0)then raise exception 'validation_error: recurring transaction incomplete';end if;
 end if;
 if r='savings_goals'and coalesce(data->>'account_id',old->>'account_id')is not null and not exists(select 1 from financegpt.accounts where id=coalesce(data->>'account_id',old->>'account_id')::uuid and user_id=uid and currency=coalesce(data->>'currency',old->>'currency','IDR'))then raise exception 'validation_error: goal account currency';end if;
 if r in('savings_goals','debts')and not exists(select 1 from financegpt.currency_metadata where code=coalesce(data->>'currency',old->>'currency','IDR'))then raise exception 'validation_error: unsupported currency';end if;
 if r='debts'and rid is not null and coalesce((data->>'principal')::bigint,(old->>'principal')::bigint)<(select coalesce(sum(principal_paid),0)from financegpt.debt_payments where debt_id=rid and user_id=uid)then raise exception 'validation_error: principal below recorded payments';end if;
 if r='debt_payments'then
  parent:=coalesce(data->>'debt_id',old->>'debt_id')::uuid;
  perform 1 from financegpt.debts where id=parent and user_id=uid for update;
  if not found then raise exception 'not_found';end if;
  if coalesce((data->>'principal_paid')::bigint,(old->>'principal_paid')::bigint,0)+(select coalesce(sum(principal_paid),0)from financegpt.debt_payments where debt_id=parent and user_id=uid and id is distinct from rid)>(select principal from financegpt.debts where id=parent and user_id=uid)then raise exception 'validation_error: overpayment';end if;
  if coalesce((data->>'interest_paid')::bigint,0)<0 then raise exception 'validation_error: negative interest';end if;
 end if;
 if data?'name'and length(trim(data->>'name'))not between 1 and 100 then raise exception 'validation_error: name required';end if;
 if rid is null then
  data:=data||jsonb_build_object('id',gen_random_uuid(),'user_id',uid);
  select string_agg(format('%I',k),',')into cols from jsonb_object_keys(data)k;
  execute format('insert into financegpt.%I as t(%s)select %s from jsonb_populate_record(null::financegpt.%I,$1)returning to_jsonb(t)',r,cols,cols,r)into result using data;
 else
  data:=data||jsonb_build_object('row_version',(old->>'row_version')::int+1);
  select string_agg(format('%I',k),',')into cols from jsonb_object_keys(data)k;
  execute format('update financegpt.%I as t set(%s)=(select %s from jsonb_populate_record(null::financegpt.%I,$1))where id=$2 and user_id=$3 returning to_jsonb(t)',r,cols,cols,r)into result using data,rid,uid;
 end if;
 return jsonb_build_object('data',result);end $$;

create function finance_private.check_managed_policy(conn financegpt.agent_connections,p jsonb)returns void language plpgsql security definer set search_path='' as $$
declare pol financegpt.agent_policies;v jsonb;old jsonb;r text:=p->>'resource';rid uuid:=(p->>'record_id')::uuid;begin
 select *into pol from financegpt.agent_policies where connection_id=conn.id and user_id=conn.user_id;
 if pol.id is null then raise exception 'permission_denied: policy missing';end if;
 if rid is not null then execute format('select to_jsonb(t)from financegpt.%I t where id=$1 and user_id=$2',r)into old using rid,conn.user_id;if old is null then raise exception 'not_found';end if;end if;
 v:=coalesce(old,'{}')||(p->'payload');
 if cardinality(pol.account_allowlist)>0 or cardinality(pol.category_allowlist)>0 then
  -- Bookkeeping records without an enforceable account/category boundary stay inaccessible to restricted connections.
  if r in('debts','debt_payments','goal_allocations')then raise exception 'permission_denied: resource requires unrestricted policy';end if;
  if r='categories'and cardinality(pol.category_allowlist)>0 and(rid is null or not(rid=any(pol.category_allowlist)))then raise exception 'permission_denied: category restriction';end if;
  if r in('transaction_templates','recurring_rules')then v:=v->'payload_json';end if;
  if r<>'categories'and cardinality(pol.account_allowlist)>0 and(v->>'account_id'is null or not((v->>'account_id')::uuid=any(pol.account_allowlist))or(v->>'destination_account_id'is not null and not((v->>'destination_account_id')::uuid=any(pol.account_allowlist))))then raise exception 'permission_denied: account restriction';end if;
  if r<>'categories'and cardinality(pol.category_allowlist)>0 and(v->>'category_id'is null or not((v->>'category_id')::uuid=any(pol.category_allowlist))or exists(select 1 from jsonb_array_elements(coalesce(v->'splits','[]'))x where not((x->>'category_id')::uuid=any(pol.category_allowlist))))then raise exception 'permission_denied: category restriction';end if;
 end if;end $$;

alter function finance_private.agent_execute(uuid,financegpt.agent_connections,text,jsonb,text)rename to agent_execute_legacy;
create function finance_private.agent_execute(uid uuid,conn financegpt.agent_connections,op text,p jsonb,idem text)returns jsonb language plpgsql security definer set search_path='' as $$declare result jsonb;begin
 if not(p?'resource')then return finance_private.agent_execute_legacy(uid,conn,op,p,idem);end if;
 if op is distinct from (case p->>'resource' when 'categories'then 'categories:write'when 'transaction_templates'then 'templates:write'when 'recurring_rules'then 'recurring:write'when 'savings_goals'then 'goals:write'when 'goal_allocations'then 'goals:write'when 'debts'then 'debts:write'when 'debt_payments'then 'debts:write'else null end) then raise exception 'permission_denied: invalid resource scope';end if;
 perform finance_private.agent_authorize(uid,conn.oauth_client_id,op);
 perform finance_private.check_managed_policy(conn,p);
 result:=finance_private.managed_resource(uid,p->>'resource',p->>'method',p->'payload',(p->>'record_id')::uuid);
 insert into financegpt.agent_audit_logs(user_id,connection_id,event_type,tool,actor,safe_diff_json,outcome)values(uid,conn.id,'agent.execute',op,'agent',jsonb_build_object('resource',p->>'resource','method',p->>'method','id',result->'data'->>'id'),'ok');
 return jsonb_build_object('status','ok')||result;end $$;

create function financegpt.manage_resource(uid uuid,client text,resource text,method text,payload jsonb,record_id uuid,idempotency_key text)returns jsonb language plpgsql security definer set search_path='' as $$
declare conn financegpt.agent_connections;pol financegpt.agent_policies;p jsonb;result jsonb;cached financegpt.idempotency_records;scope text;pending financegpt.agent_pending_actions;begin
 if not exists(select 1 from financegpt.profiles where user_id=uid and status='active'and not must_change_password)then raise exception 'permission_denied';end if;
 scope:=case resource when'categories'then'categories:write'when'transaction_templates'then'templates:write'when'recurring_rules'then'recurring:write'when'savings_goals'then'goals:write'when'goal_allocations'then'goals:write'when'debts'then'debts:write'when'debt_payments'then'debts:write'else null end;
 if scope is null or length(idempotency_key)not between 8 and 200 then raise exception 'validation_error';end if;
 p:=jsonb_build_object('resource',resource,'method',method,'payload',payload,'record_id',record_id);
 perform pg_advisory_xact_lock(hashtextextended(uid||':managed:'||idempotency_key,0));
 select *into cached from financegpt.idempotency_records where user_id=uid and operation='managed:'||coalesce(client,'self')and key=idempotency_key;
 if found then if cached.request_hash<>md5(p::text)then raise exception 'conflict: idempotency payload changed';end if;return cached.response_ref;end if;
 if client is not null then
  conn:=finance_private.agent_authorize(uid,client,scope);perform finance_private.check_managed_policy(conn,p);
  select *into pol from financegpt.agent_policies where connection_id=conn.id;
  if(select count(*)from financegpt.agent_audit_logs where connection_id=conn.id and event_type='agent.execute'and occurred_at>now()-interval'1 hour')>=coalesce((pol.limits_json->>'hourly_cap')::int,30)then raise exception 'rate_limited';end if;
  if pol.approval_mode='always'or method='DELETE'or resource in('debt_payments','goal_allocations')or(resource='recurring_rules'and coalesce(payload->>'mode','auto-post')='auto-post')then
   insert into financegpt.agent_pending_actions(user_id,connection_id,operation,payload_hash,payload_json,idempotency_key)values(uid,conn.id,scope,md5(p::text),p,idempotency_key)returning *into pending;
   result:=jsonb_build_object('status','pending_approval','action_id',pending.id,'expires_at',pending.expires_at);
  else result:=finance_private.agent_execute(uid,conn,scope,p,idempotency_key);end if;
 else result:=jsonb_build_object('status','ok')||finance_private.managed_resource(uid,resource,method,payload,record_id);end if;
 insert into financegpt.idempotency_records(user_id,operation,key,request_hash,response_ref)values(uid,'managed:'||coalesce(client,'self'),idempotency_key,md5(p::text),result);
 return result;end $$;
-- Extend the trusted policy editor without changing the original checks.
do $$declare b text;begin
 select pg_get_functiondef('financegpt.save_agent_policy(uuid,jsonb,text)'::regprocedure)into b;
 b:=replace(b,'''recurring:write'')','''recurring:write'',''recurring:read'',''templates:read'',''templates:write'',''goals:read'',''goals:write'',''debts:read'',''debts:write'')');execute b;
end $$;
revoke all on function finance_private.managed_resource(uuid,text,text,jsonb,uuid),finance_private.check_managed_policy(financegpt.agent_connections,jsonb),finance_private.agent_execute(uuid,financegpt.agent_connections,text,jsonb,text),finance_private.agent_execute_legacy(uuid,financegpt.agent_connections,text,jsonb,text),financegpt.manage_resource(uuid,text,text,text,jsonb,uuid,text)from public,anon,authenticated;
grant execute on function financegpt.manage_resource(uuid,text,text,text,jsonb,uuid,text)to service_role;

-- Encrypted provider credentials and authoritative AI state are server-only.
create table financegpt.ai_providers(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),name text not null,format text not null check(format in('openai','anthropic','gemini')),base_url text not null,api_key_ciphertext text not null,model text default '',context_tokens integer not null default 16000 check(context_tokens between 4096 and 2000000),output_tokens integer not null default 2048 check(output_tokens between 256 and 32000),vision boolean not null default false,tools boolean not null default true,auto_record boolean not null default false,created_at timestamptz default now(),unique(id,user_id));
create table financegpt.ai_chats(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),provider_id uuid not null,title text not null default 'Chat baru',summary text not null default '',summary_through bigint not null default 0,busy_until timestamptz,created_at timestamptz default now(),foreign key(provider_id,user_id)references financegpt.ai_providers(id,user_id)on delete cascade);
create table financegpt.ai_messages(id bigint generated always as identity primary key,user_id uuid not null references auth.users(id),chat_id uuid not null references financegpt.ai_chats(id)on delete cascade,role text not null check(role in('user','assistant')),content text not null,request_key text,usage_json jsonb default '{}',created_at timestamptz default now());
create unique index ai_message_request on financegpt.ai_messages(user_id,chat_id,request_key,role)where request_key is not null;
create index ai_chat_messages on financegpt.ai_messages(user_id,chat_id,id);
create index ai_provider_owner on financegpt.ai_providers(user_id,id);
create index ai_chat_owner on financegpt.ai_chats(user_id,created_at desc);
create table financegpt.ai_actions(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),chat_id uuid not null references financegpt.ai_chats(id)on delete cascade,tool text not null,args jsonb not null,status text not null default 'pending'check(status in('pending','executed','rejected')),result jsonb,busy_until timestamptz,request_key text not null,created_at timestamptz default now(),unique(user_id,chat_id,request_key));
create table financegpt.ai_uploads(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),chat_id uuid not null references financegpt.ai_chats(id)on delete cascade,path text not null,sha256 text not null,created_at timestamptz default now(),unique(user_id,chat_id,path));
create index ai_upload_owner on financegpt.ai_uploads(user_id,chat_id);
create index ai_action_owner on financegpt.ai_actions(user_id,chat_id,created_at);
do $$declare t text;begin foreach t in array array['ai_providers','ai_chats','ai_messages','ai_actions','ai_uploads']loop
 execute format('alter table financegpt.%I enable row level security',t);
 execute format('revoke all on financegpt.%I from public,anon,authenticated',t);
 execute format('grant all on financegpt.%I to service_role',t);
 end loop;end $$;
grant usage,select on sequence financegpt.ai_messages_id_seq to service_role;
create function finance_private.managed_version()returns trigger language plpgsql set search_path='' as $$begin new.row_version:=old.row_version+1;return new;end $$;
do $$declare t text;b text;begin
 foreach t in array array['categories','transaction_templates','recurring_rules','savings_goals','goal_allocations','debts','debt_payments']loop
 execute format('create trigger managed_version before update on financegpt.%I for each row execute function finance_private.managed_version()',t);
 end loop;
 select pg_get_functiondef('financegpt.generate_personal_token(text,integer)'::regprocedure)into b;
 b:=replace(b,'''analytics:read'']','''analytics:read'',''templates:read'',''recurring:read'',''goals:read'',''debts:read'']');execute b;
end $$;
revoke all on function finance_private.managed_version()from public,anon,authenticated;
update storage.buckets set allowed_mime_types=array['image/jpeg','image/png','image/webp','application/pdf','text/plain','text/csv']where id='financegpt-private';
create unique index ai_receipt_once on financegpt.transactions(user_id,source_ref)where source_ref like 'ai-receipt:%'and reversal_of is null;
notify pgrst,'reload schema';
commit;
