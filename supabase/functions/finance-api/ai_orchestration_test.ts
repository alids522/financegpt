import { aiRoute } from "./ai.ts";
function assert(v: unknown, m = "Assertion failed"): void {
  if (!v) throw Error(m);
}
class MemoryDB {
  tables: Record<string, any[]> = {};
  seq = 0;
  storage = {
    from: (_name: string) => ({
      upload: async () => ({ data: { path: "test" }, error: null }),
      remove: async () => ({ data: [], error: null }),
    }),
  };
  from(t: string) {
    this.tables[t] ??= [];
    return new Query(this, t);
  }
}
class Query implements PromiseLike<any> {
  filters: ((r: any) => boolean)[] = [];
  op = "select";
  payload: any;
  one = false;
  max = 10000;
  column = "";
  ascending = true;
  constructor(public db: MemoryDB, public table: string) {}
  select(_v = "*") {
    return this;
  }
  eq(k: string, v: any) {
    this.filters.push((r) => r[k] === v);
    return this;
  }
  gt(k: string, v: any) {
    this.filters.push((r) => r[k] > v);
    return this;
  }
  in(k: string, v: any[]) {
    this.filters.push((r) => v.includes(r[k]));
    return this;
  }
  or(_s: string) {
    this.filters.push((r) =>
      !r.busy_until || Date.parse(r.busy_until) < Date.now()
    );
    return this;
  }
  ilike(k: string, v: string) {
    this.filters.push((r) =>
      String(r[k]).toLowerCase().includes(v.replace(/%/g, "").toLowerCase())
    );
    return this;
  }
  order(k: string, o?: any) {
    this.column = k;
    this.ascending = o?.ascending !== false;
    return this;
  }
  limit(n: number) {
    this.max = n;
    return this;
  }
  single() {
    this.one = true;
    return this;
  }
  maybeSingle() {
    this.one = true;
    return this;
  }
  insert(p: any) {
    this.op = "insert";
    this.payload = p;
    return this;
  }
  upsert(p: any, _o?: any) {
    return this.insert(p);
  }
  update(p: any) {
    this.op = "update";
    this.payload = p;
    return this;
  }
  delete() {
    this.op = "delete";
    return this;
  }
  then<TResult1 = any, TResult2 = never>(
    ok?: ((v: any) => TResult1 | PromiseLike<TResult1>) | null,
    fail?: ((e: any) => TResult2 | PromiseLike<TResult2>) | null,
  ): PromiseLike<TResult1 | TResult2> {
    try {
      const all = this.db.tables[this.table];
      let rows = all.filter((r) => this.filters.every((f) => f(r)));
      if (this.op === "insert") {
        const n = ++this.db.seq;
        const row = {
          id: this.table === "ai_messages"
            ? n
            : `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`,
          summary: "",
          summary_through: 0,
          busy_until: null,
          status: "pending",
          title: "Chat baru",
          created_at: new Date().toISOString(),
          ...this.payload,
        };
        all.push(row);
        rows = [row];
      }
      if (this.op === "update") {
        for (const r of rows) Object.assign(r, this.payload);
      }
      if (this.op === "delete") {
        this.db.tables[this.table] = all.filter((r) => !rows.includes(r));
      }
      if (this.column) {
        rows.sort((a, b) =>
          (a[this.column] > b[this.column] ? 1 : -1) * (this.ascending ? 1 : -1)
        );
      }
      const value = {
        data: this.one ? rows[0] || null : rows.slice(0, this.max),
        error: null,
      };
      return Promise.resolve(value).then(ok, fail);
    } catch (e) {
      return Promise.reject(e).then(ok, fail);
    }
  }
}
async function fixture() {
  const db = new MemoryDB();
  const mutations: any[] = [];
  const d = {
    db,
    uid: "11111111-1111-4111-8111-111111111111",
    profile: { timezone: "Asia/Jakarta", base_currency: "IDR" },
    tools: [],
    checked: async (q: any) => {
      const r = await q;
      if (r.error) throw r.error;
      return r.data;
    },
    route: async (path: string, method: string, body?: any, key?: string) => {
      mutations.push({ path, method, body, key });
      return { status: "ok", data: { id: "transaction1" } };
    },
  };
  const request = (path: string, method: string, p?: any) =>
    aiRoute(
      path,
      new Request("https://example.com" + path, {
        method,
        body: p ? JSON.stringify(p) : undefined,
      }),
      d,
    );
  const provider = await request("/ai/providers", "POST", {
    name: "Test provider",
    format: "openai",
    base_url: "https://example.com/v1",
    api_key: "never-return-this-key",
    model: "test-model",
    context_tokens: 32000,
    output_tokens: 1024,
    vision: true,
    tools: true,
    auto_record: false,
  });
  const chat = await request("/ai/chats", "POST", { provider_id: provider.id });
  return { db, d, request, provider, chat, mutations };
}
function assistant(text: string, calls: any[] = [], finish = "stop") {
  return Response.json({
    choices: [{
      finish_reason: finish,
      message: {
        content: text,
        tool_calls: calls.map((args, i) => ({
          id: "call" + i,
          type: "function",
          function: { name: "finance_write", arguments: JSON.stringify(args) },
        })),
      },
    }],
    usage: { prompt_tokens: 20, completion_tokens: 10 },
  });
}
async function isolated(fn: () => Promise<void>) {
  const fetch = globalThis.fetch, dns = Deno.resolveDns;
  const old = Deno.env.get("FINANCE_AI_MASTER_KEY");
  Deno.env.set("FINANCE_AI_MASTER_KEY", btoa("k".repeat(32)));
  Deno.resolveDns =
    ((_h: string, type: string) =>
      Promise.resolve(type === "A" ? ["8.8.8.8"] : [])) as any;
  try {
    await fn();
  } finally {
    globalThis.fetch = fetch;
    Deno.resolveDns = dns;
    if (old) Deno.env.set("FINANCE_AI_MASTER_KEY", old);
    else Deno.env.delete("FINANCE_AI_MASTER_KEY");
  }
}
Deno.test("AI encrypts credentials with owner binding and isolates chat lookup", () =>
  isolated(async () => {
    const f = await fixture();
    const raw = f.db.tables.ai_providers[0];
    assert(!raw.api_key_ciphertext.includes("never-return"));
    assert(
      !JSON.stringify(await f.request("/ai/providers", "GET")).includes(
        "api_key",
      ),
    );
    const other = { ...f.d, uid: "22222222-2222-4222-8222-222222222222" };
    let failed = false;
    try {
      await aiRoute(
        "/ai/chats/" + f.chat.id + "/send",
        new Request("https://example.com", {
          method: "POST",
          body: JSON.stringify({
            text: "read foreign",
            request_key: "request-111",
          }),
        }),
        other,
      );
    } catch {
      failed = true;
    }
    assert(failed);
    assert(f.mutations.length === 0);
  }));
