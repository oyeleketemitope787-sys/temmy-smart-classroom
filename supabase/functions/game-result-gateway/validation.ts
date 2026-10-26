/**
 * Pure request validation for the review-only, step-based game-result protocol.
 *
 * This validates the request shape only. A session token must still be checked
 * against stored session and attempt state, and the server must calculate
 * correctness. Never accept a score, maximum, student, teacher, or correctness
 * value from the browser.
 */
const GAME_ID = "grade3-temmy-number-challenge";
const QUESTION_COUNT = 15;
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

function validSessionAndGame(value: Record<string, unknown>): boolean {
  return typeof value.session_token === "string" &&
    UUID_PATTERN.test(value.session_token) &&
    value.game_id === GAME_ID;
}

export function validateResultRequest(
  value: unknown,
): ResultRequestValidation {
  if (!isRecord(value)) return { ok: false };

  if (value.action === "start_attempt") {
    if (!hasExactKeys(value, ["action", "session_token", "game_id"]) ||
        !validSessionAndGame(value)) {
      return { ok: false };
    }
    return {
      ok: true,
      request: {
        action: "start_attempt",
        session_token: value.session_token as string,
        game_id: GAME_ID,
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
    ]) || !validSessionAndGame(value)) {
      return { ok: false };
    }

    const questionIndex = value.question_index;
    const choiceIndex = value.choice_index;
    if (!Number.isInteger(questionIndex) ||
        (questionIndex as number) < 0 ||
        (questionIndex as number) >= QUESTION_COUNT ||
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
        game_id: GAME_ID,
        question_index: questionIndex as number,
        choice_index: choiceIndex as number,
      },
    };
  }

  return { ok: false };
}
