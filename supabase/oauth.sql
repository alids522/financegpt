begin;
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
commit;
