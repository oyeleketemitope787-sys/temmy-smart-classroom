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

function chosen(q: { options: string[]; correct_choice_index: number }): string {
  return q.options[q.correct_choice_index];
}

function verifySemanticAnswer(q: ReturnType<typeof generateNumberChallengeQuestions>[number]) {
  const answer = chosen(q);

  if (q.question_index <= 2) {
    const match = q.prompt.match(/^(\d+) ___ (\d+)$/);
    assert(match, "comparison prompt format should be valid");
    const a = Number(match[1]), b = Number(match[2]);
    const expected = a < b ? "<" : a > b ? ">" : "=";
    assert(answer === expected, "comparison correct choice must match numeric ordering");
    return;
  }

  if ([3, 4, 13].includes(q.question_index)) {
    const ascending = q.prompt.startsWith("Smallest");
    const source = q.prompt.slice(q.prompt.indexOf(":") + 1)
      .split(",").map((value) => Number(value.trim()));
    const sorted = [...source].sort((a, b) => ascending ? a - b : b - a).join(", ");
    assert(answer === sorted, "ordered-list answer must have the requested order");
    return;
  }

  if (q.question_index === 5) {
    const match = q.prompt.match(/closest to (\d+)/);
    assert(match, "closest-number target should be present");
    const target = Number(match[1]);
    const chosenDistance = Math.abs(Number(answer) - target);
    const bestDistance = Math.min(...q.options.map((value) => Math.abs(Number(value) - target)));
    assert(chosenDistance === bestDistance, "chosen number must be uniquely closest");
    return;
  }

  if (q.question_index === 6 || q.question_index === 9) {
    const match = q.prompt.match(/^___ < (\d+)$/);
    assert(match, "less-than prompt should be valid");
    assert(Number(answer) < Number(match[1]), "answer must be less than the target");
    return;
  }

  if (q.question_index === 7) {
    const match = q.prompt.match(/^(\d+) < ___$/);
    assert(match, "number-less-than prompt should be valid");
    assert(Number(answer) > Number(match[1]), "answer must be greater than the left value");
    return;
  }

  if (q.question_index === 8) {
    const match = q.prompt.match(/^___ > (\d+)$/);
    assert(match, "greater-than prompt should be valid");
    assert(Number(answer) > Number(match[1]), "answer must be greater than the target");
    return;
  }

  if (q.question_index === 10) {
    const match = q.prompt.match(/between (\d+) and (\d+)/);
    assert(match, "between-number bounds should be present");
    assert(Number(answer) > Number(match[1]) && Number(answer) < Number(match[2]),
      "answer must be strictly between both bounds");
    return;
  }

  if (q.question_index === 11) {
    const match = answer.match(/^(\d+) (<|>|=) (\d+)$/);
    assert(match, "truth-comparison answer should be a comparison");
    const a = Number(match[1]), b = Number(match[3]);
    const holds = match[2] === "<" ? a < b : match[2] === ">" ? a > b : a === b;
    assert(holds, "selected comparison statement must be true");
    return;
  }

  if (q.question_index === 12) {
    const match = q.prompt.match(/says (\d+) > (\d+) because/);
    assert(match, "place-value reasoning question should be valid");
    assert(Number(match[1]) < Number(match[2]), "the pupil's stated inequality should be false");
    assert(answer === "No", "answer should reject the pupil's reasoning");
    return;
  }

  if (q.question_index === 14) {
    const largest = Math.max(...q.options.map(Number));
    assert(Number(answer) === largest, "selected answer must be greatest among choices");
  }
}

Deno.test("generates 15 valid questions across 200 deterministic runs", () => {
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
      verifySemanticAnswer(question);
    });
  }
});

Deno.test("different attempt seeds produce fresh question content", () => {
  const first = generateNumberChallengeQuestions(seededRandom(7));
  const second = generateNumberChallengeQuestions(seededRandom(81));
  const firstPrompts = first.map((question) => question.prompt).join("|");
  const secondPrompts = second.map((question) => question.prompt).join("|");
  assert(firstPrompts !== secondPrompts, "different seeds should change generated values");
});

Deno.test("choice order can vary across attempts", () => {
  const first = generateNumberChallengeQuestions(seededRandom(19));
  const second = generateNumberChallengeQuestions(seededRandom(20));
  const firstChoices = first.map((question) => question.options.join("|")).join(";");
  const secondChoices = second.map((question) => question.options.join("|")).join(";");
  assert(firstChoices !== secondChoices, "choice order should vary across attempts");
});
