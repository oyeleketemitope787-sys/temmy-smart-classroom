/**
 * Central, server-side game scoring contract — review-only.
 *
 * Only trusted server code may call these functions after it has verified
 * each answer from protected attempt state. Never pass a score or max_score
 * directly from the browser into this module.
 *
 * Keep the scoring catalogue aligned with the exact game scoring algorithm.
 */
export type GameScoringRule = {
  gameId: string;
  displayName: string;
  questionCount: number;
  maxScore: number;
  ruleVersion: string;
  rewardPointsEqualScore: true;
};

/**
 * The current Number Challenge adds points for correct answers, streaks, and
 * a final-question bonus. Its all-correct theoretical maximum is:
 * 15 base + 13 streak>=3 bonuses + 11 streak>=5 bonuses + 2 final bonus = 41.
 *
 * Therefore, the score/maximum pair for this existing rule is e.g. 24/41,
 * not 24/15. If the game's scoring logic changes, version and re-verify this
 * catalogue entry before release.
 *
 * Other games (including games out of 20) must be explicitly registered with
 * their own approved rule, actual max score, and version. Unknown games fail
 * closed; there is no global fallback maximum.
 */
export const GAME_SCORING_CATALOGUE: Readonly<Record<string, GameScoringRule>> =
  Object.freeze({
    "grade3-temmy-number-challenge": Object.freeze({
      gameId: "grade3-temmy-number-challenge",
      displayName: "Temmy Number Challenge",
      questionCount: 15,
      maxScore: 41,
      ruleVersion: "number-challenge-streak-v1",
      rewardPointsEqualScore: true,
    }),
  });

export const GAME_MODES = ["practice", "challenge", "class"] as const;
export type GameMode = typeof GAME_MODES[number];

export type ValidatedAttemptResponse = {
  status: "in_progress" | "completed";
  mode: GameMode;
  score: number;
  maxScore: number;
  questionsAnswered: number;
  questionCount: number;
  correctCount: number;
  livesRemaining: number;
  rule: GameScoringRule;
};

export type AttemptResponseValidation =
  | { ok: true; result: ValidatedAttemptResponse }
  | {
    ok: false;
    reason:
      | "unknown_game"
      | "invalid_response"
      | "catalogue_mismatch"
      | "invalid_progress"
      | "invalid_question"
      | "invalid_completion";
  };

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasExactKeys(value: Record<string, unknown>, allowed: string[]): boolean {
  return Object.keys(value).every((key) => allowed.includes(key)) &&
    allowed.every((key) => Object.prototype.hasOwnProperty.call(value, key));
}

/**
 * Validate the complete database response before returning it to a game client.
 * In-progress responses must contain exactly one public question and no answer
 * key; completed responses must show an exact score-to-points match.
 */
