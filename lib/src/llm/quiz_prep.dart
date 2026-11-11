import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/knowledge_item.dart';
import '../practice/quiz_quality.dart';
import '../providers/knowledge_providers.dart';
import 'llm_provider.dart';
import 'llm_providers.dart';

/// Tuning for [QuizPrep]; overridable in tests.
class QuizPrepConfig {
  const QuizPrepConfig({
    this.batchSize = 12,
    this.batchGap = const Duration(seconds: 4),
    this.debounce = const Duration(seconds: 3),
    this.maxAttemptsPerNote = 2,
  });

  /// Notes per request. One request per batch is what keeps free-tier keys
  /// alive: limits count requests far more than tokens.
  final int batchSize;

  /// Pause between batches so a big backlog stays under per-minute limits.
  final Duration batchGap;

  /// Wait after a note change before starting, so a burst of edits or a sync
  /// becomes one run.
  final Duration debounce;

  /// A note whose quiz keeps coming back unusable is skipped for the rest of
  /// the app session instead of burning requests on it.
  final int maxAttemptsPerNote;
}

final quizPrepConfigProvider =
    Provider<QuizPrepConfig>((ref) => const QuizPrepConfig());

/// Why AI quiz generation is paused.
enum AiPause { rateLimited, quotaExhausted, auth, network, error }

class QuizPrepState {
  const QuizPrepState({this.running = false, this.pause, this.pausedUntil});

  final bool running;
  final AiPause? pause;

  /// When the pause ends on its own; null for pauses that need the user (a
  /// rejected key).
  final DateTime? pausedUntil;

  bool get isPaused =>
      pause != null &&
      (pausedUntil == null || DateTime.now().isBefore(pausedUntil!));

  QuizPrepState copyWith({bool? running}) => QuizPrepState(
        running: running ?? this.running,
        pause: pause,
        pausedUntil: pausedUntil,
      );
}

/// Generates and caches multiple-choice quizzes **ahead of time**, in batches,
/// so practice never waits on (or fails because of) the AI.
///
/// Runs in the background whenever notes change or an AI key is attached. When
/// the AI reports a rate limit, a used-up quota, a bad key or no network, it
/// pauses — retrying later on its own where that makes sense — and exposes the
/// reason so the UI can say why some notes have no AI question yet.
class QuizPrep extends Notifier<QuizPrepState> {
  Timer? _timer;
  Future<void>? _current;
  final Map<String, int> _attempts = {};
  List<String> _priority = const [];
  final _batchDone = StreamController<void>.broadcast();

  QuizPrepConfig get _config => ref.read(quizPrepConfigProvider);

  @override
  QuizPrepState build() {
    ref.listen(llmProvider, (_, _) {
      // A new key or model gets a fresh start.
      _attempts.clear();
      state = const QuizPrepState();
      schedule();
    });
    ref.listen(knowledgeListProvider, (_, _) => schedule());
    ref.onDispose(() {
      _timer?.cancel();
      _batchDone.close();
    });
    Future.microtask(schedule);
    return const QuizPrepState();
  }

  /// Notes that still need a quiz and haven't used up their attempts.
  List<KnowledgeItem> _candidates() {
    final items = ref.read(knowledgeListProvider).asData?.value ?? const [];
    final byId = {for (final i in items) i.id: i};
    bool eligible(KnowledgeItem i) =>
        i.needsQuiz && (_attempts[i.id] ?? 0) < _config.maxAttemptsPerNote;
    final first = [
      for (final id in _priority)
        if (byId[id] case final item? when eligible(item)) item,
    ];
    final firstIds = {for (final i in first) i.id};
    return [
      ...first,
      for (final i in items)
        if (!firstIds.contains(i.id) && eligible(i)) i,
    ];
  }

  /// Starts a background run after the debounce, unless nothing can happen.
  void schedule({Duration? delay}) {
    if (ref.read(llmProvider) == null) return;
    _timer?.cancel();
    _timer = Timer(delay ?? _config.debounce, run);
  }

  /// Runs until every note has a quiz, generation pauses, or the AI is
  /// detached. Concurrent calls share the run in progress.
  Future<void> run() => _current ??= _run().whenComplete(() => _current = null);

