-- Finance Tracker fresh installation. No credentials.
begin;

-- Source: core.sql
-- Finance Tracker v1. All money is integer minor units (IDR exponent 0).
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

-- Source: security.sql
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

-- Source: shared_auth.sql
-- Optional compatibility for this shared self-hosted instance.
-- Preserve the existing invitation-only policy for the other applications.
do $$ declare definition text;begin
 if to_regprocedure('private.on_signup()') is not null then
  select pg_get_functiondef('private.on_signup()'::regprocedure) into definition;
  if position('financegpt' in definition)=0 then
   definition:=regexp_replace(definition,'(?i)begin',E'begin\n  if new.raw_user_meta_data->>''app'' = ''financegpt'' then return new; end if;');
   execute definition;
  end if;
 end if;
 if to_regprocedure('public.handle_new_wa_user()') is not null then
  drop trigger if exists on_auth_user_created on auth.users;
  create trigger on_auth_user_created after insert on auth.users for each row when(coalesce(new.raw_user_meta_data->>'app','')<>'financegpt') execute function public.handle_new_wa_user();
 end if;
end $$;

-- Source: oauth.sql
-- This hook leaves other applications' claims unchanged. Finance OAuth tokens
-- are bound to the exact MCP resource and cannot use direct Data API policies.
create function finance_private.custom_access_token_hook(event jsonb) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare claims jsonb:=event->'claims';client text:=coalesce(event->>'client_id',event->'claims'->>'client_id');begin
 if client is not null and exists(select 1 from auth.oauth_clients where id::text=client and client_uri='https://supabase.adoetz52.my.id/functions/v1/finance-api/mcp' and deleted_at is null) then
  claims:=jsonb_set(claims,'{aud}','"https://supabase.adoetz52.my.id/functions/v1/finance-api/mcp"');
  return jsonb_set(event,'{claims}',claims);
 end if;return event;end $$;
grant usage on schema finance_private to supabase_auth_admin;
revoke all on function finance_private.custom_access_token_hook(jsonb) from public,anon,authenticated;
grant execute on function finance_private.custom_access_token_hook(jsonb) to supabase_auth_admin;

-- Source: hardening.sql
-- A forced password change blocks access to data as well as financial writes.
create or replace function finance_private.trusted(uid uuid) returns boolean language sql stable security definer set search_path='' as $$
 select uid=(select auth.uid()) and (select auth.jwt()->>'client_id') is null and exists(select 1 from financegpt.profiles p where p.user_id=uid and p.status='active' and not p.must_change_password)
 and exists(select 1 from auth.sessions s where s.id=nullif(auth.jwt()->>'session_id','')::uuid and s.user_id=uid)
$$;
alter table financegpt.journal_entries add column sequence_no bigint generated always as identity;
-- Keep the reviewed financial service body in one place and apply focused changes.
do $$declare body text;begin
 select pg_get_functiondef('finance_private.post_transaction(uuid,jsonb,text,text)'::regprocedure) into body;
 body:=replace(body,'order by created_at desc limit 1','order by sequence_no desc limit 1');
 body:=replace(body,'if t.reversal_of is not null then signed:=-signed; end if;',E'if t.type=''adjustment'' and t.custom_fields->>''adjustment_direction''=''decrease'' then signed:=-signed;end if;\n  if t.reversal_of is not null then signed:=-signed; end if;');
 execute body;
 select pg_get_functiondef('financegpt.create_account(jsonb,text)'::regprocedure) into body;
 body:=replace(body,'name,type,currency,opening_balance) values(uid,payload->>''name'',coalesce(payload->>''type'',''cash''),coalesce(payload->>''currency'',''IDR''),opening)',
 'name,type,currency,opening_balance,allow_negative) values(uid,payload->>''name'',coalesce(payload->>''type'',''cash''),coalesce(payload->>''currency'',''IDR''),opening,coalesce((payload->>''allow_negative'')::boolean,true))');
 execute body;
end $$;
create function finance_private.validate_transaction() returns trigger language plpgsql security definer set search_path='' as $$
declare f financegpt.custom_field_definitions;value jsonb;begin
 if new.custom_fields is null or jsonb_typeof(new.custom_fields)<>'object' then raise exception 'Custom fields must be an object';end if;
 for f in select * from financegpt.custom_field_definitions where user_id=new.user_id loop
  value:=new.custom_fields->f.field_key;
  if f.required and (value is null or value='null'::jsonb or value='""'::jsonb)then raise exception 'Required custom field: %',f.field_key;end if;
  if value is not null and value not in ('null'::jsonb,'""'::jsonb)then
   if (f.field_type='number' and jsonb_typeof(value)<>'number')or(f.field_type='boolean' and jsonb_typeof(value)<>'boolean')or(f.field_type in ('text','enum','date')and jsonb_typeof(value)<>'string')then raise exception 'Invalid custom field type: %',f.field_key;end if;
   if f.field_type='date' then perform (new.custom_fields->>f.field_key)::date;end if;
   if f.field_type='enum' and not (coalesce(f.options_json->'values','[]') @> jsonb_build_array(value))then raise exception 'Invalid enum option: %',f.field_key;end if;
  end if;
 end loop;
 return new;end $$;
