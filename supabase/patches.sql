begin;
create or replace function finance_private.agent_change_audit()returns trigger language plpgsql security definer set search_path='' as $$begin
 insert into financegpt.agent_audit_logs(user_id,connection_id,event_type,actor,safe_diff_json,outcome)values(new.user_id,case when tg_table_name='agent_connections'then new.id else (to_jsonb(new)->>'connection_id')::uuid end,tg_table_name||'.'||lower(tg_op),'self',jsonb_build_object('id',new.id),'ok');return new;end $$;
revoke all on function finance_private.agent_change_audit()from public,anon,authenticated;
notify pgrst,'reload schema';
commit;
