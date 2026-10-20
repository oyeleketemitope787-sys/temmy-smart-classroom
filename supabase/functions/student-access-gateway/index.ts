/**
 * STUDENT ACCESS GATEWAY — REVIEW-ONLY SCAFFOLD
 *
 * DO NOT DEPLOY.
 * This intentionally fails closed. It is not ready to route student requests:
 * - atomic database rate limiting is not implemented;
 * - trusted source metadata has not been verified;
 * - HMAC secret handling and database grants are not finalized;
 * - frontend response compatibility still requires isolated testing.
 *
 * Keep this file on security-review/student-login-hardening only.
 * Never place a service-role key or HMAC secret in browser code or logs.
 */
import { createClient } from "npm:@supabase/supabase-js@2";

const ALLOWED_ORIGINS = new Set([
  "https://classroom.stgloriousschool.org",
  "https://oyeleketemitope787-sys.github.io",
]);

const MAX_BODY_BYTES = 16 * 1024;
const CODE_PATTERN = /^[A-Fa-f0-9]{8}$/;
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

type Action =
  | "login"
  | "point_history"
  | "live_activities"
  | "game_sessions"
  | "messages"
  | "mark_messages_read"
  | "send_message"
  | "submit_activity"
  | "start_game_session";

type RequestBody = {
  action?: unknown;
  access_code?: unknown;
  message?: unknown;
  activity_id?: unknown;
  answer?: unknown;
  game_id?: unknown;
};

const corsHeaders = (origin: string | null) => {
  const permitted = origin !== null && ALLOWED_ORIGINS.has(origin);
  return {
    "Vary": "Origin",
    ...(permitted ? { "Access-Control-Allow-Origin": origin } : {}),
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
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

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function validate(body: RequestBody):
  | { ok: true; action: Action; args: Record<string, unknown> }
  | { ok: false } {
  if (typeof body.action !== "string") return { ok: false };
  if (typeof body.access_code !== "string") return { ok: false };

  const code = body.access_code.trim();
  if (!CODE_PATTERN.test(code)) return { ok: false };

  // Explicit action allowlist: never accept an RPC name from the caller.
  switch (body.action as Action) {
    case "login":
      return { ok: true, action: "login", args: { p_access_code: code } };
    case "point_history":
      return { ok: true, action: "point_history", args: { p_access_code: code } };
    case "live_activities":
      return { ok: true, action: "live_activities", args: { p_access_code: code } };
    case "game_sessions":
      return { ok: true, action: "game_sessions", args: { p_access_code: code } };
    case "messages":
      return { ok: true, action: "messages", args: { p_access_code: code } };
    case "mark_messages_read":
      return {
        ok: true,
        action: "mark_messages_read",
        args: { p_access_code: code },
      };
    case "send_message":
      if (typeof body.message !== "string") return { ok: false };
      if (body.message.length > 2000) return { ok: false };
      return {
        ok: true,
        action: "send_message",
        args: { p_access_code: code, p_message: body.message },
      };
    case "submit_activity":
      if (typeof body.activity_id !== "string" ||
          !UUID_PATTERN.test(body.activity_id)) return { ok: false };
      if (typeof body.answer !== "string" || body.answer.length > 10000) {
        return { ok: false };
      }
      return {
        ok: true,
        action: "submit_activity",
        args: {
          p_access_code: code,
          p_activity_id: body.activity_id,
          p_answer: body.answer,
        },
      };
    case "start_game_session":
      if (typeof body.game_id !== "string") return { ok: false };
      // Validate shape here; final allowed game IDs must be confirmed from
      // the repository/database before this action is enabled.
      if (!/^[a-zA-Z0-9_-]{1,100}$/.test(body.game_id)) return { ok: false };
      return {
        ok: true,
        action: "start_game_session",
        args: { p_access_code: code, p_game_id: body.game_id },
      };
    default:
      return { ok: false };
  }
}

const RPC_BY_ACTION: Record<Action, string> = {
  login: "student_portal_login",
  point_history: "get_student_point_history",
  live_activities: "get_student_live_activities",
  game_sessions: "get_student_game_sessions",
  messages: "get_student_messages",
  mark_messages_read: "mark_student_messages_read",
  send_message: "send_student_message",
  submit_activity: "submit_student_activity",
  start_game_session: "start_student_game_session",
};

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
  if (!isRecord(parsed)) {
    return jsonResponse(400, { error: "Invalid request." }, origin);
  }

  const checked = validate(parsed as RequestBody);
  if (!checked.ok) {
    return jsonResponse(400, { error: "Invalid request." }, origin);
  }

  /*
   * FAIL-CLOSED GATE:
   * Do not set this to true until the limiter, trusted-source decision,
   * secret strategy, narrow DB grants, response contracts, and isolated tests
   * are complete. Even when enabled, the limiter call must be added BEFORE
   * the RPC below. This scaffold intentionally does not execute an RPC.
   */
  if (Deno.env.get("STUDENT_ACCESS_GATEWAY_READY") !== "true") {
    return jsonResponse(503, { error: "Student access is temporarily unavailable." }, origin);
  }

  // A second hard stop prevents accidental RPC access before the rate limiter
  // is implemented and reviewed. Remove only as part of a reviewed completion.
  return jsonResponse(503, { error: "Student access is temporarily unavailable." }, origin);

  // Planned implementation (deliberately unreachable until reviewed):
  // const url = Deno.env.get("SUPABASE_URL");
  // const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  // if (!url || !serviceKey) return jsonResponse(503, { error: "Unavailable." }, origin);
  // const supabase = createClient(url, serviceKey, {
  //   auth: { persistSession: false, autoRefreshToken: false },
  // });
  // const { data, error } = await supabase.rpc(RPC_BY_ACTION[checked.action], checked.args);
  // if (error) {
  //   // Log only a request correlation ID and a sanitized category, never args/codes.
  //   return jsonResponse(400, { error: "Unable to complete request." }, origin);
  // }
  // return jsonResponse(200, { data }, origin);
});
