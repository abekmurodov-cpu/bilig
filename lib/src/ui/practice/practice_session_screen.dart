import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_strings.dart';
import '../../llm/llm_provider.dart';
import '../../llm/llm_providers.dart';
import '../../llm/quiz_prep.dart';
import '../../models/knowledge_item.dart';
import '../../practice/answer_matching.dart';
import '../../practice/cloze.dart';
import '../../practice/code_drills.dart';
import '../../practice/practice_models.dart';
import '../../providers/knowledge_providers.dart';
import '../../scheduler/spaced_repetition.dart';
import '../widgets/code_field.dart';
import '../widgets/code_highlighter.dart';
import '../widgets/flip_card.dart';
import '../widgets/markable_text.dart';
import '../widgets/note_image.dart';

const TextStyle _monoStyle = TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.4);

/// Runs a configured practice session over [queue]. Each answered card feeds the
/// SM-2 scheduler (correct → good, wrong → again), which updates the note's
/// `lastCorrect` and therefore its tree-view leaf color.
class PracticeSessionScreen extends ConsumerStatefulWidget {
  const PracticeSessionScreen({
    super.key,
    required this.config,
    required this.queue,
  });

  final PracticeConfig config;
  final List<KnowledgeItem> queue;

  @override
  ConsumerState<PracticeSessionScreen> createState() =>
      _PracticeSessionScreenState();
}

