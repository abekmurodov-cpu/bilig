import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge/src/models/knowledge_item.dart';
import 'package:knowledge/src/ui/widgets/category_tree.dart';
import 'package:knowledge/src/ui/widgets/tree_model.dart';

final now = DateTime(2026, 1, 10);

KnowledgeItem note(bool? lastCorrect, {DateTime? due}) => KnowledgeItem(
      id: 'x',
      front: 'q',
      type: KnowledgeType.fact,
      createdAt: DateTime(2026, 1, 1),
      dueDate: due ?? DateTime(2026, 2, 1),
      lastCorrect: lastCorrect,
    );

void main() {
  group('leafColor', () {
    test('new / never-reviewed note is autumn gold', () {
      expect(leafColor(note(null), now: now), autumnLeafColor);
    });

    test('last-wrong note is autumn gold', () {
      expect(leafColor(note(false), now: now), autumnLeafColor);
    });

    test('recalled note that is not due is green', () {
      expect(leafColor(note(true), now: now), summerLeafColor);
    });

    test('recalled note that is due again turns gold', () {
      expect(leafColor(note(true, due: DateTime(2026, 1, 5)), now: now),
          autumnLeafColor);
    });
  });

  group('TreeModel', () {
    test('has exactly one leaf per note', () {
      for (final n in [1, 2, 3, 7, 30, 120, 900]) {
        expect(TreeModel.generate(count: n, seed: 'c').leaves.length, n);
      }
    });

    test('grows with note count', () {
      final small = TreeModel.generate(count: 2, seed: 'c');
      final big = TreeModel.generate(count: 60, seed: 'c');
      expect(big.size.height, greaterThan(small.size.height * 1.5));
      expect(big.trunkWidth, greaterThan(small.trunkWidth));
    });

    test('adding a note within a stage keeps existing leaves in place', () {
      final a = TreeModel.generate(count: 14, seed: 'c');
      final b = TreeModel.generate(count: 15, seed: 'c');
      expect(a.stage, b.stage);
      for (var i = 0; i < a.leaves.length; i++) {
        expect(b.leaves[i].position, a.leaves[i].position);
      }
    });
  });
}
