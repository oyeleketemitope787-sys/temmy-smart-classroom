/**
 * Pure request validation for the review-only, central game scoring protocol.
 *
 * This validates request shape only. Session state and answers must still be
 * verified by trusted server code. Never accept score, max_score, student,
 * teacher, points, or correctness values from the browser.
 */
import {
  GAME_SCORING_CATALOGUE,
  type GameScoringRule,
} from "./scoring-contract.ts";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export type StartAttemptRequest = {
  action: "start_attempt";
  session_token: string;
  game_id: string;
};

export type SubmitAnswerRequest = {
  action: "submit_answer";
  session_token: string;
  game_id: string;
  question_index: number;
  choice_index: number;
};

export type GameRequest = StartAttemptRequest | SubmitAnswerRequest;

export type ResultRequestValidation =
  | { ok: true; request: GameRequest }
  | { ok: false };

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasExactKeys(value: Record<string, unknown>, allowed: string[]) {
  return Object.keys(value).every((key) => allowed.includes(key)) &&
    allowed.every((key) => Object.prototype.hasOwnProperty.call(value, key));
}

function validSessionAndRule(
  value: Record<string, unknown>,
  catalogue: Readonly<Record<string, GameScoringRule>>,
): GameScoringRule | null {
  if (typeof value.session_token !== "string" ||
      !UUID_PATTERN.test(value.session_token) ||
      typeof value.game_id !== "string") {
    return null;
  }
  return catalogue[value.game_id] ?? null;
}

/**
 * Optional catalogue injection exists only to test games with other maxima.
 * Production callers should use the server-owned default catalogue; never
 * build this catalogue from request data or browser-provided configuration.
 */
export function validateResultRequest(
  value: unknown,
  catalogue: Readonly<Record<string, GameScoringRule>> = GAME_SCORING_CATALOGUE,
): ResultRequestValidation {
  if (!isRecord(value)) return { ok: false };

  if (value.action === "start_attempt") {
    if (!hasExactKeys(value, ["action", "session_token", "game_id"])) {
      return { ok: false };
    }
    const rule = validSessionAndRule(value, catalogue);
    if (!rule) return { ok: false };

    return {
      ok: true,
      request: {
        action: "start_attempt",
        session_token: value.session_token as string,
        game_id: rule.gameId,
      },
    };
  }

  if (value.action === "submit_answer") {
    if (!hasExactKeys(value, [
      "action",
      "session_token",
      "game_id",
      "question_index",
      "choice_index",
    ])) {
      return { ok: false };
    }

    const rule = validSessionAndRule(value, catalogue);
    if (!rule) return { ok: false };

    const questionIndex = value.question_index;
    const choiceIndex = value.choice_index;
    if (!Number.isInteger(questionIndex) ||
        (questionIndex as number) < 0 ||
        (questionIndex as number) >= rule.questionCount ||
        !Number.isInteger(choiceIndex) ||
        (choiceIndex as number) < 0 ||
        (choiceIndex as number) > 3) {
      return { ok: false };
    }

    return {
      ok: true,
      request: {
        action: "submit_answer",
        session_token: value.session_token as string,
        game_id: rule.gameId,
        question_index: questionIndex as number,
        choice_index: choiceIndex as number,
      },
    };
  }

  return { ok: false };
}
