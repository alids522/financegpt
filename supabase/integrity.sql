begin;
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
commit;
