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
