/**
 * Pure request validation for the review-only game-result gateway.
 *
 * This validates shape only; answers remain untrusted until checked against
 * authoritative attempt state. Do not use this as proof of gameplay.
 */
const GAME_ID = "grade3-temmy-number-challenge";
const QUESTION_COUNT = 15;
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export type AnswerSubmission = {
  question_index: number;
  choice_index: number;
};

export type SubmitResultRequest = {
  action: "submit_result";
  session_token: string;
  game_id: string;
  answers: AnswerSubmission[];
};

export type ResultRequestValidation =
  | { ok: true; request: SubmitResultRequest }
  | { ok: false };

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasExactKeys(value: Record<string, unknown>, allowed: string[]) {
  return Object.keys(value).every((key) => allowed.includes(key)) &&
    allowed.every((key) => Object.prototype.hasOwnProperty.call(value, key));
}

export function validateResultRequest(
  value: unknown,
): ResultRequestValidation {
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
  if (!Array.isArray(value.answers) ||
      value.answers.length < 1 ||
      value.answers.length > QUESTION_COUNT) {
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
