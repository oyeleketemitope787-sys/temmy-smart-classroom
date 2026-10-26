import { validateResultRequest } from "./validation.ts";

const token = "00000000-0000-4000-8000-000000000001";
const validPayload = {
  action: "submit_result",
  session_token: token,
  game_id: "grade3-temmy-number-challenge",
  answers: [{ question_index: 0, choice_index: 1 }],
};

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

Deno.test("accepts a well-formed answer payload", () => {
  const result = validateResultRequest(validPayload);
  assert(result.ok, "expected request to be accepted by the shape validator");
  assert(result.request.answers.length === 1, "expected one answer");
  assert(result.request.session_token === token, "token should be preserved");
});

Deno.test("rejects client-supplied score fields", () => {
  const result = validateResultRequest({
    ...validPayload,
    score: 15,
    max_score: 15,
  });
  assert(!result.ok, "score fields must not be accepted from the browser");
});

Deno.test("rejects client-supplied student identity", () => {
  const result = validateResultRequest({
    ...validPayload,
    student_id: token,
  });
  assert(!result.ok, "student identity must be derived from the stored session");
});

Deno.test("rejects an unsupported game ID", () => {
  const result = validateResultRequest({
    ...validPayload,
    game_id: "unapproved-game",
  });
  assert(!result.ok, "expected an unknown game to be rejected");
});

Deno.test("rejects an invalid session token", () => {
  const result = validateResultRequest({
    ...validPayload,
    session_token: "not-a-uuid",
  });
  assert(!result.ok, "expected malformed token to be rejected");
});

Deno.test("rejects duplicate question indexes", () => {
  const result = validateResultRequest({
    ...validPayload,
    answers: [
      { question_index: 0, choice_index: 1 },
      { question_index: 0, choice_index: 2 },
    ],
  });
  assert(!result.ok, "a question must appear at most once");
});

Deno.test("rejects answer indexes outside supported bounds", () => {
  const badQuestion = validateResultRequest({
    ...validPayload,
    answers: [{ question_index: 15, choice_index: 1 }],
  });
  const badChoice = validateResultRequest({
    ...validPayload,
    answers: [{ question_index: 0, choice_index: 4 }],
  });
  assert(!badQuestion.ok, "question indexes must be 0..14");
  assert(!badChoice.ok, "choice indexes must be 0..3");
});

Deno.test("rejects empty and oversized answer lists", () => {
  const empty = validateResultRequest({ ...validPayload, answers: [] });
  const oversized = validateResultRequest({
    ...validPayload,
    answers: Array.from(
      { length: 16 },
      (_, question_index) => ({ question_index, choice_index: 0 }),
    ),
  });
  assert(!empty.ok, "at least one attempted question is required");
  assert(!oversized.ok, "there are only 15 questions");
});

Deno.test("rejects unexpected nested fields", () => {
  const result = validateResultRequest({
    ...validPayload,
    answers: [{ question_index: 0, choice_index: 1, correct: true }],
  });
  assert(!result.ok, "client correctness claims must not be accepted");
});