create trigger validate_custom_fields before insert or update on financegpt.transactions for each row execute function finance_private.validate_transaction();
create function finance_private.split_type()returns trigger language plpgsql security definer set search_path='' as $$begin
 if not exists(select 1 from financegpt.categories c join financegpt.transactions t on t.id=new.transaction_id and t.user_id=c.user_id where c.id=new.category_id and c.type=t.type and not c.archived)then raise exception 'Split category must match transaction type';end if;
 return new;end $$;
create trigger split_type before insert or update on financegpt.transaction_splits for each row execute function finance_private.split_type();
create function finance_private.category_type_guard()returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.type<>old.type and exists(select 1 from financegpt.transactions where category_id=old.id)then raise exception 'Used category type cannot be changed; archive it and create another';end if;return new;end $$;
create trigger category_type_guard before update on financegpt.categories for each row execute function finance_private.category_type_guard();
create function finance_private.budget_history()returns trigger language plpgsql security definer set search_path='' as $$begin
 if tg_op='UPDATE' and new.row_version<>old.row_version+1 then raise exception 'Conflict: budget version changed';end if;
 insert into financegpt.budget_periods(user_id,budget_id,start_at,end_at,planned_amount,version)values(new.user_id,new.id,new.period_start,new.period_end,new.amount,new.row_version);
 return new;end $$;
create trigger budget_history after insert or update on financegpt.budgets for each row execute function finance_private.budget_history();
create function finance_private.agent_change_audit()returns trigger language plpgsql security definer set search_path='' as $$begin
 insert into financegpt.agent_audit_logs(user_id,connection_id,event_type,actor,safe_diff_json,outcome)values(new.user_id,case when tg_table_name='agent_connections'then new.id else new.connection_id end,tg_table_name||'.'||lower(tg_op),'self',jsonb_build_object('id',new.id),'ok');return new;end $$;
create trigger agent_connection_audit after insert or update on financegpt.agent_connections for each row execute function finance_private.agent_change_audit();
create trigger agent_permission_audit after insert or update on financegpt.agent_permissions for each row execute function finance_private.agent_change_audit();
create trigger agent_policy_audit after insert or update on financegpt.agent_policies for each row execute function finance_private.agent_change_audit();

create function financegpt.delete_empty_account(account_id uuid)returns void language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();entry uuid;begin
 if not finance_private.trusted(uid) then raise exception 'Access denied';end if;
 if not exists(select 1 from financegpt.accounts where id=account_id and user_id=uid)then raise exception 'Account not found';end if;
 if exists(select 1 from financegpt.transactions where user_id=uid and(account_id=delete_empty_account.account_id or destination_account_id=delete_empty_account.account_id))then raise exception 'Archive accounts with transaction history';end if;
 for entry in select distinct entry_id from financegpt.journal_lines where ledger_account_id=account_id and user_id=uid loop
  delete from financegpt.journal_lines where entry_id=entry;delete from financegpt.journal_entries where id=entry;
 end loop;
 delete from financegpt.accounts where id=account_id and user_id=uid;
end $$;
revoke all on all functions in schema finance_private from public,anon,authenticated;
grant execute on function finance_private.trusted(uuid)to authenticated;
grant execute on function finance_private.custom_access_token_hook(jsonb)to supabase_auth_admin;
revoke all on function financegpt.delete_empty_account(uuid)from public,anon;
grant execute on function financegpt.delete_empty_account(uuid)to authenticated;
grant all on all sequences in schema financegpt to service_role;
notify pgrst,'reload schema';

-- Source: patches.sql
create or replace function finance_private.agent_change_audit()returns trigger language plpgsql security definer set search_path='' as $$begin
 insert into financegpt.agent_audit_logs(user_id,connection_id,event_type,actor,safe_diff_json,outcome)values(new.user_id,case when tg_table_name='agent_connections'then new.id else (to_jsonb(new)->>'connection_id')::uuid end,tg_table_name||'.'||lower(tg_op),'self',jsonb_build_object('id',new.id),'ok');return new;end $$;
revoke all on function finance_private.agent_change_audit()from public,anon,authenticated;
notify pgrst,'reload schema';

-- Source: operations.sql
-- Publication events are refresh hints; balances remain authoritative in the journal.
do $$declare t text;begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime')then
  foreach t in array array['transactions','budgets','accounts','agent_pending_actions','agent_connections','savings_goals','goal_allocations']loop
   if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='financegpt' and tablename=t)then execute format('alter publication supabase_realtime add table financegpt.%I',t);end if;
  end loop;
 end if;
