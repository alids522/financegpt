-- Finance Tracker v1. All money is integer minor units (IDR exponent 0).
begin;
create schema if not exists financegpt;
create schema if not exists finance_private;
revoke all on schema finance_private from public;
grant usage on schema financegpt to authenticated, service_role;

create table financegpt.profiles (
 user_id uuid primary key references auth.users(id) on delete cascade,
 username_normalized text not null unique check(username_normalized ~ '^[a-z0-9_]{3,24}$'),
 display_name text not null, base_currency text not null default 'IDR', timezone text not null default 'Asia/Jakarta',
 theme text not null default 'system' check(theme in ('light','dark','system')),
 week_start int not null default 1 check(week_start between 1 and 7),
 status text not null default 'active' check(status in ('active','suspended')),
 must_change_password boolean not null default false, settings_json jsonb not null default '{}',
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table financegpt.user_roles(user_id uuid primary key references auth.users(id), role text not null check(role in ('user','admin')), created_by uuid, created_at timestamptz default now());
create table financegpt.accounts(
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id), name text not null check(length(name) between 1 and 100),
 type text not null default 'cash' check(type in ('cash','bank','ewallet','other')), currency text not null default 'IDR' check(currency ~ '^[A-Z]{3}$'),
 opening_balance bigint not null default 0, status text not null default 'active' check(status in ('active','archived')),
 color text default '#456D9A', allow_negative boolean default true, created_at timestamptz default now(), updated_at timestamptz default now(), unique(id,user_id)
);
create table financegpt.categories(
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id), name text not null,
 type text not null check(type in ('income','expense')), parent_id uuid, color text default '#456D9A', icon text default 'category',
 archived boolean default false, sort_order int default 0, default_budget bigint, created_at timestamptz default now(), updated_at timestamptz default now(),
 unique(id,user_id), foreign key(parent_id,user_id) references financegpt.categories(id,user_id), check(parent_id is distinct from id)
);
create table financegpt.transactions(
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id),
 type text not null check(type in ('expense','income','transfer','adjustment')), status text not null default 'posted' check(status in ('draft','pending','posted','voided')),
 account_id uuid not null, destination_account_id uuid, category_id uuid, amount bigint not null check(amount>0 and amount<=9000000000000000), currency text not null default 'IDR',
 effective_at timestamptz not null, merchant text default '', description text default '', notes text default '', tags text[] default '{}', custom_fields jsonb default '{}',
 source_ref text, source text not null default 'self', attachment_path text, reversal_of uuid, row_version int not null default 1,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(id,user_id),
 foreign key(account_id,user_id) references financegpt.accounts(id,user_id), foreign key(destination_account_id,user_id) references financegpt.accounts(id,user_id),
 foreign key(category_id,user_id) references financegpt.categories(id,user_id), foreign key(reversal_of,user_id) references financegpt.transactions(id,user_id),
 check(type <> 'transfer' or (destination_account_id is not null and destination_account_id<>account_id)), check(type in ('transfer','adjustment') or category_id is not null)
);
create index transactions_period on financegpt.transactions(user_id,effective_at desc,id);
create index transactions_category on financegpt.transactions(user_id,category_id,effective_at);
create index transactions_status on financegpt.transactions(user_id,status);
create table financegpt.transaction_splits(id uuid primary key default gen_random_uuid(), user_id uuid not null, transaction_id uuid not null, category_id uuid not null, amount bigint not null check(amount>0), foreign key(transaction_id,user_id) references financegpt.transactions(id,user_id),foreign key(category_id,user_id) references financegpt.categories(id,user_id));
create table financegpt.journal_entries(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),transaction_id uuid,posted_at timestamptz not null default now(),status text not null default 'posted',reversal_of uuid references financegpt.journal_entries(id),created_at timestamptz default now(),unique(id,user_id));
create table financegpt.journal_lines(id uuid primary key default gen_random_uuid(),user_id uuid not null,entry_id uuid not null,ledger_account_id uuid,offset_code text,amount_signed bigint not null,currency text not null,foreign key(entry_id,user_id) references financegpt.journal_entries(id,user_id),foreign key(ledger_account_id,user_id) references financegpt.accounts(id,user_id),check(ledger_account_id is not null or offset_code is not null));
create index journal_account on financegpt.journal_lines(user_id,ledger_account_id);
create table financegpt.transaction_templates(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),name text not null,payload_json jsonb not null default '{}',favourite boolean default false,sort_order int default 0,created_at timestamptz default now(),updated_at timestamptz default now());
create table financegpt.custom_field_definitions(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),entity_type text default 'transaction',field_key text not null,field_type text not null check(field_type in ('text','number','date','boolean','enum')),options_json jsonb default '{}',required boolean default false,unique(user_id,field_key));
create table financegpt.custom_field_values(id uuid primary key default gen_random_uuid(),transaction_id uuid references financegpt.transactions(id),field_definition_id uuid references financegpt.custom_field_definitions(id),value_json jsonb,user_id uuid not null references auth.users(id));
create table financegpt.tags(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),name text not null,unique(user_id,name));
create table financegpt.transaction_tags(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),transaction_id uuid references financegpt.transactions(id),tag_id uuid references financegpt.tags(id));
create table financegpt.budgets(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),name text not null,category_id uuid,account_id uuid,amount bigint not null check(amount>0),currency text default 'IDR',cadence text default 'monthly',rollover text default 'none',period_start date not null,period_end date not null,alerts_json jsonb default '[50,75,90,100]',row_version int default 1,created_at timestamptz default now(),updated_at timestamptz default now(),unique(id,user_id),foreign key(category_id,user_id) references financegpt.categories(id,user_id),foreign key(account_id,user_id) references financegpt.accounts(id,user_id),check(period_end>=period_start));
create table financegpt.budget_periods(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),budget_id uuid not null references financegpt.budgets(id),start_at date,end_at date,planned_amount bigint,version int default 1);
create table financegpt.forecast_runs(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),period jsonb,method text,model_version text default 'v1',assumptions_json jsonb,totals_json jsonb,created_at timestamptz default now());
create table financegpt.forecast_points(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),run_id uuid references financegpt.forecast_runs(id),date date,actual_amount bigint,predicted_amount bigint,lower bigint,upper bigint);
create table financegpt.forecast_scenarios(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),base_run_id uuid references financegpt.forecast_runs(id),changes_json jsonb,result_json jsonb,created_at timestamptz default now());
create table financegpt.recurring_rules(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),name text not null,next_at timestamptz not null,cadence text not null default 'monthly' check(cadence in ('daily','weekly','monthly','yearly')),payload_json jsonb not null,mode text default 'pending' check(mode in ('draft','pending','auto-post')),active boolean default true,end_at timestamptz,created_at timestamptz default now());
create table financegpt.savings_goals(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),name text not null,target_amount bigint not null check(target_amount>0),target_date date not null,account_id uuid,currency text default 'IDR',created_at timestamptz default now(),unique(id,user_id),foreign key(account_id,user_id) references financegpt.accounts(id,user_id));
create table financegpt.goal_allocations(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),goal_id uuid not null,amount bigint not null check(amount>0),notes text default '',created_at timestamptz default now(),foreign key(goal_id,user_id) references financegpt.savings_goals(id,user_id));
create table financegpt.debts(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),name text not null,counterparty text not null,kind text default 'debt' check(kind in ('debt','receivable')),principal bigint not null check(principal>0),rate numeric default 0,due date not null,currency text default 'IDR',created_at timestamptz default now(),unique(id,user_id));
create table financegpt.debt_payments(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),debt_id uuid not null,transaction_id uuid,principal_paid bigint not null check(principal_paid>0),interest_paid bigint default 0,created_at timestamptz default now(),foreign key(debt_id,user_id) references financegpt.debts(id,user_id),foreign key(transaction_id,user_id) references financegpt.transactions(id,user_id));
create table financegpt.import_jobs(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),format text,status text default 'needs_review',mapping_json jsonb,source_ref text,totals_json jsonb,created_at timestamptz default now());
create table financegpt.import_rows(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),job_id uuid references financegpt.import_jobs(id),line_no int,normalized_json jsonb,confidence numeric,disposition text,error_code text);
create table financegpt.export_jobs(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),type text,format text,filter_snapshot jsonb,status text default 'pending',output_path text,expires_at timestamptz,created_at timestamptz default now());
create table financegpt.agent_connections(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),oauth_client_id text not null,display_name text not null,status text not null default 'active' check(status in ('active','paused','revoked')),connected_at timestamptz default now(),revoked_at timestamptz,unique(user_id,oauth_client_id));
create table financegpt.agent_permissions(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),connection_id uuid not null references financegpt.agent_connections(id),permission text not null,enabled boolean not null default false,updated_at timestamptz default now(),unique(connection_id,permission));
create table financegpt.agent_policies(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),connection_id uuid not null unique references financegpt.agent_connections(id),limits_json jsonb default '{"create_limit":1000000,"edit_limit":250000,"daily_cap":5000000,"hourly_cap":30}',account_allowlist uuid[] default '{}',category_allowlist uuid[] default '{}',approval_mode text default 'risk');
create table financegpt.agent_pending_actions(id uuid primary key default gen_random_uuid(),connection_id uuid not null references financegpt.agent_connections(id),user_id uuid not null references auth.users(id),operation text not null,payload_hash text not null,payload_json jsonb not null,idempotency_key text not null,expected_version int,expires_at timestamptz not null default now()+interval '10 minutes',status text not null default 'pending',created_at timestamptz default now(),unique(connection_id,idempotency_key));
create table financegpt.agent_executions(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),connection_id uuid references financegpt.agent_connections(id),action_id uuid unique references financegpt.agent_pending_actions(id),idempotency_key text,execution_result jsonb,executed_at timestamptz default now(),unique(connection_id,idempotency_key));
create table financegpt.agent_audit_logs(id uuid primary key default gen_random_uuid(),connection_id uuid references financegpt.agent_connections(id),user_id uuid not null references auth.users(id),event_type text not null,tool text,actor text not null default 'self',safe_diff_json jsonb,outcome text,request_id text,occurred_at timestamptz default now());
create table financegpt.admin_audit_logs(id uuid primary key default gen_random_uuid(),admin_user_id uuid not null references auth.users(id),target_user_id uuid references auth.users(id),action text not null,reason text not null,result jsonb,timestamp timestamptz default now());
create table financegpt.idempotency_records(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),operation text not null,key text not null,request_hash text not null,response_ref jsonb,expires_at timestamptz default now()+interval '365 days',unique(user_id,operation,key));

