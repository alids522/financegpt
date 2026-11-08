-- Optional compatibility for this shared self-hosted instance.
-- Preserve the existing invitation-only policy for the other applications.
begin;
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
commit;