end $$;
-- Reconciliation is read-only and exposes no other user's data to regular clients.
create function financegpt.ledger_health()returns jsonb language sql security definer set search_path='' as $$
 select jsonb_build_object('imbalanced_entries',(select count(*)from(select entry_id,currency from financegpt.journal_lines group by entry_id,currency having sum(amount_signed)<>0)x),'checked_at',now())
$$;
revoke all on function financegpt.ledger_health()from public,anon,authenticated;
grant execute on function financegpt.ledger_health()to service_role;
notify pgrst,'reload schema';

-- Source: resources.sql
create function financegpt.save_resource(resource text,payload jsonb,idempotency_key text,record_id uuid default null,expected_version int default null)returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();allowed text[];data jsonb:=payload;cache financegpt.idempotency_records;result jsonb;columns text;request_hash text;old_version int;begin
 if not finance_private.trusted(uid) then raise exception 'Access denied';end if;
 allowed:=case resource
 when 'accounts'then array['name','color','status','allow_negative']
 when 'categories'then array['name','type','parent_id','color','icon','archived','sort_order','default_budget']
 when 'transaction_templates'then array['name','payload_json','favourite','sort_order']
 when 'budgets'then array['name','category_id','account_id','amount','currency','cadence','rollover','period_start','period_end','alerts_json']
 when 'recurring_rules'then array['name','next_at','cadence','payload_json','mode','active','end_at']
 else null end;
 if allowed is null or (resource='accounts'and record_id is null)then raise exception 'Unsupported resource operation';end if;
 if jsonb_typeof(payload)<>'object' or exists(select 1 from jsonb_object_keys(payload)k where not(k=any(allowed)))then raise exception 'Invalid resource fields';end if;
 if length(idempotency_key)<8 then raise exception 'Idempotency key required';end if;
 request_hash:=md5(jsonb_build_object('payload',payload,'id',record_id,'version',expected_version)::text);
 perform pg_advisory_xact_lock(hashtextextended(uid||':resource:'||idempotency_key,0));
 select * into cache from financegpt.idempotency_records where user_id=uid and operation='resource:'||resource and key=idempotency_key;
 if found then if cache.request_hash<>request_hash then raise exception 'Conflict: idempotency payload changed';end if;return cache.response_ref;end if;
 if resource='budgets' and record_id is not null then
  select row_version into old_version from financegpt.budgets where id=record_id and user_id=uid for update;
  if not found or old_version is distinct from expected_version then raise exception 'Conflict: budget version changed';end if;
  data:=data||jsonb_build_object('row_version',old_version+1);
 end if;
 if record_id is null then
  data:=data||jsonb_build_object('id',gen_random_uuid(),'user_id',uid);
  select string_agg(format('%I',k),',')into columns from jsonb_object_keys(data)k;
  execute format('insert into financegpt.%I as target(%s)select %s from jsonb_populate_record(null::financegpt.%I,$1)returning to_jsonb(target.*)',resource,columns,columns,resource)into result using data;
 else
  select string_agg(format('%I',k),',')into columns from jsonb_object_keys(data)k;
  execute format('update financegpt.%I as target set(%s)=(select %s from jsonb_populate_record(null::financegpt.%I,$1))where id=$2 and user_id=$3 returning to_jsonb(target.*)',resource,columns,columns,resource)into result using data,record_id,uid;
  if result is null then raise exception 'Record not found';end if;
 end if;
 insert into financegpt.idempotency_records(user_id,operation,key,request_hash,response_ref)values(uid,'resource:'||resource,idempotency_key,request_hash,result);
 return result;
end $$;
revoke all on function financegpt.save_resource(text,jsonb,text,uuid,int)from public,anon;
grant execute on function financegpt.save_resource(text,jsonb,text,uuid,int)to authenticated;
-- Read-only aggregation includes split allocations and category descendants.
create function financegpt.budget_actuals(uid uuid)returns jsonb language sql security definer set search_path='' as $$
 select coalesce(jsonb_agg(to_jsonb(b)||jsonb_build_object('actual_minor',coalesce(actual.value,0),'remaining_minor',b.amount-coalesce(actual.value,0))),'[]')from financegpt.budgets b
 left join lateral(select sum((case when b.category_id is null then t.amount when exists(select 1 from financegpt.transaction_splits s where s.transaction_id=t.id)then coalesce((select sum(s.amount)from financegpt.transaction_splits s join financegpt.categories c on c.id=s.category_id where s.transaction_id=t.id and(c.id=b.category_id or c.parent_id=b.category_id)),0)else case when t.category_id=b.category_id or exists(select 1 from financegpt.categories c where c.id=t.category_id and c.parent_id=b.category_id)then t.amount else 0 end end)*case when t.reversal_of is null then 1 else -1 end)value from financegpt.transactions t join financegpt.profiles p on p.user_id=t.user_id where t.user_id=b.user_id and t.status='posted' and t.type='expense' and t.currency=b.currency and(b.account_id is null or t.account_id=b.account_id)and(t.effective_at at time zone p.timezone)::date between b.period_start and b.period_end)actual on true where b.user_id=uid