create function finance_private.trusted(uid uuid) returns boolean language sql stable security definer set search_path='' as $$
 select uid=(select auth.uid()) and (select auth.jwt()->>'client_id') is null and exists(select 1 from financegpt.profiles p where p.user_id=uid and p.status='active')
 and exists(select 1 from auth.sessions s where s.id=nullif(auth.jwt()->>'session_id','')::uuid and s.user_id=uid)
$$;
grant usage on schema finance_private to authenticated;
grant execute on function finance_private.trusted(uuid) to authenticated;
do $$ declare t text; begin
 for t in select tablename from pg_tables where schemaname='financegpt' loop
  execute format('alter table financegpt.%I enable row level security',t);
  if t not in ('user_roles','admin_audit_logs') then
   execute format('create policy owned_read on financegpt.%I for select to authenticated using(finance_private.trusted(user_id))',t);
  end if;
  if t in ('categories','transaction_templates','custom_field_definitions','tags','budgets','forecast_runs','forecast_scenarios','recurring_rules','savings_goals','goal_allocations','debts','debt_payments','import_jobs','import_rows','export_jobs','agent_connections','agent_permissions','agent_policies') then
   execute format('create policy owned_insert on financegpt.%I for insert to authenticated with check(finance_private.trusted(user_id))',t);
   execute format('create policy owned_update on financegpt.%I for update to authenticated using(finance_private.trusted(user_id)) with check(finance_private.trusted(user_id))',t);
   execute format('grant insert,update on financegpt.%I to authenticated',t);
  end if;
  execute format('grant select on financegpt.%I to authenticated',t);
 end loop;