export function validateCentralAttemptResponse(
  gameId: string,
  value: unknown,
  requestedMode?: GameMode,
  catalogue: Readonly<Record<string, GameScoringRule>> = GAME_SCORING_CATALOGUE,
): AttemptResponseValidation {
  if (!Object.prototype.hasOwnProperty.call(catalogue, gameId)) {
    return { ok: false, reason: "unknown_game" };
  }
  const rule = catalogue[gameId];
  if (!rule || !isRecord(value)) {
    return { ok: false, reason: "invalid_response" };
  }

  const mode = value.mode;
  if (typeof mode !== "string" ||
      !(GAME_MODES as readonly string[]).includes(mode)) {
    return { ok: false, reason: "invalid_response" };
  }
  if (requestedMode !== undefined && mode !== requestedMode) {
    return { ok: false, reason: "catalogue_mismatch" };
  }

  if (value.game_id !== rule.gameId ||
      value.max_score !== rule.maxScore ||
      value.question_count !== rule.questionCount ||
      value.score_rule_version !== rule.ruleVersion) {
    return { ok: false, reason: "catalogue_mismatch" };
  }

  const status = value.status;
  if (status !== "in_progress" && status !== "completed") {
    return { ok: false, reason: "invalid_response" };
  }

  const score = value.score;
  const questionsAnswered = value.questions_answered;
  const questionCount = value.question_count;
  const correctCount = value.correct_count;
  const livesRemaining = value.lives_remaining;

  if (!Number.isSafeInteger(score) ||
      (score as number) < 0 ||
      (score as number) > rule.maxScore ||
      !Number.isSafeInteger(questionsAnswered) ||
      (questionsAnswered as number) < 0 ||
      (questionsAnswered as number) > rule.questionCount ||
      !Number.isSafeInteger(correctCount) ||
      (correctCount as number) < 0 ||
      (correctCount as number) > (questionsAnswered as number) ||
      !Number.isSafeInteger(livesRemaining) ||
      (livesRemaining as number) < 0 ||
      (livesRemaining as number) > 3) {
    return { ok: false, reason: "invalid_progress" };
  }

  if ((mode !== "challenge" && (livesRemaining as number) !== 3) ||
      (status === "in_progress" &&
        ((questionsAnswered as number) >= rule.questionCount ||
         (mode === "challenge" && (livesRemaining as number) === 0))) {
    return { ok: false, reason: "invalid_progress" };
  }

  if (status === "completed") {
    const finishedAllQuestions = questionsAnswered === rule.questionCount;
    const challengeRanOutOfLives = mode === "challenge" && livesRemaining === 0;
    if (value.points_awarded !== score ||
        questionsAnswered === 0 ||
        (!finishedAllQuestions && !challengeRanOutOfLives)) {
      return { ok: false, reason: "invalid_completion" };
    }
  } else {
    if (Object.prototype.hasOwnProperty.call(value, "points_awarded") &&
        value.points_awarded !== null) {
      return { ok: false, reason: "invalid_completion" };
    }

    const question = value.question;
    if (!isRecord(question) ||
        !hasExactKeys(question, ["question_index", "prompt", "options", "hint"]) ||
        question.question_index !== questionsAnswered ||
        typeof question.prompt !== "string" ||
        question.prompt.trim().length < 1 ||
        question.prompt.length > 1000 ||
        !Array.isArray(question.options) ||
        question.options.length !== 4 ||
        question.options.some((option) => typeof option !== "string") ||
        new Set(question.options).size !== 4 ||
        !(question.hint === null ||
          (typeof question.hint === "string" && question.hint.length <= 500))) {
      return { ok: false, reason: "invalid_question" };
    }
  }

  return {
    ok: true,
    result: {
      status,
      mode: mode as GameMode,
      score: score as number,
      maxScore: rule.maxScore,
      questionsAnswered: questionsAnswered as number,
      questionCount: rule.questionCount,
      correctCount: correctCount as number,
      livesRemaining: livesRemaining as number,
      rule,
    },
  };
}

export type VerifiedScoreResult = {
  game_id: string;
  score: number;
  max_score: number;
  points_awarded: number;
  score_rule_version: string;
};

export type ScoreValidation =
  | { ok: true; result: VerifiedScoreResult }
  | {
    ok: false;
    reason: "unknown_game" | "invalid_score" | "score_exceeds_maximum";
  };

/**
 * Validate a score already calculated by trusted server logic.
 * max_score is always derived from the catalogue, never the request body.
 * A valid score is rewarded exactly; no silent LEAST()/clamping is applied.
 */
export function buildVerifiedScoreResult(
  gameId: string,
  verifiedScore: unknown,
  catalogue: Readonly<Record<string, GameScoringRule>> = GAME_SCORING_CATALOGUE,
): ScoreValidation {
  if (!Object.prototype.hasOwnProperty.call(catalogue, gameId)) {
    return { ok: false, reason: "unknown_game" };
  }
  const rule = catalogue[gameId];
  if (!rule) return { ok: false, reason: "unknown_game" };

  if (typeof verifiedScore !== "number" ||
      !Number.isSafeInteger(verifiedScore) ||
      verifiedScore < 0) {
    return { ok: false, reason: "invalid_score" };
  }

  if (verifiedScore > rule.maxScore) {
    return { ok: false, reason: "score_exceeds_maximum" };
  }

  return {
    ok: true,
    result: {
      game_id: rule.gameId,
      score: verifiedScore,
      max_score: rule.maxScore,
      points_awarded: verifiedScore,
      score_rule_version: rule.ruleVersion,
    },
  };
}

/**
 * One-answer scoring for Number Challenge v1.
 * The trusted caller must derive isCorrect from the stored correct answer,
 * not from the browser. Persist nextStreak and total score atomically.
 */
export function scoreNumberChallengeAnswer(args: {
  questionIndex: number;
  isCorrect: boolean;
  currentStreak: number;
}): { pointsDelta: number; nextStreak: number } {
  const { questionIndex, isCorrect, currentStreak } = args;
  if (!Number.isInteger(questionIndex) || questionIndex < 0 || questionIndex >= 15) {
    throw new RangeError("questionIndex must be between 0 and 14");
  }
  if (!Number.isInteger(currentStreak) || currentStreak < 0 || currentStreak > questionIndex) {
    throw new RangeError("currentStreak is outside the valid attempt range");
  }

  if (!isCorrect) return { pointsDelta: 0, nextStreak: 0 };

  const nextStreak = currentStreak + 1;
  let pointsDelta = 1;
  if (nextStreak >= 3) pointsDelta += 1;
  if (nextStreak >= 5) pointsDelta += 1;
  if (questionIndex === 14) pointsDelta += 2;

  return { pointsDelta, nextStreak };
}

export type CentralScoreDisplay = {
  score_label: string;
  points_awarded: number;
  points_awarded_label: string;
  max_score: number;
  score_rule_version: string;
};

/**
 * Build the stable values that the central game platform should render.
 * The UI must not hardcode "/15" or derive the denominator from question count.
 */
export function buildCentralScoreDisplay(
  verified: VerifiedScoreResult,
): CentralScoreDisplay {
  return {
    score_label: String(verified.score) + "/" + String(verified.max_score),
    points_awarded: verified.points_awarded,
    points_awarded_label: String(verified.points_awarded) +
      (verified.points_awarded === 1 ? " point awarded" : " points awarded"),
    max_score: verified.max_score,
    score_rule_version: verified.score_rule_version,
  };
}
