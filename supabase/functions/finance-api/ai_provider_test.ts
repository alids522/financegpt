import {
  complete,
  decode,
  type Message,
  planWindow,
  privateIp,
  type Provider,
  wire,
} from "./ai_provider.ts";
import { permittedPath, sniff } from "./ai.ts";
function assert(v: unknown, m = "Assertion failed"): asserts v {
  if (!v) throw Error(m);
}
const p: Provider = {
  format: "openai",
  base_url: "https://example.com/v1",
  api_key: "test-key",
  model: "test-model",
  output_tokens: 1024,
};
const tool = {
  name: "read_accounts",
  description: "Read accounts",
  parameters: { type: "object", properties: {} },
};
const messages: Message[] = [{ role: "system", content: "System" }, {
  role: "user",
  content: "Receipt",
  images: [{ mime: "image/png", data: "aGVsbG8=" }],
}, {
  role: "assistant",
  content: "",
  calls: [{ id: "call-1", name: "read_accounts", args: {} }],
}, { role: "tool", callId: "call-1", content: "[]" }];
Deno.test("OpenAI-compatible text image and tool wire format", () => {
  const w = wire(p, messages, [tool]);
  const b = w.body as any;
  assert(w.url.endsWith("/chat/completions"));
  assert(w.headers.Authorization === "Bearer test-key");
  assert(
    b.messages[1].content[1].image_url.url.startsWith("data:image/png;base64,"),
  );
  assert(b.messages[2].tool_calls[0].id === "call-1");
  assert(b.messages[3].tool_call_id === "call-1");
  assert(b.tools[0].function.parameters.type === "object");
});
Deno.test("Anthropic image and matching tool result blocks", () => {
  const w = wire({ ...p, format: "anthropic" }, messages, [tool]);
  const b = w.body as any;
  assert(b.system === "System");
  assert(b.messages[0].content[1].source.media_type === "image/png");
  assert(b.messages[1].content[0].type === "tool_use");
  assert(b.messages[2].content[0].tool_use_id === "call-1");
  assert(b.tools[0].input_schema.type === "object");
});
Deno.test("Gemini retains opaque thought signatures on function calls", () => {
  const data = {
    candidates: [{
      content: {
        parts: [{
          thoughtSignature: "opaque-signature",
          functionCall: { name: "read_accounts", args: {} },
        }],
      },
    }],
  };
  const r = decode("gemini", data);
  const w = wire({ ...p, format: "gemini" }, [{
    role: "assistant",
    content: "",
    calls: r.calls,
  }, { role: "tool", callId: "read_accounts", content: "[]" }], [tool]);
  const b = w.body as any;
  assert(b.contents[0].parts[0].thoughtSignature === "opaque-signature");
  assert(b.contents[1].parts[0].functionResponse.name === "read_accounts");
});
Deno.test("all adapters normalize usage and truncation", () => {
  assert(
    decode("openai", {
      choices: [{ finish_reason: "length", message: { content: "cut" } }],
    }).truncated,
  );
  assert(
    decode("anthropic", { stop_reason: "max_tokens", content: [] }).truncated,
  );
  assert(
    decode("gemini", { candidates: [{ finishReason: "MAX_TOKENS" }] })
      .truncated,
  );
});
Deno.test("context budget reserves output, rejects huge prompts and charges images", () => {
  assert(
    planWindow([{ role: "user", content: "hello" }], [], 16000, 2048).fits,
  );
  assert(
    !planWindow([{ role: "user", content: "x".repeat(50000) }], [], 16000, 2048)
      .fits,
  );
  assert(!planWindow([messages[1]], [], 16000, 2048).fits);
});
Deno.test("SSRF guard identifies private networks and IPv4 mapped IPv6", () => {
  for (
    const ip of [
      "127.0.0.1",
      "10.0.0.2",
      "169.254.169.254",
      "192.168.1.1",
      "172.16.1.1",
      "100.64.0.1",
      "::1",
      "::ffff:127.0.0.1",
      "fc00::1",
    ]
  ) assert(privateIp(ip), ip);
  assert(!privateIp("8.8.8.8"));
  assert(!privateIp("2606:4700:4700::1111"));
});
Deno.test("file types are identified by bytes, binary HTML is rejected", () => {
  assert(sniff(new TextEncoder().encode("%PDF-1.7")) === "application/pdf");
  assert(sniff(new Uint8Array([255, 216, 255, 0])) === "image/jpeg");
  assert(sniff(new Uint8Array([0, 0, 1, 2])) === null);
  assert(sniff(new TextEncoder().encode("<script>bad</script>")) === null);
});
Deno.test("AI tool path allowlist denies auth admin arbitrary URLs and other AI secrets", () => {
  for (
    const path of [
      "admin/users",
      "auth/me",
      "tokens",
      "ai/providers",
      "https://evil.example",
      "../accounts",
    ]
  ) {
    let denied = false;
    try {
      permittedPath(path, false);
    } catch {
      denied = true;
    }
    assert(denied, path);
  }
  assert(
    permittedPath("transactions?limit=10", false) === "transactions?limit=10",
  );
});
Deno.test("legacy compatible output token parameter retries only a recognized unsupported field", async () => {
  const original = globalThis.fetch;
  let count = 0;
  try {
    globalThis.fetch = async (_url, init) => {
      const body = JSON.parse(String(init?.body));
      if (++count === 1) {
        assert(body.max_completion_tokens === 1024);
        return Response.json({ error: { param: "max_completion_tokens" } }, {
          status: 400,
        });
      }
      assert(body.max_tokens === 1024);
      assert(!("max_completion_tokens" in body));
      return Response.json({ choices: [{ message: { content: "ok" } }] });
    };
    assert(
      (await complete(p, [{ role: "user", content: "hello" }])).text === "ok",
    );
    assert(count === 2);
  } finally {
    globalThis.fetch = original;
  }
});
Deno.test("provider request integration normalizes actual HTTP response shapes", async () => {
  const original = globalThis.fetch;
  try {
    for (const format of ["openai", "anthropic", "gemini"] as const) {
      globalThis.fetch = async (_url, init) => {
        const body = JSON.parse(String(init?.body));
        assert(body.model === "test-model" || format === "gemini");
        return Response.json(
          format === "openai"
            ? {
              choices: [{
                message: {
                  content: "ok",
                  tool_calls: [{
                    id: "1",
                    function: { name: "read_accounts", arguments: "{}" },
                  }],
                },
              }],
            }
            : format === "anthropic"
            ? {
              content: [{ type: "text", text: "ok" }, {
                type: "tool_use",
                id: "1",
                name: "read_accounts",
                input: {},
              }],
            }
            : {
              candidates: [{
                content: {
                  parts: [{ text: "ok" }, {
                    functionCall: { name: "read_accounts", args: {} },
                  }],
                },
              }],
            },
        );
      };
      const r = await complete({ ...p, format }, messages, [tool]);
      assert(r.text === "ok");
      assert(r.calls[0].name === "read_accounts");
    }
  } finally {
    globalThis.fetch = original;
  }
});
