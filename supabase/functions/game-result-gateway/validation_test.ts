import { validateResultRequest } from "./validation.ts";
import type { GameScoringRule } from "./scoring-contract.ts";

const token = "00000000-0000-4000-8000-000000000001";
const gameId = "grade3-temmy-number-challenge";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

Deno.test("accepts a valid start-attempt request", () => {
  const result = validateResultRequest({
    action: "start_attempt",
    session_token: token,
    game_id: gameId,
    mode: "practice",
  });
  assert(result.ok, "expected a valid start request");
  assert(result.request.action === "start_attempt", "expected start action");
});

Deno.test("accepts all documented Number Challenge modes", () => {
  for (const mode of ["practice", "challenge", "class"] as const) {
    const result = validateResultRequest({
      action: "start_attempt",
      session_token: token,
      game_id: gameId,
      mode,
    });
    assert(result.ok, "expected mode to be accepted: " + mode);
    if (result.ok) {
      assert(result.request.action === "start_attempt", "expected start action");
      assert(result.request.mode === mode, "selected mode should be preserved");
    }
  }
});

Deno.test("accepts one valid answer submission", () => {
  const result = validateResultRequest({
    action: "submit_answer",
    session_token: token,
    game_id: gameId,
    question_index: 0,
    choice_index: 1,
  });
  assert(result.ok, "expected a valid answer request");
  assert(result.request.action === "submit_answer", "expected submit-answer action");
});

Deno.test("rejects client-supplied score fields", () => {
  const result = validateResultRequest({
    action: "submit_answer",
    session_token: token,
    game_id: gameId,
    question_index: 0,
    choice_index: 1,
    score: 15,
    max_score: 15,
  });
  assert(!result.ok, "score fields must not be accepted from the browser");
});

Deno.test("rejects client-supplied student identity", () => {
  const result = validateResultRequest({
    action: "start_attempt",
    session_token: token,
    game_id: gameId,
    mode: "practice",
    student_id: token,
  });
  assert(!result.ok, "student identity must come from the stored session");
});

Deno.test("rejects client-supplied correctness claims", () => {
  const result = validateResultRequest({
    action: "submit_answer",
    session_token: token,
    game_id: gameId,
    question_index: 0,
    choice_index: 1,
    is_correct: true,
  });
  assert(!result.ok, "correctness must be calculated on the trusted side");
});

Deno.test("rejects an unsupported game mode", () => {
  const result = validateResultRequest({
    action: "start_attempt",
    session_token: token,
    game_id: gameId,
    mode: "speed-hack",
  });
  assert(!result.ok, "unsupported modes must be rejected");
});

Deno.test("rejects an unsupported game ID", () => {
  const result = validateResultRequest({
    action: "start_attempt",
    session_token: token,
    game_id: "unapproved-game",
    mode: "practice",
  });
  assert(!result.ok, "expected an unknown game to be rejected");
});

Deno.test("rejects inherited object property names as game IDs", () => {
  for (const candidate of ["__proto__", "constructor", "toString"]) {
    const result = validateResultRequest({
      action: "start_attempt",
      session_token: token,
      game_id: candidate,
      mode: "practice",
    });
    assert(!result.ok, "non-catalogue property name must not be accepted: " + candidate);
  }
});

Deno.test("rejects an invalid session token", () => {
  const result = validateResultRequest({
    action: "start_attempt",
    session_token: "not-a-uuid",
    game_id: gameId,
    mode: "practice",
  });
  assert(!result.ok, "expected malformed token to be rejected");
});

Deno.test("rejects out-of-range question and choice indexes", () => {
  const badQuestion = validateResultRequest({
    action: "submit_answer",
    session_token: token,
    game_id: gameId,
    question_index: 15,
    choice_index: 1,
  });
  const badChoice = validateResultRequest({
    action: "submit_answer",
    session_token: token,
    game_id: gameId,
    question_index: 0,
    choice_index: 4,
  });
  assert(!badQuestion.ok, "question indexes must be 0..14");
  assert(!badChoice.ok, "choice indexes must be 0..3");
});

Deno.test("rejects negative and non-integer indexes", () => {
  const negative = validateResultRequest({
    action: "submit_answer",
    session_token: token,
    game_id: gameId,
    question_index: -1,
    choice_index: 0,
  });
  const fractional = validateResultRequest({
    action: "submit_answer",
    session_token: token,
    game_id: gameId,
    question_index: 0.5,
    choice_index: 1,
  });
  assert(!negative.ok, "negative indexes must be rejected");
  assert(!fractional.ok, "fractional indexes must be rejected");
});

Deno.test("rejects unknown actions and unexpected nested fields", () => {
  const action = validateResultRequest({
    action: "submit_result",
    session_token: token,
    game_id: gameId,
    mode: "practice",
  });
  const nested = validateResultRequest({
    action: "submit_answer",
    session_token: token,
    game_id: gameId,
    question_index: 0,
    choice_index: 1,
    metadata: { score: 15 },
  });
  assert(!action.ok, "the deprecated bulk-result action must be rejected");
  assert(!nested.ok, "unexpected fields must be rejected");
});


Deno.test("supports a separately registered 20-question game", () => {
  const catalogue: Readonly<Record<string, GameScoringRule>> = {
    "test-game-out-of-20": {
      gameId: "test-game-out-of-20",
      displayName: "Test Game (20 points)",
      questionCount: 20,
      maxScore: 20,
      ruleVersion: "test-v1",
      rewardPointsEqualScore: true,
    },
  };
  const start = validateResultRequest({
    action: "start_attempt",
    session_token: token,
    game_id: "test-game-out-of-20",
    mode: "challenge",
  }, catalogue);
  const lastAnswer = validateResultRequest({
    action: "submit_answer",
    session_token: token,
    game_id: "test-game-out-of-20",
    question_index: 19,
    choice_index: 3,
  }, catalogue);
  assert(start.ok, "the registered 20-question game should be accepted");
  assert(lastAnswer.ok, "question index 19 should be valid for a 20-question game");
});

Deno.test("rejects question indexes beyond that game's configured count", () => {
  const catalogue: Readonly<Record<string, GameScoringRule>> = {
    "test-game-out-of-20": {
      gameId: "test-game-out-of-20",
      displayName: "Test Game (20 points)",
      questionCount: 20,
      maxScore: 20,
      ruleVersion: "test-v1",
      rewardPointsEqualScore: true,
    },
  };
  const result = validateResultRequest({
    action: "submit_answer",
    session_token: token,
    game_id: "test-game-out-of-20",
    question_index: 20,
    choice_index: 0,
  }, catalogue);
  assert(!result.ok, "question index 20 should be invalid for a 20-question game");
});
