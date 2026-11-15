import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge/src/llm/llm_provider.dart';
import 'package:knowledge/src/llm/llm_providers.dart';
import 'package:knowledge/src/llm/quiz_prep.dart';
import 'package:knowledge/src/models/knowledge_item.dart';
import 'package:knowledge/src/providers/knowledge_providers.dart';
import 'package:knowledge/src/scheduler/spaced_repetition.dart';

import 'widget_test.dart' show FakeRepository;

/// Records batches and answers each with a good quiz unless told otherwise.
class FakeLlm implements LlmProvider {
  final batches = <List<String>>[];
  LlmException? failWith;
  bool garble = false;
  Future<void> Function()? duringRequest;

  @override
  Future<Map<String, List<McQuiz>>> generateQuizzes(List<KnowledgeItem> items,
      {int distractorCount = 3, int variantCount = 3}) async {
    batches.add([for (final i in items) i.id]);
    await duringRequest?.call();
    if (failWith != null) throw failWith!;
    return {
      for (final i in items)
        i.id: garble
            ? const [McQuiz(question: 'Q?', answer: 'same', distractors: ['same', 'Same'])]
            : [
                for (final angle in ['What about', 'Why', 'When'])
                  McQuiz(
                    question: '$angle ${i.id}?',
                    answer: '$angle answer ${i.id}',
                    distractors: const ['wrong one', 'wrong two', 'wrong three'],
                  ),
              ],
    };
  }

  @override
  String get displayName => 'fake';
  @override
  Future<String> expandNote(KnowledgeItem item) => throw UnimplementedError();
  @override
  Future<McQuiz> generateQuiz(KnowledgeItem item, {int distractorCount = 3}) =>
      throw UnimplementedError();
  @override
  Future<LlmGrade> gradeAnswer(KnowledgeItem item, String answer) =>
      throw UnimplementedError();
  @override
  Future<LlmGrade> gradeCode(KnowledgeItem item, String submitted) =>
      throw UnimplementedError();
  @override
  Future<String> suggestCategory(String front, String? back) =>
      throw UnimplementedError();
  @override
  Future<List<String>> suggestHighlights(KnowledgeItem item) =>
      throw UnimplementedError();
  @override
  Future<String> explainMistake(KnowledgeItem item,
          {required String question,
          required String answer,
          String? studentAnswer}) =>
      throw UnimplementedError();
  @override
  bool get canReadImages => false;
  @override
  bool get canTranscribe => false;
  @override
  Future<List<NoteDraft>> notesFromImage(Attachment image) =>
      throw UnimplementedError();
  @override
  Future<List<NoteDraft>> notesFromText(String text) =>
      throw UnimplementedError();
  @override
  Future<String> transcribe(Attachment audio) => throw UnimplementedError();
}

KnowledgeItem note(String id) {
  final now = DateTime(2026, 1, 1);
  return KnowledgeItem(
    id: id,
    front: 'fact $id',
    type: KnowledgeType.fact,
    createdAt: now,
    dueDate: now,
  );
}

Future<(ProviderContainer, FakeLlm)> setUpWith(List<String> ids) async {
  final repo = FakeRepository();
  for (final id in ids) {
    await repo.save(note(id));
  }
  final llm = FakeLlm();
  final container = ProviderContainer(overrides: [
    knowledgeRepositoryProvider.overrideWithValue(repo),
    llmProvider.overrideWithValue(llm),
    quizPrepConfigProvider.overrideWithValue(const QuizPrepConfig(
      batchSize: 2,
      batchGap: Duration.zero,
      debounce: Duration(hours: 1), // tests drive runs explicitly
    )),
  ]);
  await container.read(knowledgeListProvider.future);
  container.read(quizPrepProvider);
  return (container, llm);
}

List<KnowledgeItem> stored(ProviderContainer c) =>
    c.read(knowledgeListProvider).requireValue;

