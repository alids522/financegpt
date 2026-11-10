import { managed } from "./managed.ts";
const uuid = { type: "string", format: "uuid" };
const transaction = {
  type: "object",
  required: ["type", "amount_minor", "currency", "account_id", "effective_at"],
  properties: {
    type: { enum: ["expense", "income", "transfer", "adjustment"] },
    amount_minor: { type: "integer", minimum: 1, maximum: 9000000000000000 },
    currency: { type: "string", pattern: "^[A-Z]{3}$" },
    account_id: uuid,
    destination_account_id: uuid,
    category_id: uuid,
    effective_at: { type: "string", format: "date-time" },
    status: { enum: ["draft", "pending", "posted", "voided"] },
    merchant: { type: "string" },
    description: { type: "string" },
    notes: { type: "string" },
    tags: { type: "array", items: { type: "string" } },
    expected_version: { type: "integer", minimum: 1 },
  },
};
export function openapi(base: string) {
  const key = {
    name: "Idempotency-Key",
    in: "header",
    required: true,
    schema: { type: "string", minLength: 8, maxLength: 200 },
  };
  const responses = {
    "200": { description: "Successful result" },
    "201": { description: "Created" },
    "202": { description: "Accepted or pending approval" },
    "400": { description: "Validation error" },
    "401": { description: "Authentication required" },
    "403": { description: "Ownership, permission, status, or session denied" },
    "409": { description: "Version or idempotency conflict" },
    "429": { description: "Rate limit exceeded" },
  };
  const operation = (
    summary: string,
    method = "get",
    schema: unknown = { type: "object" },
  ) => ({
    summary,
    security: [{ bearerAuth: [] }],
    parameters: method === "get" ? [] : [key],
    ...(method === "get" ? {} : {
      requestBody: {
        required: true,
        content: { "application/json": { schema } },
      },
    }),
    responses,
  });
  const paths: Record<string, unknown> = {};
  for (
    const resource of [
      "accounts",
      "categories",
      "transaction-templates",
      "budgets",
    ]
  ) {
    paths["/" + resource] = {
      get: operation("List owned " + resource),
      post: operation("Create " + resource, "post"),
    };
    paths["/" + resource + "/{id}"] = {
      parameters: [{ name: "id", in: "path", required: true, schema: uuid }],
      patch: operation(
        "Update owned " + resource + "; budgets require expected_version",
        "patch",
      ),
    };
  }
  paths["/accounts/{id}/reconcile"] = {
    parameters: [{ name: "id", in: "path", required: true, schema: uuid }],
    post: operation(
      "Reconcile to statement balance with reason and audit",
      "post",
      {
        type: "object",
        required: ["statement_balance", "reason"],
        properties: {
          statement_balance: { type: "integer" },
          reason: { type: "string", minLength: 3 },
        },
      },
    ),
  };
  (paths["/transaction-templates/{id}"] as Record<string, unknown>).delete =
    operation(
      "Delete an owned template; historical transactions remain intact",
      "delete",
    );
  paths["/tokens"] = {
    get: operation("List own token metadata; secrets are never returned"),
    post: operation(
      "Generate per-user API/MCP token; trusted user login only",
      "post",
      {
        type: "object",
        required: ["name"],
        properties: {
          name: { type: "string", maxLength: 80 },
          expires_in_days: { type: "integer", minimum: 1, maximum: 365 },
        },
      },
    ),
  };
  paths["/tokens/{id}"] = {
    parameters: [{ name: "id", in: "path", required: true, schema: uuid }],
    delete: operation("Permanently revoke own token", "delete"),
  };
  paths["/accounts/{id}/statement"] = {
    parameters: [{ name: "id", in: "path", required: true, schema: uuid }],
    get: {
      ...operation(
        "Bank-style journal statement; inclusive user-timezone dates",
      ),
      parameters: [{
        name: "start",
        in: "query",
        required: true,
        schema: { type: "string", format: "date" },
      }, {
        name: "end",
        in: "query",
        required: true,
        schema: { type: "string", format: "date" },
      }],
    },
  };
  paths["/transactions"] = {
    get: {
      ...operation("Cursor-paginated transactions"),
      parameters: [
        "start",
        "end",
        "account_id",
        "category_id",
        "type",
        "status",
        "currency",
        "search",
        "cursor",
      ].map((name) => ({ name, in: "query", schema: { type: "string" } }))
        .concat(
          [{
            name: "limit",
            in: "query",
            schema: { type: "integer", minimum: 1, maximum: 200 },
          }] as any,
        ),
    },
    post: operation(
      "Atomic financial posting; OAuth clients obey approval policy",
      "post",
      transaction,
    ),
  };
  paths["/transactions/{id}"] = {
    parameters: [{ name: "id", in: "path", required: true, schema: uuid }],
    get: operation("Read owned transaction"),
    patch: operation(
      "Versioned correction through reversal journal",
      "patch",
      transaction,
    ),
  };
  paths["/transfers"] = {
    post: operation(
      "Atomic same-currency transfer; no real bank movement",
      "post",
      transaction,
    ),
  };
  for (
    const resource of [
      "analytics/summary",
      "analytics/categories",
      "analytics/cashflow",
      "budgets/actual",
      "forecasts",
      "agents/connections",
      "agents/approvals",
      "agents/audit",
      "admin/users",
      "admin/audit",
    ]
  ) paths["/" + resource] = { get: operation("Read " + resource) };
  paths["/forecasts/simulate"] = {
    post: operation("Deterministic simulation, no actual mutation", "post"),
  };
  paths["/imports"] = {
    post: operation(
      "Create normalized CSV/PDF preview; no posting before confirmation",
      "post",
      {
        type: "object",
        required: ["rows"],
        properties: {
          format: { enum: ["csv", "pdf"] },
          rows: { type: "array", maxItems: 1000, items: transaction },
        },
      },
    ),
  };
  paths["/imports/extract-pdf"] = {
    post: operation(
      "Extract text from digital PDF; trusted user and mandatory review",
      "post",
      {
        type: "object",
        required: ["data"],
        properties: { data: { type: "string", contentEncoding: "base64" } },
      },
    ),
  };
  paths["/imports/{id}"] = {
    parameters: [{ name: "id", in: "path", required: true, schema: uuid }],
    get: operation("Read owned import and preview"),
  };
  paths["/imports/{id}/confirm"] = {
    parameters: [{ name: "id", in: "path", required: true, schema: uuid }],
    post: operation("Confirm reviewed rows atomically", "post", {
      type: "object",
      required: ["reviewed"],
      properties: { reviewed: { const: true } },
    }),
  };
  paths["/exports"] = {
    get: operation("List export jobs"),
    post: operation(
      "Queue private CSV/PDF report; agents require user approval",
      "post",
    ),
  };
  paths["/exports/{id}"] = {
    parameters: [{ name: "id", in: "path", required: true, schema: uuid }],
    get: operation(
      "Poll job; completed jobs include a short-lived private download URL",
    ),
  };
  for (const action of ["approve", "reject"]) {
    paths["/agents/approvals/{id}/" + action] = {
      parameters: [{ name: "id", in: "path", required: true, schema: uuid }],
      post: operation(
        "Trusted user " + action + "; Agent self-approval is denied",
        "post",
      ),
    };
  }
  for (
    const action of [
      "suspend",
      "reactivate",
      "reset-password",
      "force-logout",
      "change-role",
    ]
  ) {
    paths["/admin/users/{id}/" + action] = {
      parameters: [{ name: "id", in: "path", required: true, schema: uuid }],
      post: operation(
        "Admin " + action + " with reason and immutable audit",
        "post",
        {
          type: "object",
          required: ["reason"],
          properties: {
            reason: { type: "string", minLength: 3 },
            identity_proof: { type: "string" },
            role: { enum: ["user", "admin"] },
          },
        },
      ),
    };
  }
  (paths["/transactions/{id}"] as Record<string, unknown>).delete = operation(
    "Void owned transaction with expected_version and reason; agents require approval",
    "delete",
  );
  for (const [path, [table, scope]] of Object.entries(managed)) {
    paths["/" + path] = {
      get: operation(
        "List own " + table + "; token scope " + scope +
          ":read; offset/limit pagination",
      ),
      post: operation(
        "Create " + table + "; token scope " + scope + ":write",
        "post",
      ),
    };
    paths["/" + path + "/{id}"] = {
      parameters: [{ name: "id", in: "path", required: true, schema: uuid }],
      get: operation("Read own " + table),
      patch: operation(
        "Patch " + table + "; expected_version required",
        "patch",
      ),
      delete: operation(
        "Delete/archive/disable " + table +
          "; expected_version required; token requires approval",
        "delete",
      ),
    };
  }
  for (
    const [path, methods] of Object.entries({
      "providers": ["get", "post"],
      "providers/{id}": ["patch", "delete"],
      "providers/{id}/models": ["post"],
      "providers/{id}/test": ["post"],
      "chats": ["get", "post"],
      "chats/{id}": ["delete"],
      "chats/{id}/messages": ["get"],
      "chats/{id}/send": ["post"],
      "actions/{id}/approve": ["post"],
      "actions/{id}/reject": ["post"],
    })
  ) {
    paths["/ai/" + path] = {
      ...(path.includes("{id}")
        ? {
          parameters: [{
            name: "id",
            in: "path",
            required: true,
            schema: uuid,
          }],
        }
        : {}),
      ...Object.fromEntries(
        methods.map(
          (method) => [
            method,
            operation(
              "Trusted owner session only; personal API tokens cannot manage AI settings, chats or approvals. " +
                path,
              method,
            ),
          ],
        ),
      ),
    };
  }
  return {
    openapi: "3.1.0",
    info: {
      title: "Adoetz Finance API",
      version: "1.0.0",
      description:
        "Integer minor units. UTC timestamps with user-timezone reporting. Account ownership, active sessions, idempotency and per-user personal token permissions are enforced server-side.",
    },
    servers: [{ url: base + "/api/v1" }],
    components: {
      securitySchemes: {
        bearerAuth: {
          type: "http",
          scheme: "bearer",
          bearerFormat: "Personal token fgt_... (UI uses Supabase session JWT)",
        },
      },
      schemas: { Transaction: transaction },
    },
    paths,
  };
}
