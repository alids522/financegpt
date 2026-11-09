# Verification record

Latest verification: [personal tokens, e-statements, navigation and build 17](TOKENS_STATEMENTS.md). The record below documents the original 2026-11-08 baseline; its OAuth integration has since been retired in favor of personal tokens.

Executed against the configured self-hosted backend on 2026-11-08. Test accounts were isolated fixtures, not real users. Production performance targets are not claimed from these functional checks.

| Area | Evidence |
|---|---|
| Release | [GitHub build 14](https://github.com/alids522/financegpt/actions/runs/42476635534) succeeded: signed APK, Web bundle, checksums and release assets |
| APK inspection | Downloaded artifact SHA-256 matched both manifest and GitHub release digest; apksigner verified v2/RSA release signature; aapt confirmed package `id.financegpt.finance_tracker`, version 1.0.0/14, INTERNET permission and three Android ABIs |
| Flutter | 22 tests passed; static analysis and formatting passed |
| Responsive UI | Dashboard, transactions, accounts, analytics, budgets, forecast, import/export, agents, settings at 360/768/1366 logical pixels, light and dark |
| Financial calculations | Integer amount parsing, USD edit round-trip, timezone boundaries, calendar weeks, PRD run-rate example, scheduled expansion, hybrid history fallback |
| CSV | Quoted newlines/delimiters/BOM, formula neutralization and native round-trip restoration |
| Fresh installation | Complete combined migration applied to an isolated empty database with Auth/Storage interfaces; ledger/RLS acceptance passed; exact temporary database removed |
| Policy regression | `supabase/tests/security_policy_acceptance.sql`: atomic policy updates, split-category restrictions, scoped analytics/forecast, destination policy checked again at approval |
| SQL acceptance | `test/database_acceptance.sql` rolls fixtures back; ledger, idempotent retry, conflict, transfer, pending/posting, refund, splits, budget versions, reconciliation, RLS, OAuth direct-API denial, session revocation |
| Authentication/admin | Immediate signup, username/email login, no cross-user financial access, protected role fields, suspension, last-admin protection, forced password change and renewed session |
| REST reports | OpenAPI/analytics/forecast; digital PDF extraction; scanned/image-only PDF rejected with OCR guidance; CSV/PDF queued jobs, retries, private download |
| MCP | Actual OAuth PKCE exchange, resource-bound token, tool permissions, small idempotent write, large-write approval, self/other-user approval denial, exactly-once execution, immediate revoke |
| MCP exports | Reports-only client can initialize; invalid policy update leaves permissions intact; budget and forecast exports require approval, expose job status and download the correct dataset |

Reproduce deterministic client checks with `flutter analyze --fatal-infos` and `flutter test`. Run SQL acceptance as an authorized database owner on a disposable Supabase database; the script wraps all fixtures in a rollback. Golden previews in `test/previews` are for visual review and optional regeneration, while widget geometry checks run on every CI build.

Not yet measured: physical Android/iOS device E2E, assistive-technology audit, p95 response-time/load/chaos targets, calibrated historical forecast accuracy. iOS distribution requires a separate Apple signing environment. Mature offline persistence and OCR remain their PRD P1/P2 phases.

Release APK SHA-256: `0dff0ba953ec6e2742ab2834fdd25b6f9ca304d214d1612b900fbe7db3665af9`. QA Auth users, finance fixtures, private report files and OAuth clients were removed after verification. The explicit administrator remains with forced password change and test sessions revoked.
