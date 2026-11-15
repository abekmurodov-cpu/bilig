import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge/src/llm/llm_provider.dart';
import 'package:knowledge/src/llm/llm_providers.dart';
import 'package:knowledge/src/llm/prompted_llm.dart';
import 'package:knowledge/src/llm/quiz_prep.dart';
import 'package:knowledge/src/models/highlights.dart';
import 'package:knowledge/src/models/knowledge_item.dart';
import 'package:knowledge/src/providers/knowledge_providers.dart';

import 'quiz_prep_test.dart' show FakeLlm, note, stored;
import 'widget_test.dart' show FakeRepository;

/// Writes a fresh, numbered question every time, as many as asked for.
class CountingLlm extends FakeLlm {
  var _n = 0;
  final asked = <KnowledgeItem>[];

  @override
  Future<Map<String, List<McQuiz>>> generateQuizzes(List<KnowledgeItem> items,
      {int distractorCount = 3, int variantCount = 3}) async {
    asked.addAll(items);
    if (failWith != null) throw failWith!;
    return {
      for (final i in items)
        i.id: [
          for (var k = 0; k < variantCount; k++)
            McQuiz(
              question: 'Question ${++_n}?',
              answer: 'answer $_n',
              distractors: const ['wrong one', 'wrong two', 'wrong three'],
            ),
        ],
    };
  }
}

Future<(ProviderContainer, CountingLlm)> start(KnowledgeItem item) async {
  final repo = FakeRepository();
  await repo.save(item);
  final llm = CountingLlm();
  final c = ProviderContainer(overrides: [
    knowledgeRepositoryProvider.overrideWithValue(repo),
    llmProvider.overrideWithValue(llm),
    quizPrepConfigProvider.overrideWithValue(
        const QuizPrepConfig(debounce: Duration(hours: 1))),
  ]);
  await c.read(knowledgeListProvider.future);
  c.read(quizPrepProvider);
  return (c, llm);
}

const _mine = QuizVariant(
    question: 'My question?', answer: 'mine', distractors: [], manual: true);

