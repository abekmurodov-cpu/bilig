import 'dart:convert';

/// The kind of thing the user captured. Used for display and, later, to tell
/// the AI layer how to expand a bare capture and what review formats fit.
enum KnowledgeType {
  fact,
  concept,
  command,
  code,
  question;

  String get label => switch (this) {
        KnowledgeType.fact => 'Fact',
        KnowledgeType.concept => 'Concept',
        KnowledgeType.command => 'Command',
        KnowledgeType.code => 'Code',
        KnowledgeType.question => 'Question',
      };
}

/// One AI-written practice question for a note: a [question] (null for notes
/// that are already a question — their own wording is used), its short
/// [answer], and wrong options.
class QuizVariant {
  const QuizVariant({this.question, required this.answer, required this.distractors});

  final String? question;
  final String answer;
  final List<String> distractors;

  Map<String, dynamic> toMap() =>
      {'question': question, 'answer': answer, 'distractors': distractors};

  static QuizVariant? fromMap(Object? map) {
    if (map is! Map) return null;
    final answer = map['answer'];
    final distractors = map['distractors'];
    if (answer is! String || distractors is! List) return null;
    return QuizVariant(
      question: map['question'] as String?,
      answer: answer,
      distractors: [for (final d in distractors) '$d'],
    );
  }
}

/// A single unit of knowledge the user wants to keep alive.
///
/// [front] is what the app shows first when quizzing (a question, a concept
/// name, a command). [back] is the answer/details — it may be null when the
/// user only jotted a fragment and hasn't filled it in (later the AI layer can
/// populate it). Scheduling fields follow the SM-2 spaced-repetition algorithm.
class KnowledgeItem {
  KnowledgeItem({
    required this.id,
    required this.front,
    this.back,
    required this.type,
    this.category,
    required this.createdAt,
    required this.dueDate,
    this.lastReviewedAt,
    this.repetitions = 0,
    this.easeFactor = 2.5,
    this.intervalDays = 0,
    DateTime? updatedAt,
    this.lastCorrect,
    this.lapses = 0,
    this.hasImage = false,
    this.quizQuestion,
    this.mcAnswer,
    this.mcDistractors = const [],
    this.fillBlankTemplate,
    this.fillBlankAnswers = const [],
    this.reorderSegments = const [],
    this.extraQuizzes = const [],
    this.badQuestions = const [],
  }) : updatedAt = updatedAt ?? createdAt;

  final String id;
  final String front;
  final String? back;
  final KnowledgeType type;
  final String? category;
  final DateTime createdAt;

  // --- Spaced-repetition state (SM-2) ---
  final DateTime dueDate;
  final DateTime? lastReviewedAt;
  final int repetitions;
  final double easeFactor;
  final int intervalDays;

  // --- Sync + review-history state ---
  /// Last local mutation time; drives last-write-wins during Telegram sync.
  final DateTime updatedAt;

  /// Whether the most recent recall was correct. Colors the tree-view leaf:
  /// true → green, false → red, null (never reviewed) → neutral/amber.
  final bool? lastCorrect;

  /// How many times recall has lapsed (graded `again`). Kept for the tree
  /// color rule and future difficulty surfacing.
  final int lapses;

  /// Whether an image is attached (bytes live in the [ImageStore] keyed by id).
  final bool hasImage;

  // --- Pre-generated quiz (concise, cached for practice) ---
  /// A question generated from the note so practice asks something answerable
  /// instead of echoing a bare fact. E.g. a fact "Water boils at 100°C" becomes
  /// "At what temperature does water boil?". Null for notes whose [front] is
  /// already a usable prompt (then practice uses [front]).
  final String? quizQuestion;

  /// Short correct answer used as the right option in multiple-choice practice
  /// (a 1–2 sentence summary, not the full [back] detail).
  final String? mcAnswer;

  /// Three short plausible-but-wrong options paired with [mcAnswer].
  final List<String> mcDistractors;

  /// More questions about the same note, so practice doesn't repeat one
  /// wording. [quizQuestion]/[mcAnswer]/[mcDistractors] stay the first one
  /// (that's what older app versions and synced copies understand).
  final List<QuizVariant> extraQuizzes;

  /// Questions the student flagged as bad, so the AI doesn't write them again.
  final List<String> badQuestions;

  /// Most flagged questions remembered per note.
  static const int maxBadQuestions = 5;

  // --- Pre-generated code drills (code notes only; no LLM at practice) ---
  /// The code with blanks replaced by «0», «1», … placeholders, paired with
  /// [fillBlankAnswers]. Used by the fill-in-the-blank coding drill.
  final String? fillBlankTemplate;

