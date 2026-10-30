import {
  calculateGameReward,
  GAME_SCORING_RULES,
  maximumRewardPoints,
  type GameScoringRule,
} from "./scoring.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

const numberChallenge = GAME_SCORING_RULES["grade3-temmy-number-challenge"];

Deno.test("perfect number challenge earns 41 reward points from 15 questions", () => {
  const result = calculateGameReward(Array.from({ length: 15 }, () => true), numberChallenge);
  assert(result.correct_count === 15, "all answers should be correct");
  assert(result.base_points === 15, "base points should be 15");
  assert(result.bonus_points === 26, "streak/final bonuses should total 26");
  assert(result.earned_points === 41, "actual reward should be 41, not capped at 15");
  assert(result.max_reward_points === 41, "perfect-run maximum should be 41");
  assert(result.accuracy_percent === 100, "accuracy should be 100 percent");
});

Deno.test("streak bonuses allow actual reward to exceed correct answers", () => {
  const result = calculateGameReward([true, true, true, true, true], numberChallenge);
  assert(result.correct_count === 5, "five answers should be correct");
  assert(result.earned_points === 9, "five consecutive correct answers earn 9 points");
  assert(result.earned_points > result.correct_count,
    "bonus points must not be clipped to the number of correct answers");
});

Deno.test("a wrong answer resets the streak", () => {
  const result = calculateGameReward(
    [true, true, false, true, true, true],
    numberChallenge,
  );
  assert(result.correct_count === 5, "five answers should be correct");
  assert(result.earned_points === 7, "the broken streak must reset bonus progression");
});

Deno.test("the final-question bonus is awarded only for a correct final answer", () => {
  const correctFinal = calculateGameReward(
    Array.from({ length: 15 }, () => true),
    numberChallenge,
  );
  const wrongFinal = calculateGameReward(
    [...Array.from({ length: 14 }, () => true), false],
    numberChallenge,
  );
  assert(correctFinal.earned_points - wrongFinal.earned_points === 4,
    "final answer also carries the third streak point plus final bonus");
});

Deno.test("supports a 20-question game whose reward maximum exceeds 20", () => {
  const twentyQuestionRule: GameScoringRule = {
    game_id: "example-grade7-challenge",
    version: "example-v1",
    question_count: 20,
    points_per_correct: 1,
    streak_bonuses: [
      { threshold: 3, points: 1 },
      { threshold: 5, points: 1 },
    ],
    final_question_bonus: 2,
  };
  const result = calculateGameReward(
    Array.from({ length: 20 }, () => true),
    twentyQuestionRule,
  );
  assert(result.correct_count === 20, "all twenty answers should be correct");
  assert(result.earned_points === 56, "twenty-question perfect run earns 56");
  assert(result.max_reward_points === 56, "maximum reward must include bonuses");
  assert(result.earned_points > 20, "earned points may exceed question count");
  assert(maximumRewardPoints(twentyQuestionRule) === 56,
    "central maximum should come from server-side rule configuration");
});

Deno.test("partial challenge-mode attempts retain the earned reward", () => {
  const result = calculateGameReward(
    [true, true, true, false, false, false],
    numberChallenge,
  );
  assert(result.answered_count === 6, "all six attempted questions should be counted");
  assert(result.earned_points === 4, "earned base and streak points should be retained");
  assert(result.max_reward_points === 41, "display ceiling remains the game's perfect-run maximum");
  assert(result.accuracy_percent === 20, "accuracy remains correct divided by 15");
});

Deno.test("rejects malformed scoring input and unsafe rule configuration", () => {
  let badAnswersRejected = false;
  try {
    calculateGameReward([true, "yes" as unknown as boolean], numberChallenge);
  } catch {
    badAnswersRejected = true;
  }
  assert(badAnswersRejected, "non-boolean correctness must be rejected");

  let badRuleRejected = false;
  try {
    maximumRewardPoints({
      ...numberChallenge,
      streak_bonuses: [
        { threshold: 3, points: 1 },
        { threshold: 3, points: 2 },
      ],
    });
  } catch {
    badRuleRejected = true;
  }
  assert(badRuleRejected, "duplicate streak thresholds must be rejected");
});
