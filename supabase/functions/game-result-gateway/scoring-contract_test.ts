import {
  buildCentralScoreDisplay,
  buildVerifiedScoreResult,
  GAME_SCORING_CATALOGUE,
  scoreNumberChallengeAnswer,
  validateCentralAttemptResponse,
  type GameScoringRule,
} from "./scoring-contract.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

Deno.test("accepts a normal in-progress attempt response and central display fields", () => {
  const checked = validateCentralAttemptResponse(
    "grade3-temmy-number-challenge",
    {
      ok: true,
      status: "in_progress",
      game_id: "grade3-temmy-number-challenge",
      mode: "practice",
      question_count: 15,
      questions_answered: 2,
      correct_count: 1,
      lives_remaining: 3,
      score: 1,
      max_score: 41,
      score_rule_version: "number-challenge-streak-v1",
      question: {
        question_index: 2,
        prompt: "123 ___ 321",
        options: ["<", ">", "=", "+"],
        hint: "Compare hundreds first.",
      },
    },
    "practice",
  );
  assert(checked.ok, "expected a valid in-progress response");
  if (checked.ok) {
    assert(checked.result.score === 1, "running score should be preserved");
    assert(checked.result.maxScore === 41, "registered maximum should be preserved");
    assert(checked.result.questionsAnswered === 2, "progress count should be preserved");
  }
});

Deno.test("accepts early challenge completion when all three lives are used", () => {
  const checked = validateCentralAttemptResponse(
    "grade3-temmy-number-challenge",
    {
      ok: true,
      status: "completed",
      game_id: "grade3-temmy-number-challenge",
      mode: "challenge",
      question_count: 15,
      questions_answered: 5,
      correct_count: 3,
      lives_remaining: 0,
      score: 4,
      max_score: 41,
      points_awarded: 4,
      score_rule_version: "number-challenge-streak-v1",
    },
  );
  assert(checked.ok, "a challenge may complete before all questions after three lives are lost");
  if (checked.ok) {
    assert(checked.result.questionsAnswered === 5, "do not pretend all 15 questions were answered");
    assert(checked.result.score === 4, "the verified score earned so far should be preserved");
  }
});

Deno.test("rejects early completion that has not reached zero lives", () => {
  const checked = validateCentralAttemptResponse(
    "grade3-temmy-number-challenge",
    {
      ok: true,
      status: "completed",
      game_id: "grade3-temmy-number-challenge",
      mode: "challenge",
      question_count: 15,
      questions_answered: 5,
      correct_count: 3,
      lives_remaining: 2,
      score: 4,
      max_score: 41,
      points_awarded: 4,
      score_rule_version: "number-challenge-streak-v1",
    },
  );
  assert(!checked.ok, "early challenge completion requires zero remaining lives");
});

Deno.test("rejects result catalogue mismatch and answer-key leakage", () => {
  const base = {
    ok: true,
    status: "in_progress",
    game_id: "grade3-temmy-number-challenge",
    mode: "class",
    question_count: 15,
    questions_answered: 0,
    correct_count: 0,
    lives_remaining: 3,
    score: 0,
    max_score: 41,
    score_rule_version: "number-challenge-streak-v1",
    question: {
      question_index: 0,
      prompt: "100 ___ 200",
      options: ["<", ">", "=", "+"],
      hint: "Compare the values.",
    },
  };
  const wrongMaximum = validateCentralAttemptResponse(
    "grade3-temmy-number-challenge",
    { ...base, max_score: 15 },
    "class",
  );
  const wrongVersion = validateCentralAttemptResponse(
    "grade3-temmy-number-challenge",
    { ...base, score_rule_version: "old-rule" },
    "class",
  );
  const leakedKey = validateCentralAttemptResponse(
    "grade3-temmy-number-challenge",
    { ...base, question: { ...base.question, correct_choice_index: 1 } },
    "class",
  );
  assert(!wrongMaximum.ok, "wrong maximum must be rejected");
  assert(!wrongVersion.ok, "wrong rule version must be rejected");
  assert(!leakedKey.ok, "the response must not expose the answer key");
});

Deno.test("completed awards must exactly match the verified score", () => {
  const checked = validateCentralAttemptResponse(
    "grade3-temmy-number-challenge",
    {
      ok: true,
      status: "completed",
      game_id: "grade3-temmy-number-challenge",
      mode: "practice",
      question_count: 15,
      questions_answered: 15,
      correct_count: 11,
      lives_remaining: 3,
      score: 14,
      max_score: 41,
      points_awarded: 13,
      score_rule_version: "number-challenge-streak-v1",
    },
  );
  assert(!checked.ok, "points awarded must equal the actual verified score");
});

Deno.test("awards the verified score without clamping", () => {
  const result = buildVerifiedScoreResult("grade3-temmy-number-challenge", 24);
  assert(result.ok, "24 is a valid score under the configured 41-point maximum");
  assert(result.result.score === 24, "record the actual score");
  assert(result.result.max_score === 41, "use the game's configured maximum");
  assert(result.result.points_awarded === 24, "award the actual verified score");
});

Deno.test("supports a registered hypothetical game out of 20", () => {
  const testCatalogue: Readonly<Record<string, GameScoringRule>> = {
    "test-game-out-of-20": {
      gameId: "test-game-out-of-20",
      displayName: "Test Game (20 points)",
      questionCount: 20,
      maxScore: 20,
      ruleVersion: "test-v1",
      rewardPointsEqualScore: true,
    },
  };
  const result = buildVerifiedScoreResult(
    "test-game-out-of-20",
    16,
    testCatalogue,
  );
  assert(result.ok, "16/20 should be a valid score");
  assert(result.result.score === 16, "store score 16");
  assert(result.result.max_score === 20, "store max score 20");
  assert(result.result.points_awarded === 16, "award 16 points");
});

