import { describe, expect, test } from "bun:test";

// ---------------------------------------------------------------------------
// 连接已运行的网关
// ---------------------------------------------------------------------------

const BASE = "http://127.0.0.1:8088";
const AUTH = "Bearer sk-local-dev";

const MODELS = ["gpt-5.5", "gpt-5.4", "deepseek/deepseek-v4-flash"] as const;

function headers(extra?: Record<string, string>) {
  return { Authorization: AUTH, "Content-Type": "application/json", ...extra };
}

function post(path: string, body: unknown, extra?: Record<string, string>) {
  return fetch(`${BASE}${path}`, {
    method: "POST",
    headers: headers(extra),
    body: JSON.stringify(body),
  });
}

// ---------------------------------------------------------------------------
// 类型
// ---------------------------------------------------------------------------

interface ModelEntry {
  id: string;
  object: string;
}
interface ResponsesResponse {
  id: string;
  object: string;
  model: string;
  status: string;
  output?: Array<Record<string, unknown>>;
  usage?: { input_tokens: number; output_tokens: number; total_tokens: number };
}
interface ChatCompletionResponse {
  id: string;
  object: string;
  model: string;
  choices: Array<{
    index: number;
    message: { role: string; content: string };
    finish_reason: string;
  }>;
  usage: {
    prompt_tokens: number;
    completion_tokens: number;
    total_tokens: number;
  };
}

// ---------------------------------------------------------------------------
// GET /v1/models
// ---------------------------------------------------------------------------

describe("GET /v1/models", () => {
  test(
    "返回 object=list，包含路由模型和 provider 模型",
    async () => {
      const res = await fetch(`${BASE}/v1/models`);
      expect(res.status).toBe(200);

      const body = (await res.json()) as { object: string; data: ModelEntry[] };
      expect(body.object).toBe("list");
      expect(Array.isArray(body.data)).toBe(true);

      const ids: string[] = body.data.map((e: ModelEntry) => e.id);
      for (const m of MODELS) expect(ids).toContain(m);
      for (const pid of [
        "gpt-5.5",
        "gpt-5.4",
        "gpt-5.4-mini",
        "deepseek/deepseek-v4-flash",
        "deepseek/deepseek-v4-pro",
      ]) {
        expect(ids).toContain(pid);
      }
    },
    { timeout: 120_000 },
  );
});

// ---------------------------------------------------------------------------
// POST /v1/responses — 每个模型
// ---------------------------------------------------------------------------

for (const model of MODELS) {
  describe(`POST /v1/responses model=${model}`, () => {
    test(
      "非流式返回有效结构",
      async () => {
        const res = await post("/v1/responses", {
          model,
          input: "用一句话介绍你自己。",
        });
        expect(res.status).toBe(200);

        const body = (await res.json()) as ResponsesResponse;
        expect(typeof body.id).toBe("string");
        expect(body.object).toBe("response");
        expect(body.model).toBe(model);
        expect(body.status).toBe("completed");
        expect(Array.isArray(body.output)).toBe(true);
        expect(body.output!.length).toBeGreaterThan(0);
        expect(body.usage).toBeDefined();
        expect(body.usage!.total_tokens).toBeGreaterThan(0);
      },
      { timeout: 120_000 },
    );

    test(
      "流式 SSE",
      async () => {
        const res = await post(
          "/v1/responses",
          { model, stream: true, input: "写一个 Swift Hello World。" },
          { Accept: "text/event-stream" },
        );
        expect(res.status).toBe(200);
        expect(res.headers.get("content-type")).toContain("text/event-stream");

        const reader = res.body!.getReader();
        const decoder = new TextDecoder();
        let delta = false,
          completed = false,
          buf = "";

        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          buf += decoder.decode(value, { stream: true });
          const lines = buf.split("\n");
          buf = lines.pop() ?? "";
          for (const line of lines) {
            if (!line.startsWith("data: ")) continue;
            const s = line.slice(6);
            if (s === "[DONE]") continue;
            try {
              const e = JSON.parse(s);
              if (e.type === "response.output_text.delta") delta = true;
              if (e.type === "response.completed") completed = true;
            } catch {
              /* */
            }
          }
        }
        expect(delta).toBe(true);
        expect(completed).toBe(true);
      },
      { timeout: 120_000 },
    );
  });
}

// ---------------------------------------------------------------------------
// POST /v1/chat/completions — 每个模型
// ---------------------------------------------------------------------------

for (const model of MODELS) {
  describe(`POST /v1/chat/completions model=${model}`, () => {
    test(
      "非流式返回有效结构",
      async () => {
        const res = await post("/v1/chat/completions", {
          model,
          messages: [{ role: "user", content: "说 hello" }],
        });
        expect(res.status).toBe(200);

        const body = (await res.json()) as ChatCompletionResponse;
        expect(typeof body.id).toBe("string");
        expect(body.object).toBe("chat.completion");
        expect(body.model).toBe(model);
        expect(Array.isArray(body.choices)).toBe(true);
        expect(body.choices[0]!.message.role).toBe("assistant");
        expect(typeof body.choices[0]!.message.content).toBe("string");
        expect(body.choices[0]!.finish_reason).toBeString();
        expect(body.usage.total_tokens).toBeGreaterThan(0);
      },
      { timeout: 120_000 },
    );

    test(
      "流式 SSE",
      async () => {
        const res = await post(
          "/v1/chat/completions",
          { model, stream: true, messages: [{ role: "user", content: "hi" }] },
          { Accept: "text/event-stream" },
        );
        expect(res.status).toBe(200);
        expect(res.headers.get("content-type")).toContain("text/event-stream");

        const reader = res.body!.getReader();
        const decoder = new TextDecoder();
        let content = false,
          finish = false,
          buf = "";

        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          buf += decoder.decode(value, { stream: true });
          const lines = buf.split("\n");
          buf = lines.pop() ?? "";
          for (const line of lines) {
            if (!line.startsWith("data: ")) continue;
            const s = line.slice(6);
            if (s === "[DONE]") continue;
            try {
              const c = JSON.parse(s);
              if (c.choices?.[0]?.delta?.content) content = true;
              if (c.choices?.[0]?.finish_reason) finish = true;
            } catch {
              /* */
            }
          }
        }
        expect(content).toBe(true);
        expect(finish).toBe(true);
      },
      { timeout: 120_000 },
    );
  });
}

// ---------------------------------------------------------------------------
// 鉴权 & 错误
// ---------------------------------------------------------------------------

describe("鉴权", () => {
  for (const path of ["/v1/responses", "/v1/chat/completions"]) {
    test(`${path} 缺 Authorization → 401`, async () => {
      const res = await fetch(`${BASE}${path}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ model: "gpt-5.5", input: "hi" }),
      });
      expect(res.status).toBe(401);
    });

    test(`${path} 错误 key → 401`, async () => {
      const res = await fetch(`${BASE}${path}`, {
        method: "POST",
        headers: {
          Authorization: "Bearer bad-key",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ model: "gpt-5.5", input: "hi" }),
      });
      expect(res.status).toBe(401);
    });
  }
});

describe("错误处理", () => {
  test("缺 model → 400", async () => {
    const res = await post("/v1/responses", { input: "hi" });
    expect(res.status).toBe(400);
  });

  test("未配置模型 → 404", async () => {
    const res = await post("/v1/responses", {
      model: "nonexistent",
      input: "hi",
    });
    expect(res.status).toBe(404);
  });
});