Deno.test("AI write is proposed, confirmed once and retries do not duplicate", () =>
  isolated(async () => {
    const f = await fixture();
    let calls = 0;
    globalThis.fetch = async () =>
      ++calls === 1
        ? assistant("", [{
          path: "transactions",
          method: "POST",
          payload: { amount: 35000 },
        }])
        : assistant("Periksa konfirmasi.");
    const input = { text: "Catat 35000", request_key: "request-123" };
    await f.request("/ai/chats/" + f.chat.id + "/send", "POST", input);
    assert(f.mutations.length === 0);
    const action = f.db.tables.ai_actions[0];
    assert(action.status === "pending");
    await f.request("/ai/actions/" + action.id + "/approve", "POST", {});
    await f.request("/ai/actions/" + action.id + "/approve", "POST", {});
    assert(f.mutations.length === 1);
    await f.request("/ai/chats/" + f.chat.id + "/send", "POST", input);
    assert(f.mutations.length === 1);
    assert(calls === 2);
  }));
Deno.test("AI blocks administrative tool paths and truncated tool execution", () =>
  isolated(async () => {
    for (const truncated of [false, true]) {
      const f = await fixture();
      let calls = 0;
      globalThis.fetch = async () =>
        ++calls === 1
          ? assistant("", [{
            path: "admin/users",
            method: "POST",
            payload: {},
          }], truncated ? "length" : "tool_calls")
          : assistant("Ditolak.");
      await f.request("/ai/chats/" + f.chat.id + "/send", "POST", {
        text: "admin",
        request_key: "request-123",
      });
      assert(f.mutations.length === 0);
      assert((f.db.tables.ai_actions || []).length === 0);
    }
  }));
