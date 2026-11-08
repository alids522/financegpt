begin;
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
commit;
