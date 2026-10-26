/**
 * GAME RESULT GATEWAY — REVIEW-ONLY FAIL-CLOSED PROPOSAL
 *
 * Status: NOT DEPLOYED; NOT READY TO AWARD POINTS.
 *
 * This endpoint validates the request contract, but intentionally does not
 * contact Supabase or write points. The currently inspected game sends only
 * a local score (and its source contains no result-submission call), while
 * the existing database RPC trusts client-provided score/max-score fields.
 *
 * Do not enable scoring here until an authoritative verification protocol is
 * agreed and implemented, and all direct callers of record_student_game_result
 * have been migrated. CORS is not authentication.
 */

const ALLOWED_ORIGINS = new Set([
  "https://games.stgloriousschool.org",
  "https://classroom.stgloriousschool.org",
  "https://oyeleketemitope787-sys.github.io",
]);

const MAX_BODY_BYTES = 16 * 1024;
const GAME_ID = "grade3-temmy-number-challenge";
const QUESTION_COUNT = 15;
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

type AnswerSubmission = {
  question_index: number;
  choice_index: number;
};

type SubmitResultRequest = {
  action: "submit_result";
  session_token: string;
  game_id: string;
  answers: AnswerSubmission[];
};

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

function hasExactKeys(value: Record<string, unknown>, allowed: string[]) {
  return Object.keys(value).every((key) => allowed.includes(key)) &&
    allowed.every((key) => Object.prototype.hasOwnProperty.call(value, key));
}

/**
 * The browser must not send score, max_score, student_id, teacher_id, or
 * game_name. Those values must be derived/validated on a trusted server.
 *
 * The submitted answers are still untrusted claims. This validator is only
 * request-shape validation; it is NOT proof that the student played the game.
 */
function validateRequest(
  value: unknown,
): { ok: true; request: SubmitResultRequest } | { ok: false } {
  if (!isRecord(value)) return { ok: false };
  if (!hasExactKeys(value, ["action", "session_token", "game_id", "answers"])) {
    return { ok: false };
  }

  if (value.action !== "submit_result") return { ok: false };
  if (typeof value.session_token !== "string" ||
      !UUID_PATTERN.test(value.session_token)) {
    return { ok: false };
  }
  if (value.game_id !== GAME_ID) return { ok: false };
  if (!Array.isArray(value.answers) || value.answers.length > QUESTION_COUNT) {
    return { ok: false };
  }

  const seenQuestions = new Set<number>();
  const answers: AnswerSubmission[] = [];

  for (const item of value.answers) {
    if (!isRecord(item) ||
        !hasExactKeys(item, ["question_index", "choice_index"])) {
      return { ok: false };
    }

    const questionIndex = item.question_index;
    const choiceIndex = item.choice_index;

    if (!Number.isInteger(questionIndex) ||
        (questionIndex as number) < 0 ||
        (questionIndex as number) >= QUESTION_COUNT ||
        !Number.isInteger(choiceIndex) ||
        (choiceIndex as number) < 0 ||
        (choiceIndex as number) > 3) {
      return { ok: false };
    }

    if (seenQuestions.has(questionIndex as number)) return { ok: false };
    seenQuestions.add(questionIndex as number);

    answers.push({
      question_index: questionIndex as number,
      choice_index: choiceIndex as number,
    });
  }

  return {
    ok: true,
    request: {
      action: "submit_result",
      session_token: value.session_token,
      game_id: value.game_id,
      answers,
    },
  };
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

  const checked = validateRequest(parsed);
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
