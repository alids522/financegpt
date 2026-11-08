begin;
create function financegpt.delete_template(template_id uuid)returns void language plpgsql security definer set search_path='' as $$begin
 if not finance_private.trusted(auth.uid())then raise exception 'Access denied';end if;
 delete from financegpt.transaction_templates where id=template_id and user_id=auth.uid();
end $$;
revoke all on function financegpt.delete_template(uuid)from public,anon;
grant execute on function financegpt.delete_template(uuid)to authenticated;
notify pgrst,'reload schema';
commit;
