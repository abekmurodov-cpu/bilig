import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_strings.dart';
import '../../llm/llm_provider.dart';
import '../../llm/llm_providers.dart';
import '../../llm/quiz_prep.dart';
import '../../models/knowledge_item.dart';
import '../../models/note_format.dart';
import '../../practice/answer_matching.dart';
import '../../practice/cloze.dart';
import '../../practice/code_drills.dart';
import '../../practice/practice_models.dart';
import '../../practice/text_blanks.dart';
import '../../providers/knowledge_providers.dart';
import '../../scheduler/spaced_repetition.dart';
import '../../providers/study_providers.dart';
import '../widgets/code_field.dart';
import '../widgets/confetti.dart';
import '../widgets/code_highlighter.dart';
import '../widgets/flip_card.dart';
import '../theme.dart';
import '../widgets/item_tile.dart';
import '../widgets/note_detail_sheet.dart';
import '../widgets/note_image.dart';
import '../widgets/note_text.dart';
import 'practice_screen.dart' show methodIcon;

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

  /// Grades given this session, newest last, so they can be undone.
  final List<_Graded> _history = [];

  /// The flashcard on screen; a new key per card so each starts face up.
  var _flipKey = GlobalKey<FlipCardState>();
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
  // Fill-in-the-blank on an ordinary note (key words taken out of its text);
  // null for code notes, which blank code tokens instead.
  TextBlanks? _textBlanks;

  /// Which words are common across the student's notes, for choosing blanks.
  late final WordStats _wordStats = WordStats(ref.read(notesSortedProvider));
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

  /// Asking the other way round: the answer is shown, the prompt recalled.
  bool get _reverse =>
      widget.config.reverse && PracticeConfig.canReverse(widget.config.method);

  bool get _usesQuiz => !_reverse && switch (widget.config.method) {
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

  /// Lets go of the blanks' fields once the card showing them has slid away.
  void _disposeBlankControllers() {
    final old = List.of(_blankControllers);
    _blankControllers.clear();
    if (old.isEmpty) return;
    Future.delayed(const Duration(milliseconds: 600), () {
      for (final c in old) {
        c.dispose();
      }
    });
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
    if (_reverse) return _item.back ?? _item.front;
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
    _flipKey = GlobalKey<FlipCardState>();
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
      case PracticeMethod.fillBlank when _item.type != KnowledgeType.code:
        _textBlanks = textBlanks(_item, stats: _wordStats);
        _setupCoding();
      case PracticeMethod.fillBlank:
      case PracticeMethod.reorder:
        _textBlanks = null;
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
      List.generate(_blankAnswers.length, (_) => TextEditingController()),
    );
    _reorderCurrent = _shuffledOrder(_item.reorderSegments.length);
  }

  /// The blanks' answers: key words of an ordinary note, or code tokens.
  List<String> get _blankAnswers => _textBlanks?.answers ?? _item.fillBlankAnswers;

  bool _blankRight(int i) => _textBlanks != null
      ? blankMatches(_blankControllers[i].text, _blankAnswers[i])
      : _blankControllers[i].text.trim() == _blankAnswers[i].trim();

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
    if (_reverse) return _item.front;
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
    _history.removeWhere((h) => h.index == _index);
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
    _buzz(grade);
    _flashGrades[_index] = grade;
    final counted = grade.quality >= 3;
    _history.add(_Graded(_index, _item, grade, counted));
    await ref.read(knowledgeListProvider.notifier).grade(_item, grade);
    _celebrateGoal();
    if (counted) _correctCount++;
    _advance();
  }

  /// Opens the note on screen to fix it (a typo, a better answer) without
  /// leaving practice; the card then shows the edited note.
  Future<void> _editCurrent() async {
    final id = _item.id;
    await showNoteDetailSheet(context, _item);
    if (!mounted || _index >= _queue.length || _item.id != id) return;
    final items = ref.read(knowledgeListProvider).asData?.value ?? const [];
    final fresh = items.where((n) => n.id == id).firstOrNull;
    if (fresh == null) {
      // Deleted from the sheet: move on.
      _advance();
      return;
    }
    setState(() => _queue[_index] = fresh);
  }

  /// Confetti the moment today's reviews reach the daily goal.
  void _celebrateGoal() {
    if (!mounted) return;
    final today = ref.read(activityProvider)[dayKey(DateTime.now())]?.reviews ?? 0;
    final goal = ref.read(dailyGoalProvider);
    if (today != goal) return;
    showConfetti(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.s.goalReached)));
  }

  /// A light tap for a good grade, a firmer one for a miss.
  void _buzz(ReviewGrade grade) => grade == ReviewGrade.again
      ? HapticFeedback.mediumImpact()
      : HapticFeedback.lightImpact();

  /// Takes back the last grade: the note is restored and its card comes back
  /// unanswered.
  Future<void> _undo() async {
    if (_history.isEmpty) return;
    final last = _history.removeLast();
    HapticFeedback.selectionClick();
    await ref.read(knowledgeListProvider.notifier).undoGrade(last.before, last.grade);
    if (!mounted) return;
    if (last.counted) _correctCount--;
    _flashGrades.remove(last.index);
    _disposeBlankControllers();
    setState(() {
      _queue[last.index] = last.before;
      _index = last.index;
      _frontier = last.index;
      _clearCard();
    });
    _prepareItem();
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
    final grade = !correct
        ? ReviewGrade.again
        : (_partial ? ReviewGrade.hard : ReviewGrade.good);
    _buzz(grade);
    _history.add(_Graded(_index, _item, grade, correct));
    await ref.read(knowledgeListProvider.notifier).grade(_item, grade);
    _celebrateGoal();
    if (correct) _correctCount++;
  }

  void _advance() {
    if (!mounted) return;
    _disposeBlankControllers();
    setState(() {
      _index++;
      if (_index > _frontier) _frontier = _index;
      _clearCard();
    });
    if (_index < _queue.length) _prepareItem();
  }

  /// Resets what the card on screen shows (answer, options, results).
  void _clearCard() {
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
        titleSpacing: 0,
        title: done
            ? Text(context.s.done)
            : Row(
                children: [
                  Icon(methodIcon(widget.config.method),
                      size: 22, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(context.s.methodLabel(widget.config.method),
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge),
                  ),
                  const SizedBox(width: 10),
                  Text('${_index + 1} / ${_queue.length}',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
        bottom: done
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(10),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: _queue.isEmpty ? 0 : _index / _queue.length),
                    duration: const Duration(milliseconds: 300),
                    builder: (context, value, _) =>
                        LinearProgressIndicator(value: value),
                  ),
                ),
              ),
        actions: [
          if (!done && !_warmingUp)
            IconButton(
              tooltip: context.s.editNote,
              icon: const Icon(Icons.edit_outlined),
              onPressed: _editCurrent,
            ),
          if (_history.isNotEmpty)
            IconButton(
              tooltip: context.s.undoGrade,
              icon: const Icon(Icons.undo),
              onPressed: _undo,
            ),
          if (!done && _canFlag)
            IconButton(
              tooltip: context.s.badQuestion,
              icon: const Icon(Icons.thumb_down_alt_outlined),
              onPressed: _flagQuestion,
            ),
        ],
      ),
      body: ReadableWidth(maxWidth: 800, child: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: done
            ? _buildDone()
            : Column(
                children: [
                  if (showPause) _PauseBanner(pause: prep.pause!),
                  Expanded(child: _buildBody()),
                ],
              ),
      )),
    );
  }

  bool get _showFlashGrades =>
      _index >= _frontier && (_revealed || !_canReveal);

  /// Keyboard shortcuts (on a Mac or with a keyboard): Space/Enter flips or
  /// moves on, 1–4 grade or pick an option, ←/→ browse flashcards, ⌘Z/Ctrl+Z
  /// undoes. Ignored while typing in a text field.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused != null &&
        (focused.widget is EditableText ||
            focused.findAncestorWidgetOfExactType<EditableText>() != null)) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final keys = HardwareKeyboard.instance;
    if (key == LogicalKeyboardKey.keyZ && (keys.isMetaPressed || keys.isControlPressed)) {
      _undo();
      return KeyEventResult.handled;
    }
    if (_index >= _queue.length || _warmingUp || _preparing) {
      return KeyEventResult.ignored;
    }
    const digits = [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
    ];
    final digit = digits.indexOf(key);
    final confirm = key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter;
    final method = widget.config.method;

    if (_selfCheck || method == PracticeMethod.flashcard) {
      final graded = _selfCheck ? _revealed : _showFlashGrades;
      if (digit >= 0 && graded && _index >= _frontier) {
        _grade(ReviewGrade.values[digit]);
        return KeyEventResult.handled;
      }
      if (confirm && !graded) {
        if (_selfCheck) {
          setState(() => _revealed = true);
        } else {
          _flipKey.currentState?.flip();
        }
        return KeyEventResult.handled;
      }
      if (!_selfCheck && key == LogicalKeyboardKey.arrowLeft && _index > 0) {
        _goToCard(_index - 1);
        return KeyEventResult.handled;
      }
      if (!_selfCheck && key == LogicalKeyboardKey.arrowRight) {
        _goToCard(_index + 1);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (_wasCorrect != null && confirm) {
      _advance();
      return KeyEventResult.handled;
    }
    final options = _options;
    if (method == PracticeMethod.multipleChoice &&
        _wasCorrect == null &&
        options != null &&
        digit >= 0 &&
        digit < options.length) {
      setState(() => _chosen = options[digit]);
      _submitObjective(options[digit] == _correctOption);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildBody() {
    if (_index != _lastIndex) {
      _direction = _index > _lastIndex ? 1 : -1;
      _lastIndex = _index;
    }
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
    final card = switch (widget.config.method) {
      PracticeMethod.flashcard => _buildFlashcard(),
      PracticeMethod.multipleChoice => _buildMultipleChoice(),
      PracticeMethod.typeAnswer => _buildTypeAnswer(),
      PracticeMethod.codeSnippet => _buildCodeSnippet(),
      PracticeMethod.fillBlank => _buildFillBlank(),
      PracticeMethod.reorder => _buildReorder(),
    };
    // Each card slides in from the side it comes from.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final incoming = child.key == ValueKey('card$_index');
        final from = Offset(incoming ? 0.12 * _direction : -0.12 * _direction, 0);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween(begin: from, end: Offset.zero).animate(animation),
            child: child,
          ),
        );
      },
      child: KeyedSubtree(key: ValueKey('card$_index'), child: card),
    );
  }

  /// 1 when moving forward through the cards, -1 when going back.
  int _direction = 1;
  int _lastIndex = 0;

  Widget _promptCard(BuildContext context, {Widget? extra}) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: practiceCardDecoration(context),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardLabel(context),
            const SizedBox(height: 14),
            NoteBody(text: _prompt, style: theme.textTheme.headlineSmall),
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

  /// The note's kind and category, over the question.
  Widget _cardLabel(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.labelMedium
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant, letterSpacing: 0.4);
    return Row(
      children: [
        TypeChip(type: _item.type, size: 28),
        const SizedBox(width: 10),
        Text(context.s.noteType(_item.type), style: muted),
        if (_item.category != null) ...[
          Text('  ·  ', style: muted),
          Flexible(
            child: Text(_item.category!,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
          ),
        ],
      ],
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

  /// Desktop and web usually have a keyboard: show the shortcuts there.
  bool get _hasKeyboard =>
      kIsWeb ||
      const {TargetPlatform.macOS, TargetPlatform.windows, TargetPlatform.linux}
          .contains(defaultTargetPlatform);

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
                          NoteBody(
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
  /// A swipe before the answer is shown: say to flip the card first.
  void _flipFirstHint() {
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Row(
          children: [
            Icon(Icons.touch_app_outlined,
                color: Theme.of(context).colorScheme.onInverseSurface),
            const SizedBox(width: 12),
            Expanded(child: Text(context.s.flipBeforeSwipe)),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
  }

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
                    SwipeCard(
                      key: ValueKey('swipe$_index'),
                      enabled: showGrades,
                      onBlockedSwipe: viewOnly ? null : _flipFirstHint,
                      leftLabel: context.s.grade(ReviewGrade.again),
                      rightLabel: context.s.grade(ReviewGrade.good),
                      onSwipe: (direction) => _grade(direction == SwipeDirection.right
                          ? ReviewGrade.good
                          : ReviewGrade.again),
                      child: FlipCard(
                        key: _flipKey,
                        onFlip: (back) {
                          if (back && !_revealed) {
                            setState(() => _revealed = true);
                          }
                        },
                        front: _cardFace(
                          _reverse
                              ? context.s.whatIsThis.toUpperCase()
                              : context.s.noteType(_item.type).toUpperCase(),
                          _prompt,
                          withImage: _item.hasImage,
                        ),
                        back: _cardFace(
                          context.s.answerLabel,
                          _revealAnswer ?? context.s.noAnswerRecorded,
                          highlights: _item.highlights,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      viewOnly
                          ? (pastGrade == null
                              ? context.s.skippedViewOnly
                              : context.s.ratedViewOnly(pastGrade))
                          : showGrades
                              ? '${context.s.howWell}  ${context.s.swipeHint}'
                              : context.s.tapToFlip,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                    if (_hasKeyboard) ...[
                      const SizedBox(height: 4),
                      Text(context.s.keyboardHint,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: theme.colorScheme.outline)),
                    ],
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
        NoteBody(
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
                    for (final (i, option) in _options!.indexed)
                      _OptionTile(
                        letter: String.fromCharCode(65 + i),
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
    final expected = plainText(_revealAnswer ?? '');
    // A clear match needs no AI request.
    if (isConfidentlyCorrect(guess, expected)) {
      await _submitObjective(true);
      return;
    }
    // A blank's answer is the exact highlighted words, checked on the device
    // (the AI's grading prompt is about the note's own question).
    // The AI grades against the note's own question, so a blank or a
    // reversed card is checked on the device.
    final llm = _isCloze || _reverse ? null : _gradingLlm;
    final aiAttached = !_isCloze && !_reverse && ref.read(llmProvider) != null;
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
      widget.config.method != PracticeMethod.fillBlank &&
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

  Widget _resultBanner({bool showAnswer = true}) {
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
            if (showAnswer) ...[
              const SizedBox(height: 8),
              Text(context.s.answerIs(plainText(_revealAnswer ?? _correctOption ?? '—'))),
            ],
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
    final text = _textBlanks;
    if (text != null) return _buildTextBlanks(text);
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
            correct: _blankRight(k),
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

  /// Fill in the blank on an ordinary note: its cue, then the passage with
  /// the key words to type back in.
  Widget _buildTextBlanks(TextBlanks blanks) {
    final theme = Theme.of(context);
    final answered = _wasCorrect != null;
    final base = theme.textTheme.bodyLarge!.copyWith(fontSize: 18, height: 2);
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final m in fillBlankPlaceholderPattern.allMatches(blanks.template)) {
      if (m.start > cursor) {
        spans.add(TextSpan(text: blanks.template.substring(cursor, m.start)));
      }
      final k = int.parse(m.group(1)!);
      if (k < _blankControllers.length) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _InlineBlank(
            controller: _blankControllers[k],
            answer: blanks.answers[k],
            answered: answered,
            correct: _blankRight(k),
            mono: false,
            onSubmitted: k == _blankControllers.length - 1 && !answered
                ? _checkBlanks
                : null,
          ),
        ));
      }
      cursor = m.end;
    }
    if (cursor < blanks.template.length) {
      spans.add(TextSpan(text: blanks.template.substring(cursor)));
    }
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _codeTaskHeader(context.s.fillBlanksTitle, context.s.textBlanksSubtitle),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: practiceCardDecoration(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _cardLabel(context),
                    const SizedBox(height: 14),
                    if (blanks.cue != null) ...[
                      Text(blanks.cue!,
                          style: theme.textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      if (_item.hasImage) ...[
                        const SizedBox(height: 12),
                        NoteImage(noteId: _item.id),
                      ],
                      const Divider(height: 28),
                    ],
                    Text.rich(TextSpan(style: base, children: spans)),
                  ],
                ),
              ),
              if (answered) _resultBanner(showAnswer: false),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: SizedBox(
            width: double.infinity,
            child: answered
                ? FilledButton(
                    onPressed: _advance,
                    child: Text(_index + 1 >= _queue.length
                        ? context.s.finish
                        : context.s.next))
                : FilledButton(onPressed: _checkBlanks, child: Text(context.s.check)),
          ),
        ),
      ],
    );
  }

  void _checkBlanks() {
    final answers = _blankAnswers;
    var allCorrect = answers.isNotEmpty;
    for (var i = 0; i < answers.length; i++) {
      if (!_blankRight(i)) allCorrect = false;
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

  /// Notes missed this session, as they are now, for another go.
  List<KnowledgeItem> get _missed {
    final ids = {for (final h in _history) if (!h.counted) h.before.id};
    final items = ref.read(knowledgeListProvider).asData?.value ?? const [];
    return [for (final i in items) if (ids.contains(i.id)) i];
  }

  bool _cheered = false;

  Widget _buildDone() {
    final theme = Theme.of(context);
    if (!_cheered && widget.queue.isNotEmpty && _correctCount / widget.queue.length >= 0.8) {
      _cheered = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showConfetti(context);
      });
    }
    final scheme = theme.colorScheme;
    final total = widget.queue.length;
    final share = total == 0 ? 0.0 : _correctCount / total;
    final missed = _missed;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 150,
                height: 150,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: share),
                      duration: const Duration(milliseconds: 900),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, _) => CircularProgressIndicator(
                        value: value,
                        strokeWidth: 12,
                        strokeCap: StrokeCap.round,
                        backgroundColor: scheme.surfaceContainerHighest,
                      ),
                    ),
                    Center(
                      child: Text('${(share * 100).round()}%',
                          style: theme.textTheme.headlineMedium),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(share >= 0.8 ? context.s.greatSession : context.s.sessionDone,
                  style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text(context.s.scored(_correctCount, total),
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 28),
              if (missed.isNotEmpty) ...[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => PracticeSessionScreen(
                            config: widget.config, queue: missed..shuffle()),
                      ),
                    ),
                    icon: const Icon(Icons.replay),
                    label: Text(context.s.practiseMissed(missed.length)),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              SizedBox(
                width: double.infinity,
                child: missed.isEmpty
                    ? FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(context.s.back))
                    : OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(context.s.back)),
              ),
            ],
          ),
        ),
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
    required this.correct,
    this.mono = true,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String answer;
  final bool answered;

  /// Whether what was typed fills the blank (shown once answered).
  final bool correct;

  /// Code is typed in a monospace font; words in the note's own.
  final bool mono;
  final VoidCallback? onSubmitted;

  static const _mono = TextStyle(fontFamily: 'monospace', fontSize: 13);

  @override
  Widget build(BuildContext context) {
    final style = mono ? _mono : Theme.of(context).textTheme.bodyLarge!.copyWith(fontSize: 17);
    if (answered) {
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
        child: Text.rich(
          TextSpan(children: [
            // What was typed, struck through, before the right word.
            if (!correct && controller.text.trim().isNotEmpty)
              TextSpan(
                text: '${controller.text.trim()} ',
                style: style.copyWith(
                    color: color.withValues(alpha: 0.7),
                    decoration: TextDecoration.lineThrough,
                    fontSize: (style.fontSize ?? 14) * 0.85),
              ),
            TextSpan(
                text: answer,
                style: style.copyWith(color: color, fontWeight: FontWeight.w600)),
          ]),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      constraints: BoxConstraints(minWidth: mono ? 48 : 72, maxWidth: mono ? 160 : 220),
      child: IntrinsicWidth(
        child: TextField(
          controller: controller,
          style: style,
          onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
          textInputAction:
              onSubmitted == null ? TextInputAction.next : TextInputAction.done,
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
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(mono ? 4 : 8)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(mono ? 4 : 8),
              borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)),
            ),
          ),
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.letter,
    required this.text,
    required this.correctAnswer,
    required this.chosen,
    required this.answered,
    required this.onTap,
  });

  /// A, B, C… (keys 1, 2, 3… pick them).
  final String letter;
  final String text;
  final String correctAnswer;
  final String? chosen;
  final bool answered;
  final VoidCallback? onTap;

  static const _right = Color(0xFF2E9E4F);
  static const _wrong = Color(0xFFD64545);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isCorrect = text == correctAnswer;
    final isChosen = text == chosen;
    final Color? accent = !answered
        ? null
        : isCorrect
            ? _right
            : isChosen
                ? _wrong
                : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Material(
        color: accent?.withValues(alpha: 0.1) ?? theme.cardTheme.color,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
              color: accent ?? scheme.outlineVariant.withValues(alpha: 0.6),
              width: accent == null ? 1 : 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent ?? scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: accent == null
                      ? Text(letter,
                          style: theme.textTheme.labelLarge
                              ?.copyWith(fontWeight: FontWeight.w700))
                      : Icon(isCorrect ? Icons.check : Icons.close,
                          size: 18, color: Colors.white),
                ),
                const SizedBox(width: 14),
                Expanded(child: NoteBody(text: text, style: theme.textTheme.bodyLarge)),
              ],
            ),
          ),
        ),
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

/// A grade given this session, kept so it can be undone.
class _Graded {
  const _Graded(this.index, this.before, this.grade, this.counted);

  /// The card's place in the queue.
  final int index;

  /// The note as it was before the grade.
  final KnowledgeItem before;
  final ReviewGrade grade;

  /// Whether it raised the session's correct count.
  final bool counted;
}
