begin;
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
commit;
