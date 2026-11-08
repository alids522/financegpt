begin;
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
commit;
