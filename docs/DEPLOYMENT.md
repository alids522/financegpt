# Backend and release deployment

## Database

A fresh Supabase installation needs PostgreSQL 17, Auth, PostgREST, Storage, and an Edge Functions runtime. Apply `supabase/migrations/20261108101048_finance_tracker_v1.sql` once, as the database owner. It installs tables, RLS, grants, functions, triggers, indexes, a private Storage bucket, and publication membership. Do not reapply the initial migration to an existing financegpt database. Root SQL files are the ordered sources of that initial migration, rather than additional migrations to run a second time.

The migration includes an explicitly guarded compatibility block for the existing shared server: it skips that server's invitation/WA signup triggers only when Auth metadata identifies `app=financegpt`. Other application registrations retain their existing behavior. The hook and all financial tables are kept outside other applications' schemas.

Expose `financegpt` in PostgREST without removing already exposed schemas. The configured server uses the `authenticator` role `pgrst.db_schemas` setting followed by PostgREST reload notifications. Enable Realtime for the application tables if publication is not already present. `finance_private` must never be an exposed REST schema.

Auth configuration: email autoconfirm enabled, signup enabled, minimum password 12 on this shared server, OAuth server enabled, dynamic registration disabled, authorization/consent path `/functions/v1/finance-api/consent`, and custom token hook `pg-functions://postgres/finance_private/custom_access_token_hook`. The hook changes audience only for clients with `client_uri` equal to the exact Finance MCP resource; other client claims are preserved.

## Edge Functions and PDF/report worker

Deploy the entire `supabase/functions/finance-api` directory as function `finance-api`. Gateway JWT verification must be disabled for this function because OAuth tokens have a resource audience and the function verifies signature, issuer, audience, expiry, user, session, and agent status itself. Supply `SUPABASE_URL` (internal gateway), `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `JWT_SECRET` for legacy HS256, and `FINANCE_PUBLIC_URL` for public URLs. Asymmetric JWTs use Auth JWKS. Keep these in the server environment.

Build `workers/Dockerfile` with its adjacent Python and Inter files. Run it on the Supabase Docker network as `financegpt-pdf`, port 8080 internal only, with the service key in a protected env file. It calls `http://kong:8000` by default, or `SUPABASE_URL` if set. Use a non-root user, read-only root filesystem, a small tmpfs, and resource limits. The worker extracts digital PDF text, processes private export jobs, runs recurring schedules/maintenance, and removes expired output files. It never exposes uploaded document contents in logs. It does not perform OCR.

For a standard MCP client, expose public metadata at `/.well-known/oauth-protected-resource/functions/v1/finance-api/mcp` and `/.well-known/oauth-authorization-server/auth/v1`. Proxy those to the function's protected-resource metadata and Auth's authorization-server metadata, respectively. OAuth `/auth/v1/oauth/` endpoints must allow standard PKCE requests without an application-specific apikey header. Existing Auth password/admin endpoints retain their original gateway protection. These additive routes are installed on the configured server with a backup of the original gateway configuration.

## Connecting an agent

Register a public OAuth client through Supabase's trusted administrator interface/API with a display name, explicit redirect URI(s), authorization-code/refresh grants, and `client_uri` exactly `https://supabase.adoetz52.my.id/functions/v1/finance-api/mcp`. Supply that client ID to the MCP client and add it under **API & AI Agents**. Automatic dynamic registration is disabled.

Use OAuth authorization code with PKCE S256 and the exact MCP resource. Request `email profile`; this self-hosted Auth signing configuration does not issue OpenID ID tokens with legacy HS256, and the app does not require one. The hosted consent page lets the user authenticate and approve the client. Configure financial permissions and limits in the app. Financial permissions are enforced independently from basic OAuth identity scopes. High-risk actions and report exports require a separate trusted-user approval in the app. Poll `get_action_status` for execution/report status and private download links.

## Administrator bootstrap

There is no automatic first-signup promotion. Run `scripts/bootstrap_admin.py --username ... --email ... --output <private-local-file>` only with authorized `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` environment variables. It creates an explicit administrator and writes its temporary password only to the chosen file. The account must change that password before accessing data. Keep the output outside the repository.

## Android signing and GitHub releases

GitHub secrets: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_PASSWORD`; alias `financegpt`. Keep the same keystore for future updates. The workflow fails if signing material is missing and publishes an APK, Web ZIP, and checksums. The Gradle distribution is checksum-pinned; CI uses a Kotlin Maven mirror to avoid unavailable redirected compiler downloads.

Before public production use, configure monitored backups/restore drills and an operational identity-proof procedure for admin-assisted resets. Existing server applications are not moved or reconfigured by this repository.
