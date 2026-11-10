// Provider wire formats stay outside the finance authorization boundary.
export type Format = "openai" | "anthropic" | "gemini";
export type Message = {
  role: "user" | "assistant" | "system" | "tool";
  content: string;
  calls?: Call[];
  callId?: string;
  images?: { mime: string; data: string }[];
};
export type Call = {
  id: string;
  name: string;
  args: Record<string, unknown>;
  raw?: any;
};
export type Tool = {
  name: string;
  description: string;
  parameters: Record<string, unknown>;
};
export type Provider = {
  format: Format;
  base_url: string;
  model: string;
  output_tokens: number;
  api_key: string;
};
export function wire(p: Provider, messages: Message[], tools: Tool[] = []) {
  const system = messages.filter((m) => m.role === "system").map((m) =>
    m.content
  ).join("\n");
  const ms = messages.filter((m) => m.role !== "system");
  const base = p.base_url.replace(/\/$/, "");
  if (p.format === "anthropic") {
    return {
      url: base + "/messages",
      headers: { "x-api-key": p.api_key, "anthropic-version": "2023-06-01" },
      body: {
        model: p.model,
        max_tokens: p.output_tokens,
        system,
        messages: ms.map((m) => ({
          role: m.role === "tool" ? "user" : m.role,
          content: m.role === "tool"
            ? [{
              type: "tool_result",
              tool_use_id: m.callId,
              content: m.content,
            }]
            : [
              ...(m.content ? [{ type: "text", text: m.content }] : []),
              ...(m.images || []).map((i) => ({
                type: "image",
                source: { type: "base64", media_type: i.mime, data: i.data },
              })),
              ...(m.calls || []).map((c) => ({
                type: "tool_use",
                id: c.id,
                name: c.name,
                input: c.args,
              })),
            ],
        })),
        ...(tools.length
          ? {
            tools: tools.map((t) => ({
              name: t.name,
              description: t.description,
              input_schema: t.parameters,
            })),
          }
          : {}),
      },
    };
  }
  if (p.format === "gemini") {
    return {
      url: base + "/models/" +
        encodeURIComponent(p.model.replace(/^models\//, "")) +
        ":generateContent",
      headers: { "x-goog-api-key": p.api_key },
      body: {
        systemInstruction: { parts: [{ text: system }] },
        contents: ms.map((m) => ({
          role: m.role === "assistant" ? "model" : "user",
          parts: m.role === "tool"
            ? [{
              functionResponse: {
                name: m.callId,
                response: { result: m.content },
              },
            }]
            : [
              ...(m.content ? [{ text: m.content }] : []),
              ...(m.images || []).map((i) => ({
                inlineData: { mimeType: i.mime, data: i.data },
              })),
              ...(m.calls || []).map((c) =>
                c.raw || ({ functionCall: { name: c.name, args: c.args } })
              ),
            ],
        })),
        generationConfig: { maxOutputTokens: p.output_tokens },
        ...(tools.length
          ? {
            tools: [{
              functionDeclarations: tools.map((t) => ({
                name: t.name,
                description: t.description,
                parametersJsonSchema: t.parameters,
              })),
            }],
          }
          : {}),
      },
    };
  }
  return {
    url: base + "/chat/completions",
    headers: { Authorization: "Bearer " + p.api_key },
    body: {
      model: p.model,
      max_completion_tokens: p.output_tokens,
      messages: messages.map((m) => ({
        role: m.role,
        content: m.images?.length
          ? [
            { type: "text", text: m.content },
            ...m.images.map((i) => ({
              type: "image_url",
              image_url: { url: `data:${i.mime};base64,${i.data}` },
            })),
          ]
          : m.content,
        ...(m.calls?.length
          ? {
            tool_calls: m.calls.map((c) => ({
              id: c.id,
              type: "function",
              function: { name: c.name, arguments: JSON.stringify(c.args) },
            })),
          }
          : {}),
        ...(m.callId ? { tool_call_id: m.callId } : {}),
      })),
      ...(tools.length
        ? { tools: tools.map((t) => ({ type: "function", function: t })) }
        : {}),
    },
  };
}
export function decode(
  format: Format,
  data: any,
): { text: string; calls: Call[]; usage: any; truncated: boolean } {
  if (format === "anthropic") {
    return {
      text: (data.content || []).filter((x: any) => x.type === "text").map((
        x: any,
      ) => x.text).join("\n"),
      calls: (data.content || []).filter((x: any) => x.type === "tool_use").map(
        (x: any) => ({ id: x.id, name: x.name, args: x.input }),
      ),
      usage: data.usage || {},
      truncated: data.stop_reason === "max_tokens",
    };
  }
  if (format === "gemini") {
    const c = data.candidates?.[0];
    return {
      text: (c?.content?.parts || []).filter((x: any) => x.text && !x.thought)
        .map((x: any) => x.text).join("\n"),
      calls: (c?.content?.parts || []).filter((x: any) => x.functionCall).map((
        x: any,
      ) => ({
        id: crypto.randomUUID(),
        name: x.functionCall.name,
        args: x.functionCall.args || {},
        raw: x,
      })),
      usage: data.usageMetadata || {},
      truncated: c?.finishReason === "MAX_TOKENS",
    };
  }
  const c = data.choices?.[0];
  return {
    text: c?.message?.content || "",
    calls: (c?.message?.tool_calls || []).map((x: any) => ({
      id: x.id,
      name: x.function.name,
      args: JSON.parse(x.function.arguments),
    })),
    usage: data.usage || {},
    truncated: c?.finish_reason === "length",
  };
}
export async function publicEndpoint(raw: string) {
  const u = new URL(raw);
  if (
    u.protocol !== "https:" || u.username || u.password || u.search || u.hash ||
    u.port && u.port !== "443"
  ) throw Error("Gunakan base URL HTTPS publik tanpa query atau kredensial.");
  const host = u.hostname.toLowerCase();
  if (
    !/^[a-z0-9.-]+$/.test(host) || !host.includes(".") ||
    host.endsWith(".local") || host.endsWith(".internal") ||
    /^\d+\./.test(host) || host === "localhost"
  ) throw Error("Endpoint privat tidak diizinkan.");
  const ips = (await Promise.allSettled([
    Deno.resolveDns(host, "A"),
    Deno.resolveDns(host, "AAAA"),
  ])).flatMap((r) => r.status === "fulfilled" ? r.value : []);
  if (!ips.length || ips.some((ip) => privateIp(ip))) {
    throw Error("Endpoint harus mengarah ke jaringan publik.");
  }
  return u.href.replace(/\/$/, "");
}
export function privateIp(ip: string) {
  if (ip.includes(":")) {
    return !/^[23][0-9a-f]{3}:/i.test(ip) || /^2001:(db8|0|10|20):/i.test(ip);
  }
  const a = ip.split(".").map(Number);
  return a.length !== 4 ||
    a.some((x) => !Number.isInteger(x) || x < 0 || x > 255) ||
    [0, 10, 127].includes(a[0]) || a[0] >= 224 ||
    a[0] === 169 && a[1] === 254 || a[0] === 172 && a[1] >= 16 && a[1] <= 31 ||
    a[0] === 192 && [0, 168].includes(a[1]) ||
    a[0] === 100 && a[1] >= 64 && a[1] <= 127 ||
    a[0] === 198 && [18, 19].includes(a[1]);
}
export async function providerJson(
  url: string,
  headers: Record<string, string>,
  body?: unknown,
) {
  const res = await fetch(url, {
    method: body === undefined ? "GET" : "POST",
    headers: { ...headers, "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
    redirect: "error",
    signal: AbortSignal.timeout(25000),
  });
  if (!res.ok) {
    const raw = (await res.text()).slice(0, 2000);
    let param = "";
    try {
      param = JSON.parse(raw).error?.param || "";
    } catch { /* opaque gateway error */ }
    throw new ProviderError(res.status, param);
  }
  const reader = res.body!.getReader();
  let size = 0;
  const chunks: Uint8Array[] = [];
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.length;
    if (size > 4_000_000) {
      await reader.cancel();
      throw Error("Respons provider terlalu besar.");
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(size);
  let pos = 0;
  for (const c of chunks) {
    bytes.set(c, pos);
    pos += c.length;
  }
  return JSON.parse(new TextDecoder().decode(bytes));
}
export async function complete(
  p: Provider,
  messages: Message[],
  tools: Tool[] = [],
) {
  const w = wire(p, messages, tools);
  let response;
  try {
    response = await providerJson(
      w.url,
      w.headers as unknown as Record<string, string>,
      w.body,
    );
  } catch (e) {
    if (
      p.format !== "openai" || !(e instanceof ProviderError) ||
      e.status !== 400 || e.param !== "max_completion_tokens"
    ) throw e;
    const body = w.body as any;
    body.max_tokens = body.max_completion_tokens;
    delete body.max_completion_tokens;
    response = await providerJson(
      w.url,
      w.headers as unknown as Record<string, string>,
      body,
    );
  }
  return decode(p.format, response);
}
class ProviderError extends Error {
  constructor(public status: number, public param: string) {
    super(
      `Provider menolak permintaan (${status}). Periksa key, model, kuota, dan kemampuan model.`,
    );
  }
}
// Deliberately pessimistic upper bound: UTF-8 bytes plus framing, not a claim of exact tokenization.
export function contextSize(ms: Message[], tools: Tool[] = []) {
  return new TextEncoder().encode(
    JSON.stringify(
      ms.map((m) => ({
        ...m,
        images: m.images?.map((i) => ({ mime: i.mime, data: "[image]" })),
      })),
    ) + JSON.stringify(tools),
  ).length + 1024 + ms.reduce((n, m) => n + (m.images?.length || 0) * 16384, 0);
}
export function planWindow(
  ms: Message[],
  tools: Tool[],
  limit: number,
  output: number,
) {
  const budget = limit - output - Math.max(1024, Math.ceil(limit * .1));
  if (budget < 2048) {
    throw Error("Context window terlalu kecil untuk konfigurasi output ini.");
  }
  return {
    budget,
    estimated: contextSize(ms, tools),
    fits: contextSize(ms, tools) <= budget,
  };
}