$$;
revoke all on function financegpt.budget_actuals(uuid)from public,anon,authenticated;
grant execute on function financegpt.budget_actuals(uuid)to service_role;
notify pgrst,'reload schema';

-- Source: jobs.sql
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

-- Source: reconciliation.sql
create table financegpt.account_reconciliations(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),account_id uuid not null,balance_before bigint not null,statement_balance bigint not null,reason text not null,transaction_id uuid,created_at timestamptz default now(),foreign key(account_id,user_id)references financegpt.accounts(id,user_id),foreign key(transaction_id,user_id)references financegpt.transactions(id,user_id));
alter table financegpt.account_reconciliations enable row level security;
create policy own_reconciliations on financegpt.account_reconciliations for select to authenticated using(finance_private.trusted(user_id));
grant select on financegpt.account_reconciliations to authenticated;
grant all on financegpt.account_reconciliations to service_role;
create function financegpt.reconcile_account(payload jsonb,idempotency_key text)returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();account financegpt.accounts;cached financegpt.idempotency_records;old_balance bigint;delta bigint;result jsonb;tx jsonb;begin
 if not finance_private.trusted(uid)then raise exception 'Access denied';end if;
 if length(idempotency_key)<8 or length(coalesce(payload->>'reason',''))<3 then raise exception 'Idempotency key and reconciliation reason are required';end if;
 perform pg_advisory_xact_lock(hashtextextended(uid||':reconcile:'||idempotency_key,0));
 select * into cached from financegpt.idempotency_records where user_id=uid and operation='reconcile'and key=idempotency_key;
 if found then if cached.request_hash<>md5(payload::text)then raise exception 'Idempotency conflict';end if;return cached.response_ref;end if;
 select * into account from financegpt.accounts where id=(payload->>'account_id')::uuid and user_id=uid for update;
 if not found or account.status<>'active'then raise exception 'Account unavailable';end if;
 select coalesce(sum(amount_signed),0)into old_balance from financegpt.journal_lines where ledger_account_id=account.id;
 delta:=(payload->>'statement_balance')::bigint-old_balance;
 if delta<>0 then
  tx:=finance_private.post_transaction(uid,jsonb_build_object('type','adjustment','status','posted','account_id',account.id,'currency',account.currency,'amount',abs(delta),'effective_at',now(),'description','Rekonsiliasi saldo','notes',payload->>'reason','custom_fields',coalesce(payload->'custom_fields','{}')||jsonb_build_object('adjustment_direction',case when delta<0 then 'decrease'else'increase'end)),idempotency_key||':posting','self');
 end if;
 insert into financegpt.account_reconciliations(user_id,account_id,balance_before,statement_balance,reason,transaction_id)values(uid,account.id,old_balance,(payload->>'statement_balance')::bigint,payload->>'reason',(tx->>'id')::uuid)returning to_jsonb(account_reconciliations.*)into result;
 insert into financegpt.idempotency_records(user_id,operation,key,request_hash,response_ref)values(uid,'reconcile',idempotency_key,md5(payload::text),result);return result;end $$;
do $$declare definition text;begin
 select pg_get_functiondef('financegpt.delete_empty_account(uuid)'::regprocedure)into definition;
 definition:=replace(definition,'where id=account_id','where id=delete_empty_account.account_id');
 definition:=replace(definition,'where ledger_account_id=account_id','where ledger_account_id=delete_empty_account.account_id');
 execute definition;
end $$;
revoke all on function financegpt.reconcile_account(jsonb,text)from public,anon;
grant execute on function financegpt.reconcile_account(jsonb,text)to authenticated;
create index splits_by_transaction on financegpt.transaction_splits(user_id,transaction_id);
create index agent_audit_period on financegpt.agent_audit_logs(user_id,occurred_at desc);
create index pending_inbox on financegpt.agent_pending_actions(user_id,status,expires_at);
create index imports_preview on financegpt.import_rows(job_id,line_no);
create index export_queue on financegpt.export_jobs(status,created_at);
create index recurring_due on financegpt.recurring_rules(next_at)where active;
notify pgrst,'reload schema';

-- Source: integrity.sql
create table financegpt.currency_metadata(code text primary key,minor_exponent int not null check(minor_exponent between 0 and 4));
insert into financegpt.currency_metadata values('IDR',0),('USD',2),('EUR',2),('SGD',2);
alter table financegpt.currency_metadata enable row level security;
create policy currency_read on financegpt.currency_metadata for select to authenticated using(true);
grant select on financegpt.currency_metadata to authenticated;
grant all on financegpt.currency_metadata to service_role;
alter table financegpt.accounts add foreign key(currency)references financegpt.currency_metadata(code);
alter table financegpt.budgets add foreign key(currency)references financegpt.currency_metadata(code);
alter table financegpt.profiles add foreign key(base_currency)references financegpt.currency_metadata(code);
create function finance_private.profile_zone_guard()returns trigger language plpgsql set search_path='' as $$begin
 if not exists(select 1 from pg_timezone_names where name=new.timezone)then raise exception 'Invalid IANA timezone';end if;return new;end $$;