end $$;
create policy own_role on financegpt.user_roles for select to authenticated using(finance_private.trusted(user_id));
create policy profile_update on financegpt.profiles for update to authenticated using(finance_private.trusted(user_id)) with check(finance_private.trusted(user_id));
grant update(display_name,base_currency,timezone,theme,week_start,settings_json) on financegpt.profiles to authenticated;
create policy account_update on financegpt.accounts for update to authenticated using(finance_private.trusted(user_id)) with check(finance_private.trusted(user_id));
grant update(name,color,status,allow_negative) on financegpt.accounts to authenticated;
create view financegpt.account_balances with (security_invoker=true) as select a.*, coalesce((select sum(l.amount_signed) from financegpt.journal_lines l where l.ledger_account_id=a.id and l.user_id=a.user_id),0)::bigint balance from financegpt.accounts a;
grant select on financegpt.account_balances to authenticated;

create function finance_private.balanced() returns trigger language plpgsql set search_path='' as $$ begin
 if exists(select 1 from financegpt.journal_lines where entry_id=new.entry_id group by currency having sum(amount_signed)<>0) then raise exception 'Unbalanced journal'; end if;
 return new; end $$;
create constraint trigger check_balance after insert or update on financegpt.journal_lines deferrable initially deferred for each row execute function finance_private.balanced();
create function finance_private.category_depth() returns trigger language plpgsql set search_path='' as $$ begin
 if new.parent_id is not null and exists(select 1 from financegpt.categories where id=new.parent_id and (parent_id is not null or type<>new.type)) then raise exception 'Category supports two levels of the same type'; end if;
 if new.parent_id is not null and exists(select 1 from financegpt.categories where parent_id=new.id) then raise exception 'Move child categories first'; end if;
 return new; end $$;
