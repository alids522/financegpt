export const managed = {
  "categories": ["categories", "categories"],
  "transaction-templates": ["transaction_templates", "templates"],
  "recurring": ["recurring_rules", "recurring"],
  "savings-goals": ["savings_goals", "goals"],
  "goal-allocations": ["goal_allocations", "goals"],
  "debts": ["debts", "debts"],
  "debt-payments": ["debt_payments", "debts"],
} as const;
export const managedTools = Object.entries(managed).flatMap((
  [path, [table, scope]],
) => [
  {
    name: "list_" + table,
    scope: scope + ":read",
    path,
    method: "GET",
    description: "List own " + table + "; bounded pagination.",
    parameters: {
      type: "object",
      properties: {
        offset: { type: "integer", minimum: 0 },
        limit: { type: "integer", minimum: 1, maximum: 100 },
      },
      additionalProperties: false,
    },
  },
  ...["create", "update", "delete"].map((verb, i) => ({
    name: verb + "_" + table,
    scope: scope + ":write",
    path,
    method: ["POST", "PATCH", "DELETE"][i],
    description: verb + " own " + table +
      ". Monetary fields are integer minor units. Edit/delete requires record_id and current expected_version. Categories delete archives, recurring delete disables. Allocations and payment records are bookkeeping; they do not move money. Deletion and payments require owner approval.",
    parameters: {
      type: "object",
      properties: {
        record_id: { type: "string" },
        payload: { type: "object", description: resourceFields(table) },
        idempotency_key: { type: "string", minLength: 8 },
      },
      required: i === 0
        ? ["payload", "idempotency_key"]
        : ["record_id", "payload", "idempotency_key"],
      additionalProperties: false,
    },
  })),
]);
function resourceFields(t: string) {
  return ({
    categories:
      "name,type(income/expense),parent_id,color,icon,archived,sort_order,default_budget",
    transaction_templates:
      "name,payload_json(transaction account_id,category_id,type,amount,currency,etc),favourite,sort_order",
    recurring_rules:
      "name,next_at(ISO),cadence(daily/weekly/monthly/yearly),payload_json(transaction),mode(draft/pending/auto-post),active,end_at",
    savings_goals:
      "name,target_amount,target_date(YYYY-MM-DD),account_id,currency",
    goal_allocations: "goal_id,amount,notes",
    debts:
      "name,counterparty,kind(debt/receivable),principal,rate,due(YYYY-MM-DD),currency",
    debt_payments:
      "debt_id,transaction_id(optional existing own ledger transaction),principal_paid,interest_paid",
  } as Record<string, string>)[t] +
    "; PATCH/DELETE also expected_version. Omit id,user_id,created_at.";
}
