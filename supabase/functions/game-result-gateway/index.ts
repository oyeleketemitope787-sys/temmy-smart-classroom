/**
 * GAME RESULT GATEWAY — REVIEW-ONLY FAIL-CLOSED PROPOSAL
 *
 * Status: NOT DEPLOYED; NOT READY TO AWARD POINTS.
 *
 * This endpoint validates the request contract, but intentionally does not
 * contact Supabase or write points. The currently inspected game calculates
 * a local score but does not visibly submit a result, while
 * the existing database RPC trusts client-provided score/max-score fields.
 *
 * Do not enable scoring here until an authoritative verification protocol is
 * agreed and implemented, and all direct callers of record_student_game_result
 * have been migrated. CORS is not authentication.
 */

import { validateResultRequest } from "./validation.ts";

const ALLOWED_ORIGINS = new Set([
  "https://games.stgloriousschool.org",
  "https://classroom.stgloriousschool.org",
  "https://oyeleketemitope787-sys.github.io",
]);

const MAX_BODY_BYTES = 16 * 1024;

const corsHeaders = (origin: string | null) => {
  const permitted = origin !== null && ALLOWED_ORIGINS.has(origin);
  return {
    Vary: "Origin",
    ...(permitted ? { "Access-Control-Allow-Origin": origin } : {}),
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers":
      "authorization, apikey, content-type, x-client-info",
    "Access-Control-Max-Age": "600",
  };
};

function jsonResponse(
  status: number,
  body: Record<string, unknown>,
  origin: string | null,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders(origin),
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
}
Deno.serve(async (req: Request) => {
  const origin = req.headers.get("origin");

  if (req.method === "OPTIONS") {
    if (origin && !ALLOWED_ORIGINS.has(origin)) {
      return jsonResponse(403, { error: "Request not permitted." }, origin);
    }
    return new Response(null, { status: 204, headers: corsHeaders(origin) });
  }

  if (req.method !== "POST") {
    return jsonResponse(405, { error: "Method not allowed." }, origin);
  }
  if (origin && !ALLOWED_ORIGINS.has(origin)) {
    return jsonResponse(403, { error: "Request not permitted." }, origin);
  }
  if (!req.headers.get("content-type")?.toLowerCase().startsWith("application/json")) {
    return jsonResponse(415, { error: "Unsupported content type." }, origin);
  }

  const declaredLength = Number(req.headers.get("content-length") ?? "0");
  if (Number.isFinite(declaredLength) && declaredLength > MAX_BODY_BYTES) {
    return jsonResponse(413, { error: "Request too large." }, origin);
  }

  let rawBody: string;
  try {
    rawBody = await req.text();
  } catch {
    return jsonResponse(400, { error: "Invalid request." }, origin);
  }
  if (new TextEncoder().encode(rawBody).byteLength > MAX_BODY_BYTES) {
    return jsonResponse(413, { error: "Request too large." }, origin);
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(rawBody);
  } catch {
    return jsonResponse(400, { error: "Invalid request." }, origin);
  }

  const checked = validateResultRequest(parsed);
  if (!checked.ok) {
    return jsonResponse(400, { error: "Invalid request." }, origin);
  }

  // Deliberately fail closed. Do not replace this with a client-supplied score
  // forwarded to record_student_game_result. A safe implementation requires:
  // 1) authoritative per-question verification / anti-replay attempt state;
  // 2) server-controlled game ID, name, and max score;
  // 3) atomic session consumption + point insertion;
  // 4) a reviewed migration of current direct RPC callers and EXECUTE grants;
  // 5) isolated end-to-end tests and a rollback plan.
  //
  // No Supabase client or service-role key is used in this review-only version.
  return jsonResponse(
    503,
    { error: "Game result awarding is disabled pending trusted score verification." },
    origin,
  );
});
