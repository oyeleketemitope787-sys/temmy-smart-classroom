/**
 * Server-side, per-attempt question generator for Temmy Number Challenge.
 *
 * The trusted caller must store correct_choice_index in protected attempt
 * state and must never return it to the browser. This generates fresh values
 * per attempt rather than reusing the fixed answer key in the public HTML.
 */
export type GeneratedQuestion = {
  question_index: number;
  prompt: string;
  options: string[];
  hint: string;
  correct_choice_index: number;
};

type RandomSource = () => number;

function randomInt(random: RandomSource, min: number, max: number): number {
  const value = random();
  const safe = Number.isFinite(value) ? Math.min(Math.max(value, 0), 0.999999999) : 0;
  return min + Math.floor(safe * (max - min + 1));
}

function shuffle<T>(items: T[], random: RandomSource): T[] {
  const output = [...items];
  for (let i = output.length - 1; i > 0; i--) {
    const j = randomInt(random, 0, i);
    [output[i], output[j]] = [output[j], output[i]];
  }
  return output;
}

function uniqueNumbers(
  random: RandomSource,
  min: number,
  max: number,
  count: number,
): number[] {
  const values = new Set<number>();
  let guard = 0;
  while (values.size < count && guard < 100) {
    values.add(randomInt(random, min, max));
    guard++;
  }
  if (values.size !== count) {
    throw new Error("Could not generate enough distinct numbers.");
  }
  return [...values];
}

function withCorrect(
  questionIndex: number,
  prompt: string,
  correct: string,
  distractors: string[],
  hint: string,
  random: RandomSource,
): GeneratedQuestion {
  const all = [correct, ...distractors];
  if (all.length !== 4 || new Set(all).size !== 4) {
    throw new Error("Question must have four distinct choices.");
  }

  const shuffled = shuffle(
    all.map((text) => ({ text, isCorrect: text === correct })),
    random,
  );
  const correctIndex = shuffled.findIndex((choice) => choice.isCorrect);

  return {
    question_index: questionIndex,
    prompt,
    options: shuffled.map((choice) => choice.text),
    hint,
    correct_choice_index: correctIndex,
  };
}

function comparison(questionIndex: number, random: RandomSource): GeneratedQuestion {
  const pair = uniqueNumbers(random, 20, 999, 2);
  const a = pair[0], b = pair[1];
  const correct = a < b ? "<" : ">";
  const choices = ["<", ">", "=", "+"];
  return withCorrect(
    questionIndex,
    String(a) + " ___ " + String(b),
    correct,
    choices.filter((choice) => choice !== correct),
    "Compare digits from left to right: hundreds, then tens, then ones.",
    random,
  );
}

function orderedList(
  questionIndex: number,
  descending: boolean,
  random: RandomSource,
): GeneratedQuestion {
  const values = uniqueNumbers(random, 20, 999, 5);
  const sorted = [...values].sort((a, b) => descending ? b - a : a - b);
  const correct = sorted.join(", ");
  const candidates = new Set<string>();
  const permutations = [
    [1, 0, 2, 3, 4],
    [0, 2, 1, 3, 4],
    [0, 1, 3, 2, 4],
    [4, 3, 2, 1, 0],
    [2, 3, 4, 0, 1],
    [1, 2, 3, 4, 0],
  ];
  for (const indexes of permutations) {
    const candidate = indexes.map((i) => sorted[i]).join(", ");
    if (candidate !== correct) candidates.add(candidate);
    if (candidates.size === 3) break;
  }
  if (candidates.size !== 3) {
    throw new Error("Could not create distinct ordering distractors.");
  }

  return withCorrect(
    questionIndex,
    (descending ? "Greatest → Smallest: " : "Smallest → Greatest: ") + values.join(", "),
    correct,
    [...candidates],
    descending ? "Start with the greatest number." : "Start with the smallest number.",
    random,
  );
}

function closestNumber(questionIndex: number, random: RandomSource): GeneratedQuestion {
  const target = randomInt(random, 120, 880);
  const delta = randomInt(random, 1, 8) * (random() < 0.5 ? -1 : 1);
  const correct = target + delta;
  const distances = shuffle([24, 33, 46], random);
  const signs = shuffle([-1, 1], random);
  const distractors = distances.map((distance, i) =>
    String(target + distance * signs[i % signs.length])
  );
  return withCorrect(
    questionIndex,
    "Which number is closest to " + target + "?",
    String(correct),
    distractors,
    "Compare how far each option is from the target number.",
    random,
  );
}