create trigger profile_zone_guard before insert or update on financegpt.profiles for each row execute function finance_private.profile_zone_guard();
do $$declare definition text;begin
 select pg_get_functiondef('finance_private.post_transaction(uuid,jsonb,text,text)'::regprocedure)into definition;
 definition:=replace(definition,'delete from financegpt.transaction_splits where transaction_id=t.id;',E'if p ? ''splits'' then delete from financegpt.transaction_splits where transaction_id=t.id;\n  elsif exists(select 1 from financegpt.transaction_splits where transaction_id=t.id)and(select sum(amount)from financegpt.transaction_splits where transaction_id=t.id)<>t.amount then raise exception ''Split amounts must be updated with the total'';end if;');execute definition;
 select pg_get_functiondef('finance_private.validate_transaction()'::regprocedure)into definition;
 definition:=replace(definition,'if new.custom_fields is null',E'if new.status=''voided''then return new;end if;\n if new.custom_fields is null');execute definition;
end $$;
alter table financegpt.recurring_rules add column anchor_day int,add column anchor_month int,add column last_error text;
create function finance_private.recurring_anchor()returns trigger language plpgsql security definer set search_path='' as $$declare zone text;begin
 select timezone into zone from financegpt.profiles where user_id=new.user_id;
 new.anchor_day:=coalesce(new.anchor_day,extract(day from new.next_at at time zone zone));new.anchor_month:=coalesce(new.anchor_month,extract(month from new.next_at at time zone zone));return new;end $$;
create trigger recurring_anchor before insert on financegpt.recurring_rules for each row execute function finance_private.recurring_anchor();
create or replace function financegpt.scheduled_tick()returns int language plpgsql security definer set search_path='' as $$
declare r financegpt.recurring_rules;payload jsonb;amount int:=0;local_next timestamp;zone text;next_month date;next_day int;begin
 for r in select rr.*from financegpt.recurring_rules rr join financegpt.profiles p on p.user_id=rr.user_id where active and next_at<=now()and p.status='active'and not p.must_change_password and(end_at is null or end_at>=next_at)order by next_at limit 50 for update of rr skip locked loop
 begin
  payload:=r.payload_json||jsonb_build_object('effective_at',r.next_at,'status',case when r.mode='auto-post'then'posted'else r.mode end);
  perform finance_private.post_transaction(r.user_id,payload,'recurring:'||r.id||':'||r.next_at,'recurring');
  select timezone into zone from financegpt.profiles where user_id=r.user_id;local_next:=r.next_at at time zone zone;
  if r.cadence in('monthly','yearly')then
   next_month:=case when r.cadence='yearly'then make_date(extract(year from local_next)::int+1,coalesce(r.anchor_month,extract(month from local_next)::int),1)else(date_trunc('month',local_next)+interval '1 month')::date end;
   next_day:=least(coalesce(r.anchor_day,extract(day from local_next)::int),extract(day from next_month+interval '1 month -1 day')::int);
   local_next:=(next_month+(next_day-1))::timestamp+local_next::time;
  else local_next:=local_next+case r.cadence when'daily'then interval'1 day'else interval'1 week'end;end if;
  update financegpt.recurring_rules set next_at=local_next at time zone zone,last_error=null where id=r.id;amount:=amount+1;
 exception when others then update financegpt.recurring_rules set last_error='Posting failed; review account, category, and custom field requirements',active=false where id=r.id;
 end;
 end loop;return amount;end $$;
revoke all on function finance_private.profile_zone_guard(),finance_private.recurring_anchor()from public,anon,authenticated;
revoke all on function financegpt.scheduled_tick()from public,anon,authenticated;
grant execute on function financegpt.scheduled_tick()to service_role;
notify pgrst,'reload schema';