class _PracticeSessionScreenState
    extends ConsumerState<PracticeSessionScreen> {
  // Local, mutable copy so generated answers/quizzes update the current card.
  late final List<KnowledgeItem> _queue = List.of(widget.queue);
  int _index = 0;
  int _correctCount = 0;

  // Prep (code drills, option set) in flight for the current card.
  bool _preparing = false;
  // Waiting for the first batch of AI questions before the first card.
  bool _warmingUp = false;
  // The current card has no usable quiz for its mode, so it is shown as a
  // reveal-and-grade-yourself card instead of a broken question.
  bool _selfCheck = false;
  // Flashcard (and self-check) state.
  bool _revealed = false;
  // Furthest card reached. Cards before it were graded or skipped and are
  // view-only when revisited with "Previous".
  int _frontier = 0;
  final Map<int, ReviewGrade> _flashGrades = {};
  // Multiple-choice state.
  List<String>? _options;
  String? _correctOption;
  String? _chosen;
  // Type-the-answer state.
  final _answerController = TextEditingController();
  // Write-the-code editor (syntax-highlighted).
  final _codeController = CodeEditingController();
  // Fill-in-the-blank: one controller per blank.
  final List<TextEditingController> _blankControllers = [];
  // Reorder: current arrangement as indices into the note's reorderSegments.
  List<int> _reorderCurrent = [];
  // Shared "answered" result for objective modes.
  bool? _wasCorrect;
  String? _feedback;

  /// The AI judged a typed answer partly right (counted, but as "hard").
  bool _partial = false;

  /// The AI's "why was I wrong?" explanation for the card on screen.
  String? _why;
  bool _explaining = false;
  bool _grading = false;

  /// How long practice waits for AI questions before starting anyway.
  static const _warmUpLimit = Duration(seconds: 25);

  bool get _usesQuiz => switch (widget.config.method) {
        PracticeMethod.multipleChoice ||
        PracticeMethod.flashcard ||
        PracticeMethod.typeAnswer =>
          true,
        _ => false,
      };

  @override
  void initState() {
    super.initState();
    final prep = ref.read(quizPrepProvider);
    final batch = ref.read(quizPrepConfigProvider).batchSize;
    _warmingUp = _usesQuiz &&
        ref.read(llmProvider) != null &&
        !prep.isPaused &&
        _queue.take(batch).any((i) => i.needsQuiz);
    if (_warmingUp) {
      _warmUp();
    } else {
      _prepareItem();
    }
  }

  /// Asks the background generator to do this session's first cards first
  /// (one request), then starts. Later cards fill in while the user works.
  Future<void> _warmUp() async {
    try {
      await ref
          .read(quizPrepProvider.notifier)
          .prepare(_queue)
          .timeout(_warmUpLimit);
    } on TimeoutException {
      // Start anyway; cards without a quiz fall back to self-check.
    }
    if (!mounted || !_warmingUp) return; // the user already tapped "Start now"
    _startAfterWarmUp();
  }

  void _startAfterWarmUp() {
    setState(() => _warmingUp = false);
    _prepareItem();
  }

  @override
  void dispose() {
    _answerController.dispose();
    _codeController.dispose();
    for (final c in _blankControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _disposeBlankControllers() {
    for (final c in _blankControllers) {
      c.dispose();
    }
    _blankControllers.clear();
  }

  KnowledgeItem get _item => _queue[_index];

  /// A fill-in-the-blank question made from the note's highlights, used
  /// when the note has no AI or own question yet (or no AI at all).
  QuizVariant? _cloze;

  /// The question this card asks: the note's active question, else a
  /// fill-in-the-blank from its highlights.
  QuizVariant? get _quiz => _item.activeQuiz ?? _cloze;

  bool get _isCloze => _item.activeQuiz == null && _cloze != null;

  /// What the card shows as the prompt.
  String get _prompt {
    final q = _quiz?.question;
    return (q != null && q.trim().isNotEmpty) ? q : _item.front;
  }

  void _setItem(KnowledgeItem updated) {
    if (!mounted) return;
    setState(() => _queue[_index] = updated);
  }

  /// Prepares the current card from the note's cached quiz (generated ahead of
  /// time by [QuizPrep] — practice itself never calls the AI for questions),
  /// then builds the multiple-choice option set.
  Future<void> _prepareItem() async {
    _syncFromStore();
    _cloze = _usesQuiz && _item.activeQuiz == null
        ? clozeQuiz(_item, ref.read(notesSortedProvider))
        : null;
    setState(() {
      _preparing = true;
      _selfCheck = false;
      _options = null;
      _correctOption = null;
    });
    switch (widget.config.method) {
      case PracticeMethod.multipleChoice:
        _buildOptions();
      case PracticeMethod.flashcard:
        break;
      case PracticeMethod.typeAnswer:
        _selfCheck = !_canReveal;
      case PracticeMethod.fillBlank:
      case PracticeMethod.reorder:
        await _ensureDrills();
        _setupCoding();
      case PracticeMethod.codeSnippet:
        break; // graded on submit against the reference code
    }
    if (mounted) setState(() => _preparing = false);
  }

  /// Generates + caches code drills (deterministically, no LLM) from the note's
  /// code, which lives in the answer/details field (back). Self-heals notes
  /// whose cached drills were built from the wrong field.
  Future<void> _ensureDrills() async {
    final drills = generateCodeDrills(_item.back ?? '');
    final upToDate = listEquals(_item.reorderSegments, drills.reorderSegments) &&
        listEquals(_item.fillBlankAnswers, drills.fillBlankAnswers) &&
        _item.fillBlankTemplate == drills.fillBlankTemplate;
    if (upToDate) return;
    final updated = _item.copyWith(
      fillBlankTemplate: drills.fillBlankTemplate,
      fillBlankAnswers: drills.fillBlankAnswers,
      reorderSegments: drills.reorderSegments,
    );
    _setItem(updated);
    await ref.read(knowledgeListProvider.notifier).persist(updated);
  }

  /// Prepares per-blank controllers or a shuffled reorder list for the current
  /// coding drill.
  void _setupCoding() {
    _disposeBlankControllers();
    _blankControllers.addAll(
      List.generate(_item.fillBlankAnswers.length, (_) => TextEditingController()),
    );
    _reorderCurrent = _shuffledOrder(_item.reorderSegments.length);
  }

  /// A shuffled index order [0..n) that differs from the sorted answer order.
  List<int> _shuffledOrder(int n) {
    final identity = List.generate(n, (i) => i);
    if (n < 2) return identity;
    final order = List.of(identity)..shuffle();
    return listEquals(order, identity) ? order.reversed.toList() : order;
  }

  /// Picks up the latest stored copy of the current note: the background
  /// generator may have cached its quiz since the session started. Cards
  /// already answered keep the copy they were shown with, so revisiting one
  /// shows the same question (the active question rotates after a grade).
  void _syncFromStore() {
    if (_index < _frontier) return;
    final items = ref.read(knowledgeListProvider).asData?.value ?? const [];
    for (final fresh in items) {
      if (fresh.id == _item.id) {
        _queue[_index] = fresh;
        return;
      }
    }
  }

  /// Builds [_options]/[_correctOption] from the cached AI quiz. Without one,
  /// options are borrowed from other notes only when that can't look silly;
  /// otherwise the card becomes a self-check card.
  void _buildOptions() {
    final String correct;
    final List<String> distractors;
    final quiz = _quiz;
    // A fill-in-the-blank needs two wrong options to be a fair choice.
    if (quiz != null && quiz.distractors.length >= (_isCloze ? 2 : 1)) {
      correct = quiz.answer;
      distractors = quiz.distractors;
    } else if (quiz != null) {
      // The student's own question without wrong options, or a
      // fill-in-the-blank without enough of them.
      setState(() => _selfCheck = true);
      return;
    } else {
      final local = _localDistractors(_item);
      if (local.length < 2) {
        setState(() => _selfCheck = true);
        return;
      }
      correct = _item.back!.trim();
      distractors = local;
    }
    final options = <String>{correct, ...distractors}.toList()..shuffle();
    setState(() {
      _correctOption = correct;
      _options = options;
    });
  }

  /// Longest answer that still reads as a multiple-choice option.
  static const _maxLocalOptionLength = 120;

  /// Wrong options borrowed from other notes' answers. Only for notes whose
  /// prompt is a real cue (a question, a concept name, a command) and only from
  /// short answers of the same kind, preferring the same category — so options
  /// are comparable instead of a random mix of facts and code.
  List<String> _localDistractors(KnowledgeItem item) {
    const promptTypes = {
      KnowledgeType.question,
      KnowledgeType.concept,
      KnowledgeType.command,
    };
    bool short(KnowledgeItem i) =>
        i.hasAnswer && i.back!.trim().length <= _maxLocalOptionLength;
    if (!promptTypes.contains(item.type) || !short(item)) return const [];
    final answer = normalizeAnswer(item.back!);
    final pool = ref
        .read(notesSortedProvider)
        .where((i) =>
            i.id != item.id &&
            i.type == item.type &&
            short(i) &&
            similarity(normalizeAnswer(i.back!), answer) < 0.8)
        .toList();
    pool.sort((a, b) {
      final aSame = a.category == item.category ? 0 : 1;
      final bSame = b.category == item.category ? 0 : 1;
      return aSame.compareTo(bSame);
    });
    return {for (final i in pool) i.back!.trim()}.take(3).toList();
  }

  /// The answer to reveal / check for the current note. When the prompt is a
  /// reworded AI question, the matching answer is that question's concise
  /// answer; otherwise prefer the note's own detailed [back].
  String? get _revealAnswer {
    final quiz = _quiz;
    final reworded = quiz?.question?.trim().isNotEmpty ?? false;
    return reworded ? quiz!.answer : (_item.back ?? quiz?.answer);
  }

  /// Whether the card on screen shows an AI question the student can flag.
  bool get _canFlag =>
      !_warmingUp &&
      !_selfCheck &&
      _usesQuiz &&
      _index < _queue.length &&
      _index >= _frontier &&
      _item.activeQuiz != null &&
      !_item.activeQuiz!.manual;

  /// "Bad question": drops the question shown, skips the card, and — if it
  /// was already answered — undoes that grade, since a bad question shouldn't
  /// count. The background generator writes new ones once none are left.
  Future<void> _flagQuestion() async {
    final strings = context.s;
    final messenger = ScaffoldMessenger.of(context);
    final answered = _wasCorrect != null;
    if (_wasCorrect == true) _correctCount--;
    // _item is the copy as shown, from before any grade (grading saves a new
    // copy but doesn't touch the queue), so saving it also undoes the grade.
    await ref
        .read(knowledgeListProvider.notifier)
        .persist(_item.dropActiveQuiz());
    messenger.showSnackBar(SnackBar(
      content: Text(answered
          ? '${strings.badQuestionThanks} ${strings.answerNotCounted}'
          : strings.badQuestionThanks),
    ));
    if (!mounted) return;
    if (widget.config.method == PracticeMethod.flashcard) {
      _goToCard(_index + 1);
    } else {
      _advance();
    }
  }

  bool get _canReveal => _revealAnswer?.trim().isNotEmpty ?? false;

  Future<void> _grade(ReviewGrade grade) async {
    _flashGrades[_index] = grade;
    await ref.read(knowledgeListProvider.notifier).grade(_item, grade);
    if (grade.quality >= 3) _correctCount++;
    _advance();
  }

  /// Flashcard navigation. Moving past the frontier skips the card ungraded.
  void _goToCard(int index) {
    if (!mounted || index < 0) return;
    setState(() {
      _index = index;
      if (index > _frontier) _frontier = index;
      _revealed = false;
    });
    if (_index < _queue.length) _prepareItem();
  }

  Future<void> _submitObjective(bool correct,
      {String? feedback, bool partial = false}) async {
    setState(() {
      _wasCorrect = correct;
      _feedback = feedback;
      _partial = correct && partial;
    });
    // Persist the outcome via the scheduler.
    await ref.read(knowledgeListProvider.notifier).grade(
          _item,
          !correct
              ? ReviewGrade.again
              : (_partial ? ReviewGrade.hard : ReviewGrade.good),
        );
    if (correct) _correctCount++;
  }

  void _advance() {
    if (!mounted) return;
    _disposeBlankControllers();
    setState(() {
      _index++;
      if (_index > _frontier) _frontier = _index;
      _revealed = false;
      _selfCheck = false;
      _chosen = null;
      _options = null;
      _correctOption = null;
      _wasCorrect = null;
      _feedback = null;
      _partial = false;
      _why = null;
      _explaining = false;
      _reorderCurrent = [];
      _answerController.clear();
      _codeController.clear();
    });
    if (_index < _queue.length) _prepareItem();
  }

  @override
  Widget build(BuildContext context) {
    final done = _index >= _queue.length;
    final prep = ref.watch(quizPrepProvider);
    final showPause = !done &&
        !_warmingUp &&
        _usesQuiz &&
        prep.isPaused &&
        ref.watch(llmProvider) != null &&
        _item.needsQuiz &&
        !_isCloze;
    return Scaffold(
      appBar: AppBar(
        title: Text(done
            ? context.s.done
            : '${context.s.methodLabel(widget.config.method)}  ${_index + 1}/${_queue.length}'),
        actions: [
          if (!done && _canFlag)
            IconButton(
              tooltip: context.s.badQuestion,
              icon: const Icon(Icons.thumb_down_alt_outlined),
              onPressed: _flagQuestion,
            ),
        ],
      ),
      body: done
          ? _buildDone()
          : Column(
              children: [
                if (showPause) _PauseBanner(pause: prep.pause!),
                Expanded(child: _buildBody()),
              ],
            ),
    );
  }

  Widget _buildBody() {
    if (_warmingUp) return _buildWarmUp();
    if (_selfCheck) {
      return _buildSelfCheck(
        widget.config.method == PracticeMethod.typeAnswer
            ? context.s.noAnswerToCheck
            : _isCloze
                ? context.s.clozeSelfCheck
                : _item.activeQuiz?.manual ?? false
                    ? context.s.ownQuestionSelfCheck
                    : context.s.noAiQuestion,
      );
    }
    return switch (widget.config.method) {
      PracticeMethod.flashcard => _buildFlashcard(),
      PracticeMethod.multipleChoice => _buildMultipleChoice(),
      PracticeMethod.typeAnswer => _buildTypeAnswer(),
      PracticeMethod.codeSnippet => _buildCodeSnippet(),
      PracticeMethod.fillBlank => _buildFillBlank(),
      PracticeMethod.reorder => _buildReorder(),
    };
  }

  Widget _promptCard(BuildContext context, {Widget? extra}) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.s.noteType(_item.type).toUpperCase(),
                style: theme.textTheme.labelSmall
                    ?.copyWith(letterSpacing: 1.2)),
            const SizedBox(height: 12),
            Text(_prompt, style: theme.textTheme.headlineSmall),
            if (_item.hasImage) ...[
              const SizedBox(height: 12),
              NoteImage(noteId: _item.id),
            ],
            ?extra,
          ],
        ),
      ),
    );
  }

  Widget _buildWarmUp() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(context.s.preparingQuestions,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _startAfterWarmUp,
            child: Text(context.s.startNow),
          ),
        ],
      ),
    );
  }

  /// Again / Hard / Good / Easy. Labels shrink rather than wrap mid-word
  /// (Russian ones are long for a quarter of a phone's width).
  Widget _gradeRow() {
    return Row(
      children: [
        for (final grade in ReviewGrade.values)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6)),
                onPressed: () => _grade(grade),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(context.s.grade(grade), maxLines: 1),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // --- Self-check (no usable quiz for this card) --------------------------
  Widget _buildSelfCheck(String hint) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: _promptCard(
              context,
              extra: _revealed
                  ? Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Divider(),
                          const SizedBox(height: 8),
                          Text(context.s.answerLabel,
                              style: theme.textTheme.labelSmall?.copyWith(
                                  letterSpacing: 1.2,
                                  color: theme.colorScheme.primary)),
                          const SizedBox(height: 8),
                          MarkableText(
                              text: _revealAnswer ?? context.s.noAnswerRecorded,
                              highlights: _item.highlights,
                              style: theme.textTheme.titleMedium),
                        ],
                      ),
                    )
                  : null,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(_revealed ? context.s.howWell : hint,
              textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: _revealed
              ? _gradeRow()
              : SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => setState(() => _revealed = true),
                    child: Text(context.s.showAnswer),
                  ),
                ),
        ),
      ],
    );
  }

  // --- Flashcard (Quizlet-style flip) ------------------------------------
  Widget _buildFlashcard() {
    final theme = Theme.of(context);
    if (_preparing) return const Center(child: CircularProgressIndicator());
    final viewOnly = _index < _frontier;
    final pastGrade = _flashGrades[_index];
    final showGrades = !viewOnly && (_revealed || !_canReveal);
    return Column(
      children: [
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FlipCard(
                      key: ValueKey(_index),
                      onFlip: (back) {
                        if (back && !_revealed) {
                          setState(() => _revealed = true);
                        }
                      },
                      front: _cardFace(
                        context.s.noteType(_item.type).toUpperCase(),
                        _prompt,
                        withImage: _item.hasImage,
                      ),
                      back: _cardFace(
                        context.s.answerLabel,
                        _revealAnswer ?? context.s.noAnswerRecorded,
                        highlights: _item.highlights,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      viewOnly
                          ? (pastGrade == null
                              ? context.s.skippedViewOnly
                              : context.s.ratedViewOnly(pastGrade))
                          : showGrades
                              ? context.s.howWell
                              : context.s.tapToFlip,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: showGrades
              ? _gradeRow()
              : const SizedBox.shrink(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: _index > 0 ? () => _goToCard(_index - 1) : null,
                icon: const Icon(Icons.chevron_left),
                label: Text(context.s.previous),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _goToCard(_index + 1),
                iconAlignment: IconAlignment.end,
                icon: const Icon(Icons.chevron_right),
                label: Text(_index + 1 >= _queue.length ? context.s.finish : context.s.next),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _cardFace(String label, String text,
      {bool withImage = false, List<String> highlights = const []}) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 1.2, color: theme.colorScheme.primary)),
        const SizedBox(height: 14),
        if (withImage) ...[
          NoteImage(noteId: _item.id, maxHeight: 140),
          const SizedBox(height: 14),
        ],
        MarkableText(
            text: text,
            highlights: highlights,
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center),
      ],
    );
  }

  // --- Multiple choice ---------------------------------------------------
  Widget _buildMultipleChoice() {
    final answered = _wasCorrect != null;
    return Column(
      children: [
        _promptCard(context),
        Expanded(
          child: _preparing || _options == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    for (final option in _options!)
                      _OptionTile(
                        text: option,
                        correctAnswer: _correctOption ?? '',
                        chosen: _chosen,
                        answered: answered,
                        onTap: answered
                            ? null
                            : () {
                                setState(() => _chosen = option);
                                _submitObjective(option == _correctOption);
                              },
                      ),
                    if (answered) _whyBox(),
                  ],
                ),
        ),
        if (answered) _nextBar(),
      ],
    );
  }

  // --- Type the answer ---------------------------------------------------
  Widget _buildTypeAnswer() {
    final answered = _wasCorrect != null;
    // Scrollable middle so long AI feedback is fully reachable; action pinned.
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                _promptCard(context),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _answerController,
                    enabled: !answered,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: context.s.yourAnswer,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: answered ? null : (_) => _checkTyped(),
                  ),
                ),
                if (answered) _resultBanner(),
                if (answered) _whyBox(),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: SizedBox(
            width: double.infinity,
            child: answered
                ? FilledButton(
                    onPressed: _advance,
                    child: Text(_index + 1 >= _queue.length ? context.s.finish : context.s.next),
                  )
                : FilledButton(
                    onPressed: (_grading || _preparing) ? null : _checkTyped,
                    child: (_grading || _preparing)
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(context.s.check),
                  ),
          ),
        ),
      ],
    );
  }

  /// The AI, unless none is attached or AI work is paused (rate limit, bad
  /// key, offline) — then grading goes straight to the on-device check.
  LlmProvider? get _gradingLlm =>
      ref.read(quizPrepProvider).isPaused ? null : ref.read(llmProvider);

  Future<void> _checkTyped() async {
    final strings = context.s;
    final guess = _answerController.text.trim();
    if (guess.isEmpty) return;
    final expected = _revealAnswer ?? '';
    // A clear match needs no AI request.
    if (isConfidentlyCorrect(guess, expected)) {
      await _submitObjective(true);
      return;
    }
    // A blank's answer is the exact highlighted words, checked on the device
    // (the AI's grading prompt is about the note's own question).
    final llm = _isCloze ? null : _gradingLlm;
    final aiAttached = !_isCloze && ref.read(llmProvider) != null;
    setState(() => _grading = true);
    bool correct;
    var partial = false;
    String? feedback;
    if (llm != null) {
      try {
        final grade = await llm.gradeAnswer(_item, guess);
        correct = grade.correct;
        partial = grade.partial;
        feedback = grade.feedback;
      } catch (e) {
        if (e is LlmException) {
          ref.read(quizPrepProvider.notifier).reportError(e);
        }
        correct = isAnswerCorrect(guess, expected);
        feedback = strings.checkedWithoutAi;
      }
    } else {
      correct = isAnswerCorrect(guess, expected);
      if (aiAttached) feedback = strings.checkedWithoutAi;
    }
    if (!mounted) return;
    setState(() => _grading = false);
    await _submitObjective(correct, feedback: feedback, partial: partial);
  }

  /// Whether "Why was I wrong?" can be offered for the card on screen.
  bool get _canExplain =>
      _wasCorrect == false &&
      !widget.config.method.isCoding &&
      ref.read(llmProvider) != null &&
      (_revealAnswer ?? _correctOption) != null;

  Future<void> _explain() async {
    final strings = context.s;
    final llm = ref.read(llmProvider);
    if (llm == null) return;
    final typed = _answerController.text.trim();
    setState(() => _explaining = true);
    String text;
    try {
      text = await llm.explainMistake(
        _item,
        question: _prompt,
        answer: _correctOption ?? _revealAnswer ?? '',
        studentAnswer: _chosen ?? (typed.isEmpty ? null : typed),
      );
    } on LlmException catch (e) {
      if (mounted) ref.read(quizPrepProvider.notifier).reportError(e);
      text = strings.aiFailure(e.kind, e.message);
    } catch (e) {
      text = strings.couldNotGenerate(e);
    }
    if (mounted) {
      setState(() {
        _explaining = false;
        _why = text;
      });
    }
  }

  /// The "Why was I wrong?" button, then the AI's explanation.
  Widget _whyBox() {
    final theme = Theme.of(context);
    final why = _why;
    if (why != null) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(why, style: theme.textTheme.bodyMedium),
      );
    }
    if (!_canExplain) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _explaining ? null : _explain,
          icon: _explaining
              ? const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.lightbulb_outline),
          label: Text(context.s.whyWrong),
        ),
      ),
    );
  }

  Widget _resultBanner() {
    final correct = _wasCorrect == true;
    final color = _partial
        ? const Color(0xFFC98A00)
        : correct
            ? const Color(0xFF2E9E4F)
            : const Color(0xFFD64545);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                    _partial
                        ? Icons.adjust
                        : (correct ? Icons.check_circle : Icons.cancel),
                    color: color),
                const SizedBox(width: 8),
                Text(
                    _partial
                        ? context.s.partlyRight
                        : (correct ? context.s.correct : context.s.incorrect),
                    style: TextStyle(
                        color: color, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Text(context.s.answerIs(_revealAnswer ?? _correctOption ?? '—')),
            if (_feedback != null) ...[
              const SizedBox(height: 4),
              Text(_feedback!, style: const TextStyle(fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _nextBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: _advance,
          child: Text(_index + 1 >= widget.queue.length ? context.s.finish : context.s.next),
        ),
      ),
    );
  }

  // --- Write the code -----------------------------------------------------
  Widget _buildCodeSnippet() {
    final answered = _wasCorrect != null;
    // The prompt (front) describes what to write; the reference code is in back.
    final task = _item.front.trim().isNotEmpty
        ? _item.front
        : context.s.reproduceSnippet;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _codeTaskHeader(
            context.s.methodLabel(PracticeMethod.codeSnippet), task),
        const SizedBox(height: 12),
        CodeField(
          controller: _codeController,
          enabled: !answered,
          hintText: context.s.writeCodeHint,
          minLines: 6,
          maxLines: 18,
        ),
        const SizedBox(height: 12),
        if (!answered)
          FilledButton(
            onPressed: _grading ? null : _checkCode,
            child: _grading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(context.s.check),
          )
        else ...[
          _resultBanner(),
          const SizedBox(height: 12),
          _referenceCodeBlock(),
          const SizedBox(height: 12),
          _nextBar(),
        ],
      ],
    );
  }

  Future<void> _checkCode() async {
    final strings = context.s;
    final submitted = _codeController.text;
    if (submitted.trim().isEmpty) return;
    final reference = _item.back ?? '';
    // An equivalent match needs no AI request.
    if (codeMatches(submitted, reference)) {
      await _submitObjective(true);
      return;
    }
    final llm = _gradingLlm;
    setState(() => _grading = true);
    bool correct;
    var partial = false;
    String? feedback;
    if (llm != null) {
      try {
        final g = await llm.gradeCode(_item, submitted);
        correct = g.correct;
        feedback = g.feedback;
      } catch (e) {
        if (e is LlmException) {
          ref.read(quizPrepProvider.notifier).reportError(e);
        }
        correct = false;
        feedback = strings.aiCheckFailed;
      }
    } else if (ref.read(llmProvider) != null) {
      correct = false;
      feedback = strings.aiCheckFailed;
    } else {
      correct = codeMatches(submitted, reference);
      feedback = correct
          ? null
          : strings.offlineCheck;
    }
    if (!mounted) return;
    setState(() => _grading = false);
    await _submitObjective(correct, feedback: feedback, partial: partial);
  }

  // --- Fill in the blank (inline tap-to-type) -----------------------------
  Widget _buildFillBlank() {
    if (_preparing) return const Center(child: CircularProgressIndicator());
    final answered = _wasCorrect != null;
    final template = _item.fillBlankTemplate ?? _item.back ?? '';
    final answers = _item.fillBlankAnswers;
    final base = _monoStyle.copyWith(color: Theme.of(context).colorScheme.onSurface);

    // Interleave highlighted code with inline editable blank boxes.
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final m in fillBlankPlaceholderPattern.allMatches(template)) {
      if (m.start > cursor) {
        spans.addAll(highlightCode(template.substring(cursor, m.start), base));
      }
      final k = int.parse(m.group(1)!);
      if (k < _blankControllers.length && k < answers.length) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _InlineBlank(
            controller: _blankControllers[k],
            answer: answers[k],
            answered: answered,
          ),
        ));
      }
      cursor = m.end;
    }
    if (cursor < template.length) {
      spans.addAll(highlightCode(template.substring(cursor), base));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _codeTaskHeader(
            context.s.fillBlanksTitle, context.s.fillBlanksSubtitle),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text.rich(TextSpan(children: spans)),
        ),
        const SizedBox(height: 16),
        if (!answered)
          FilledButton(onPressed: _checkBlanks, child: Text(context.s.check))
        else ...[
          _resultBanner(),
          const SizedBox(height: 12),
          _nextBar(),
        ],
      ],
    );
  }

  void _checkBlanks() {
    final answers = _item.fillBlankAnswers;
    var allCorrect = answers.isNotEmpty;
    for (var i = 0; i < answers.length; i++) {
      if (_blankControllers[i].text.trim() != answers[i].trim()) {
        allCorrect = false;
      }
    }
    _submitObjective(allCorrect);
  }

  // --- Reorder the code ---------------------------------------------------
  Widget _buildReorder() {
    if (_preparing) return const Center(child: CircularProgressIndicator());
    final answered = _wasCorrect != null;
    final segments = _item.reorderSegments;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: _codeTaskHeader(
              context.s.reorderTitle, context.s.reorderSubtitle),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _reorderCurrent.length,
            // No trailing handles — the whole block is the drag target, grabbed
            // immediately on press (snappy on touch, click-drag on desktop).
            buildDefaultDragHandles: false,
            onReorderItem: _onReorder,
            itemBuilder: (context, i) {
              final scheme = Theme.of(context).colorScheme;
              final idx = _reorderCurrent[i];
              final base = _monoStyle.copyWith(color: scheme.onSurface);
              final border = !answered
                  ? scheme.outlineVariant
                  : (idx == i
                      ? const Color(0xFF2E9E4F)
                      : const Color(0xFFD64545));
              final card = Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                elevation: 0,
                color: scheme.surfaceContainerHighest,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                      color: border, width: answered && idx != i ? 2 : 1),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      if (!answered)
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Icon(Icons.drag_indicator,
                              size: 18, color: scheme.outline),
                        ),
                      Expanded(
                        child: Text.rich(
                            TextSpan(children: highlightCode(segments[idx], base))),
                      ),
                    ],
                  ),
                ),
              );
              return answered
                  ? KeyedSubtree(key: ValueKey(idx), child: card)
                  : ReorderableDragStartListener(
                      key: ValueKey(idx), index: i, child: card);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: answered
              ? Column(
                  children: [_resultBanner(), const SizedBox(height: 12), _nextBar()])
              : SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                      onPressed: _checkReorder, child: Text(context.s.check)),
                ),
        ),
      ],
    );
  }

  // onReorderItem pre-adjusts newIndex for the removed item, so no -1 fixup.
  void _onReorder(int oldIndex, int newIndex) {
    if (_wasCorrect != null) return;
    setState(() {
      final moved = _reorderCurrent.removeAt(oldIndex);
      _reorderCurrent.insert(newIndex, moved);
    });
  }

  void _checkReorder() {
    final ordered = [for (final idx in _reorderCurrent) _item.reorderSegments[idx]];
    _submitObjective(listEquals(ordered, _item.reorderSegments));
  }

  // --- Shared code widgets ------------------------------------------------
  Widget _codeTaskHeader(String title, String subtitle) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1.2)),
        const SizedBox(height: 4),
        Text(subtitle, style: theme.textTheme.bodyMedium),
      ],
    );
  }

  Widget _codeBlock(String code) {
    final base = _monoStyle.copyWith(
        color: Theme.of(context).colorScheme.onSurface);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text.rich(TextSpan(children: highlightCode(code, base))),
      ),
    );
  }

  Widget _referenceCodeBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.s.reference, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 4),
        _codeBlock(_item.back ?? ''),
      ],
    );
  }

  Widget _buildDone() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.emoji_events_outlined,
              size: 72, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(context.s.scored(_correctCount, widget.queue.length),
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.s.back),
          ),
        ],
      ),
    );
  }
}