function inequality(
  questionIndex: number,
  kind: "less-than" | "greater-than",
  random: RandomSource,
): GeneratedQuestion {
  const target = randomInt(random, 150, 850);
  const correct = kind === "less-than"
    ? target - randomInt(random, 1, 80)
    : target + randomInt(random, 1, 80);
  const distractors = kind === "less-than"
    ? [target, target + 11, target + 37]
    : [target, target - 13, target - 41];

  return withCorrect(
    questionIndex,
    kind === "less-than" ? "___ < " + target : "___ > " + target,
    String(correct),
    distractors.map(String),
    kind === "less-than"
      ? "Choose a number smaller than the given number."
      : "Choose a number greater than the given number.",
    random,
  );
}

function numberLessThan(questionIndex: number, random: RandomSource): GeneratedQuestion {
  const target = randomInt(random, 150, 850);
  const correct = target + randomInt(random, 1, 80);
  return withCorrect(
    questionIndex,
    String(target) + " < ___",
    String(correct),
    [target, target - 12, target - 39].map(String),
    "The missing number must be greater than the number on the left.",
    random,
  );
}

function betweenNumbers(questionIndex: number, random: RandomSource): GeneratedQuestion {
  const lower = randomInt(random, 120, 500);
  const gap = randomInt(random, 40, 160);
  const upper = lower + gap;
  const correct = lower + randomInt(random, 1, gap - 1);
  const distractors = [
    lower,
    upper,
    Math.max(0, lower - randomInt(random, 5, 25)),
  ];
  return withCorrect(
    questionIndex,
    "Which number lies strictly between " + lower + " and " + upper + "?",
    String(correct),
    distractors.map(String),
    "The answer is greater than the lower number and less than the upper number.",
    random,
  );
}

function trueComparison(questionIndex: number, random: RandomSource): GeneratedQuestion {
  const pair = uniqueNumbers(random, 100, 999, 2);
  const low = Math.min(pair[0], pair[1]);
  const high = Math.max(pair[0], pair[1]);
  return withCorrect(
    questionIndex,
    "Which statement is TRUE?",
    String(low) + " < " + String(high),
    [
      String(high) + " < " + String(low),
      String(low) + " > " + String(high),
      String(low) + " = " + String(high),
    ],
    "Compare the values of the two numbers.",
    random,
  );
}

function placeValueReasoning(questionIndex: number, random: RandomSource): GeneratedQuestion {
  const hundreds = randomInt(random, 1, 8);
  const tens = randomInt(random, 1, 7);
  const aOnes = randomInt(random, 5, 9);
  const bOnes = randomInt(random, 0, 4);
  const a = hundreds * 100 + tens * 10 + aOnes;
  const b = hundreds * 100 + (tens + 1) * 10 + bOnes;

  return withCorrect(
    questionIndex,
    "A pupil says " + a + " > " + b + " because " + aOnes + " > " + bOnes + ". Is the pupil correct?",
    "No",
    ["Yes", "Sometimes", "Cannot tell"],
    "Compare hundreds first, then tens, then ones.",
    random,
  );
}

function greatestNumber(questionIndex: number, random: RandomSource): GeneratedQuestion {
  const values = uniqueNumbers(random, 100, 999, 4);
  const correct = String(Math.max(...values));
  return withCorrect(
    questionIndex,
    "Which is the greatest number?",
    correct,
    values.filter((value) => String(value) !== correct).slice(0, 3).map(String),
    "Compare hundreds, then tens, then ones.",
    random,
  );
}

/**
 * Generates 15 fresh questions. Inject random in tests; production should
 * supply a Web Crypto-backed random source rather than Math.random.
 */
export function generateNumberChallengeQuestions(
  random: RandomSource = Math.random,
): GeneratedQuestion[] {
  return [
    comparison(0, random),
    comparison(1, random),
    comparison(2, random),
    orderedList(3, false, random),
    orderedList(4, true, random),
    closestNumber(5, random),
    inequality(6, "less-than", random),
    numberLessThan(7, random),
    inequality(8, "greater-than", random),
    inequality(9, "less-than", random),
    betweenNumbers(10, random),
    trueComparison(11, random),
    placeValueReasoning(12, random),
    orderedList(13, false, random),
    greatestNumber(14, random),
  ];
}
