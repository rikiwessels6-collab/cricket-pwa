import { afterEach, describe, expect, it, vi } from "vitest";
import worker, { buildPrompt } from "../src/index";

const env = { ANTHROPIC_API_KEY: "test-key", APP_TOKEN: "app-secret" };
const image = "A".repeat(200);

function req(body: unknown, token = "app-secret", path = "/v1/plate") {
  return new Request(`https://relay.example${path}`, {
    method: "POST",
    headers: { "content-type": "application/json", "x-app-token": token },
    body: JSON.stringify(body),
  });
}

const plate = {
  items: [{ name: "Grilled chicken breast", grams: 160, kcal: 264, protein: 50, carbs: 0, fat: 6, fibre: 0, confidence: "high", basis: "LiDAR region 95 cm² × 1.6 cm" }],
  questions: [{ id: "oil", text: "Cooked in oil?", options: [{ label: "None", kcal: 0, fat: 0, carbs: 0, protein: 0 }, { label: "1 tsp", kcal: 40, fat: 4.5, carbs: 0, protein: 0 }] }],
  notFood: false,
};

function mockAnthropic(content: string, stop = "end_turn") {
  const calls: any[] = [];
  vi.stubGlobal("fetch", vi.fn(async (url: string, init: RequestInit) => {
    calls.push({ url: String(url), init, body: JSON.parse(String(init.body)) });
    return new Response(JSON.stringify({
      id: "msg_1", type: "message", role: "assistant", model: "claude-opus-5-5", stop_reason: stop, stop_details: null,
      content: [{ type: "text", text: content }], usage: { input_tokens: 10, output_tokens: 10 },
    }), { status: 200, headers: { "content-type": "application/json", "request-id": "req_1" } });
  }));
  return calls;
}

afterEach(() => vi.unstubAllGlobals());

describe("relay", () => {
  it("rejects wrong token and wrong path", async () => {
    expect((await worker.fetch(req({ imageBase64: image }, "nope"), env)).status).toBe(401);
    expect((await worker.fetch(req({ imageBase64: image }, "app-secret", "/other"), env)).status).toBe(404);
  });

  it("rejects bad bodies", async () => {
    expect((await worker.fetch(req({ imageBase64: "short" }), env)).status).toBe(400);
  });

  it("returns validated plate JSON and sends image, prompt and model", async () => {
    const calls = mockAnthropic(JSON.stringify(plate));
    const res = await worker.fetch(req({ imageBase64: image, depth: { plateDiameterCm: 27, regions: [{ areaCm2: 95, heightCm: 1.6 }] } }), env);
    expect(res.status).toBe(200);
    const out: any = await res.json();
    expect(out.items[0].name).toBe("Grilled chicken breast");
    expect(out.questions[0].options).toHaveLength(2);
    const sent = calls[0].body;
    expect(sent.model).toBe("claude-opus-5-5");
    expect(sent.messages[0].content[0].type).toBe("image");
    expect(sent.messages[0].content[1].text).toContain("27.0 cm");
    expect(sent.output_config.format.type).toBe("json_schema");
    expect(JSON.stringify(sent)).not.toContain("app-secret");
  });

  it("maps malformed model output and refusals", async () => {
    mockAnthropic("not json");
    expect((await worker.fetch(req({ imageBase64: image }), env)).status).toBe(502);
    mockAnthropic("", "refusal");
    expect((await worker.fetch(req({ imageBase64: image }), env)).status).toBe(422);
  });

  it("prompt mentions missing depth and keeps user note as data", () => {
    const p = buildPrompt({ imageBase64: image, mediaType: "image/jpeg", note: "1 tbsp olive oil" });
    expect(p).toContain("No depth measurements");
    expect(p).toContain('"1 tbsp olive oil"');
  });
});
