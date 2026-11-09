# Finance Tracker

Flutter Web, Android, and iOS source implementing the [Finance Tracker PRD v1.0](docs/Finance_Tracker_PRD_v1.0.md). Indonesian UI, Inter typography, translucent glass light/dark/system themes, desktop sidebar/tablet rail/mobile drawer, and no bottom navigation.

The [visual refresh](docs/UI_REFRESH.md) follows the user-provided reference images, with blue glass surfaces, flowing backgrounds, rounded cards, a horizontal account carousel, balance visibility, and responsive dashboard charts. This newer visual direction supersedes the original PRD appearance tokens.

## Download

Get the signed Android APK, Web bundle, and SHA-256 checksums from [GitHub Releases](https://github.com/alids522/financegpt/releases). The [build workflow](https://github.com/alids522/financegpt/actions/workflows/build.yml) runs formatting, static analysis, 28 unit/widget tests, Android release signing, and Web compilation. iOS source is included; an iOS distribution build requires macOS and Apple signing.

Latest verified update: [build 17 APK](https://github.com/alids522/financegpt/releases/download/v1.0.0-build.17/finance-tracker-android.apk), with personal API/MCP tokens, per-account PDF/CSV statements, dashboard forecast, Android Back handling and a floating mobile drawer. See the [verification record](docs/TOKENS_STATEMENTS.md).

## Implemented

- Signup without email confirmation, username/email login, session checks, password change, and audited admin-assisted password reset with a forced change. No email forgot-password flow.
- User-owned accounts, integer minor-unit ledger, atomic same-currency transfers, opening balances, reconciliations, reversals, refunds, split categories, transaction versions, and idempotent retries. Internal transfers never become income/expense.
- Categories/subcategories, templates, typed custom fields, configurable optional transaction fields, search/filter/sort/pagination, saved views, and calendar/timezone period boundaries.
- Per-account e-statements in PDF/CSV with inclusive custom dates or complete calendar months, opening/debit/credit/closing and running balances from the ledger.
- Dashboard and analytics, budget/actual/remaining/projected variance, deterministic run-rate/scheduled/hybrid forecast, assumptions, scenario simulation, and low-confidence labels. Currency balances are reported separately; no invented FX conversion.
- CSV import/export and digital PDF extraction/import with mapping, explicit review, validation, duplicate choices, and idempotent chunks. Native reports and queued REST/MCP exports support CSV/PDF transactions, budget, and forecast datasets. Private export links expire.
- Generate per-user personal tokens directly in API & AI Agents for both REST and remote MCP. Tokens are shown once, stored only as SHA-256 hashes, expire after 1–365 days, and support read/write scopes, account/category restrictions, approval, pause/revocation and audit. Finance OAuth integration is retired; token credentials cannot authenticate to the shared Supabase Data API or other applications.
- Admin metadata search, suspension/reactivation, role changes, forced logout, and password reset with reason/proof. Admin status grants no access to another user's finance records.
- Floating rounded mobile drawer, direct dashboard forecast, and Android Back navigation: subpages return to dashboard, then two Back presses within two seconds exit.
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