  /// The removed tokens, in placeholder order, for the fill-in-the-blank drill.
  final List<String> fillBlankAnswers;

  /// The code split into logical chunks in their correct order. The reorder
  /// drill shuffles these and asks the user to restore the order.
  final List<String> reorderSegments;

  bool get hasAnswer => back != null && back!.trim().isNotEmpty;

  /// Every cached question, the stored first one included.
  List<QuizVariant> get quizVariants => [
        if (hasMcOptions)
          QuizVariant(question: quizQuestion, answer: mcAnswer!, distractors: mcDistractors),
        ...extraQuizzes,
      ];

  /// Index of the question practice asks now. It moves on with every review
  /// (a correct one raises [repetitions], a lapse raises [lapses]), so the
  /// note is asked a different way next time.
  int get _activeIndex {
    final n = quizVariants.length;
    return n == 0 ? 0 : (repetitions + lapses) % n;
  }

  /// The question practice asks now, or null when none is cached.
  QuizVariant? get activeQuiz {
    final variants = quizVariants;
    return variants.isEmpty ? null : variants[_activeIndex];
  }

  /// What practice shows as the prompt: the active question if it rewords the
  /// note, otherwise the raw [front].
  String get practicePrompt {
    final q = activeQuiz?.question;
    return (q != null && q.trim().isNotEmpty) ? q : front;
  }

  /// This note without its active question (flagged as bad), remembering the
  /// wording so it isn't generated again. When it was the last question the
  /// note needs a new quiz.
  KnowledgeItem dropActiveQuiz() {
    final variants = quizVariants;
    if (variants.isEmpty) return this;
    final dropped = variants.removeAt(_activeIndex);
    final bad = [...badQuestions, dropped.question ?? dropped.answer];
    final first = variants.isEmpty ? null : variants.first;
    return KnowledgeItem.fromMap({
      ...toMap(),
      'quizQuestion': first?.question,
      'mcAnswer': first?.answer,
      'mcDistractors': first?.distractors ?? const <String>[],
      'extraQuizzes': [for (final v in variants.skip(1)) v.toMap()],
      'badQuestions': bad.sublist(
          bad.length > maxBadQuestions ? bad.length - maxBadQuestions : 0),
    });
  }

  /// True once a full multiple-choice set (correct + ≥1 distractor) is cached.
  bool get hasMcOptions =>
      mcAnswer != null && mcAnswer!.trim().isNotEmpty && mcDistractors.isNotEmpty;

  /// True when practice still lacks a cached AI quiz for this note: no option
  /// set yet, or a content note (anything but a question) without its reworded
  /// [quizQuestion].
  bool get needsQuiz =>
      front.trim().isNotEmpty &&
      (!hasMcOptions ||
          (type != KnowledgeType.question &&
              (quizQuestion == null || quizQuestion!.trim().isEmpty)));

  /// This note with its cached AI quiz dropped, so it gets regenerated. Used
  /// when the note's content is edited and the old quiz no longer matches.
  KnowledgeItem withoutQuiz() => KnowledgeItem.fromMap({
        ...toMap(),
        'quizQuestion': null,
        'mcAnswer': null,
        'mcDistractors': const <String>[],
        'extraQuizzes': const <Object>[],
        'badQuestions': const <String>[],
      });

  /// True once at least one code drill has been pre-generated for this note.
  bool get hasCodeDrills =>
      fillBlankAnswers.isNotEmpty || reorderSegments.length > 1;

  /// Weak point: recently missed, or lapsed repeatedly. Drives the "Weak points"
  /// practice scope and the red tree leaves.
  bool get isWeak => lastCorrect == false || lapses >= 2;

  bool isDue(DateTime now) => !dueDate.isAfter(now);

