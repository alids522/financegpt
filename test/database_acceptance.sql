-- Run as postgres on a disposable database or through an authorized server session.
-- All fixture users, sessions, journals and settings are rolled back.
begin;
do $$
declare a uuid:=gen_random_uuid();b uuid:=gen_random_uuid();sa uuid:=gen_random_uuid();sb uuid:=gen_random_uuid();cash uuid;bank uuid;foreign_account uuid;cat uuid;cat2 uuid;key text:=gen_random_uuid()::text;p jsonb;t jsonb;pending jsonb;edited jsonb;split_tx jsonb;budget jsonb;v bigint;count_before int;failed boolean;claims jsonb;
begin
 insert into auth.users(id,email,encrypted_password,raw_user_meta_data)values(a,'sql-qa-'||a||'@example.com','fixture',jsonb_build_object('app','financegpt','username','sqlqa_'||left(a::text,8))),(b,'sql-qa-'||b||'@example.com','fixture',jsonb_build_object('app','financegpt','username','sqlqa_'||left(b::text,8)));
 insert into auth.sessions(id,user_id,created_at,updated_at)values(sa,a,now(),now()),(sb,b,now(),now());
 claims:=jsonb_build_object('sub',a,'role','authenticated','aud','authenticated','session_id',sa);perform set_config('request.jwt.claims',claims::text,true);
 execute 'set local role authenticated';
 perform financegpt.initialize_profile();cash:=(financegpt.create_account('{"name":"QA Cash","currency":"IDR","opening_balance":1000000}',gen_random_uuid()::text)->>'id')::uuid;bank:=(financegpt.create_account('{"name":"QA Bank","currency":"IDR","opening_balance":0}',gen_random_uuid()::text)->>'id')::uuid;
 select id into cat from financegpt.categories where user_id=a and type='expense'limit 1;
 p:=jsonb_build_object('type','expense','amount',35000,'currency','IDR','account_id',cash,'category_id',cat,'effective_at',now(),'description','QA lunch');
 t:=financegpt.save_transaction(p,key);assert(financegpt.save_transaction(p,key)->>'id')=t->>'id','Idempotent retry duplicated transaction';
 select balance into v from financegpt.account_balances where id=cash;assert v=965000,'Expense balance mismatch';
 failed:=false;begin perform financegpt.save_transaction(p||'{"amount":36000}',key);exception when others then failed:=true;end;assert failed,'Changed idempotency payload accepted';
 perform financegpt.save_transaction(jsonb_build_object('type','transfer','amount',100000,'currency','IDR','account_id',cash,'destination_account_id',bank,'effective_at',now()),gen_random_uuid()::text);
 select sum(balance)into v from financegpt.account_balances where user_id=a;assert v=965000,'Transfer changed net assets';
 pending:=financegpt.save_transaction(p||'{"status":"pending","amount":15000}',gen_random_uuid()::text);
 select sum(balance)into v from financegpt.account_balances where user_id=a;assert v=965000,'Pending affected actual';
 perform financegpt.save_transaction(pending||jsonb_build_object('status','posted','expected_version',1),gen_random_uuid()::text);
 edited:=financegpt.save_transaction(t||'{"amount":40000,"expected_version":1}',gen_random_uuid()::text);
 perform financegpt.save_transaction(p||jsonb_build_object('amount',10000,'reversal_of',t->>'id'),gen_random_uuid()::text);
 select sum(balance)into v from financegpt.account_balances where user_id=a;assert v=955000,'Edit/refund balance mismatch';
 select count(*)into count_before from financegpt.transactions;
 failed:=false;begin perform financegpt.save_transaction(p||jsonb_build_object('splits',jsonb_build_array(jsonb_build_object('category_id',cat,'amount',1))),gen_random_uuid()::text);exception when others then failed:=true;end;assert failed,'Invalid split accepted';assert(select count(*)from financegpt.transactions)=count_before,'Failed split was not rolled back';
 cat2:=(financegpt.save_resource('categories','{"name":"QA split category","type":"expense"}',gen_random_uuid()::text)->>'id')::uuid;
 split_tx:=financegpt.save_transaction(p||jsonb_build_object('amount',50000,'splits',jsonb_build_array(jsonb_build_object('category_id',cat,'amount',20000),jsonb_build_object('category_id',cat2,'amount',30000))),gen_random_uuid()::text);
 perform financegpt.save_transaction(split_tx||jsonb_build_object('expected_version',1,'description','Keep split history'),gen_random_uuid()::text);
 assert(select count(*)from financegpt.transaction_splits where transaction_id=(split_tx->>'id')::uuid)=2,'Edit silently removed splits';
 budget:=financegpt.save_resource('budgets',jsonb_build_object('name','QA Budget','amount',100000,'currency','IDR','category_id',cat,'period_start',current_date-1,'period_end',current_date+1),gen_random_uuid()::text);
 perform financegpt.save_resource('budgets','{"amount":200000}',gen_random_uuid()::text,(budget->>'id')::uuid,1);
 failed:=false;begin perform financegpt.save_resource('budgets','{"amount":300000}',gen_random_uuid()::text,(budget->>'id')::uuid,1);exception when others then failed:=true;end;assert failed,'Stale budget version accepted';
 perform financegpt.reconcile_account(jsonb_build_object('account_id',cash,'statement_balance',700000,'reason','QA statement reconciliation'),gen_random_uuid()::text);
 select balance into v from financegpt.account_balances where id=cash;assert v=700000,'Reconciliation did not reach target';
 failed:=false;begin update financegpt.transactions set amount=1 where id=(t->>'id')::uuid;exception when insufficient_privilege then failed:=true;end;assert failed,'Direct financial update bypassed ledger';
 perform set_config('request.jwt.claims',(claims||jsonb_build_object('client_id','test-oauth-client'))::text,true);assert(select count(*)from financegpt.transactions)=0,'OAuth token bypassed service policy';
 failed:=false;begin perform financegpt.resolve_approval(gen_random_uuid(),true);exception when others then failed:=true;end;assert failed,'OAuth self-approval accepted';
 perform set_config('request.jwt.claims',jsonb_build_object('sub',b,'role','authenticated','aud','authenticated','session_id',sb)::text,true);perform financegpt.initialize_profile();assert(select count(*)from financegpt.transactions where user_id=a)=0,'User B could read user A';
 failed:=false;begin perform financegpt.save_transaction(p,gen_random_uuid()::text);exception when others then failed:=true;end;assert failed,'Cross-user account write accepted';
 execute 'reset role';
 select (x->>'actual_minor')::bigint into v from jsonb_array_elements(financegpt.budget_actuals(a))x where x->>'id'=budget->>'id';assert v=65000,'Budget actual ignored refunds or split allocations';
 assert not exists(select 1 from financegpt.journal_lines where user_id=a group by entry_id,currency having sum(amount_signed)<>0),'Unbalanced journal';
 delete from auth.sessions where id=sa;perform set_config('request.jwt.claims',claims::text,true);execute 'set local role authenticated';assert(select count(*)from financegpt.profiles where user_id=a)=0,'Revoked session retained data access';execute 'reset role';
 assert('2026-10-31 17:00:00+00'::timestamptz at time zone 'Asia/Jakarta')::date='2026-11-01'::date,'Jakarta month boundary incorrect';
 raise notice 'PASS: ledger, idempotency, transfer, pending, refund, split, budget version, reconciliation, RLS, OAuth bypass, revoke and timezone acceptance';
end $$;
rollback;
