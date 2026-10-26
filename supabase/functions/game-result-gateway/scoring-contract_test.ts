import {
  buildCentralScoreDisplay,
  buildVerifiedScoreResult,
  GAME_SCORING_CATALOGUE,
  scoreNumberChallengeAnswer,
  type GameScoringRule,
} from "./scoring-contract.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

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