  KnowledgeItem copyWith({
    String? front,
    String? back,
    KnowledgeType? type,
    String? category,
    DateTime? dueDate,
    DateTime? lastReviewedAt,
    int? repetitions,
    double? easeFactor,
    int? intervalDays,
    DateTime? updatedAt,
    bool? lastCorrect,
    int? lapses,
    bool? hasImage,
    String? quizQuestion,
    String? mcAnswer,
    List<String>? mcDistractors,
    String? fillBlankTemplate,
    List<String>? fillBlankAnswers,
    List<String>? reorderSegments,
    List<QuizVariant>? extraQuizzes,
    List<String>? badQuestions,
  }) {
    return KnowledgeItem(
      id: id,
      front: front ?? this.front,
      back: back ?? this.back,
      type: type ?? this.type,
      category: category ?? this.category,
      createdAt: createdAt,
      dueDate: dueDate ?? this.dueDate,
      lastReviewedAt: lastReviewedAt ?? this.lastReviewedAt,
      repetitions: repetitions ?? this.repetitions,
      easeFactor: easeFactor ?? this.easeFactor,
      intervalDays: intervalDays ?? this.intervalDays,
      updatedAt: updatedAt ?? this.updatedAt,
      lastCorrect: lastCorrect ?? this.lastCorrect,
      lapses: lapses ?? this.lapses,
      hasImage: hasImage ?? this.hasImage,
      quizQuestion: quizQuestion ?? this.quizQuestion,
      mcAnswer: mcAnswer ?? this.mcAnswer,
      mcDistractors: mcDistractors ?? this.mcDistractors,
      fillBlankTemplate: fillBlankTemplate ?? this.fillBlankTemplate,
      fillBlankAnswers: fillBlankAnswers ?? this.fillBlankAnswers,
      reorderSegments: reorderSegments ?? this.reorderSegments,
      extraQuizzes: extraQuizzes ?? this.extraQuizzes,
      badQuestions: badQuestions ?? this.badQuestions,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'front': front,
        'back': back,
        'type': type.name,
        'category': category,
        'createdAt': createdAt.toIso8601String(),
        'dueDate': dueDate.toIso8601String(),
        'lastReviewedAt': lastReviewedAt?.toIso8601String(),
        'repetitions': repetitions,
        'easeFactor': easeFactor,
        'intervalDays': intervalDays,
        'updatedAt': updatedAt.toIso8601String(),
        'lastCorrect': lastCorrect,
        'lapses': lapses,
        'hasImage': hasImage,
        'quizQuestion': quizQuestion,
        'mcAnswer': mcAnswer,
        'mcDistractors': mcDistractors,
        'fillBlankTemplate': fillBlankTemplate,
        'fillBlankAnswers': fillBlankAnswers,
        'reorderSegments': reorderSegments,
        'extraQuizzes': [for (final q in extraQuizzes) q.toMap()],
        'badQuestions': badQuestions,
      };

  factory KnowledgeItem.fromMap(Map<String, dynamic> map) => KnowledgeItem(
        id: map['id'] as String,
        front: map['front'] as String,
        back: map['back'] as String?,
        type: KnowledgeType.values.firstWhere(
          (t) => t.name == map['type'],
          orElse: () => KnowledgeType.fact,
        ),
        category: map['category'] as String?,
        createdAt: DateTime.parse(map['createdAt'] as String),
        dueDate: DateTime.parse(map['dueDate'] as String),
        lastReviewedAt: map['lastReviewedAt'] == null
            ? null
            : DateTime.parse(map['lastReviewedAt'] as String),
        repetitions: (map['repetitions'] as num?)?.toInt() ?? 0,
        easeFactor: (map['easeFactor'] as num?)?.toDouble() ?? 2.5,
        intervalDays: (map['intervalDays'] as num?)?.toInt() ?? 0,
        updatedAt: map['updatedAt'] == null
            ? DateTime.parse(map['createdAt'] as String)
            : DateTime.parse(map['updatedAt'] as String),
        lastCorrect: map['lastCorrect'] as bool?,
        lapses: (map['lapses'] as num?)?.toInt() ?? 0,
        hasImage: map['hasImage'] as bool? ?? false,
        quizQuestion: map['quizQuestion'] as String?,
        mcAnswer: map['mcAnswer'] as String?,
        mcDistractors:
            (map['mcDistractors'] as List?)?.map((e) => e.toString()).toList() ??
                const [],
        fillBlankTemplate: map['fillBlankTemplate'] as String?,
        fillBlankAnswers:
            (map['fillBlankAnswers'] as List?)?.map((e) => e.toString()).toList() ??
                const [],
        reorderSegments:
            (map['reorderSegments'] as List?)?.map((e) => e.toString()).toList() ??
                const [],
        extraQuizzes: [
          for (final q in (map['extraQuizzes'] as List?) ?? const [])
            ?QuizVariant.fromMap(q),
        ],
        badQuestions:
            (map['badQuestions'] as List?)?.map((e) => e.toString()).toList() ??
                const [],
      );

  String toJson() => jsonEncode(toMap());

  factory KnowledgeItem.fromJson(String source) =>
      KnowledgeItem.fromMap(jsonDecode(source) as Map<String, dynamic>);
}