-- Source: forecast.sql
create or replace function financegpt.forecast_data(uid uuid,period_start timestamptz,period_end timestamptz,currency_code text default 'IDR',model text default 'run_rate',allowed_accounts uuid[] default '{}',allowed_categories uuid[] default '{}')returns jsonb language plpgsql security definer set search_path='' as $$
declare zone text;days int;elapsed int;actual bigint;variable bigint;history bigint;history_days int;first_history timestamptz;known_expense bigint:=0;known_income bigint:=0;estimated bigint;budget bigint;balance bigint;r financegpt.recurring_rules;due timestamptz;local_due timestamp;next_month date;anchor_day int;scheduled jsonb:='[]';i int;begin
 select timezone into zone from financegpt.profiles where user_id=uid and status='active'and not must_change_password;if not found then raise exception 'Account inactive';end if;
 if forecast_data.period_end<=forecast_data.period_start or forecast_data.period_end-forecast_data.period_start>interval'366 days'then raise exception 'Forecast range must be 1–366 days';end if;
 if model not in('run_rate','scheduled','hybrid')then raise exception 'Unsupported forecast model';end if;
 days:=greatest(1,(forecast_data.period_end at time zone zone)::date-(forecast_data.period_start at time zone zone)::date);elapsed:=least(days,greatest(1,(now()at time zone zone)::date-(forecast_data.period_start at time zone zone)::date+1));
 select coalesce(sum(t.amount*case when t.reversal_of is null then 1 else -1 end),0),coalesce(sum(case when t.source<>'recurring'and not(t.tags@>array['scheduled'])then t.amount*case when t.reversal_of is null then 1 else -1 end else 0 end),0)into actual,variable from financegpt.transactions t where t.user_id=uid and t.currency=currency_code and t.status='posted'and t.type='expense'and t.effective_at>=forecast_data.period_start and t.effective_at<forecast_data.period_end and(cardinality(allowed_accounts)=0 or t.account_id=any(allowed_accounts))and(cardinality(allowed_categories)=0 or t.category_id=any(allowed_categories));
 select coalesce(sum(t.amount*case when t.reversal_of is null then 1 else -1 end),0),min(t.effective_at)into history,first_history from financegpt.transactions t where t.user_id=uid and t.currency=currency_code and t.status='posted'and t.type='expense'and t.source<>'recurring'and not(t.tags@>array['scheduled'])and t.effective_at>=forecast_data.period_start-interval'90 days'and t.effective_at<forecast_data.period_start and(cardinality(allowed_accounts)=0 or t.account_id=any(allowed_accounts))and(cardinality(allowed_categories)=0 or t.category_id=any(allowed_categories));
 history_days:=case when first_history is null then 0 else least(90,greatest(1,(forecast_data.period_start at time zone zone)::date-(first_history at time zone zone)::date))end;
 for r in select *from financegpt.recurring_rules rr where rr.user_id=uid and rr.active and rr.payload_json->>'currency'=currency_code and(cardinality(allowed_accounts)=0 or(rr.payload_json->>'account_id')::uuid=any(allowed_accounts))and(cardinality(allowed_categories)=0 or(rr.payload_json->>'category_id')::uuid=any(allowed_categories))loop
  due:=r.next_at;anchor_day:=coalesce(r.anchor_day,extract(day from due at time zone zone));i:=0;
  while due<forecast_data.period_end and(r.end_at is null or due<=r.end_at)and i<1000 loop
   if due>=forecast_data.period_start and due>now()then
    if r.payload_json->>'type'='expense'then known_expense:=known_expense+(r.payload_json->>'amount')::bigint;elsif r.payload_json->>'type'='income'then known_income:=known_income+(r.payload_json->>'amount')::bigint;end if;
    scheduled:=scheduled||jsonb_build_array(jsonb_build_object('name',r.name,'effective_at',due,'type',r.payload_json->>'type','amount_minor',(r.payload_json->>'amount')::bigint,'account_id',r.payload_json->>'account_id'));
   end if;
   local_due:=due at time zone zone;
   if r.cadence in('monthly','yearly')then
    next_month:=case when r.cadence='yearly'then make_date(extract(year from local_due)::int+1,coalesce(r.anchor_month,extract(month from local_due)::int),1)else(date_trunc('month',local_due)+interval'1 month')::date end;
    local_due:=(next_month+(least(anchor_day,extract(day from next_month+interval'1 month -1 day')::int)-1))::timestamp+local_due::time;
   else local_due:=local_due+case r.cadence when'daily'then interval'1 day'else interval'1 week'end;end if;
   due:=local_due at time zone zone;i:=i+1;
  end loop;
 end loop;
 select known_expense+coalesce(sum(case when t.type='expense'then t.amount else 0 end),0),known_income+coalesce(sum(case when t.type='income'then t.amount else 0 end),0)into known_expense,known_income from financegpt.transactions t where t.user_id=uid and t.currency=currency_code and t.status='pending'and t.effective_at>now()and t.effective_at>=forecast_data.period_start and t.effective_at<forecast_data.period_end and(cardinality(allowed_accounts)=0 or t.account_id=any(allowed_accounts))and(cardinality(allowed_categories)=0 or t.category_id=any(allowed_categories));
 estimated:=case model when'scheduled'then actual+known_expense when'hybrid'then actual+known_expense+round(case when history_days>=14 then history::numeric/history_days else variable::numeric/elapsed end*(days-elapsed))::bigint else round(actual::numeric*days/elapsed)::bigint end;
 select coalesce(sum(b.amount),0)into budget from financegpt.budgets b where b.user_id=uid and b.currency=currency_code and b.period_start<=(forecast_data.period_end at time zone zone)::date-1 and b.period_end>=(forecast_data.period_start at time zone zone)::date and(cardinality(allowed_accounts)=0 or b.account_id=any(allowed_accounts))and(cardinality(allowed_categories)=0 or b.category_id=any(allowed_categories))and(b.category_id is null or not exists(select 1 from financegpt.budgets g where g.user_id=uid and g.category_id is null and g.currency=currency_code and g.period_start<=(forecast_data.period_end at time zone zone)::date-1 and g.period_end>=(forecast_data.period_start at time zone zone)::date and(cardinality(allowed_accounts)=0 or g.account_id=any(allowed_accounts))and cardinality(allowed_categories)=0));
 select coalesce(sum(l.amount_signed),0)into balance from financegpt.journal_lines l join financegpt.accounts a on a.id=l.ledger_account_id where l.user_id=uid and l.currency=currency_code and(cardinality(allowed_accounts)=0 or a.id=any(allowed_accounts));
 return jsonb_build_object('currency',currency_code,'actual_minor',actual,'known_scheduled_minor',known_expense,'known_income_minor',known_income,'forecast_eop_minor',estimated,'budget_minor',budget,'remaining_minor',budget-actual,'projected_variance_minor',budget-estimated,'expected_closing_cash_minor',balance+known_income-(estimated-actual),'elapsed_days',elapsed,'total_days',days,'historical_days',history_days,'method',model,'model_version','v1','confidence','low','known_scheduled',scheduled,'assumptions',jsonb_build_array('Posted actual only; transfers excluded; refunds netted',case when model='hybrid'and history_days<14 then'Historical data under 14 days; variable run-rate fallback'else'Historical variable window up to 90 days; recurring excluded'end,'No calibrated historical accuracy; no cross-currency FX aggregation'),'generated_at',now());