create trigger category_depth before insert or update on financegpt.categories for each row execute function finance_private.category_depth();

create function financegpt.initialize_profile() returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); u auth.users; un text; begin
 if uid is null or auth.jwt()->>'client_id' is not null then raise exception 'Authentication required'; end if;
 if exists(select 1 from financegpt.profiles where user_id=uid) then return '{}'::jsonb; end if;
 select * into u from auth.users where id=uid;
 un:=lower(u.raw_user_meta_data->>'username');
 if un is null or un!~'^[a-z0-9_]{3,24}$' then raise exception 'Invalid username'; end if;
 insert into financegpt.profiles(user_id,username_normalized,display_name) values(uid,un,un);
 insert into financegpt.user_roles(user_id,role) values(uid,'user');
 insert into financegpt.categories(user_id,name,type,sort_order)
 select uid,x.name,x.type,x.ord from (values ('Gaji & Bonus','income',0),('Freelance','income',1),('Bisnis','income',2),('Hadiah','income',3),('Lainnya','income',4),('Makanan & Minuman','expense',5),('Belanja Harian','expense',6),('Transportasi','expense',7),('Tempat Tinggal','expense',8),('Tagihan','expense',9),('Belanja','expense',10),('Kesehatan','expense',11),('Keluarga & Pendidikan','expense',12),('Hiburan','expense',13),('Langganan','expense',14),('Biaya Admin','expense',15),('Lainnya','expense',16))x(name,type,ord);
 return '{}'::jsonb; end $$;