Deno.test("rejects scores above the configured maximum rather than clamping", () => {
  const result = buildVerifiedScoreResult("grade3-temmy-number-challenge", 42);
  assert(!result.ok, "42 must exceed the registered max score 41");
  if (!result.ok) {
    assert(result.reason === "score_exceeds_maximum", "expected maximum-score rejection");
  }
});

Deno.test("rejects negative, fractional, unsafe, or nonnumeric scores", () => {
  for (const value of [-1, 0.5, Number.MAX_SAFE_INTEGER + 1, "12", null]) {
    const result = buildVerifiedScoreResult("grade3-temmy-number-challenge", value);
    assert(!result.ok, "invalid score must be rejected");
  }
});

Deno.test("rejects unregistered games without a fallback maximum", () => {
  const result = buildVerifiedScoreResult("unknown-game", 10);
  assert(!result.ok, "unknown game must be rejected");
  if (!result.ok) assert(result.reason === "unknown_game", "expected unknown-game reason");
  assert(
    GAME_SCORING_CATALOGUE["grade3-temmy-number-challenge"].maxScore === 41,
    "registered Number Challenge maximum should include all bonuses",
  );
});

Deno.test("rejects inherited object property names as game IDs", () => {
  for (const candidate of ["__proto__", "constructor", "toString"]) {
    const result = buildVerifiedScoreResult(candidate, 1);
    assert(!result.ok, "non-catalogue property name must be rejected: " + candidate);
  }
});

Deno.test("scores a perfect Number Challenge run at 41 points", () => {
  let streak = 0;
  let total = 0;
  for (let questionIndex = 0; questionIndex < 15; questionIndex++) {
    const outcome = scoreNumberChallengeAnswer({
      questionIndex,
      isCorrect: true,
      currentStreak: streak,
    });
    total += outcome.pointsDelta;
    streak = outcome.nextStreak;
  }
  assert(total === 41, "perfect run maximum should equal the registered maximum");
});

Deno.test("streak bonuses and final-question bonus follow the configured rule", () => {
  const thirdCorrect = scoreNumberChallengeAnswer({
    questionIndex: 2,
    isCorrect: true,
    currentStreak: 2,
  });
  assert(thirdCorrect.pointsDelta === 2, "third consecutive answer earns one bonus");
  assert(thirdCorrect.nextStreak === 3, "streak should advance");

  const fifthCorrect = scoreNumberChallengeAnswer({
    questionIndex: 4,
    isCorrect: true,
    currentStreak: 4,
  });
  assert(fifthCorrect.pointsDelta === 3, "fifth consecutive answer earns two bonuses");

  const finalCorrect = scoreNumberChallengeAnswer({
    questionIndex: 14,
    isCorrect: true,
    currentStreak: 14,
  });
  assert(finalCorrect.pointsDelta === 5, "final answer includes base, streak bonuses and final bonus");
});

Deno.test("an incorrect answer resets the streak and adds no points", () => {
  const outcome = scoreNumberChallengeAnswer({
    questionIndex: 5,
    isCorrect: false,
    currentStreak: 5,
  });
  assert(outcome.pointsDelta === 0, "incorrect answer earns no points");
  assert(outcome.nextStreak === 0, "incorrect answer resets streak");
});

Deno.test("rejects invalid question and streak state", () => {
  let rejectedQuestion = false;
  let rejectedStreak = false;
  try {
    scoreNumberChallengeAnswer({ questionIndex: 15, isCorrect: true, currentStreak: 0 });
  } catch {
    rejectedQuestion = true;
  }
  try {
    scoreNumberChallengeAnswer({ questionIndex: 3, isCorrect: true, currentStreak: 4 });
  } catch {
    rejectedStreak = true;
  }
  assert(rejectedQuestion, "question index 15 must be rejected");
  assert(rejectedStreak, "streak cannot exceed the preceding question count");
});


Deno.test("central display uses the stored game-specific maximum", () => {
  const currentGame = buildVerifiedScoreResult("grade3-temmy-number-challenge", 24);
  assert(currentGame.ok, "24 should be valid under Number Challenge's 41-point rule");
  const currentDisplay = buildCentralScoreDisplay(currentGame.result);
  assert(currentDisplay.score_label === "24/41", "central UI should not display 24/15");
  assert(currentDisplay.points_awarded_label === "24 points awarded", "award label should show exact points");

  const testCatalogue: Readonly<Record<string, GameScoringRule>> = {
    "test-game-out-of-20": {
      gameId: "test-game-out-of-20",
      displayName: "Test Game (20 points)",
      questionCount: 20,
      maxScore: 20,
      ruleVersion: "test-v1",
      rewardPointsEqualScore: true,
    },
  };
  const outOf20 = buildVerifiedScoreResult("test-game-out-of-20", 16, testCatalogue);
  assert(outOf20.ok, "16/20 should be valid");
  const outOf20Display = buildCentralScoreDisplay(outOf20.result);
  assert(outOf20Display.score_label === "16/20", "central UI should display 16/20");
  assert(outOf20Display.points_awarded_label === "16 points awarded", "16 points should be awarded");
});
