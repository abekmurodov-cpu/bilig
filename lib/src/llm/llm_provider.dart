import '../models/knowledge_item.dart';

/// Result of grading a free-typed answer with an LLM.
class LlmGrade {
  const LlmGrade({required this.correct, this.feedback});

  final bool correct;
  final String? feedback;
}

/// A cached multiple-choice quiz for a note: one concise correct answer plus
/// short plausible-but-wrong distractors. Kept deliberately terse (1–2
/// sentences each) so options read cleanly rather than dumping the full detail.
class McQuiz {
  const McQuiz({
    required this.question,
    required this.answer,
    required this.distractors,
  });

  /// A clear question testing the note (reworded from a bare fact if needed).
  final String question;
  final String answer;
  final List<String> distractors;
}

/// Why an LLM call failed, so callers can react (pause, tell the user) instead
/// of silently degrading.
enum LlmErrorKind {
  /// Too many requests right now; retry after [LlmException.retryAfter].
  rateLimited,

  /// The daily / billing quota is used up; retrying today won't help.
  quotaExhausted,

  /// The key was rejected.
  auth,

  /// No connection or the request timed out.
  network,

  /// The model answered, but not in a usable shape.
  badResponse,

  /// Anything else (server error, bad model name, ...).
  other,
}

class LlmException implements Exception {
  const LlmException(this.kind, this.message, {this.retryAfter});

  final LlmErrorKind kind;
  final String message;
  final Duration? retryAfter;

  @override
  String toString() => message;
}

/// Abstraction over a large-language-model backend. Implementations are
/// attached/detached at runtime by the user (starting with Gemini). Every
/// method may throw — preferably an [LlmException] — and callers treat the LLM
/// as a best-effort enhancement with a non-LLM fallback.
abstract class LlmProvider {
  /// Human-readable name of the attached model/provider (for settings UI).
  String get displayName;

  /// Given a note whose answer is missing, returns a concise answer/explanation
  /// for its [KnowledgeItem.front].
  Future<String> expandNote(KnowledgeItem item);

  /// Builds a full multiple-choice quiz for [item]: a concise correct answer
  /// plus [distractorCount] short wrong options. Works even when the note has no
  /// recorded answer yet (it reasons from the prompt).
  Future<McQuiz> generateQuiz(KnowledgeItem item, {int distractorCount = 3});

  /// Builds quizzes for several notes in **one** request, keyed by note id:
  /// up to [variantCount] differently-angled questions per note. Notes the
  /// model skipped or garbled are simply absent from the result.
  Future<Map<String, List<McQuiz>>> generateQuizzes(
    List<KnowledgeItem> items, {
    int distractorCount = 3,
    int variantCount = 3,
  });

  /// Judges whether [answer] is a correct response to [item].
  Future<LlmGrade> gradeAnswer(KnowledgeItem item, String answer);

  /// Grades a rewritten code snippet against the note's reference code: passes
  /// when [submitted] is valid, working code that accomplishes the same thing
  /// (it need not be identical). Judges syntax/logic, not exact text.
  Future<LlmGrade> gradeCode(KnowledgeItem item, String submitted);

  /// Suggests a short category/tag for a freshly captured note.
  Future<String> suggestCategory(String front, String? back);
}
