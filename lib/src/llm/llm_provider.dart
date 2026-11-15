import 'dart:typed_data';

import '../models/knowledge_item.dart';

/// Result of grading a free-typed answer with an LLM.
class LlmGrade {
  const LlmGrade({required this.correct, this.partial = false, this.feedback});

  /// Right in substance (a [partial] answer counts as correct, but weaker).
  final bool correct;

  /// Got the main idea but missed or garbled part of it.
  final bool partial;
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

/// A file sent along with a prompt: a photo or a voice recording.
class Attachment {
  const Attachment(this.mimeType, this.bytes);

  final String mimeType;
  final Uint8List bytes;

  bool get isImage => mimeType.startsWith('image/');

  /// An image attachment, its type read from the file's first bytes.
  factory Attachment.image(Uint8List bytes) {
    final png = bytes.length > 4 && bytes[0] == 0x89 && bytes[1] == 0x50;
    final webp = bytes.length > 12 &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP';
    return Attachment(
        png ? 'image/png' : (webp ? 'image/webp' : 'image/jpeg'), bytes);
  }
}

/// A note the AI proposed (from a photo or pasted text) for the student to
/// keep or drop before anything is saved.
class NoteDraft {
  const NoteDraft({
    required this.front,
    this.back,
    this.type = KnowledgeType.concept,
    this.category,
    this.highlights = const [],
    this.tags = const [],
  });

  final String front;
  final String? back;
  final KnowledgeType type;
  final String? category;

  /// Key ideas already marked (Anki cloze deletions become highlights).
  final List<String> highlights;
  final List<String> tags;

  NoteDraft copyWith({String? front, String? back, KnowledgeType? type}) =>
      NoteDraft(
        front: front ?? this.front,
        back: back ?? this.back,
        type: type ?? this.type,
        category: category,
        highlights: highlights,
        tags: tags,
      );
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

  /// After a wrong answer: why the right answer is right (and the student's
  /// isn't), plus a short memory trick. 2-3 short lines.
  Future<String> explainMistake(KnowledgeItem item,
      {required String question, required String answer, String? studentAnswer});

  /// Whether this AI can read photos (most current models can).
  bool get canReadImages;

  /// Whether this AI can turn a voice recording into text.
  bool get canTranscribe;

  /// Reads study material in a photo (a textbook page, slide, whiteboard)
  /// and proposes notes from it.
  Future<List<NoteDraft>> notesFromImage(Attachment image);

  /// Splits pasted study text (a lecture summary, an article) into notes.
  Future<List<NoteDraft>> notesFromText(String text);

  /// Writes down what is said in a voice recording, in its own language.
  Future<String> transcribe(Attachment audio);

  /// Picks the few key words or ideas in [item] worth highlighting, copied
  /// exactly from the note's text.
  Future<List<String>> suggestHighlights(KnowledgeItem item);

  /// Groups the notes of one course ([category]) into a few topics: note id
  /// → topic name. Existing topic names are reused where they fit.
  Future<Map<String, String>> suggestTopics(String category, List<KnowledgeItem> notes);
}
