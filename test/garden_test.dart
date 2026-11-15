import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge/src/models/knowledge_item.dart';
import 'package:knowledge/src/providers/stats.dart';
import 'package:knowledge/src/providers/study_providers.dart';
import 'package:knowledge/src/ui/widgets/category_tree.dart';
import 'package:knowledge/src/ui/widgets/tree_model.dart';

import 'key_ideas_test.dart' show note;

void main() {
  final now = DateTime(2026, 6, 20, 12);

  KnowledgeItem reviewed({required int dueInDays, bool correct = true, int interval = 5}) =>
      note('n', 'Q', back: 'A').copyWith(
        lastReviewedAt: now.subtract(const Duration(days: 30)),
        dueDate: now.add(Duration(days: dueInDays)),
        lastCorrect: correct,
        intervalDays: interval,
        stability: interval.toDouble(),
      );

  group('leaves', () {
    test('green, gold, wilting after days overdue, fallen after weeks', () {
      expect(leafLook(reviewed(dueInDays: 3), now: now), LeafLook.green);
      expect(leafLook(note('n', 'new'), now: now), LeafLook.gold);
      expect(leafLook(reviewed(dueInDays: -1), now: now), LeafLook.gold);
      expect(leafLook(reviewed(dueInDays: -5), now: now), LeafLook.wilting);
      expect(leafLook(reviewed(dueInDays: -20), now: now), LeafLook.fallen);
    });

    test('a never-reviewed note never falls', () {
      final old = note('n', 'old').copyWith(dueDate: now.subtract(const Duration(days: 60)));
      expect(leafLook(old, now: now), LeafLook.gold);
    });

    test('blossoms when all green, fruit when settled', () {
      final green = [for (var i = 0; i < 3; i++) reviewed(dueInDays: 5)];
      expect(treeBloom(green, now: now), TreeBloom.blossom);
      expect(treeBloom([for (var i = 0; i < 3; i++) reviewed(dueInDays: 25, interval: 25)], now: now),
          TreeBloom.fruit);
      expect(treeBloom([...green, note('x', 'new')], now: now), TreeBloom.none);
      expect(treeBloom(green.take(2).toList(), now: now), TreeBloom.none);
    });

    test('a fallen leaf is tapped where it lies', () {
      final model = TreeModel.generate(count: 3, seed: 'Bio');
      final ground = model.fallenSlot(1);
      final tip = ground.position + Offset.fromDirection(ground.angle, TreeModel.leafLength / 2);
      expect(model.leafAt(tip, fallen: const [false, true, false]), 1);
    });
  });

  group('stats', () {
    test('stages: new, learning, learned', () {
      final s = noteStages([
        note('a', 'new'),
        reviewed(dueInDays: 2),
        reviewed(dueInDays: 30, interval: 30),
        reviewed(dueInDays: 30, interval: 30, correct: false),
      ]);
      expect((s.fresh, s.learning, s.learned), (1, 2, 1));
    });

    test('recall now is 90% one stability after the review', () {
      final n = note('a', 'Q').copyWith(
          lastReviewedAt: now.subtract(const Duration(days: 10)), stability: 10);
      expect(averageRecall([n], now: now), closeTo(0.9, 0.001));
      expect(averageRecall([note('b', 'new')], now: now), isNull);
    });

    test('upcoming: overdue counts today', () {
      expect(upcomingReviews([
        reviewed(dueInDays: -3),
        reviewed(dueInDays: 0),
        reviewed(dueInDays: 2),
        reviewed(dueInDays: 9),
      ], now: now), [2, 0, 1, 0, 0, 0, 0]);
    });

    test('weekly recall sums Monday-based weeks', () {
      // 2026-06-20 is a Saturday; its week starts Monday the 15th.
      final weeks = weeklyRecall({
        '2026-06-15': const DayActivity(reviews: 4, correct: 3),
        '2026-06-20': const DayActivity(reviews: 6, correct: 6),
        '2026-06-14': const DayActivity(reviews: 2, correct: 0),
      }, now: now, weeks: 2);
      expect(weeks.map((w) => (w.start.day, w.reviews, w.correct)), [(8, 2, 0), (15, 10, 9)]);
    });
  });
}
