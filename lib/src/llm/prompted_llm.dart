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
  Future<String> complete(String prompt,
      {bool json = false, List<Attachment> attachments = const []});

  @override
  bool get canReadImages => true;

  @override
  bool get canTranscribe => false;

  /// Most notes proposed from one photo or text.
  static const int maxDrafts = 25;

  static String _notesRules(String source) =>
      'You turn study material into flashcard notes for a spaced-repetition '
      'app. From $source, write one note per important, self-contained fact, '
      'term, rule or idea (usually 3-12; more only for dense material, at '
      'most $maxDrafts). Skip titles, page numbers, filler and anything not '
      'worth remembering.\n'
      'Return JSON only: {"notes": [{"front": "...", "back": "...", '
      '"type": "fact|concept|command|code|question", "category": "..."}]}\n'
      '- "front": a short cue to recall from: a term, a question, or a '
      'command (max ~15 words).\n'
      '- "back": the answer or explanation, 1-3 sentences (for code, the '
      'code itself).\n'
      '- "category": one short subject label (1-2 words), the same for '
      'related notes.\n'
      '- Write in the same language as the material.\n'
      'If there is nothing worth studying, return {"notes": []}.';

  @override
  Future<List<NoteDraft>> notesFromImage(Attachment image) async {
    final raw = await complete(_notesRules('the attached photo'),
        json: true, attachments: [image]);
    return parseDrafts(raw);
  }

  @override
  Future<List<NoteDraft>> notesFromText(String text) async {
    final clipped = text.length > 12000 ? text.substring(0, 12000) : text;
    final raw = await complete(
        '${_notesRules('the text below')}\n\nText:\n$clipped',
        json: true);
    return parseDrafts(raw);
  }

  /// Parses proposed notes, dropping empty and repeated ones.
  static List<NoteDraft> parseDrafts(String raw) {
    final decoded = decodeJsonLoose(raw);
    final list = decoded is Map ? decoded['notes'] : decoded;
    if (list is! List) {
      throw const LlmException(
          LlmErrorKind.badResponse, 'The AI returned no notes');
    }
    final seen = <String>{};
    final out = <NoteDraft>[];
    for (final n in list) {
      if (n is! Map) continue;
      final front = '${n['front'] ?? ''}'.trim();
      if (front.isEmpty || !seen.add(front.toLowerCase())) continue;
      final back = '${n['back'] ?? ''}'.trim();
      final category = '${n['category'] ?? ''}'.trim();
      out.add(NoteDraft(
        front: front,
        back: back.isEmpty ? null : back,
        type: KnowledgeType.values.firstWhere(
            (t) => t.name == '${n['type']}'.trim().toLowerCase(),
            orElse: () => KnowledgeType.concept),
        category: category.isEmpty ? null : category,
      ));
      if (out.length == maxDrafts) break;
    }
    return out;
  }

  /// Transcribes by sending the audio with the prompt; only backends whose
  /// models hear audio (see [canTranscribe]) should be asked.
  @override
  Future<String> transcribe(Attachment audio) async {
    final text = await complete(
      'Transcribe this voice recording exactly as spoken, in the language '
      'spoken, with normal punctuation. Reply with the transcript only. If '
      'nothing is said, reply with an empty line.',
      attachments: [audio],
    );
    return text.trim();
  }

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
    final quizzes = await generateQuizzes([item],
        distractorCount: distractorCount, variantCount: 1);
    final quiz = quizzes[item.id]?.first;
    if (quiz == null) {
      throw const LlmException(
          LlmErrorKind.badResponse, 'The AI returned an unusable quiz');
    }
    return quiz;
  }

  @override
  Future<Map<String, List<McQuiz>>> generateQuizzes(
    List<KnowledgeItem> items, {
    int distractorCount = 3,
    int variantCount = 3,
  }) async {
    if (items.isEmpty) return const {};
    final raw = await complete(
        quizBatchPrompt(items, distractorCount, variantCount: variantCount),
        json: true);
    return parseQuizBatch(raw, items, distractorCount: distractorCount);
  }

  /// One prompt for many notes. Notes are numbered 1..n instead of sending
  /// their UUIDs, which saves tokens and is harder for the model to garble.
  static String quizBatchPrompt(
    List<KnowledgeItem> items,
    int distractorCount, {
    int variantCount = 3,
  }) {
    final notes = StringBuffer();
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      notes.writeln('[${i + 1}] (${item.type.label.toLowerCase()}) '
          '${_clip(item.front)}');
      if (item.hasAnswer) notes.writeln('    Detail: ${_clip(item.back!)}');
      if (item.highlights.isNotEmpty) {
        notes.writeln('    Key ideas the student highlighted: '
            '${item.highlights.map(_clip).join(' | ')}');
      }
      final existing = [
        for (final v in item.quizVariants) v.question ?? item.front,
      ];
      if (existing.isNotEmpty) {
        notes.writeln('    It already has these questions; write different '
            'ones: ${existing.map(_clip).join(' | ')}');
      }
      if (item.badQuestions.isNotEmpty) {
        notes.writeln('    The student flagged these earlier attempts as bad; '
            'do not repeat them: ${item.badQuestions.map(_clip).join(' | ')}');
      }
    }
    final variantRule = variantCount <= 1
        ? '- "variants": exactly 1 item.\n'
        : '- "variants": $variantCount items that each test the note from a '
            'DIFFERENT angle (e.g. the term from its definition, the '
            'definition from the term, a key detail, a consequence or use), '
            'so the student can\'t just memorize one wording. For a note that '
            'is already a question, give 1 variant, unless it already has '
            'questions listed — then rephrase or approach it differently.\n';
    return 'You write quiz items for a spaced-repetition study app. '
        'For EACH note below, write multiple-choice questions.\n'
        'Return JSON only, in this shape:\n'
        '{"items": [{"id": 1, "variants": [{"question": "...", "answer": "...", '
        '"distractors": ["...", "..."]}]}]}\n'
        'Rules:\n'
        '- "id": the note number in square brackets.\n'
        '$variantRule'
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
        '- When a note lists key ideas the student highlighted, build its '
        'questions around them: cover different highlighted ideas first, and '
        'test what each means, does or relates to in the note — a highlighted '
        'term can be the answer, but don\'t just ask to repeat it.\n'
        '- Write each item in the same language as its note.\n\n'
        'Notes:\n$notes';
  }

  /// Parses a batch reply into quizzes keyed by note id. Tolerates code fences,
  /// a bare top-level list, string ids, and items without a "variants" list
  /// (one flat question). Malformed entries are dropped.
  static Map<String, List<McQuiz>> parseQuizBatch(
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
    } else if (decoded is Map &&
        (decoded['question'] != null || decoded['variants'] != null) &&
        items.length == 1) {
      entries = [
        {...decoded, 'id': 1},
      ];
    } else {
      throw const LlmException(
          LlmErrorKind.badResponse, 'The AI returned an unusable quiz');
    }

    McQuiz? parseOne(Object? v) {
      if (v is! Map) return null;
      final question = '${v['question'] ?? ''}'.trim();
      final answer = '${v['answer'] ?? ''}'.trim();
      final rawDistractors = v['distractors'];
      if (question.isEmpty || answer.isEmpty || rawDistractors is! List) {
        return null;
      }
      final distractors = rawDistractors
          .map((e) => '$e'.trim())
          .where((e) => e.isNotEmpty && e != answer)
          .take(distractorCount)
          .toList();
      return McQuiz(question: question, answer: answer, distractors: distractors);
    }

    final result = <String, List<McQuiz>>{};
    for (final entry in entries) {
      if (entry is! Map) continue;
      final number = int.tryParse('${entry['id']}'.trim());
      if (number == null || number < 1 || number > items.length) continue;
      final variants = entry['variants'] is List
          ? [for (final v in entry['variants'] as List) ?parseOne(v)]
          : [?parseOne(entry)];
      if (variants.isNotEmpty) result[items[number - 1].id] = variants;
    }
    return result;
  }

  @override
  Future<LlmGrade> gradeAnswer(KnowledgeItem item, String answer) async {
    final raw = await complete(
      'Grade a student\'s answer to a flashcard, written from memory. Judge '
      'the meaning, not the wording (ignore typos, synonyms and language).\n'
      '- "correct": it has the key idea of the expected answer.\n'
      '- "partial": it has part of the key idea but misses or garbles '
      'something important.\n'
      '- "wrong": it misses the key idea or contradicts it.\n'
      'Return JSON: {"verdict": "correct"|"partial"|"wrong", "feedback": '
      '"one short sentence; for partial or wrong, say what was missing"}. '
      'Write the feedback in the language of the question.\n\n'
      'Question: ${item.practicePrompt}\n'
      'Expected answer: ${_clip(item.activeQuiz?.answer ?? item.back ?? '')}\n'
      'Student answer: $answer',
      json: true,
    );
    return _parseGrade(raw);
  }

  @override
  Future<String> explainMistake(KnowledgeItem item,
      {required String question,
      required String answer,
      String? studentAnswer}) async {
    final text = await complete(
      'A student got a flashcard wrong. Help them remember it next time. '
      'In at most 2 short sentences explain why the correct answer is right'
      '${studentAnswer == null ? '' : ' and why their answer is not'}. Then, '
      'on a new line starting with "💡 ", give one short memory trick '
      '(a mnemonic, an image or a link to something familiar). Write in the '
      'language of the question. No preamble, no markdown.\n\n'
      'Question: ${_clip(question)}\n'
      'Correct answer: ${_clip(answer)}\n'
      '${studentAnswer == null ? '' : 'Student answered: ${_clip(studentAnswer)}\n'}'
      '${item.hasAnswer ? 'Note: ${_clip(item.back!)}' : ''}',
    );
    return text.trim();
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
    final verdict =
        decoded is Map ? '${decoded['verdict'] ?? ''}'.trim().toLowerCase() : '';
    if (decoded is Map && const ['correct', 'partial', 'wrong'].contains(verdict)) {
      return LlmGrade(
        correct: verdict != 'wrong',
        partial: verdict == 'partial',
        feedback: decoded['feedback'] as String?,
      );
    }
    if (decoded is Map && decoded['correct'] is bool) {
      return LlmGrade(
        correct: decoded['correct'] as bool,
        feedback: decoded['feedback'] as String?,
      );
    }
    throw const LlmException(
        LlmErrorKind.badResponse, 'The AI returned an unusable grade');
  }

  /// Most key ideas suggested at once: a few strong marks beat many weak ones.
  static const int maxSuggestedHighlights = 4;

  @override
  Future<List<String>> suggestHighlights(KnowledgeItem item) async {
    final raw = await complete(
      'A student is studying this note. Pick the 2-$maxSuggestedHighlights most '
      'important key terms or short key phrases (1-4 words each) worth '
      'highlighting for revision: the ideas an exam would ask about, not '
      'filler words. Copy each one EXACTLY as it appears in the note text.\n'
      'Return JSON: {"highlights": ["...", "..."]}.\n\n'
      'Note: ${_clip(item.front)}'
      '${item.hasAnswer ? '\n${_clip(item.back!)}' : ''}',
      json: true,
    );
    final decoded = decodeJsonLoose(raw);
    final list = decoded is Map ? decoded['highlights'] : decoded;
    if (list is! List) {
      throw const LlmException(
          LlmErrorKind.badResponse, 'The AI returned no key ideas');
    }
    return parseHighlights(item, [for (final h in list) '$h']);
  }

  /// Most notes sent in one "sort into topics" request.
  static const int maxNotesToSort = 150;

  @override
  Future<Map<String, String>> suggestTopics(
      String category, List<KnowledgeItem> notes) async {
    final batch = notes.take(maxNotesToSort).toList();
    final existing = {for (final n in batch) if (n.topic != null) n.topic!};
    final list = StringBuffer();
    for (var i = 0; i < batch.length; i++) {
      final n = batch[i];
      final back = n.back == null ? '' : ' — ${_clip(n.back!.replaceAll('\n', ' '))}';
      list.writeln('${i + 1}. ${_clip(n.front.replaceAll('\n', ' '))}$back');
    }
    // Plain lines rather than JSON: with many notes, some models (and
    // Groq's strict JSON check) trip over long JSON lists.
    final raw = await complete(
      'A student\'s course "$category" has the numbered notes below. Group them '
      'into 3-8 topics (sections of the course a student would study separately). '
      'Topic names: 1-3 words, Title Case, in the language of the notes.'
      '${existing.isEmpty ? '' : ' Reuse these existing topic names where they fit: ${existing.join(', ')}.'}'
      ' Every note gets exactly one topic.\n'
      'Reply with one line per topic and nothing else, in this form:\n'
      'Topic name: 1, 4, 7\n\n'
      'Notes:\n$list',
    );
    return parseTopics(batch, raw);
  }

  /// Note id → topic from the AI's reply: "Topic: 1, 4, 7" lines (or the
  /// same as JSON). Note numbers are 1-based; notes it left out or numbers
  /// it made up are skipped.
  static Map<String, String> parseTopics(List<KnowledgeItem> notes, String raw) {
    final groups = <(String, List<Object?>)>[];
    final decoded = decodeJsonLoose(raw);
    final topics = decoded is Map ? decoded['topics'] : decoded;
    if (topics is List) {
      for (final t in topics) {
        if (t is Map && t['notes'] is List) {
          groups.add(('${t['name'] ?? ''}', t['notes'] as List));
        }
      }
    } else {
      final line = RegExp(r'^[\s\-*#\d.)]*\**(.+?)\**\s*[:：\-–—]\s*([\d,\s]+)\.?\s*$');
      for (final l in raw.split('\n')) {
        final m = line.firstMatch(l.trim());
        if (m == null) continue;
        groups.add((m.group(1)!, m.group(2)!.split(RegExp(r'[,\s]+'))));
      }
    }
    final out = <String, String>{};
    for (final (rawName, members) in groups) {
      final name = rawName.trim().replaceAll(RegExp(r'^["“]|["”]$'), '');
      if (name.isEmpty) continue;
      for (final m in members) {
        final i = (m is num ? m.toInt() : int.tryParse('$m'.trim()) ?? 0) - 1;
        if (i >= 0 && i < notes.length) out.putIfAbsent(notes[i].id, () => name);
      }
    }
    if (out.isEmpty) {
      throw const LlmException(LlmErrorKind.badResponse, 'The AI returned no topics');
    }
    return out;
  }

  /// Keeps the suggestions that really occur in the note (models sometimes
  /// paraphrase), trimmed, without repeats, at most [maxSuggestedHighlights].
  static List<String> parseHighlights(KnowledgeItem item, List<String> raw) {
    final text = '${item.front}\n${item.back ?? ''}'.toLowerCase();
    final out = <String>[];
    for (final h in raw) {
      final phrase = h.trim().replaceAll(RegExp(r"""^["'«“]+|["'»”.,;:]+$"""), '');
      if (phrase.isEmpty || !text.contains(phrase.toLowerCase())) continue;
      if (out.any((o) => o.toLowerCase() == phrase.toLowerCase())) continue;
      out.add(phrase);
    }
    return out.take(maxSuggestedHighlights).toList();
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