/// An inline, tap-to-type blank rendered inside the fill-in-the-blank code.
/// After checking, it reveals the correct token colored by whether the user
/// matched it.
class _InlineBlank extends StatelessWidget {
  const _InlineBlank({
    required this.controller,
    required this.answer,
    required this.answered,
  });

  final TextEditingController controller;
  final String answer;
  final bool answered;

  static const _mono = TextStyle(fontFamily: 'monospace', fontSize: 13);

  @override
  Widget build(BuildContext context) {
    if (answered) {
      final correct = controller.text.trim() == answer.trim();
      final color =
          correct ? const Color(0xFF2E9E4F) : const Color(0xFFD64545);
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color),
        ),
        child: Text(answer,
            style: _mono.copyWith(color: color, fontWeight: FontWeight.w600)),
      );
    }
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      constraints: const BoxConstraints(minWidth: 48, maxWidth: 160),
      child: IntrinsicWidth(
        child: TextField(
          controller: controller,
          style: _mono,
          textAlign: TextAlign.center,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            filled: true,
            fillColor: Theme.of(context)
                .colorScheme
                .primaryContainer
                .withValues(alpha: 0.4),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
          ),
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.text,
    required this.correctAnswer,
    required this.chosen,
    required this.answered,
    required this.onTap,
  });

  final String text;
  final String correctAnswer;
  final String? chosen;
  final bool answered;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isCorrect = text == correctAnswer;
    final isChosen = text == chosen;
    Color? border;
    if (answered) {
      if (isCorrect) {
        border = const Color(0xFF2E9E4F);
      } else if (isChosen) {
        border = const Color(0xFFD64545);
      }
    }
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: border == null
            ? BorderSide.none
            : BorderSide(color: border, width: 2),
      ),
      child: ListTile(
        title: Text(text),
        trailing: answered && isCorrect
            ? const Icon(Icons.check, color: Color(0xFF2E9E4F))
            : (answered && isChosen
                ? const Icon(Icons.close, color: Color(0xFFD64545))
                : null),
        onTap: onTap,
      ),
    );
  }
}

/// Thin notice that AI questions are paused, and what practice does meanwhile.
class _PauseBanner extends StatelessWidget {
  const _PauseBanner({required this.pause});

  final AiPause pause;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 20, color: scheme.onTertiaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${context.s.aiPauseReason(pause)} ${context.s.aiPauseFallback}',
                style: TextStyle(color: scheme.onTertiaryContainer, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