  /// Gets quizzes for the first [count] notes of an upcoming practice [queue]
  /// generated first. Completes when they are ready, when generation pauses,
  /// or when no progress is possible — the caller adds its own timeout.
  Future<void> prepare(List<KnowledgeItem> queue, {int? count}) async {
    final wanted = queue.take(count ?? _config.batchSize).map((i) => i.id).toList();
    _priority = wanted;
    bool ready() {
      final pending = _candidates().map((i) => i.id).toSet();
      return !wanted.any(pending.contains);
    }

    while (!ready() && !state.isPaused && ref.read(llmProvider) != null) {
      // Errors only if the notifier is disposed mid-wait; then just stop.
      final batch = _batchDone.stream.first.then((_) {}, onError: (_) {});
      final runFuture = run();
      await Future.any([batch, runFuture]);
    }
  }

  /// Clears pauses and per-note attempt counts and starts a run now (the
  /// "Prepare now" button).
  Future<void> retryNow() {
    _attempts.clear();
    state = QuizPrepState(running: state.running);
    return run();
  }

  Future<void> _run() async {
    // Never change state synchronously: callers may be mid-build (a practice
    // screen starting up).
    await Future<void>.value();
    while (true) {
      final llm = ref.read(llmProvider);
      if (llm == null || state.isPaused) break;
      final batch = _candidates().take(_config.batchSize).toList();
      if (batch.isEmpty) break;

      state = state.copyWith(running: true);
      for (final item in batch) {
        _attempts[item.id] = (_attempts[item.id] ?? 0) + 1;
      }
      try {
        final quizzes = await llm.generateQuizzes(batch);
        await _save(batch, quizzes);
        if (state.pause != null) state = QuizPrepState(running: state.running);
      } on LlmException catch (e) {
        reportError(e);
      } catch (_) {
        reportError(const LlmException(LlmErrorKind.other, 'Unexpected error'));
      }
      if (!_batchDone.isClosed) _batchDone.add(null);
      if (state.isPaused) break;
      if (_candidates().isEmpty) break;
      await Future<void>.delayed(_config.batchGap);
    }
    state = state.copyWith(running: false);
  }

  /// Applies good quizzes onto the **current** copy of each note, so a grade
  /// recorded while the request was in flight isn't overwritten. Notes edited
  /// meanwhile are skipped; they'll be picked up again.
  Future<void> _save(List<KnowledgeItem> batch, Map<String, McQuiz> quizzes) async {
    final current = {
      for (final i in ref.read(knowledgeListProvider).asData?.value ?? const <KnowledgeItem>[])
        i.id: i,
    };
    final updates = <KnowledgeItem>[];
    for (final sent in batch) {
      final quiz = quizzes[sent.id];
      final now = current[sent.id];
      if (quiz == null || now == null) continue;
      if (now.front != sent.front || now.back != sent.back) continue;
      if (quizProblem(quiz) != null) continue;
      updates.add(applyQuiz(now, quiz));
    }
    if (updates.isNotEmpty) {
      await ref.read(knowledgeListProvider.notifier).persistAll(updates);
    }
  }

  /// Pauses AI work after [e]. Also called by practice when grading with the
  /// AI fails, so the whole app backs off together.
  void reportError(LlmException e) {
    final (pause, wait) = switch (e.kind) {
      LlmErrorKind.rateLimited =>
        (AiPause.rateLimited, e.retryAfter ?? const Duration(minutes: 1)),
      LlmErrorKind.quotaExhausted => (AiPause.quotaExhausted, const Duration(hours: 1)),
      LlmErrorKind.auth => (AiPause.auth, null),
      LlmErrorKind.network => (AiPause.network, const Duration(minutes: 2)),
      // A garbled reply only costs those notes an attempt; keep going.
      LlmErrorKind.badResponse => (null, null),
      LlmErrorKind.other => (AiPause.error, const Duration(minutes: 5)),
    };
    if (pause == null) return;
    state = QuizPrepState(
      running: state.running,
      pause: pause,
      pausedUntil: wait == null ? null : DateTime.now().add(wait),
    );
    if (wait != null) schedule(delay: wait + const Duration(seconds: 1));
  }
}

/// Writes [quiz] onto [item]. Content notes (anything but a question) get the
/// reworded question as their practice prompt; answer-less notes get the
/// concise answer as their answer.
KnowledgeItem applyQuiz(KnowledgeItem item, McQuiz quiz) {
  var updated = item.copyWith(
    mcAnswer: quiz.answer,
    mcDistractors: quiz.distractors,
    back: item.hasAnswer ? item.back : quiz.answer,
  );
  if (item.type != KnowledgeType.question) {
    updated = updated.copyWith(quizQuestion: quiz.question);
  }
  return updated;
}

final quizPrepProvider =
    NotifierProvider<QuizPrep, QuizPrepState>(QuizPrep.new);
