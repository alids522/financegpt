begin;
create table finance_private.personal_tokens(
 id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),connection_id uuid not null unique references financegpt.agent_connections(id),token_hash text not null unique check(length(token_hash)=64),prefix text not null,created_at timestamptz not null default now(),expires_at timestamptz not null,revoked_at timestamptz,last_used_at timestamptz);
alter table finance_private.personal_tokens enable row level security;
revoke all on finance_private.personal_tokens from public,anon,authenticated;
create index personal_tokens_owner on finance_private.personal_tokens(user_id,created_at desc);
create function financegpt.generate_personal_token(display_name text,expires_in_days int default 90)returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();conn uuid:=gen_random_uuid();secret text;token_id uuid;expiry timestamptz;begin
 if not finance_private.trusted(uid)then raise exception 'Access denied';end if;
 if length(trim(display_name))not between 1 and 80 or expires_in_days not between 1 and 365 then raise exception 'Nama token dan masa berlaku 1-365 hari diperlukan';end if;
 perform pg_advisory_xact_lock(hashtextextended(uid||':personal_tokens',0));
 if(select count(*)from finance_private.personal_tokens where user_id=uid and revoked_at is null and expires_at>now())>=50 then raise exception 'Maksimal 50 token aktif';end if;
 secret:='fgt_'||encode(extensions.gen_random_bytes(32),'hex');expiry:=now()+make_interval(days=>expires_in_days);
 insert into financegpt.agent_connections(id,user_id,oauth_client_id,display_name)values(conn,uid,'pat:'||conn,trim(display_name));
 insert into financegpt.agent_policies(user_id,connection_id)values(uid,conn);
 insert into financegpt.agent_permissions(user_id,connection_id,permission,enabled)select uid,conn,x,true from unnest(array['accounts:read','transactions:read','categories:read','budgets:read','forecasts:read','analytics:read'])x;
 insert into finance_private.personal_tokens(user_id,connection_id,token_hash,prefix,expires_at)values(uid,conn,encode(sha256(convert_to(secret,'UTF8')),'hex'),left(secret,12),expiry)returning id into token_id;
 return jsonb_build_object('id',token_id,'connection_id',conn,'token',secret,'expires_at',expiry);end $$;
create function financegpt.list_personal_tokens()returns jsonb language plpgsql security definer set search_path='' as $$begin
 if not finance_private.trusted(auth.uid())then raise exception 'Access denied';end if;
 return(select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'connection_id',c.id,'name',c.display_name,'prefix',t.prefix,'created_at',t.created_at,'expires_at',t.expires_at,'last_used_at',t.last_used_at,'status',case when t.revoked_at is not null or c.status='revoked'then'revoked'when t.expires_at<=now()then'expired'else c.status end)order by t.created_at desc),'[]')from finance_private.personal_tokens t join financegpt.agent_connections c on c.id=t.connection_id and c.user_id=t.user_id where t.user_id=auth.uid());end $$;
create function financegpt.revoke_personal_token(token_id uuid)returns void language plpgsql security definer set search_path='' as $$declare conn uuid;begin
 if not finance_private.trusted(auth.uid())then raise exception 'Access denied';end if;
 update finance_private.personal_tokens set revoked_at=coalesce(revoked_at,now())where id=token_id and user_id=auth.uid()returning connection_id into conn;
 if conn is null then raise exception 'Token not found';end if;
 update financegpt.agent_connections set status='revoked',revoked_at=coalesce(revoked_at,now())where id=conn and user_id=auth.uid();end $$;
create function financegpt.authenticate_personal_token(hash text)returns jsonb language plpgsql security definer set search_path='' as $$declare t finance_private.personal_tokens;c financegpt.agent_connections;p financegpt.profiles;begin
 select *into t from finance_private.personal_tokens where token_hash=hash and revoked_at is null and expires_at>now();
 if not found then raise exception 'unauthorized: Token invalid, expired or revoked';end if;
 select *into c from financegpt.agent_connections where id=t.connection_id and user_id=t.user_id and status='active';
 if not found then raise exception 'unauthorized: Token inactive';end if;
 select *into p from financegpt.profiles where user_id=t.user_id and status='active'and not must_change_password;
 if not found then raise exception 'unauthorized: Account inactive';end if;
 update finance_private.personal_tokens set last_used_at=now()where id=t.id and(last_used_at is null or last_used_at<now()-interval'1 minute');
 return jsonb_build_object('uid',t.user_id,'token_id',t.id,'client_id',c.oauth_client_id,'connection_id',c.id,'profile',to_jsonb(p));end $$;
