# Finance Tracker

Flutter Web, Android, and iOS source implementing the [Finance Tracker PRD v1.0](docs/Finance_Tracker_PRD_v1.0.md). Indonesian UI, Inter typography, restrained light/dark/system themes, desktop sidebar/tablet rail/mobile drawer, and no bottom navigation.

## Download

Get the signed Android APK, Web bundle, and SHA-256 checksums from [GitHub Releases](https://github.com/alids522/financegpt/releases). The [build workflow](https://github.com/alids522/financegpt/actions/workflows/build.yml) runs formatting, static analysis, 22 unit/widget tests, Android release signing, and Web compilation. iOS source is included; an iOS distribution build requires macOS and Apple signing.

## Implemented

- Signup without email confirmation, username/email login, session checks, password change, and audited admin-assisted password reset with a forced change. No email forgot-password flow.
- User-owned accounts, integer minor-unit ledger, atomic same-currency transfers, opening balances, reconciliations, reversals, refunds, split categories, transaction versions, and idempotent retries. Internal transfers never become income/expense.
- Categories/subcategories, templates, typed custom fields, configurable optional transaction fields, search/filter/sort/pagination, saved views, and calendar/timezone period boundaries.
- Dashboard and analytics, budget/actual/remaining/projected variance, deterministic run-rate/scheduled/hybrid forecast, assumptions, scenario simulation, and low-confidence labels. Currency balances are reported separately; no invented FX conversion.
- CSV import/export and digital PDF extraction/import with mapping, explicit review, validation, duplicate choices, and idempotent chunks. Native reports and queued REST/MCP exports support CSV/PDF transactions, budget, and forecast datasets. Private export links expire.
- OAuth PKCE remote MCP, permission-aware tool listing, account/category policy restrictions, write thresholds, trusted-user approval, immediate connection revocation, and audit logs. OAuth tokens cannot bypass policy through the Data API.
- Admin metadata search, suspension/reactivation, role changes, forced logout, and password reset with reason/proof. Admin status grants no access to another user's finance records.
- Basic recurring schedules, goals, and debts are included as early P1 functionality.

The PRD explicitly phases the mature persistent offline queue, advanced calibrated forecast history/confidence, bulk editing/merge, and full backup/restore as P1; OCR of scanned PDFs, household and investment tracking are P2. They are not represented as completed functionality. This release is online-first with an in-memory list cache and stable retry keys. Automated widget tests cover shared UI at 360/768/1366 widths in both themes. Device E2E and performance/chaos targets have not been measured.

## Backend

- Supabase: `https://supabase.adoetz52.my.id`
- Application schema: `financegpt` (privileged helpers: `finance_private`)
- REST: `https://supabase.adoetz52.my.id/functions/v1/finance-api/api/v1`
- [OpenAPI](https://supabase.adoetz52.my.id/functions/v1/finance-api/openapi.json)
- MCP: `https://supabase.adoetz52.my.id/functions/v1/finance-api/mcp`

The client contains only the public anon key. Service credentials, SSH credentials, administrator passwords, and Android signing backups are excluded from Git. See [deployment](docs/DEPLOYMENT.md) and [verification](docs/VERIFICATION.md).

## Development

Flutter 3.44.1 / Dart 3.12.1, Java 17, and an Android SDK are used by CI. Package versions and the lockfile are pinned.

```sh
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos
flutter test
flutter run
flutter build apk --release
flutter build web --release
```

Optional `--dart-define` values: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SCHEMA`, and `API_URL`. Defaults target the configured server. Local Android builds use debug signing unless `android/key.properties` is supplied; GitHub releases require the persistent signing secrets.

UI previews can be regenerated with `flutter test test/shell_widget_test.dart --dart-define=GENERATE_PREVIEWS=true --update-goldens`. Inter is distributed under its bundled OFL license.
