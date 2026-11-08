-- Authorized owner only. All fixtures roll back.
begin;
do $$
declare uid uuid:=gen_random_uuid();sid uuid:=gen_random_uuid();cash uuid;bank uuid;cat uuid;other_cat uuid;conn uuid:=gen_random_uuid();tx jsonb;pending jsonb;p jsonb;failed boolean;result jsonb;begin
 insert into auth.users(id,email,encrypted_password,raw_user_meta_data)values(uid,'policy-'||uid||'@example.com','fixture',jsonb_build_object('app','financegpt','username','policy_'||left(uid::text,8)));
 insert into auth.sessions(id,user_id,created_at,updated_at)values(sid,uid,now(),now());
 perform set_config('request.jwt.claims',jsonb_build_object('sub',uid,'role','authenticated','session_id',sid)::text,true);
 execute 'set local role authenticated';perform financegpt.initialize_profile();
 cash:=(financegpt.create_account('{"name":"Policy cash","opening_balance":1000000}',gen_random_uuid()::text)->>'id')::uuid;
 bank:=(financegpt.create_account('{"name":"Policy bank"}',gen_random_uuid()::text)->>'id')::uuid;
 select id into cat from financegpt.categories where user_id=uid and type='expense'limit 1;
 select id into other_cat from financegpt.categories where user_id=uid and type='expense'and id<>cat limit 1;
 insert into financegpt.agent_connections(id,user_id,oauth_client_id,display_name)values(conn,uid,'policy-qa-client','Policy fixture');
 p:=jsonb_build_object('permissions',jsonb_build_object('transactions:create',true,'analytics:read',true),'limits','{"daily_cap":5000000,"hourly_cap":30}'::jsonb,'account_allowlist',jsonb_build_array(cash,bank),'category_allowlist',jsonb_build_array(cat));
 perform financegpt.save_agent_policy(conn,p,gen_random_uuid()::text);
 failed:=false;begin perform financegpt.save_agent_policy(conn,p||'{"permissions":{"transactions:create":false},"limits":{"daily_cap":-1}}',gen_random_uuid()::text);exception when others then failed:=true;end;
 assert failed,'Invalid policy accepted';assert(select enabled from financegpt.agent_permissions where connection_id=conn and permission='transactions:create'),'Failed policy partially changed permission';
 tx:=jsonb_build_object('type','expense','amount',5000,'currency','IDR','account_id',cash,'category_id',cat,'effective_at',now(),'splits',jsonb_build_array(jsonb_build_object('category_id',cat,'amount',2000),jsonb_build_object('category_id',other_cat,'amount',3000)));
 perform financegpt.save_transaction(tx,gen_random_uuid()::text);
 execute 'reset role';
 failed:=false;begin perform financegpt.agent_mutate(uid,'policy-qa-client','transactions:create',tx,gen_random_uuid()::text);exception when others then failed:=true;end;assert failed,'Agent created disallowed split';
 result:=financegpt.analytics_data(uid,now()-interval'1 day',now()+interval'1 day','IDR','{}',array[cat]);assert(result->>'expense_minor')::bigint=0,'Restricted analytics leaked split';
 result:=financegpt.forecast_data(uid,now()-interval'1 day',now()+interval'1 day','IDR','run_rate','{}',array[cat]);assert(result->>'actual_minor')::bigint=0,'Restricted forecast leaked split';
 pending:=financegpt.agent_mutate(uid,'policy-qa-client','transactions:create',jsonb_build_object('type','transfer','amount',10000,'currency','IDR','account_id',cash,'destination_account_id',bank,'effective_at',now()),gen_random_uuid()::text);
 assert pending->>'status'='pending_approval','Transfer did not require approval';
 execute 'set local role authenticated';perform financegpt.save_agent_policy(conn,p||jsonb_build_object('account_allowlist',jsonb_build_array(cash)),gen_random_uuid()::text);
 failed:=false;begin perform financegpt.resolve_approval((pending->>'action_id')::uuid,true);exception when others then failed:=true;end;assert failed,'Approval ignored changed destination policy';
 execute 'reset role';
 raise notice 'PASS: atomic policy, split write restrictions, scoped analytics/forecast, policy recheck at approval';
end $$;
rollback;