-- Enforce username uniqueness during signup, before creating an Auth user.
create function finance_private.signup_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare un text:=lower(new.raw_user_meta_data->>'username'); begin
 -- Other applications share this Supabase instance. Only guard finance registrations.
 if new.raw_user_meta_data->>'app'='financegpt' then
  if un is null or un!~'^[a-z0-9_]{3,24}$' then raise exception 'Invalid username'; end if;
  perform pg_advisory_xact_lock(hashtextextended('finance-username:'||un,0));
  if exists(select 1 from financegpt.profiles where username_normalized=un) or exists(select 1 from auth.users where lower(raw_user_meta_data->>'username')=un and raw_user_meta_data->>'app'='financegpt') then raise exception 'Username unavailable'; end if;
 end if; return new; end $$;
create trigger finance_signup_guard before insert on auth.users for each row execute function finance_private.signup_guard();

create function financegpt.create_account(payload jsonb, idempotency_key text) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); aid uuid; eid uuid; old financegpt.idempotency_records; result jsonb; opening bigint:=coalesce((payload->>'opening_balance')::bigint,0); begin
 if not finance_private.trusted(uid) then raise exception 'Access denied'; end if;
 if length(idempotency_key)<8 then raise exception 'Idempotency key required'; end if;
 perform pg_advisory_xact_lock(hashtextextended(uid||':account:'||idempotency_key,0));
 select * into old from financegpt.idempotency_records where user_id=uid and operation='account' and key=idempotency_key;
 if found then if old.request_hash<>md5(payload::text) then raise exception 'Idempotency payload conflict'; end if; return old.response_ref; end if;
 insert into financegpt.accounts(user_id,name,type,currency,opening_balance) values(uid,payload->>'name',coalesce(payload->>'type','cash'),coalesce(payload->>'currency','IDR'),opening) returning id into aid;
 insert into financegpt.journal_entries(user_id) values(uid) returning id into eid;
 insert into financegpt.journal_lines(user_id,entry_id,ledger_account_id,amount_signed,currency) values(uid,eid,aid,opening,coalesce(payload->>'currency','IDR'));
 insert into financegpt.journal_lines(user_id,entry_id,offset_code,amount_signed,currency) values(uid,eid,'opening_equity',-opening,coalesce(payload->>'currency','IDR'));
 result:=jsonb_build_object('id',aid);
 insert into financegpt.idempotency_records(user_id,operation,key,request_hash,response_ref) values(uid,'account',idempotency_key,md5(payload::text),result);
 return result; end $$;

