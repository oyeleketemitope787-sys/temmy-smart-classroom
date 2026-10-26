/**
 * CENTRAL GAME SCORING GATEWAY — REVIEW BRANCH ONLY.
 *
 * NOT DEPLOYED. Do not set the feature flags until the SQL proposal has been
 * converted to an approved migration, isolated tests pass, and the game client
 * has been migrated. Both flags are a hard stop; either unset/false returns
 * HTTP 503 without contacting Supabase.
 *
 * This is a private server-side adapter: service-role credentials are read
 * only from Edge Function environment variables and never sent to the browser.
 */

import { createClient } from "npm:@supabase/supabase-js@2";
import { generateNumberChallengeQuestions } from "./question-generator.ts";
import {
  buildCentralScoreDisplay,
  buildVerifiedScoreResult,
  GAME_SCORING_CATALOGUE,
} from "./scoring-contract.ts";
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

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function disabledResponse(origin: string | null): Response {
  return jsonResponse(
    503,
    { error: "Game scoring is disabled pending approved deployment and verification." },
    origin,
  );
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

  // Default-deny feature gate. There is intentionally no RPC call before both
  // flags are explicitly set in the server environment.
  if (Deno.env.get("GAME_RESULT_GATEWAY_READY") !== "true" ||
      Deno.env.get("GAME_RESULT_WRITE_ENABLED") !== "true") {
    return disabledResponse(origin);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return disabledResponse(origin);
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  let rpcResult: { data: unknown; error: { message: string } | null };

  if (checked.request.action === "start_attempt") {
    const rule = GAME_SCORING_CATALOGUE[checked.request.game_id];
    if (!rule) {
      return jsonResponse(400, { error: "This game is not registered for central scoring." }, origin);
    }

    // A generator must be explicitly implemented for every registered game.
    // Only Number Challenge is wired in this review version.
    if (checked.request.game_id !== "grade3-temmy-number-challenge") {
      return jsonResponse(503, { error: "Question generation is not configured for this game." }, origin);
    }

    const questions = generateNumberChallengeQuestions();
    if (questions.length !== rule.questionCount) {
      return disabledResponse(origin);
    }

    rpcResult = await supabase.rpc("begin_game_attempt", {
      p_session_token: checked.request.session_token,
      p_game_id: checked.request.game_id,
      p_questions: questions,
    });
  } else {
    rpcResult = await supabase.rpc("record_game_attempt_answer", {
      p_session_token: checked.request.session_token,
      p_question_index: checked.request.question_index,
      p_choice_index: checked.request.choice_index,
    });
  }

  // Never include the raw Postgres error or request token in browser responses.
  if (rpcResult.error || !isRecord(rpcResult.data) || rpcResult.data.ok !== true) {
    return jsonResponse(400, { error: "The game request could not be completed." }, origin);
  }

  const result = rpcResult.data;
  const rule = GAME_SCORING_CATALOGUE[checked.request.game_id];
  if (!rule ||
      result.game_id !== rule.gameId ||
      result.max_score !== rule.maxScore ||
      !Number.isSafeInteger(result.score) ||
      (result.score as number) < 0 ||
      (result.score as number) > rule.maxScore) {
    return disabledResponse(origin);
  }

  if (result.status === "completed") {
    const verified = buildVerifiedScoreResult(
      checked.request.game_id,
      result.score,
    );
    if (!verified.ok ||
        result.max_score !== verified.result.max_score ||
        result.points_awarded !== verified.result.points_awarded ||
        result.score_rule_version !== verified.result.score_rule_version) {
      // A database/code catalogue mismatch is fail-closed; never rewrite score.
      return disabledResponse(origin);
    }

    return jsonResponse(200, {
      ...result,
      score_display: buildCentralScoreDisplay(verified.result),
    }, origin);
  }

  if (result.status !== "in_progress") {
    return disabledResponse(origin);
  }

  // While playing, report the running score/max only; do not claim that points
  // have been awarded until the final result and point transaction commit.
  return jsonResponse(200, {
    ...result,
    score_display: {
      score_label: String(result.score) + "/" + String(result.max_score),
      max_score: result.max_score,
    },
  }, origin);
});