revoke all on function financegpt.generate_personal_token(text,int),financegpt.list_personal_tokens(),financegpt.revoke_personal_token(uuid),financegpt.authenticate_personal_token(text)from public,anon,authenticated;
grant execute on function financegpt.generate_personal_token(text,int),financegpt.list_personal_tokens(),financegpt.revoke_personal_token(uuid)to authenticated;
grant execute on function financegpt.authenticate_personal_token(text)to service_role;
update financegpt.agent_connections set status='revoked',revoked_at=coalesce(revoked_at,now())where oauth_client_id not like'pat:%'and status<>'revoked';
-- Authoritative account statements use immutable journal movements, not edited transaction totals.
create function financegpt.account_statement_data(uid uuid,account uuid,date_from date,date_to date)returns jsonb language plpgsql security definer set search_path='' as $$
declare a financegpt.accounts;zone text;start_at timestamptz;end_at timestamptz;opening bigint;debits bigint;credits bigint;rows_json jsonb;total int;begin
 select *into a from financegpt.accounts where id=account and user_id=uid;
 if not found then raise exception 'Account not found';end if;
 select timezone into zone from financegpt.profiles where user_id=uid and status='active'and not must_change_password;
 if not found then raise exception 'Access denied';end if;
 if date_from is null or date_to is null or date_to<date_from or date_to-date_from>3660 then raise exception 'Rentang tanggal tidak valid (maksimal 10 tahun)';end if;
 start_at:=date_from::timestamp at time zone zone;end_at:=(date_to+1)::timestamp at time zone zone;
 select coalesce(sum(l.amount_signed),0)into opening from financegpt.journal_lines l join financegpt.journal_entries e on e.id=l.entry_id and e.user_id=l.user_id where l.user_id=uid and l.ledger_account_id=account and e.posted_at<start_at;
 select count(*),coalesce(sum(greatest(-l.amount_signed,0)),0),coalesce(sum(greatest(l.amount_signed,0)),0)into total,debits,credits from financegpt.journal_lines l join financegpt.journal_entries e on e.id=l.entry_id and e.user_id=l.user_id where l.user_id=uid and l.ledger_account_id=account and e.posted_at>=start_at and e.posted_at<end_at;
 if total>20000 then raise exception 'Mutasi melebihi 20.000 baris; gunakan periode lebih pendek';end if;
 select coalesce(jsonb_agg(to_jsonb(x)order by x.posted_at,x.sequence_no,x.line_id),'[]')into rows_json from(
 select l.id line_id,e.id entry_id,e.transaction_id,e.posted_at,e.sequence_no,case when e.transaction_id is null then'Saldo awal rekening'when e.reversal_of is not null then'Koreksi / pembalikan jurnal'else coalesce(nullif(t.description,''),case t.type when'transfer'then'Transfer antar rekening'when'adjustment'then'Penyesuaian saldo'else'Transaksi'end)end description,coalesce(t.merchant,'')merchant,case when e.reversal_of is not null then'reversal'else coalesce(t.type,'opening')end type,greatest(-l.amount_signed,0)debit_minor,greatest(l.amount_signed,0)credit_minor,opening+sum(l.amount_signed)over(order by e.posted_at,e.sequence_no,l.id rows unbounded preceding)balance_minor
 from financegpt.journal_lines l join financegpt.journal_entries e on e.id=l.entry_id and e.user_id=l.user_id left join financegpt.transactions t on t.id=e.transaction_id and t.user_id=l.user_id where l.user_id=uid and l.ledger_account_id=account and e.posted_at>=start_at and e.posted_at<end_at)x;
 return jsonb_build_object('account_id',a.id,'account_name',a.name,'currency',a.currency,'timezone',zone,'date_from',date_from,'date_to',date_to,'opening_minor',opening,'debit_minor',debits,'credit_minor',credits,'closing_minor',opening+credits-debits,'row_count',total,'rows',rows_json,'generated_at',now(),'calculation','Posted journal movements; transfers, refunds and correction journals included; date range inclusive in account owner timezone');end $$;
revoke all on function financegpt.account_statement_data(uuid,uuid,date,date)from public,anon,authenticated;
grant execute on function financegpt.account_statement_data(uuid,uuid,date,date)to service_role;
create index journal_statement_period on financegpt.journal_entries(user_id,posted_at,sequence_no);

create or replace function finance_private.agent_authorize(uid uuid,client text,scope text)returns financegpt.agent_connections language plpgsql security definer set search_path='' as $$
declare conn financegpt.agent_connections;begin
 select *into conn from financegpt.agent_connections where user_id=uid and oauth_client_id=client for update;
 if not found or conn.status<>'active'then raise exception 'revoked: agent connection unavailable';end if;
 if conn.oauth_client_id like'pat:%'and not exists(select 1 from finance_private.personal_tokens where connection_id=conn.id and user_id=uid and revoked_at is null and expires_at>now())then raise exception 'revoked: personal token expired or revoked';end if;
 if not exists(select 1 from financegpt.profiles where user_id=uid and status='active'and not must_change_password)then raise exception 'permission_denied: account unavailable';end if;
 if scope like'admin:%'or scope='agent_permissions:write'or not exists(select 1 from financegpt.agent_permissions where connection_id=conn.id and permission=scope and enabled)then raise exception 'permission_denied: scope unavailable';end if;
 return conn;end $$;
revoke all on function finance_private.agent_authorize(uuid,text,text)from public,anon,authenticated;

notify pgrst,'reload schema';
commit;