void main() {
  group('highlights', () {
    const text = 'The Krebs cycle runs in the mitochondria.';
    ({int start, int end}) word(String w) {
      final at = text.indexOf(w);
      return (start: at, end: at + w.length);
    }

    test('tapping next to a mark joins it into one phrase', () {
      var h = toggleWord(text, const [], word('Krebs'));
      expect(h, ['Krebs']);
      h = toggleWord(text, h, word('cycle'));
      expect(h, ['Krebs cycle']);
      h = toggleWord(text, h, word('mitochondria'));
      expect(h, ['Krebs cycle', 'mitochondria']);
    });

    test('tapping a marked word unmarks its whole phrase', () {
      expect(toggleWord(text, const ['Krebs cycle', 'mitochondria'], word('cycle')),
          ['mitochondria']);
    });

    test('matching ignores case and merges overlaps', () {
      expect(highlightRanges('Cell and cell wall', const ['cell', 'cell wall']),
          [(start: 0, end: 4), (start: 9, end: 18)]);
    });

    test('a selection is trimmed and swallows the marks inside it', () {
      expect(addPhrase(const ['Krebs'], ' Krebs cycle, '), ['Krebs cycle']);
      expect(addPhrase(const ['Krebs cycle'], 'cycle'), ['Krebs cycle']);
      expect(removeAt(text, const ['Krebs cycle', 'mitochondria'], word('Krebs')),
          ['mitochondria']);
    });

    test('editing a note keeps only highlights still in the text', () {
      expect(keptHighlights(const ['ATP', 'Krebs'], 'Makes ATP', null), ['ATP']);
    });
  });

  group('note questions', () {
    test('a student’s own question stops background generation and survives edits',
        () async {
      final item = note('a').putQuiz(_mine);
      expect(item.needsQuiz, isFalse);
      final (c, _) = await start(item);
      addTearDown(c.dispose);
      await c.read(knowledgeListProvider.notifier).updateItem(stored(c).single,
          front: 'changed fact', type: KnowledgeType.fact);
      expect(stored(c).single.quizVariants.single.question, 'My question?');
    });

    test('deleting an AI question remembers it; deleting your own doesn’t', () {
      final item = applyQuizzes(note('a'),
              const [McQuiz(question: 'AI q?', answer: 'x', distractors: ['y', 'z'])])
          .putQuiz(_mine);
      expect(item.removeQuiz(0).badQuestions, ['AI q?']);
      expect(item.removeQuiz(1).badQuestions, isEmpty);
      expect(item.removeQuiz(0).quizVariants.single.manual, isTrue);
    });

    test('+3 adds three new questions after the existing ones', () async {
      final (c, llm) = await start(note('a').putQuiz(_mine));
      addTearDown(c.dispose);
      final added = await c.read(quizPrepProvider.notifier).generateMore('a', count: 3);
      expect(added, 3);
      final variants = stored(c).single.quizVariants;
      expect(variants.map((v) => v.question),
          ['My question?', 'Question 1?', 'Question 2?', 'Question 3?']);
      // The AI was told what the note already has.
      expect(PromptedLlm.quizBatchPrompt(llm.asked, 3),
          contains('already has these questions; write different ones: My question?'));
    });

    test('stops at the per-note limit', () async {
      final (c, _) = await start(note('a'));
      addTearDown(c.dispose);
      final prep = c.read(quizPrepProvider.notifier);
      for (var i = 0; i < 3; i++) {
        await prep.generateMore('a', count: 3);
      }
      expect(stored(c).single.quizVariants.length, KnowledgeItem.maxQuizzes);
      expect(await prep.generateMore('a'), 0);
    });

    test('rewrite replaces one question in place and remembers the old one',
        () async {
      final first = applyQuizzes(note('a'), const [
        McQuiz(question: 'Old 1?', answer: 'a1', distractors: ['x', 'y', 'z']),
        McQuiz(question: 'Old 2?', answer: 'a2', distractors: ['x', 'y', 'z']),
      ]);
      final (c, llm) = await start(first);
      addTearDown(c.dispose);
      expect(await c.read(quizPrepProvider.notifier).rewrite('a', 0), isTrue);
      final item = stored(c).single;
      expect(item.quizVariants.map((v) => v.question), ['Question 1?', 'Old 2?']);
      expect(item.badQuestions, ['Old 1?']);
      expect(llm.asked.single.badQuestions, ['Old 1?']);
    });

    test('a failed rewrite changes nothing', () async {
      final first = applyQuizzes(note('a'), const [
        McQuiz(question: 'Old?', answer: 'a1', distractors: ['x', 'y', 'z']),
      ]);
      final (c, llm) = await start(first);
      addTearDown(c.dispose);
      llm.failWith = const LlmException(LlmErrorKind.rateLimited, 'slow down');
      await expectLater(
          c.read(quizPrepProvider.notifier).rewrite('a', 0), throwsA(isA<LlmException>()));
      expect(stored(c).single.quizVariants.single.question, 'Old?');
      expect(c.read(quizPrepProvider).pause, AiPause.rateLimited);
    });

    test('new highlights drop the AI questions so they are rewritten around them',
        () async {
      final first = applyQuizzes(note('a'), const [
        McQuiz(question: 'Old?', answer: 'a1', distractors: ['x', 'y', 'z']),
      ]).putQuiz(_mine);
      final (c, _) = await start(first);
      addTearDown(c.dispose);
      await c
          .read(knowledgeListProvider.notifier)
          .setHighlights(stored(c).single, const ['fact']);
      final item = stored(c).single;
      expect(item.highlights, ['fact']);
      expect(item.quizVariants.single.manual, isTrue);
      expect(PromptedLlm.quizBatchPrompt([item], 3),
          contains('Key ideas the student highlighted: fact'));
    });
  });
}
