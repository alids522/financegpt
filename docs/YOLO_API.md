# API/MCP execution modes

Open **API & AI Agents → Atur izin dan batas → Mode eksekusi API / MCP**.

| Mode | Behavior |
|---|---|
| Risk | Existing conditional approvals, including transfers, voids, budget changes, exports, allocations/payments and auto-post recurring changes |
| Selalu minta approval | Every permitted write becomes an owner proposal |
| YOLO — langsung jalankan | Permitted requests execute immediately, including operations that otherwise always require approval |

YOLO bypasses approval triggers, including create/edit amount thresholds, backdated records and non-IDR requests. It does not grant scopes, remove account/category allowlists, bypass ownership or version checks, alter the ledger, remove daily/hourly caps, revive an expired/revoked token, or expose admin and permission management to tokens. Transaction deletion remains a traceable void/reversal.

The policy endpoint accepts `approval_mode: "risk" | "always" | "yolo"`. Only the trusted, logged-in token owner can change it. Permissions and the existing hard limits are preserved when changing mode in the app. Read-only tokens remain read-only in YOLO.

Enabling YOLO does not execute a backlog. An explicit identical retry of a still-pending request can execute once under the new policy. Rejected/expired proposals stay rejected/expired, changed payloads conflict, and current token/policy/ledger checks run again. Successful retries are idempotent and audited.

New tokens can inherit the owner's `profiles.settings_json.api_approval_mode` preference when it is `yolo`; other owners retain the existing `risk` default. Activation for the requesting owner's existing valid tokens and new-token preference was performed separately, without changing other users' settings, scopes, limits or financial records.

This mode controls Finance REST/MCP token execution. Finance AI chat confirmations and the MCP host application's own tool confirmation controls are separate.

Verification: fresh-database migration plus existing ledger/security/token/resource SQL acceptance and `supabase/tests/yolo_approval_acceptance.sql`; live REST/MCP tests using newly created QA owners; phone/tablet policy UI regression tests verifying mode persistence without changing scopes or limits. The live checks covered a pending transfer resumed exactly once, direct YOLO transaction void, category deletion and goal allocation, cross-owner denial, token policy escalation denial and a daily-cap rejection.