end $$;
revoke all on function financegpt.forecast_data(uuid,timestamptz,timestamptz,text,text,uuid[],uuid[])from public,anon,authenticated;
grant execute on function financegpt.forecast_data(uuid,timestamptz,timestamptz,text,text,uuid[],uuid[])to service_role;
notify pgrst,'reload schema';

-- Source: analytics.sql
create function financegpt.analytics_data(uid uuid,period_start timestamptz,period_end timestamptz,currency_code text default 'IDR',allowed_accounts uuid[] default '{}',allowed_categories uuid[] default '{}')returns jsonb language sql security definer set search_path='' as $$
with base as(
 select t.*from financegpt.transactions t where t.user_id=uid and t.status='posted'and t.currency=currency_code and t.effective_at>=period_start and t.effective_at<period_end and(cardinality(allowed_accounts)=0 or t.account_id=any(allowed_accounts))and(cardinality(allowed_categories)=0 or t.category_id=any(allowed_categories))
),allocations as(
 select t.id,t.type,s.category_id,s.amount*case when t.reversal_of is null then 1 else -1 end amount from base t join financegpt.transaction_splits s on s.transaction_id=t.id
 union all select t.id,t.type,t.category_id,t.amount*case when t.reversal_of is null then 1 else -1 end from base t where not exists(select 1 from financegpt.transaction_splits s where s.transaction_id=t.id)
),totals as(select coalesce(sum(case when type='income'then amount*case when reversal_of is null then 1 else -1 end else 0 end),0)income,coalesce(sum(case when type='expense'then amount*case when reversal_of is null then 1 else -1 end else 0 end),0)expense,count(*)count from base),prior as(
 select coalesce(sum(case when t.type='expense'then t.amount*case when t.reversal_of is null then 1 else -1 end else 0 end),0)expense from financegpt.transactions t where t.user_id=uid and t.status='posted'and t.currency=currency_code and t.effective_at>=period_start-(period_end-period_start)and t.effective_at<period_start and(cardinality(allowed_accounts)=0 or t.account_id=any(allowed_accounts))and(cardinality(allowed_categories)=0 or t.category_id=any(allowed_categories))
)
select jsonb_build_object('currency',currency_code,'income_minor',totals.income,'expense_minor',totals.expense,'net_minor',totals.income-totals.expense,'transaction_count',totals.count,'period',jsonb_build_object('start',period_start,'end',period_end,'timezone',(select timezone from financegpt.profiles where user_id=uid)),'prior_period_expense_minor',prior.expense,'expense_change_percent',case when prior.expense=0 then null else round((totals.expense-prior.expense)*100.0/prior.expense,2)end,
'categories',coalesce((select jsonb_agg(x)from(select c.id,c.name,sum(a.amount)amount_minor from allocations a join financegpt.categories c on c.id=a.category_id where a.type='expense'group by c.id,c.name order by sum(a.amount)desc)x),'[]'),
'income_sources',coalesce((select jsonb_agg(x)from(select c.id,c.name,sum(a.amount)amount_minor from allocations a join financegpt.categories c on c.id=a.category_id where a.type='income'group by c.id,c.name order by sum(a.amount)desc)x),'[]'),
'merchants',coalesce((select jsonb_agg(x)from(select coalesce(nullif(merchant,''),'Tanpa merchant')name,sum(amount*case when reversal_of is null then 1 else -1 end)amount_minor from base where type='expense'group by merchant order by sum(amount)desc limit 20)x),'[]'),
'cashflow',coalesce((select jsonb_agg(x)from(select(t.effective_at at time zone p.timezone)::date date,coalesce(sum(case when t.type='income'then t.amount*case when t.reversal_of is null then 1 else -1 end else 0 end),0)income_minor,coalesce(sum(case when t.type='expense'then t.amount*case when t.reversal_of is null then 1 else -1 end else 0 end),0)expense_minor from base t join financegpt.profiles p on p.user_id=t.user_id group by(t.effective_at at time zone p.timezone)::date order by date)x),'[]'),'calculation','Posted only; transfers excluded; refunds netted; splits allocated to category; prior comparison uses equal-length preceding period')from totals,prior
$$;
revoke all on function financegpt.analytics_data(uuid,timestamptz,timestamptz,text,uuid[],uuid[])from public,anon,authenticated;
grant execute on function financegpt.analytics_data(uuid,timestamptz,timestamptz,text,uuid[],uuid[])to service_role;
notify pgrst,'reload schema';

