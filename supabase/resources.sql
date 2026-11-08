begin;
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
commit;
