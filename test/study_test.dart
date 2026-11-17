import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge/src/llm/llm_provider.dart';
import 'package:knowledge/src/models/knowledge_item.dart';
import 'package:knowledge/src/providers/knowledge_providers.dart';
import 'package:knowledge/src/providers/study_providers.dart';
import 'package:knowledge/src/scheduler/spaced_repetition.dart';

import 'key_ideas_test.dart' show CannedLlm, note;
import 'widget_test.dart' show FakeRepository;

void main() {
  group('AI grading', () {
    final item = note('n', 'What does ATP store?', back: 'Energy');

    Future<LlmGrade> grade(String reply) => CannedLlm(reply).gradeAnswer(item, 'x');

    test('correct / partial / wrong verdicts', () async {
      final partial = await grade('{"verdict": "partial", "feedback": "Missing what kind."}');
      expect((partial.correct, partial.partial), (true, true));
      expect(partial.feedback, 'Missing what kind.');
      final wrong = await grade('{"verdict": "Wrong"}');
      expect((wrong.correct, wrong.partial), (false, false));
      final old = await grade('{"correct": true}');
      expect((old.correct, old.partial), (true, false));
    });

    test('the grading prompt asks for the three verdicts', () async {
      final llm = CannedLlm('{"verdict": "correct"}');
      await llm.gradeAnswer(item, 'energy');
      expect(llm.lastPrompt, contains('"partial"'));
    });

    test('why was I wrong: question, answer and the student’s pick go in',
        () async {
      final llm = CannedLlm('ATP stores energy in its bonds.\n💡 A Tiny Power-pack.');
      final text = await llm.explainMistake(item,
          question: 'What does ATP store?', answer: 'Energy', studentAnswer: 'Water');
      expect(text, contains('💡'));
      expect(llm.lastPrompt, contains('Student answered: Water'));
    });
  });

  group('streaks', () {
    final today = DateTime(2026, 3, 10, 18);
    Map<String, DayActivity> days(List<int> ago) => {
          for (final d in ago)
            dayKey(today.subtract(Duration(days: d))): const DayActivity(reviews: 3),
        };

    test('counts back from today, or from yesterday before studying today', () {
      expect(currentStreak(days([0, 1, 2, 4]), now: today), 3);
      expect(currentStreak(days([1, 2]), now: today), 2);
      expect(currentStreak(days([2, 3]), now: today), 0);
    });

    test('longest run ever', () {
      expect(longestStreak(days([0, 5, 6, 7, 8, 20])), 4);
    });
  });

  test('grading uses the exam date, counts the day, and undo takes it back',
      () async {
    final repo = FakeRepository();
    final item = note('n', 'Q', back: 'A', category: 'Bio');
    await repo.save(item);
    final c = ProviderContainer(overrides: [
      knowledgeRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(c.dispose);
    await c.read(knowledgeListProvider.future);
    final examDay = DateTime.now().add(const Duration(days: 3));
    await c.read(examsProvider.notifier).set('Bio', examDay);
    expect(c.read(examsProvider.notifier).upcoming('Bio'), isNotNull);

    final store = c.read(knowledgeListProvider.notifier);
    // Learned well: without the exam this would be weeks away.
    await store.grade(item, ReviewGrade.easy);
    final graded = c.read(knowledgeListProvider).requireValue.single;
    expect(graded.dueDate.isBefore(DateTime(examDay.year, examDay.month, examDay.day)),
        isTrue);
    expect(c.read(activityProvider)[dayKey(DateTime.now())]!.reviews, 1);

    // Meanwhile the AI added a question; undo keeps it.
    await store.persist(graded.putQuiz(const QuizVariant(
        question: 'New?', answer: 'Yes', distractors: ['No', 'Maybe'])));
    await store.undoGrade(item, ReviewGrade.easy);
    final undone = c.read(knowledgeListProvider).requireValue.single;
    expect(undone.lastReviewedAt, isNull);
    expect(undone.stability, isNull);
    expect(undone.quizVariants.single.question, 'New?');
    expect(c.read(activityProvider), isEmpty);
  });
}
