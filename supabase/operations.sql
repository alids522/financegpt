begin;
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
commit;
