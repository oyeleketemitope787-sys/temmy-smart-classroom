/**
 * Central, server-side reward scoring engine.
 *
 * Input must be a sequence of correctness results derived by the trusted
 * service from protected per-attempt answer keys. Never pass booleans supplied
 * directly by a browser.
 *
 * max_reward_points is the theoretical perfect-run reward. It may exceed
 * question_count because bonuses can award additional points.
 */
export type StreakBonus = {
  threshold: number;
  points: number;
};

export type GameScoringRule = {
  game_id: string;
  version: string;
  question_count: number;
  points_per_correct: number;
  streak_bonuses: StreakBonus[];
  final_question_bonus: number;
};

export type ScoringResult = {
  game_id: string;
  scoring_rule_version: string;
  question_count: number;
  answered_count: number;
  correct_count: number;
  accuracy_percent: number;
  base_points: number;
  bonus_points: number;
  earned_points: number;
  max_reward_points: number;
};

function validateRule(rule: GameScoringRule): void {
  if (!rule.game_id.trim() || !rule.version.trim()) {
    throw new Error("A game ID and scoring-rule version are required.");
  }
  if (!Number.isInteger(rule.question_count) ||
      rule.question_count < 1 || rule.question_count > 100) {
    throw new Error("Question count must be an integer from 1 to 100.");
  }
  if (!Number.isInteger(rule.points_per_correct) ||
      rule.points_per_correct < 0 || rule.points_per_correct > 100) {
    throw new Error("Points per correct answer must be an integer from 0 to 100.");
  }
  if (!Number.isInteger(rule.final_question_bonus) ||
      rule.final_question_bonus < 0 || rule.final_question_bonus > 1000) {
    throw new Error("Final-question bonus must be an integer from 0 to 1000.");
  }

  const thresholds = new Set<number>();
  for (const bonus of rule.streak_bonuses) {
    if (!Number.isInteger(bonus.threshold) ||
        bonus.threshold < 1 || bonus.threshold > rule.question_count ||
        !Number.isInteger(bonus.points) || bonus.points < 0 || bonus.points > 1000 ||
        thresholds.has(bonus.threshold)) {
      throw new Error("Invalid or duplicate streak bonus configuration.");
    }
    thresholds.add(bonus.threshold);
  }
}

function calculateEarned(
  correctAnswers: boolean[],
  rule: GameScoringRule,
): { correctCount: number; basePoints: number; bonusPoints: number; earnedPoints: number } {
  let streak = 0;
  let correctCount = 0;
  let basePoints = 0;
  let bonusPoints = 0;

  for (let index = 0; index < correctAnswers.length; index++) {
    if (correctAnswers[index]) {
      correctCount++;
      streak++;
      basePoints += rule.points_per_correct;

      for (const bonus of rule.streak_bonuses) {
        if (streak >= bonus.threshold) bonusPoints += bonus.points;
      }

      if (index === rule.question_count - 1) {
        bonusPoints += rule.final_question_bonus;
      }
    } else {
      streak = 0;
    }
  }

  return {
    correctCount,
    basePoints,
    bonusPoints,
    earnedPoints: basePoints + bonusPoints,
  };
}

export function maximumRewardPoints(rule: GameScoringRule): number {
  validateRule(rule);
  const perfectRun = Array.from({ length: rule.question_count }, () => true);
  return calculateEarned(perfectRun, rule).earnedPoints;
}

export function calculateGameReward(
  correctAnswers: boolean[],
  rule: GameScoringRule,
): ScoringResult {
  validateRule(rule);

  if (!Array.isArray(correctAnswers) ||
      correctAnswers.length < 1 ||
      correctAnswers.length > rule.question_count ||
      correctAnswers.some((value) => typeof value !== "boolean")) {
    throw new Error("Correctness results must be a non-empty valid sequence.");
  }

  const calculated = calculateEarned(correctAnswers, rule);
  const maxReward = maximumRewardPoints(rule);
  const accuracy = Math.round(
    (calculated.correctCount / rule.question_count) * 100,
  );

  if (calculated.earnedPoints > maxReward) {
    throw new Error("Calculated reward exceeds the configured maximum.");
  }

  return {
    game_id: rule.game_id,
    scoring_rule_version: rule.version,
    question_count: rule.question_count,
    answered_count: correctAnswers.length,
    correct_count: calculated.correctCount,
    accuracy_percent: accuracy,
    base_points: calculated.basePoints,
    bonus_points: calculated.bonusPoints,
    earned_points: calculated.earnedPoints,
    max_reward_points: maxReward,
  };
}

/**
 * Reviewed central registry entry for the currently inspected Temmy Number
 * Challenge. Future games must add an explicit server-side rule entry.
 */
export const GAME_SCORING_RULES: Record<string, GameScoringRule> = {
  "grade3-temmy-number-challenge": {
    game_id: "grade3-temmy-number-challenge",
    version: "tnc-streak-v1",
    question_count: 15,
    points_per_correct: 1,
    streak_bonuses: [
      { threshold: 3, points: 1 },
      { threshold: 5, points: 1 },
    ],
    final_question_bonus: 2,
  },
};