void main() {
  test('fills every note in batches, one request per batch', () async {
    final (c, llm) = await setUpWith(['a', 'b', 'c', 'd', 'e']);
    addTearDown(c.dispose);
    await c.read(quizPrepProvider.notifier).run();

    expect(llm.batches.map((b) => b.length), [2, 2, 1]);
    expect(stored(c).where((i) => i.needsQuiz), isEmpty);
    final a = stored(c).firstWhere((i) => i.id == 'a');
    expect(a.quizQuestion, 'What about a?');
    expect(a.extraQuizzes.map((q) => q.question), ['Why a?', 'When a?']);
    expect(a.back, 'What about answer a', reason: 'answer-less notes get the answer');
  });

  test('a practice queue jumps the line', () async {
    final (c, llm) = await setUpWith(['a', 'b', 'c', 'd', 'e']);
    addTearDown(c.dispose);
    final queue = stored(c).where((i) => i.id == 'd' || i.id == 'e').toList();
    await c.read(quizPrepProvider.notifier).prepare(queue);

    expect(llm.batches.first, unorderedEquals(['d', 'e']));
    final byId = {for (final i in stored(c)) i.id: i};
    expect(byId['d']!.needsQuiz, isFalse);
    expect(byId['e']!.needsQuiz, isFalse);
  });

  test('unusable quizzes are not saved and give up after max attempts', () async {
    final (c, llm) = await setUpWith(['a']);
    addTearDown(c.dispose);
    llm.garble = true;
    final prep = c.read(quizPrepProvider.notifier);
    await prep.run();
    await prep.run();

    expect(llm.batches, hasLength(2));
    expect(stored(c).single.needsQuiz, isTrue);
  });

  test('a rate limit pauses generation', () async {
    final (c, llm) = await setUpWith(['a', 'b', 'c']);
    addTearDown(c.dispose);
    llm.failWith = const LlmException(LlmErrorKind.rateLimited, 'slow down',
        retryAfter: Duration(minutes: 1));
    await c.read(quizPrepProvider.notifier).run();

    expect(llm.batches, hasLength(1));
    final state = c.read(quizPrepProvider);
    expect(state.isPaused, isTrue);
    expect(state.pause, AiPause.rateLimited);
  });

  test('a rejected key pauses until the user acts', () async {
    final (c, llm) = await setUpWith(['a']);
    addTearDown(c.dispose);
    llm.failWith = const LlmException(LlmErrorKind.auth, 'bad key');
    await c.read(quizPrepProvider.notifier).run();
    expect(c.read(quizPrepProvider).pause, AiPause.auth);
    expect(c.read(quizPrepProvider).pausedUntil, isNull);

    llm.failWith = null;
    await c.read(quizPrepProvider.notifier).retryNow();
    expect(c.read(quizPrepProvider).isPaused, isFalse);
    expect(stored(c).single.needsQuiz, isFalse);
  });

  test('a grade recorded mid-request is kept', () async {
    final (c, llm) = await setUpWith(['a']);
    addTearDown(c.dispose);
    llm.duringRequest = () => c
        .read(knowledgeListProvider.notifier)
        .grade(stored(c).single, ReviewGrade.good);
    await c.read(quizPrepProvider.notifier).run();

    final a = stored(c).single;
    expect(a.lastCorrect, isTrue);
    expect(a.repetitions, 1);
    expect(a.needsQuiz, isFalse);
  });

  test('the asked question rotates with each review', () async {
    final (c, _) = await setUpWith(['a']);
    addTearDown(c.dispose);
    await c.read(quizPrepProvider.notifier).run();
    final asked = <String>[];
    for (var i = 0; i < 4; i++) {
      final a = stored(c).single;
      asked.add(a.practicePrompt);
      await c.read(knowledgeListProvider.notifier).grade(a, ReviewGrade.good);
    }
    expect(asked, ['What about a?', 'Why a?', 'When a?', 'What about a?']);
  });

  test('flagging drops the shown question; the last one triggers a rewrite', () async {
    final (c, llm) = await setUpWith(['a']);
    addTearDown(c.dispose);
    final prep = c.read(quizPrepProvider.notifier);
    await prep.run();
    final notifier = c.read(knowledgeListProvider.notifier);

    for (final expected in ['What about a?', 'Why a?', 'When a?']) {
      final a = stored(c).single;
      expect(a.practicePrompt, expected);
      await notifier.persist(a.dropActiveQuiz());
    }
    final a = stored(c).single;
    expect(a.needsQuiz, isTrue);
    expect(a.badQuestions, ['What about a?', 'Why a?', 'When a?']);

    // The rewrite can't bring back a flagged question.
    await prep.retryNow();
    // 1 initial batch + up to maxAttemptsPerNote (2) tries at a rewrite.
    expect(llm.batches, hasLength(3));
    expect(stored(c).single.needsQuiz, isTrue,
        reason: 'the fake AI only knows the three flagged questions');
  });

  test('editing a note drops its stale quiz', () async {
    final (c, _) = await setUpWith(['a']);
    addTearDown(c.dispose);
    await c.read(quizPrepProvider.notifier).run();
    final a = stored(c).single;
    expect(a.needsQuiz, isFalse);

    await c.read(knowledgeListProvider.notifier).updateItem(a,
        front: 'a different fact', back: a.back, type: a.type, category: null);
    expect(stored(c).single.needsQuiz, isTrue);
    expect(stored(c).single.mcAnswer, isNull);
  });
}
