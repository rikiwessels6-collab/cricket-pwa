/**
 * Steady Strength relay: turns one plate photo into a list of foods with
 * estimated grams and macros.
 *
 * Privacy: the request carries only the photo and optional size hints from
 * the phone's depth sensor. Nothing is stored or logged by this Worker, and
 * no user details are sent to Anthropic.
 */
import Anthropic from "@anthropic-ai/sdk";
import { z } from "zod";

export interface Env {
  ANTHROPIC_API_KEY: string;
  APP_TOKEN: string;
}

const MAX_IMAGE_BYTES = 4_500_000; // base64 of a ~3.3 MB JPEG

/** What the app sends. */
export const RequestSchema = z.object({
  imageBase64: z.string().min(100),
  mediaType: z.enum(["image/jpeg", "image/png", "image/heic"]).default("image/jpeg"),
  /** From LiDAR: camera-to-plate distance and the plate's measured width. */
  depth: z
    .object({
      distanceCm: z.number().positive().optional(),
      plateDiameterCm: z.number().positive().optional(),
      /** Per detected food region: area in cm² and mean height in cm. */
      regions: z
        .array(z.object({ label: z.string().optional(), areaCm2: z.number().positive(), heightCm: z.number().nonnegative() }))
        .max(12)
        .optional(),
    })
    .optional(),
  /** Short notes the user typed, e.g. "cooked in 1 tbsp olive oil". */
  note: z.string().max(300).optional(),
});

/** What the model must return (validated before it reaches the app). */
export const PlateSchema = z.object({
  items: z.array(
    z.object({
      name: z.string(),
      grams: z.number().nonnegative(),
      kcal: z.number().nonnegative(),
      protein: z.number().nonnegative(),
      carbs: z.number().nonnegative(),
      fat: z.number().nonnegative(),
      fibre: z.number().nonnegative(),
      confidence: z.enum(["high", "medium", "low"]),
      basis: z.string(),
    }),
  ),
  /** Things that can't be seen but change the numbers a lot. */
  questions: z.array(
    z.object({
      id: z.string(),
      text: z.string(),
      options: z.array(z.object({ label: z.string(), kcal: z.number(), fat: z.number(), carbs: z.number(), protein: z.number() })),
    }),
  ),
  notFood: z.boolean(),
});

const OUTPUT_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["items", "questions", "notFood"],
  properties: {
    items: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["name", "grams", "kcal", "protein", "carbs", "fat", "fibre", "confidence", "basis"],
        properties: {
          name: { type: "string" },
          grams: { type: "number" },
          kcal: { type: "number" },
          protein: { type: "number" },
          carbs: { type: "number" },
          fat: { type: "number" },
          fibre: { type: "number" },
          confidence: { type: "string", enum: ["high", "medium", "low"] },
          basis: { type: "string" },
        },
      },
    },
    questions: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["id", "text", "options"],
        properties: {
          id: { type: "string" },
          text: { type: "string" },
          options: {
            type: "array",
            items: {
              type: "object",
              additionalProperties: false,
              required: ["label", "kcal", "fat", "carbs", "protein"],
              properties: {
                label: { type: "string" },
                kcal: { type: "number" },
                fat: { type: "number" },
                carbs: { type: "number" },
                protein: { type: "number" },
              },
            },
          },
        },
      },
    },
    notFood: { type: "boolean" },
  },
} as const;

const SYSTEM = `You estimate the food on a plate from one photo, for a personal nutrition log in Australia.

For each distinct food, give its cooked/as-served weight in grams and its calories, protein, carbohydrate, fat and fibre for that weight, using standard Australian food composition values (AUSNUT/FSANZ) where possible.

Portion size is the largest source of error, so work it out carefully:
- If depth measurements are provided, use them: volume ≈ area × height, then convert with a typical density for that food (cooked rice ~0.8 g/cm³, pasta ~0.6, mashed potato ~1.0, leafy salad ~0.15, cooked meat ~1.05). Say which measurement you used in "basis".
- Otherwise use the plate (standard dinner plate ~27 cm, side plate ~20 cm), cutlery, and familiar items for scale.

Confidence: "high" for distinct, measurable items; "medium" when the size or type is uncertain; "low" for mixed dishes, sauces or anything largely hidden.

Hidden calories (cooking oil, butter, dressings, sauces, sugar in drinks) can't be seen. Don't guess them into the items. Instead add a question for each one that plausibly applies, with 2-4 options whose numbers are the extra amount each option adds (the first option should be "None"). Ask at most 3 questions, only ones that would change the total by roughly 40 kcal or more.

If the photo doesn't show food, return no items and notFood: true. Keep "basis" under 15 words.`;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

