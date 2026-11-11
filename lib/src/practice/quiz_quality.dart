import '../llm/llm_provider.dart';
import 'answer_matching.dart';

/// Why a generated quiz was rejected before being cached.
enum QuizProblem {
  empty,
  tooFewOptions,
  duplicateOptions,
  answerInQuestion,
  answerTooLong,
  lengthGivesAway,
}

/// Checks a generated [quiz] for the mistakes that make practice feel broken:
/// missing parts, repeated options, the answer leaked into the question, or a
/// correct option that stands out just by being much longer. Returns null when
/// the quiz is fine to cache.
QuizProblem? quizProblem(McQuiz quiz) {
  final question = normalizeAnswer(quiz.question);
  final answer = normalizeAnswer(quiz.answer);
  if (question.isEmpty || answer.isEmpty) return QuizProblem.empty;
  if (quiz.answer.length > 200) return QuizProblem.answerTooLong;

  final options = [answer];
  for (final d in quiz.distractors) {
    final n = normalizeAnswer(d);
    if (n.isEmpty) continue;
    if (options.any((o) => o == n || similarity(o, n) > 0.9)) {
      return QuizProblem.duplicateOptions;
    }
    options.add(n);
  }
  if (options.length < 3) return QuizProblem.tooFewOptions;

  // "What is the capital of France? → Paris" is fine; "In what city is Paris,
  // the capital of France? → Paris" is not. Only multi-character answers count,
  // so a one-letter or numeric answer can't false-positive.
  if (answer.length >= 4 && ' $question '.contains(' $answer ')) {
    return QuizProblem.answerInQuestion;
  }

  final distractorLengths = [
    for (final d in quiz.distractors) d.trim().length,
  ];
  final longest = distractorLengths.reduce((a, b) => a > b ? a : b);
  if (quiz.answer.trim().length > 40 &&
      quiz.answer.trim().length > longest * 2.2) {
    return QuizProblem.lengthGivesAway;
  }
  return null;
}