Deno.test("receipt auto record requires opt-in and matching arithmetic", () =>
  isolated(async () => {
    for (const valid of [false, true]) {
      const f = await fixture();
      f.db.tables.ai_providers[0].auto_record = true;
      let calls = 0;
      globalThis.fetch = async () =>
        ++calls === 1
          ? assistant("", [{
            path: "transactions",
            method: "POST",
            receipt: true,
            receipt_complete: true,
            verified_total: 35000,
            receipt_totals: {
              subtotal: valid ? 35000 : 30000,
              discount: 0,
              tax: 0,
              total: 35000,
            },
            payload: {
              amount: 35000,
              type: "expense",
              currency: "IDR",
              account_id: "own",
              category_id: "own",
              effective_at: "2026-11-10T12:00:00Z",
            },
          }])
          : assistant("Selesai.");
      await f.request("/ai/chats/" + f.chat.id + "/send", "POST", {
        text: "Struk belanja",
        request_key: "request-123",
        attachment: {
          name: "receipt.png",
          data: btoa(String.fromCharCode(137, 80, 78, 71, 0, 0, 0)),
        },
      });
      assert(f.mutations.length === (valid ? 1 : 0));
      if (valid) {
        assert(f.mutations[0].body.source_ref.startsWith("ai-receipt:"));
        assert(f.mutations[0].body.attachment_path.startsWith(f.d.uid + "/"));
      } else assert(f.db.tables.ai_actions.length === 1);
    }
  }));
Deno.test("long conversations compact persisted history before inference", () =>
  isolated(async () => {
    const f = await fixture();
    for (let i = 0; i < 12; i++) {
      await f.d.checked(
        f.db.from("ai_messages").insert({
          user_id: f.d.uid,
          chat_id: f.chat.id,
          role: i % 2 ? "assistant" : "user",
          content: "x".repeat(5000),
        }),
      );
    }
    let summaries = 0;
    globalThis.fetch = async (_u, init) => {
      const b = JSON.parse(String(init?.body));
      if (b.messages[0].content.startsWith("Summarize")) {
        summaries++;
        return assistant(
          "User sedang merencanakan anggaran; tidak ada transaksi tersimpan.",
        );
      }
      return assistant("Lanjut.");
    };
    const r = await f.request("/ai/chats/" + f.chat.id + "/send", "POST", {
      text: "Lanjutkan",
      request_key: "request-123",
    });
    assert(summaries > 0);
    assert(r.usage_json.compacted === true);
    assert(f.db.tables.ai_chats[0].summary_through > 0);
  }));

Deno.test("original history retrieval is bound to both owner and chat", () =>
  isolated(async () => {
    const f = await fixture();
    await f.d.checked(
      f.db.from("ai_messages").insert({
        user_id: f.d.uid,
        chat_id: f.chat.id,
        role: "user",
        content: "Merchant owned note",
      }),
    );
    await f.d.checked(
      f.db.from("ai_messages").insert({
        user_id: "other-user",
        chat_id: f.chat.id,
        role: "user",
        content: "Merchant FOREIGN SECRET",
      }),
    );
    let calls = 0;
    globalThis.fetch = async (_u, init) => {
      if (++calls === 1) {
        return Response.json({
          choices: [{
            message: {
              content: "",
              tool_calls: [{
                id: "history1",
                type: "function",
                function: {
                  name: "finance_history",
                  arguments: JSON.stringify({ query: "Merchant" }),
                },
              }],
            },
          }],
        });
      }
      const body = String(init?.body);
      assert(body.includes("owned note"));
      assert(!body.includes("FOREIGN SECRET"));
      return assistant("Riwayat milik Anda.");
    };
    await f.request("/ai/chats/" + f.chat.id + "/send", "POST", {
      text: "Cari Merchant lama",
      request_key: "request-history",
    });
    assert(calls === 2);
  }));
