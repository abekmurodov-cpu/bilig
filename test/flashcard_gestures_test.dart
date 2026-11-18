import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge/src/l10n/app_strings.dart';
import 'package:knowledge/src/models/knowledge_item.dart';
import 'package:knowledge/src/practice/practice_models.dart';
import 'package:knowledge/src/providers/knowledge_providers.dart';
import 'package:knowledge/src/ui/practice/practice_session_screen.dart';
import 'package:knowledge/src/ui/widgets/flip_card.dart';

import 'key_ideas_test.dart' show note;
import 'widget_test.dart' show FakeRepository;

void main() {
  Future<FakeRepository> open(WidgetTester tester, List<KnowledgeItem> notes) async {
    final repo = FakeRepository();
    for (final n in notes) {
      await repo.save(n);
    }
    await tester.binding.setSurfaceSize(const Size(500, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [knowledgeRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        home: PracticeSessionScreen(
          config: const PracticeConfig(
              method: PracticeMethod.flashcard, scope: PracticeScope.all),
          queue: notes,
        ),
      ),
    ));
    await tester.pump();
    return repo;
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 500));
  }

  final a = note('a', 'Capital of Japan?', back: 'Tokyo');
  final b = note('b', 'Capital of Italy?', back: 'Rome');

  testWidgets('keyboard: Space flips, 1 grades Again, ⌘Z undoes', (tester) async {
    final repo = await open(tester, [a, b]);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Again'), findsOneWidget, reason: 'grades show after flipping');

    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await settle(tester);
    expect((await repo.getAll()).firstWhere((n) => n.id == 'a').lapses, 1);
    expect(find.text('Capital of Italy?'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await settle(tester);
    final undone = (await repo.getAll()).firstWhere((n) => n.id == 'a');
    expect((undone.lapses, undone.lastReviewedAt), (0, null));
    expect(find.text('Capital of Japan?'), findsOneWidget, reason: 'back on that card');
  });

  testWidgets('swiping right after flipping grades Good; not before', (tester) async {
    final repo = await open(tester, [a, b]);
    await tester.drag(find.byType(SwipeCard), const Offset(400, 0));
    await settle(tester);
    expect(find.text('Capital of Japan?'), findsOneWidget, reason: 'not flipped yet');
    expect(find.text(const AppStrings(AppLanguage.en).flipBeforeSwipe), findsOneWidget,
        reason: 'says why the swipe did nothing');

    await tester.tap(find.byType(FlipCard));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.drag(find.byType(SwipeCard), const Offset(400, 0));
    await settle(tester);
    final graded = (await repo.getAll()).firstWhere((n) => n.id == 'a');
    expect((graded.lastCorrect, graded.repetitions), (true, 1));
    expect(find.text('Capital of Italy?'), findsOneWidget);
    expect(find.byIcon(Icons.undo), findsOneWidget);
  });
}
