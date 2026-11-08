begin;
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
