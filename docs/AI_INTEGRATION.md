# Adoetz Finance: personal AI and resource API

This update adds user-owned AI connections and chat, plus REST/MCP control of categories, transaction templates, recurring rules, savings goals/allocations, debts and payment records. Branding uses the user-supplied wallet artwork and the display name Adoetz Finance; Android's package ID and release certificate stay compatible with existing installations.

## Setup

Open **Finance AI → Tambah provider**, choose the endpoint format, and enter a base URL and your own API key. Formats are OpenAI-compatible Chat Completions, Anthropic Messages, and Gemini native GenerateContent. Model brand does not choose the protocol: Gemini through an OpenAI-compatible gateway uses the OpenAI adapter.

Save and fetch models, or enter a model ID manually. Discovery may be unavailable on a gateway. Native Gemini model metadata can populate input/output limits; otherwise configure the documented limits yourself. A returned model ID does not verify generation eligibility, quota, image support, or tools. **Uji koneksi** explicitly spends provider quota to test text/tool transport. Vision is a separate user-configured capability and is not marked verified by a text test. The implementation does not silently switch providers.

The app sends the required conversation and document data to the selected endpoint. Keys are never sent to a model as prompt content, returned to clients after saving, or stored as plaintext in the database. AES-256-GCM uses a random nonce and authenticated owner ID. Credential tables, chat state, messages, uploads and actions have RLS enabled and no grants to anonymous/authenticated database clients. Server routes verify an active trusted user session and filter every object by owner; personal Finance API tokens cannot manage AI connections, chats or confirmations.

## Chat, memory and actions

Chats persist per user/provider. The app constructs each request from the system rules, a stored summary, relevant original history and the current message. A bounded history-search tool retrieves old original messages from the same owned chat. Current balances and financial calculations come from the finance API, not memory.

Context preflight conservatively estimates UTF-8 framing and image allocation, reserving output and a margin. This is an upper-bound heuristic for ordinary text, not an exact universal tokenizer or a guarantee for every vision model. Older messages are summarized in bounded batches before overflow; originals remain stored. Very long histories may require another request after partial compaction. A file/message that cannot fit receives an explicit error rather than silent truncation. Compaction is lossy; exact old details should be retrieved from originals. The selected model's actual limits remain authoritative.

Generation and tool execution are bounded (eight turns, at most eight calls per response, a request deadline, per-call timeout and per-user request limits). Truncated generations do not execute their tool calls. Financial writes normally create a visible proposal. Only the owning logged-in user can confirm/reject it; a lease and stable idempotency key prevent concurrent confirmation/retry from duplicating a write. App financial procedures still validate ownership, currency, versions, required fields and ledger rules. No arbitrary SQL, shell, URL fetching, admin/auth/token-management tools are exposed to the AI.

## Receipts and documents

Uploads support JPG, PNG, WEBP, PDF, UTF-8 TXT and CSV, maximum 5 MB. Files live in the private Finance bucket under the owner's prefix. Text and digital PDFs are extracted first. Scanned PDF pages are rendered to images for the chosen vision model; a maximum of eight scanned pages is allowed per analysis. Longer text/files receive a split-document instruction. A text-only model cannot read a photograph; the UI does not hide that limitation or reroute it elsewhere.

Uploaded documents, transaction descriptions, history and tool results are untrusted data, never permission sources. **Automatic receipt recording is off by default.** Opt-in automatic recording requires the model to report complete receipt fields, explicit account/category/currency/date, a positive integer expense, and matching subtotal minus discount plus tax and total. The server validates those numeric fields and finance ownership again. A source SHA-256 reference prevents the same uploaded bytes from creating duplicate receipt transactions. This does not prove OCR accuracy or detect every rephotographed/edited copy: uncertain readings require review, and visual extraction can still be wrong.

Deleting a chat/provider removes its messages, summary, proposals and unlinked upload files. Receipt files already referenced by a ledger transaction remain available as that transaction's evidence. Removing a connection removes the stored credential; it does not revoke the key at the external provider.