create function finance_private.post_transaction(uid uuid,p jsonb,idem text,actor text default 'self') returns jsonb language plpgsql security definer set search_path='' as $$
declare old financegpt.transactions; t financegpt.transactions; cached financegpt.idempotency_records; aid uuid; eid uuid; prev uuid; signed bigint; result jsonb; a financegpt.accounts; dest financegpt.accounts; split jsonb; begin
 if not exists(select 1 from financegpt.profiles where user_id=uid and status='active' and (not must_change_password or actor='admin')) then raise exception 'Account inactive or password change required'; end if;
 if length(idem)<8 or length(idem)>200 then raise exception 'Idempotency key required'; end if;
 perform pg_advisory_xact_lock(hashtextextended(uid||':transaction:'||idem,0));
 select * into cached from financegpt.idempotency_records where user_id=uid and operation='transaction' and key=idem;
 if found then if cached.request_hash<>md5(p::text) then raise exception 'Idempotency payload conflict'; end if; return cached.response_ref; end if;
 if p->>'id' is not null then
  select * into old from financegpt.transactions where id=(p->>'id')::uuid and user_id=uid for update;
  if not found then raise exception 'Transaction not found'; end if;
  if (p->>'expected_version')::int is distinct from old.row_version then raise exception 'Conflict: transaction changed on another device'; end if;
 end if;
 select * into a from financegpt.accounts where id=(p->>'account_id')::uuid and user_id=uid for update;
 if not found or a.status<>'active' then raise exception 'Account unavailable'; end if;
 if a.currency<>p->>'currency' then raise exception 'Account currency mismatch'; end if;
 if p->>'type'='transfer' then
  select * into dest from financegpt.accounts where id=(p->>'destination_account_id')::uuid and user_id=uid for update;
  if not found or dest.status<>'active' or dest.currency<>a.currency or dest.id=a.id then raise exception 'Transfer requires different active accounts with the same currency'; end if;
 end if;
 if p->>'type' in ('expense','income') and not exists(select 1 from financegpt.categories where id=(p->>'category_id')::uuid and user_id=uid and type=p->>'type' and not archived) then raise exception 'Category unavailable'; end if;
 if p->>'type'='adjustment' and length(coalesce(p->>'notes',''))<3 then raise exception 'Adjustment reason required'; end if;
 if p->>'reversal_of' is not null and not exists(select 1 from financegpt.transactions where id=(p->>'reversal_of')::uuid and user_id=uid and type=p->>'type' and status='posted') then raise exception 'Invalid refund source'; end if;
 if old.id is not null then
  select id into prev from financegpt.journal_entries where transaction_id=old.id and reversal_of is null order by created_at desc limit 1;
  if prev is not null and old.status='posted' then
   insert into financegpt.journal_entries(user_id,transaction_id,reversal_of) values(uid,old.id,prev) returning id into eid;
   insert into financegpt.journal_lines(user_id,entry_id,ledger_account_id,offset_code,amount_signed,currency) select uid,eid,ledger_account_id,offset_code,-amount_signed,currency from financegpt.journal_lines where entry_id=prev;
  end if;
  update financegpt.transactions set type=p->>'type',status=coalesce(p->>'status','posted'),account_id=a.id,destination_account_id=nullif(p->>'destination_account_id','')::uuid,category_id=nullif(p->>'category_id','')::uuid,amount=(p->>'amount')::bigint,currency=a.currency,effective_at=(p->>'effective_at')::timestamptz,merchant=coalesce(p->>'merchant',''),description=coalesce(p->>'description',''),notes=coalesce(p->>'notes',''),tags=array(select jsonb_array_elements_text(coalesce(p->'tags','[]'))),custom_fields=coalesce(p->'custom_fields','{}'),attachment_path=p->>'attachment_path',source_ref=p->>'source_ref',row_version=row_version+1,updated_at=now() where id=old.id returning * into t;
  delete from financegpt.transaction_splits where transaction_id=t.id;
 else
  insert into financegpt.transactions(user_id,type,status,account_id,destination_account_id,category_id,amount,currency,effective_at,merchant,description,notes,tags,custom_fields,source_ref,source,attachment_path,reversal_of)
  values(uid,p->>'type',coalesce(p->>'status','posted'),a.id,nullif(p->>'destination_account_id','')::uuid,nullif(p->>'category_id','')::uuid,(p->>'amount')::bigint,a.currency,(p->>'effective_at')::timestamptz,coalesce(p->>'merchant',''),coalesce(p->>'description',''),coalesce(p->>'notes',''),array(select jsonb_array_elements_text(coalesce(p->'tags','[]'))),coalesce(p->'custom_fields','{}'),p->>'source_ref',actor,p->>'attachment_path',nullif(p->>'reversal_of','')::uuid) returning * into t;
 end if;
 if jsonb_array_length(coalesce(p->'splits','[]'))>0 then
  if (select sum((x->>'amount')::bigint) from jsonb_array_elements(p->'splits')x)<>t.amount then raise exception 'Split total must equal transaction amount'; end if;
  for split in select * from jsonb_array_elements(p->'splits') loop
   insert into financegpt.transaction_splits(user_id,transaction_id,category_id,amount) values(uid,t.id,(split->>'category_id')::uuid,(split->>'amount')::bigint);
  end loop;
 end if;
 if t.status='posted' then
  signed:=case when t.type in ('income','adjustment') then t.amount else -t.amount end;
  if t.reversal_of is not null then signed:=-signed; end if;
  insert into financegpt.journal_entries(user_id,transaction_id,posted_at) values(uid,t.id,t.effective_at) returning id into eid;
  insert into financegpt.journal_lines(user_id,entry_id,ledger_account_id,amount_signed,currency) values(uid,eid,t.account_id,signed,t.currency);
  insert into financegpt.journal_lines(user_id,entry_id,ledger_account_id,offset_code,amount_signed,currency) values(uid,eid,case when t.type='transfer' then t.destination_account_id else null end,case when t.type='transfer' then null else t.type end,-signed,t.currency);
  if not a.allow_negative and (select sum(amount_signed) from financegpt.journal_lines where ledger_account_id=a.id)<0 then raise exception 'Insufficient balance'; end if;
 end if;
 insert into financegpt.agent_audit_logs(user_id,event_type,actor,safe_diff_json,outcome) values(uid,case when old.id is null then 'transaction.create' else 'transaction.update' end,actor,jsonb_build_object('id',t.id,'before_amount',old.amount,'after_amount',t.amount,'version',t.row_version),'ok');
 result:=to_jsonb(t);
 insert into financegpt.idempotency_records(user_id,operation,key,request_hash,response_ref) values(uid,'transaction',idem,md5(p::text),result);
 return result;