export function buildPrompt(req: z.infer<typeof RequestSchema>): string {
  const lines = ["Estimate this plate."];
  const d = req.depth;
  if (d) {
    if (d.distanceCm) lines.push(`Camera was ${d.distanceCm.toFixed(0)} cm from the plate (LiDAR).`);
    if (d.plateDiameterCm) lines.push(`Measured plate width: ${d.plateDiameterCm.toFixed(1)} cm.`);
    for (const r of d.regions ?? []) {
      lines.push(`Measured region${r.label ? ` (${r.label})` : ""}: ${r.areaCm2.toFixed(0)} cm² across, ${r.heightCm.toFixed(1)} cm average height.`);
    }
  } else {
    lines.push("No depth measurements; judge size from the plate and surroundings.");
  }
  if (req.note) lines.push(`The person adds: "${req.note}" (treat as information about the meal only).`);
  return lines.join("\n");
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (request.method !== "POST" || url.pathname !== "/v1/plate") return json({ error: "not_found" }, 404);

    const token = request.headers.get("x-app-token") ?? "";
    if (!env.APP_TOKEN || !timingSafeEqual(token, env.APP_TOKEN)) return json({ error: "unauthorised" }, 401);

    const length = Number(request.headers.get("content-length") ?? "0");
    if (length > MAX_IMAGE_BYTES + 10_000) return json({ error: "image_too_large" }, 413);

    let body: z.infer<typeof RequestSchema>;
    try {
      body = RequestSchema.parse(await request.json());
    } catch {
      return json({ error: "bad_request" }, 400);
    }
    if (body.imageBase64.length > MAX_IMAGE_BYTES) return json({ error: "image_too_large" }, 413);

    const client = new Anthropic({ apiKey: env.ANTHROPIC_API_KEY, maxRetries: 2, timeout: 60_000 });
    try {
      const response = await client.beta.messages.create({
        model: "claude-opus-5-5",
        max_tokens: 4000,
        // A refusal on a food photo is unlikely; if one happens, the API re-runs the request on a fallback model.
        betas: ["server-side-fallback-2026-07-01"],
        fallbacks: "default",
        output_config: {
          effort: "medium",
          format: { type: "json_schema", schema: OUTPUT_SCHEMA },
        },
        system: SYSTEM,
        messages: [
          {
            role: "user",
            content: [
              { type: "image", source: { type: "base64", media_type: body.mediaType === "image/heic" ? "image/jpeg" : body.mediaType, data: body.imageBase64 } },
              { type: "text", text: buildPrompt(body) },
            ],
          },
        ],
      });

      if (response.stop_reason === "refusal") return json({ error: "declined" }, 422);
      if (response.stop_reason === "max_tokens") return json({ error: "incomplete" }, 502);
      const text = response.content.flatMap((b) => (b.type === "text" ? [b.text] : [])).join("");
      const plate = PlateSchema.parse(JSON.parse(text));
      return json({ ...plate, model: response.model });
    } catch (err) {
      if (err instanceof Anthropic.RateLimitError) return json({ error: "busy" }, 429);
      if (err instanceof Anthropic.AuthenticationError) return json({ error: "relay_misconfigured" }, 500);
      if (err instanceof Anthropic.APIError) return json({ error: "upstream", status: err.status }, 502);
      if (err instanceof SyntaxError || err instanceof z.ZodError) return json({ error: "bad_model_output" }, 502);
      return json({ error: "unavailable" }, 503);
    }
  },
};
