import 'dart:convert';

import '../models/knowledge_item.dart';
import 'llm_provider.dart';

/// Implements every [LlmProvider] task on top of a single text-completion
/// call, so each backend only has to say how to send a prompt. Prompts and
/// response parsing live here and are shared by all backends.
abstract class PromptedLlm implements LlmProvider {
  /// Sends [prompt] and returns the model's reply text. With [json] the
  /// backend should switch on its strict-JSON output mode when it has one.
  /// Should throw [LlmException] on failure.
  Future<String> complete(String prompt, {bool json = false});

  /// Note details longer than this are trimmed before prompting: the quiz only
  /// needs the gist, and long code/explanations burn tokens.
  static const int maxDetailChars = 600;

  @override
  Future<String> expandNote(KnowledgeItem item) {
    return complete(
      'You are helping build a spaced-repetition flashcard. '
      'Give a concise, correct answer/explanation (1-3 sentences) for this '
      '${item.type.label.toLowerCase()} prompt. Write in the same language as '
      'the prompt. Reply with the answer only, no preamble.\n\n'
      'Prompt: ${item.front}',
    );
  }

  @override
  Future<McQuiz> generateQuiz(KnowledgeItem item,
      {int distractorCount = 3}) async {
    final quizzes =
        await generateQuizzes([item], distractorCount: distractorCount);
    final quiz = quizzes[item.id];
    if (quiz == null) {
      throw const LlmException(
          LlmErrorKind.badResponse, 'The AI returned an unusable quiz');
    }
    return quiz;
  }

  @override
  Future<Map<String, McQuiz>> generateQuizzes(
    List<KnowledgeItem> items, {
    int distractorCount = 3,
  }) async {
    if (items.isEmpty) return const {};
    final raw = await complete(quizBatchPrompt(items, distractorCount), json: true);
    return parseQuizBatch(raw, items, distractorCount: distractorCount);
  }