## Resource API and MCP

| REST path | Read/write scopes | Table |
|---|---|---|
| `/categories` | `categories:read`, `categories:write` | categories |
| `/transaction-templates` | `templates:read`, `templates:write` | transaction_templates |
| `/recurring` | `recurring:read`, `recurring:write` | recurring_rules |
| `/savings-goals`, `/goal-allocations` | `goals:read`, `goals:write` | savings_goals, goal_allocations |
| `/debts`, `/debt-payments` | `debts:read`, `debts:write` | debts, debt_payments |

Collection GET uses `limit` (1–100) and `offset`; POST creates. `/{id}` supports GET/PATCH/DELETE. Mutation requests require `Idempotency-Key`; PATCH/DELETE bodies require `expected_version` from `row_version`. Fields are described in MCP tool schemas and OpenAPI. Each table has list/create/update/delete MCP tools. New tokens include the new read scopes; existing tokens need their permissions updated in **API & AI Agents**.

Referenced categories are preserved by archiving; recurring DELETE disables the schedule. Other resource deletion follows foreign-key integrity. Token deletions, allocations/payments and auto-post recurring changes require owner approval; other writes follow the token policy. Restricted connections cannot access resources whose account/category scope cannot be enforced. Nested template/recurring account, category and split references must belong to the owner.

Goal allocations and debt-payment records are bookkeeping and do not move money by themselves. Link a payment to an actual owned ledger transaction when appropriate; do not double-count expenses. Overpayments and reducing principal below recorded payments are rejected. Financial transaction DELETE is a versioned, reason-required void/reversal, not deletion of journal evidence.

## Deployment and validation

Apply migration `20261110024941_ai_integration_resource_api.sql`, deploy all Finance API modules, and rebuild the private PDF worker. Set `FINANCE_AI_MASTER_KEY` to a persistent base64-encoded 32-byte random secret. On the configured self-hosted Edge Runtime, a deployment-injected private `ai_key.ts` module supplies the same persistent secret because arbitrary filesystem reads are not bundled into the function. The committed module contains an empty placeholder only. Keep the real module and encryption-key backup outside Git; rotating the master key requires re-encrypting existing provider credentials.

Checks: 31 Flutter unit/widget tests, strict analysis/formatting, 16 Deno adapter/orchestration tests, isolated fresh-database migrations and rollback acceptance, and live two-user REST/MCP/security/confirmation checks. Live digital PDF extraction and scanned-page rendering passed. QA fixtures were deleted using only their newly generated owner IDs. Provider generation itself is tested with mocked HTTP contracts; no real user's AI key was supplied or charged. Users can run the explicit connection test with their chosen provider/model.

## Verified release

[GitHub build 21](https://github.com/alids522/financegpt/actions/runs/42751207716) passed and published the [Adoetz Finance Android APK and Web bundle](https://github.com/alids522/financegpt/releases/tag/v1.0.0-build.21), from source `7342cae8b4a075ad33c1a310b0fb1df879f7f054`.

The downloaded APK is 70,070,171 bytes. Its SHA-256 matched both the artifact checksum manifest and GitHub release digest: `cdf26d08757e3b17bbb591c4542ace0690a77bf9d64829e619d7c7bb225eff49`. Android apksigner verified the persistent v2/RSA release certificate (`bac212873b8f49fe3a565736e52dcdfa3f3bc78ca3803f9e52345759b5db9d3d`). Package inspection confirmed `id.financegpt.finance_tracker`, version `1.0.0`/`21`, label **Adoetz Finance**, INTERNET permission and arm64-v8a/armeabi-v7a/x86_64 support. The APK launcher image matched the supplied-artwork-derived launcher PNG pixel for pixel, and its in-app branding asset matched the repository asset exactly.

Live schema security advisors completed with no Finance-related warning/error findings. The backend and private PDF worker are deployed. Visual review of the phone AI screen confirmed the supplied logo, readable action cards and upload/chat controls; physical-device E2E and real-provider generation remain separate from these checks.
