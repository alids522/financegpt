# Personal tokens, e-statements and navigation update

User-requested changes on 2026-11-09:

- Finance external API and MCP now authenticate with generated personal tokens instead of OAuth. Registration and token generation are separate from the server-wide Supabase Auth account pool. Tokens bind to an immutable owner ID, have per-connection policies, expose their secret only once and store a SHA-256 hash in an unexposed private table with RLS. Revocation and expiry are checked on requests and again on financial execution/approval.
- Each account exports a PDF/CSV e-statement for full calendar months or inclusive custom dates. Opening and running balances come from authoritative journal entries, including internal transfers, refunds, corrections and opening equity. Nothing is silently dropped from export; oversized ranges are rejected explicitly.
- Dashboard has a selected Forecast mode, actual and projected lines, a labeled deterministic estimate, budget guide and link to assumptions. A zero-actual/nonzero-budget regression protects chart rendering.
- Android Back closes the drawer first, sends subpages to the dashboard, and requires a second Back within two seconds on the dashboard to exit. Main content returns to the top when switching pages.
- The mobile drawer's outer sheet is transparent. Only the inset rounded glass panel floats above the dimmed screen, leaving status/navigation safe areas outside the panel.

Verification: 28 Flutter tests, strict analysis/formatting, a real generated PDF parsed for opening/closing values and transaction text, rollback-only SQL acceptance, and end-to-end live REST/MCP tests with two newly created QA accounts. The live tests verified read-only defaults, per-user isolation, token-management denial to PATs, no required apikey header, idempotent financial writes, approvals, transfer statements, cross-user denial, immediate revocation and expiry. Only those newly created QA accounts and fixtures were removed afterward.

SQL regression: `supabase/tests/token_statement_acceptance.sql`. Client regressions: `test/token_statement_widget_test.dart`, `test/domain_test.dart`, `test/shell_widget_test.dart`.

The initial migration plus the personal-token/statement upgrade were applied on an isolated empty database with Supabase Auth/Storage interfaces and pgcrypto; both ledger/RLS and new token/statement SQL acceptance passed. The exact temporary database was removed. Supabase CLI security advisors completed over the authorized SSH tunnel with no Finance-related warning/error findings. Shared-app findings were outside this change.

## Verified release

[Build 17](https://github.com/alids522/financegpt/actions/runs/42628017898) passed all checks and published the [signed APK and Web bundle](https://github.com/alids522/financegpt/releases/tag/v1.0.0-build.17). App source: `59cdb9ebbf94673781bfea9a28313b4e588a141e`.

The downloaded APK matched the artifact checksum manifest and GitHub release digest: `00311aace8993f6102ff51f466d76e4591fb59f4d024c1a86933eb15eeeb35ad`. Android apksigner verified its v2 signature with the same persistent release certificate as previous builds (`bac212873b8f49fe3a565736e52dcdfa3f3bc78ca3803f9e52345759b5db9d3d`). Package inspection confirmed `id.financegpt.finance_tracker`, version `1.0.0`/`17`, INTERNET permission, and arm64-v8a, armeabi-v7a and x86_64 support.

The generated statement PDF was also rendered and visually inspected: the account/period header, opening and closing summaries, debit/credit/running-balance table, and page footer were readable with no clipping or overlap.