end $$;
create function financegpt.save_transaction(payload jsonb,idempotency_key text) returns jsonb language plpgsql security definer set search_path='' as $$ begin
 if not finance_private.trusted(auth.uid()) then raise exception 'Access denied'; end if;
 return finance_private.post_transaction(auth.uid(),payload,idempotency_key,'self'); end $$;
create function financegpt.confirm_import(payloads jsonb,idempotency_key text) returns jsonb language plpgsql security definer set search_path='' as $$
declare p jsonb; i int:=0; results jsonb:='[]'; begin
 if not finance_private.trusted(auth.uid()) or jsonb_array_length(payloads)>1000 then raise exception 'Access denied or import too large'; end if;
 for p in select * from jsonb_array_elements(payloads) loop
  results:=results||jsonb_build_array(finance_private.post_transaction(auth.uid(),p,idempotency_key||':'||i,'import')); i:=i+1;
 end loop; return results; end $$;

-- All privileged helpers are private; every exposed RPC checks its actor explicitly.
revoke all on all functions in schema finance_private from public,anon,authenticated;
grant execute on function finance_private.trusted(uuid) to authenticated;
revoke all on all functions in schema financegpt from public,anon,authenticated;
grant execute on function financegpt.initialize_profile(),financegpt.create_account(jsonb,text),financegpt.save_transaction(jsonb,text),financegpt.confirm_import(jsonb,text) to authenticated;
grant all on all tables in schema financegpt to service_role;
grant execute on all functions in schema financegpt to service_role;
-- A private bucket with ownership paths, never public URLs.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('financegpt-private','financegpt-private',false,10485760,array['application/pdf','text/csv','image/jpeg','image/png']) on conflict(id) do nothing;
create policy finance_files_read on storage.objects for select to authenticated using(bucket_id='financegpt-private' and (storage.foldername(name))[1]=auth.uid()::text and finance_private.trusted(auth.uid()));
create policy finance_files_insert on storage.objects for insert to authenticated with check(bucket_id='financegpt-private' and (storage.foldername(name))[1]=auth.uid()::text and finance_private.trusted(auth.uid()));
create policy finance_files_delete on storage.objects for delete to authenticated using(bucket_id='financegpt-private' and (storage.foldername(name))[1]=auth.uid()::text and finance_private.trusted(auth.uid()));
notify pgrst,'reload schema';
commit;
