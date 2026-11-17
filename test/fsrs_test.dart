import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge/src/models/knowledge_item.dart';
import 'package:knowledge/src/scheduler/spaced_repetition.dart';

void main() {
  const fsrs = SpacedRepetition();
  final day0 = DateTime(2026, 3, 1, 9);

  KnowledgeItem fresh() => KnowledgeItem(
        id: 'n',
        front: 'What is FSRS?',
        back: 'A spaced-repetition scheduler.',
        type: KnowledgeType.question,
        createdAt: day0,
        dueDate: day0,
      );

  test('recall odds are 90% after one stability-length', () {
    expect(SpacedRepetition.retrievability(10, 10), closeTo(0.9, 1e-9));
  });

  test('first review: harder ratings come back sooner', () {
    int days(ReviewGrade g) => fsrs.schedule(fresh(), g, now: day0).intervalDays;
    expect(days(ReviewGrade.again), 1);
    expect(days(ReviewGrade.hard), lessThanOrEqualTo(days(ReviewGrade.good)));
    expect(days(ReviewGrade.good), lessThan(days(ReviewGrade.easy)));
    expect(fsrs.schedule(fresh(), ReviewGrade.easy, now: day0).intervalDays, 16);
  });

  test('intervals grow with each on-time "good" review', () {
    var item = fresh();
    var now = day0;
    final intervals = <int>[];
    for (var i = 0; i < 4; i++) {
      item = fsrs.schedule(item, ReviewGrade.good, now: now);
      intervals.add(item.intervalDays);
      now = item.dueDate.add(const Duration(hours: 9));
    }
    for (var i = 1; i < intervals.length; i++) {
      expect(intervals[i], greaterThan(intervals[i - 1]));
    }
    expect(item.repetitions, 4);
    expect(item.difficulty, isNotNull);
  });

  test('forgetting drops stability and counts a lapse', () {
    final learned = fsrs.schedule(fresh(), ReviewGrade.easy, now: day0);
    final forgot = fsrs.schedule(learned, ReviewGrade.again,
        now: learned.dueDate.add(const Duration(days: 3)));
    expect(forgot.stability, lessThan(learned.stability!));
    expect(forgot.lapses, 1);
    expect(forgot.lastCorrect, isFalse);
    expect(forgot.intervalDays, 1);
  });

  test('a note reviewed only under SM-2 keeps its progress', () {
    final old = fresh().copyWith(
        repetitions: 5, intervalDays: 40, easeFactor: 2.5,
        lastReviewedAt: day0.subtract(const Duration(days: 40)));
    final next = fsrs.schedule(old, ReviewGrade.good, now: day0);
    expect(next.intervalDays, greaterThan(40));
  });

  test('an upcoming exam keeps the next review before the exam day', () {
    final learned = fsrs.schedule(fresh(), ReviewGrade.easy, now: day0);
    final exam = DateTime(2026, 3, 8);
    final next = fsrs.schedule(learned, ReviewGrade.easy,
        now: DateTime(2026, 3, 3, 9), examDate: exam);
    expect(next.dueDate.isBefore(exam), isTrue);
    expect(next.dueDate, DateTime(2026, 3, 7));
  });
}