-- Source: templates.sql
create function financegpt.delete_template(template_id uuid)returns void language plpgsql security definer set search_path='' as $$begin
 if not finance_private.trusted(auth.uid())then raise exception 'Access denied';end if;
 delete from financegpt.transaction_templates where id=template_id and user_id=auth.uid();
end $$;
revoke all on function financegpt.delete_template(uuid)from public,anon;
grant execute on function financegpt.delete_template(uuid)to authenticated;
notify pgrst,'reload schema';

-- Source: form_validation.sql
alter table financegpt.custom_field_definitions add column created_at timestamptz not null default now();
create or replace function finance_private.validate_transaction() returns trigger language plpgsql security definer set search_path='' as $$
declare f financegpt.custom_field_definitions;value jsonb;preferences jsonb;key text;required_since timestamptz;begin
 if new.status='voided'then return new;end if;
 if new.custom_fields is null or jsonb_typeof(new.custom_fields)<>'object' then raise exception 'Custom fields must be an object';end if;
 for f in select * from financegpt.custom_field_definitions where user_id=new.user_id loop
  value:=new.custom_fields->f.field_key;
  if f.required and new.created_at>=f.created_at and(value is null or value='null'::jsonb or value='""'::jsonb)then raise exception 'Required custom field: %',f.field_key;end if;
  if value is not null and value not in('null'::jsonb,'""'::jsonb)then
   if(f.field_type='number'and jsonb_typeof(value)<>'number')or(f.field_type='boolean'and jsonb_typeof(value)<>'boolean')or(f.field_type in('text','enum','date')and jsonb_typeof(value)<>'string')then raise exception 'Invalid custom field type: %',f.field_key;end if;
   if f.field_type='date'then perform(new.custom_fields->>f.field_key)::date;end if;
   if f.field_type='enum'and not(coalesce(f.options_json->'values','[]')@>jsonb_build_array(value))then raise exception 'Invalid enum option: %',f.field_key;end if;
  end if;
 end loop;
 select settings_json->'transaction_form'into preferences from financegpt.profiles where user_id=new.user_id;
 required_since:=coalesce((preferences->>'updated_at')::timestamptz,'infinity');
 if new.created_at>=required_since then
  for key in select jsonb_array_elements_text(coalesce(preferences->'required','[]'))loop
   if key in('description','merchant','notes')and length(trim(coalesce(to_jsonb(new)->>key,'')))=0 then raise exception 'Required field: %',key;end if;
   if key='tags'and coalesce(cardinality(new.tags),0)=0 then raise exception 'Required field: tags';end if;
  end loop;
 end if;
 if new.attachment_path is not null and(new.attachment_path not like new.user_id::text||'/%'or new.attachment_path like'%..%'or not exists(select 1 from storage.objects where bucket_id='financegpt-private'and name=new.attachment_path))then raise exception 'Invalid private attachment';end if;
 return new;end $$;
revoke all on function finance_private.validate_transaction()from public,anon,authenticated;
notify pgrst,'reload schema';

-- Source: agent_integrity.sql
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

-- Source: agent_policy.sql
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

-- Source: policy_reads.sql
-- Category restrictions apply to every split; restricted agents cannot read a
-- complete transaction that includes categories outside their allowed scope.
do $$declare definition text;signature text;begin
 foreach signature in array array['financegpt.analytics_data(uuid,timestamptz,timestamptz,text,uuid[],uuid[])','financegpt.forecast_data(uuid,timestamptz,timestamptz,text,text,uuid[],uuid[])']loop
  select pg_get_functiondef(signature::regprocedure)into definition;
  definition:=replace(definition,'and(cardinality(allowed_categories)=0 or t.category_id=any(allowed_categories))','and(cardinality(allowed_categories)=0 or(t.category_id=any(allowed_categories)and not exists(select 1 from financegpt.transaction_splits s where s.transaction_id=t.id and not(s.category_id=any(allowed_categories)))))');
  execute definition;
 end loop;
end $$;
notify pgrst,'reload schema';

commit;