  /// One prompt for many notes. Notes are numbered 1..n instead of sending
  /// their UUIDs, which saves tokens and is harder for the model to garble.
  static String quizBatchPrompt(List<KnowledgeItem> items, int distractorCount) {
    final notes = StringBuffer();
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      notes.writeln('[${i + 1}] (${item.type.label.toLowerCase()}) '
          '${_clip(item.front)}');
      if (item.hasAnswer) notes.writeln('    Detail: ${_clip(item.back!)}');
    }
    return 'You write quiz items for a spaced-repetition study app. '
        'For EACH note below, write one multiple-choice item.\n'
        'Return JSON only, in this shape:\n'
        '{"items": [{"id": 1, "question": "...", "answer": "...", '
        '"distractors": ["...", "..."]}]}\n'
        'Rules:\n'
        '- "id": the note number in square brackets.\n'
        '- "question": a clear question that TESTS the note. If the note is not '
        'already a question (a fact, a code snippet, a command, or a '
        'concept/term), REWRITE it as a question — never echo the note back, '
        'and never put the answer inside the question. For code or commands, '
        'ask what it does or outputs. Examples: '
        '"Water boils at 100°C" -> "At what temperature does water boil?"; '
        'a Python snippet reversing a list -> "What does this code do?"; '
        '"git reset --hard" -> "Which git command discards all local changes?". '
        'If the note is already a question, keep it.\n'
        '- "answer": the CORRECT answer, ONE short phrase or sentence '
        '(max ~15 words). Never copy long explanations or long code.\n'
        '- "distractors": exactly $distractorCount plausible but clearly WRONG '
        'answers, each distinct from the answer and from each other, in the '
        'same style and of similar length as the answer, so the length does '
        'not give the answer away.\n'
        '- Write each item in the same language as its note.\n\n'
        'Notes:\n$notes';
  }

  /// Parses a batch reply into quizzes keyed by note id. Tolerates code fences,
  /// a bare top-level list, and string ids. Malformed entries are dropped.
  static Map<String, McQuiz> parseQuizBatch(
    String raw,
    List<KnowledgeItem> items, {
    int distractorCount = 3,
  }) {
    final decoded = decodeJsonLoose(raw);
    final List<dynamic> entries;
    if (decoded is List) {
      entries = decoded;
    } else if (decoded is Map && decoded['items'] is List) {
      entries = decoded['items'] as List;
    } else if (decoded is Map && decoded['question'] != null && items.length == 1) {
      entries = [
        {...decoded, 'id': 1},
      ];
    } else {
      throw const LlmException(
          LlmErrorKind.badResponse, 'The AI returned an unusable quiz');
    }

    final result = <String, McQuiz>{};
    for (final entry in entries) {
      if (entry is! Map) continue;
      final number = int.tryParse('${entry['id']}'.trim());
      if (number == null || number < 1 || number > items.length) continue;
      final question = '${entry['question'] ?? ''}'.trim();
      final answer = '${entry['answer'] ?? ''}'.trim();
      final rawDistractors = entry['distractors'];
      if (question.isEmpty || answer.isEmpty || rawDistractors is! List) {
        continue;
      }
      final distractors = rawDistractors
          .map((e) => '$e'.trim())
          .where((e) => e.isNotEmpty && e != answer)
          .take(distractorCount)
          .toList();
      result[items[number - 1].id] =
          McQuiz(question: question, answer: answer, distractors: distractors);
    }
    return result;
  }

  @override
  Future<LlmGrade> gradeAnswer(KnowledgeItem item, String answer) async {
    final raw = await complete(
      'Grade a student\'s answer to a flashcard. Decide if it is essentially '
      'correct (meaning matches, ignore wording/typos/language). '
      'Return JSON: {"correct": true|false, "feedback": "one short sentence"}.\n\n'
      'Question: ${item.practicePrompt}\n'
      'Expected answer: ${_clip(item.mcAnswer ?? item.back ?? '')}\n'
      'Student answer: $answer',
      json: true,
    );
    return _parseGrade(raw);
  }

  @override
  Future<LlmGrade> gradeCode(KnowledgeItem item, String submitted) async {
    final raw = await complete(
      'Grade a coding exercise. The student rewrote a code snippet from memory. '
      'Pass if the submission is syntactically valid and accomplishes the same '
      'thing as the reference — it need NOT be identical (different names, '
      'formatting, or equivalent constructs are fine). Fail only for wrong logic '
      'or broken syntax.\n'
      'Return JSON: {"correct": true|false, "feedback": "one short sentence"}.\n\n'
      'Task: ${item.front}\n'
      'Reference:\n${item.back}\n\nStudent:\n$submitted',
      json: true,
    );
    return _parseGrade(raw);
  }

  @override
  Future<String> suggestCategory(String front, String? back) async {
    final text = await complete(
      'Suggest ONE short category label (1-2 words, Title Case) for this note. '
      'Reply with the label only.\n\nNote: $front'
      '${back == null ? '' : '\n${_clip(back)}'}',
    );
    return text.split('\n').first.trim();
  }

  static LlmGrade _parseGrade(String raw) {
    final decoded = decodeJsonLoose(raw);
    if (decoded is Map && decoded['correct'] is bool) {
      return LlmGrade(
        correct: decoded['correct'] as bool,
        feedback: decoded['feedback'] as String?,
      );
    }
    throw const LlmException(
        LlmErrorKind.badResponse, 'The AI returned an unusable grade');
  }

  /// Decodes JSON that may be wrapped in a code fence or surrounded by prose.
  /// Returns null when nothing parseable is found.
  static Object? decodeJsonLoose(String raw) {
    final text = raw
        .trim()
        .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
        .replaceFirst(RegExp(r'\s*```$'), '')
        .trim();
    try {
      return jsonDecode(text);
    } on FormatException {
      // Fall back to the outermost {...} or [...] span.
      final start = text.indexOf(RegExp(r'[\[{]'));
      final end = text.lastIndexOf(RegExp(r'[\]}]'));
      if (start < 0 || end <= start) return null;
      try {
        return jsonDecode(text.substring(start, end + 1));
      } on FormatException {
        return null;
      }
    }
  }

  static String _clip(String s) {
    final t = s.trim();
    return t.length <= maxDetailChars ? t : '${t.substring(0, maxDetailChars)}…';
  }
}
