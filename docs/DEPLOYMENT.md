# Backend and release deployment

## Database

A fresh Supabase installation needs PostgreSQL 17, Auth, PostgREST, Storage, and an Edge Functions runtime. Apply the initial `supabase/migrations/20261108101048_finance_tracker_v1.sql` once as the database owner, followed by `20261109131759_personal_tokens_statements.sql`. Existing installations need only the latter upgrade. It installs tables, RLS, grants, functions, triggers, indexes, a private Storage bucket, and publication membership. Do not reapply the initial migration to an existing financegpt database. Root SQL files are the ordered sources of that initial migration, rather than additional migrations to run a second time.

The migration includes an explicitly guarded compatibility block for the existing shared server: it skips that server's invitation/WA signup triggers only when Auth metadata identifies `app=financegpt`. Other application registrations retain their existing behavior. The hook and all financial tables are kept outside other applications' schemas.

Expose `financegpt` in PostgREST without removing already exposed schemas. The configured server uses the `authenticator` role `pgrst.db_schemas` setting followed by PostgREST reload notifications. Enable Realtime for the application tables if publication is not already present. `finance_private` must never be an exposed REST schema.

Auth configuration: email autoconfirm and signup enabled, minimum password 12 on the configured shared server. Finance uses normal user login for its UI and opaque personal tokens for external API/MCP access. Global Supabase OAuth settings and the historical custom token hook may remain for other applications; Finance OAuth client tokens are now rejected, old Finance connections revoked, and Finance consent/metadata routes return 410.

## Edge Functions and PDF/report worker

Deploy the entire `supabase/functions/finance-api` directory as function `finance-api`. Gateway JWT verification must be disabled for this function because personal tokens are opaque. The function checks their hash, live owner profile, expiry, revocation, connection and permissions. UI session JWTs still receive signature/issuer/audience/session checks. Supply `SUPABASE_URL` (internal gateway), `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `JWT_SECRET` for legacy HS256, and `FINANCE_PUBLIC_URL` for public URLs. Asymmetric JWTs use Auth JWKS. Keep these in the server environment.

Build `workers/Dockerfile` with its adjacent Python and Inter files. Run it on the Supabase Docker network as `financegpt-pdf`, port 8080 internal only, with the service key in a protected env file. It calls `http://kong:8000` by default, or `SUPABASE_URL` if set. Use a non-root user, read-only root filesystem, a small tmpfs, and resource limits. The worker extracts digital PDF text, processes private export jobs, runs recurring schedules/maintenance, and removes expired output files. It never exposes uploaded document contents in logs. It does not perform OCR.

## API and MCP tokens

In the app, open **API & AI Agents → Generate token**, provide a name and lifetime, and copy the token from the one-time dialog. The default is read-only and 90 days; supported lifetime is 1–365 days. Use the settings icon to grant write scopes, limits, approval policy, and account/category restrictions. The owner can pause or permanently revoke each token. Losing the secret requires generating a new token.

Both interfaces use `Authorization: Bearer fgt_...` without an apikey header or OAuth registration:

- REST: `https://supabase.adoetz52.my.id/functions/v1/finance-api/api/v1`
- MCP: `https://supabase.adoetz52.my.id/functions/v1/finance-api/mcp`

The MCP client must support manually configured Bearer authentication. Requests are limited to 120/minute/token, with additional financial mutation limits. Generation requires an active, trusted user session; tokens cannot create tokens, approve actions, access admin endpoints, or bypass policies through Supabase REST. Metadata lists are owner-only and exclude secrets/hashes. Raw secrets are never persisted, including in idempotency caches. Other apps sharing Supabase Auth do not accept these Finance-specific tokens.

`POST /tokens` takes `{ "name": "My integration", "expires_in_days": 90 }` using the UI user session. `GET /tokens` lists own metadata; `DELETE /tokens/{id}` revokes it. Existing Finance OAuth connections are retired. Shared-server OAuth/gateway routes used by other apps are not disabled.

## E-statements

Under **Accounts & Wallets**, each account has an **E-statement** button. Select a month (day 1 through its actual last day, including leap years), or a custom inclusive date range, display the preview, then export PDF or CSV. The report includes opening balance, credit/debit totals, closing balance and every movement's running balance. Transfers, refunds, opening and correction journals are included. The preview shows 15 rows; exported files contain all rows. CSV amounts are integer minor units with a single UTF-8 BOM; PDF amounts use the account currency's display units.

REST: `GET /accounts/{id}/statement?start=YYYY-MM-DD&end=YYYY-MM-DD`; MCP: `get_account_statement` with `account_id`, `start`, `end`. Dates are inclusive in the owner's timezone. Access is restricted to the owner; a personal token also needs account/transaction read permissions and the full permitted category scope for that account. Maximum range is 10 years / 20,000 movements per request. Use a shorter range if exceeded.

## Administrator bootstrap

There is no automatic first-signup promotion. Run `scripts/bootstrap_admin.py --username ... --email ... --output <private-local-file>` only with authorized `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` environment variables. It creates an explicit administrator and writes its temporary password only to the chosen file. The account must change that password before accessing data. Keep the output outside the repository.

## Android signing and GitHub releases

GitHub secrets: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_PASSWORD`; alias `financegpt`. Keep the same keystore for future updates. The workflow fails if signing material is missing and publishes an APK, Web ZIP, and checksums. The Gradle distribution is checksum-pinned; CI uses a Kotlin Maven mirror to avoid unavailable redirected compiler downloads.

Before public production use, configure monitored backups/restore drills and an operational identity-proof procedure for admin-assisted resets. Existing server applications are not moved or reconfigured by this repository.
