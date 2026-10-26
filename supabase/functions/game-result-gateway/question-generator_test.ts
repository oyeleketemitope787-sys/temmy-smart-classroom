import { generateNumberChallengeQuestions } from "./question-generator.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function seededRandom(seed: number): () => number {
  let state = seed >>> 0;
  return () => {
    state = (1664525 * state + 1013904223) >>> 0;
    return state / 0x100000000;
  };
}

Deno.test("generates 15 questions with sequential indexes", () => {
  for (let seed = 1; seed <= 200; seed++) {
    const questions = generateNumberChallengeQuestions(seededRandom(seed));
    assert(questions.length === 15, "each attempt must have 15 questions");

    questions.forEach((question, index) => {
      assert(question.question_index === index, "question indexes must be sequential");
      assert(question.prompt.trim().length > 0, "question prompt must be present");
      assert(question.hint.trim().length > 0, "hint must be present");
      assert(question.options.length === 4, "each question must have four options");
      assert(new Set(question.options).size === 4, "options must be distinct");
      assert(
        Number.isInteger(question.correct_choice_index) &&
          question.correct_choice_index >= 0 &&
          question.correct_choice_index <= 3,
        "correct choice index must be within bounds",
      );
    });
  }
});

Deno.test("repeated generation produces fresh question content", () => {
  const first = generateNumberChallengeQuestions(seededRandom(7));
  const second = generateNumberChallengeQuestions(seededRandom(81));
  const firstPrompts = first.map((question) => question.prompt).join("|");
  const secondPrompts = second.map((question) => question.prompt).join("|");
  assert(firstPrompts !== secondPrompts, "different seeds should change generated values");
});

Deno.test("generated choice order may vary between attempts", () => {
  const first = generateNumberChallengeQuestions(seededRandom(19));
  const second = generateNumberChallengeQuestions(seededRandom(20));
  const firstChoices = first.map((question) => question.options.join("|")).join(";");
  const secondChoices = second.map((question) => question.options.join("|")).join(";");
  assert(firstChoices !== secondChoices, "choice order should vary across attempts");
});
