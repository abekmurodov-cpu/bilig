import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge/src/data/settings_repository.dart';
import 'package:knowledge/src/l10n/app_strings.dart';
import 'package:knowledge/src/providers/knowledge_providers.dart';
import 'package:knowledge/src/providers/settings_providers.dart';
import 'package:knowledge/src/providers/study_providers.dart';
import 'package:knowledge/src/ui/widgets/study_cards.dart';

import 'key_ideas_test.dart' show note;
import 'widget_test.dart' show FakeRepository;

void main() {
  testWidgets('the exam card on Home changes and removes its exam', (tester) async {
    final repo = FakeRepository();
    await repo.save(note('a', 'Q1', back: 'A', category: 'Algebra'));
    await repo.save(note('m', 'Q2', back: 'A', category: 'Mobile'));
    final container = ProviderContainer(overrides: [
      knowledgeRepositoryProvider.overrideWithValue(repo),
      settingsRepositoryProvider.overrideWithValue(SettingsRepository.memory()),
    ]);
    addTearDown(container.dispose);
    final today = DateUtils.dateOnly(DateTime.now());
    await container.read(examsProvider.notifier).set('Mobile', today.add(const Duration(days: 10)));

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        localizationsDelegates: [AppStrings.delegate],
        home: Scaffold(body: ExamCards()),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Mobile exam in 10 days'), findsOneWidget);

    // Tapping the card opens the dialog on that exam, not the first category.
    await tester.tap(find.text('Mobile exam in 10 days'));
    await tester.pumpAndSettle();
    expect(find.text('Remove exam'), findsOneWidget);

    // A new day from the calendar.
    await tester.tap(find.byIcon(Icons.event).last);
    await tester.pumpAndSettle();
    final day = today.add(const Duration(days: 12));
    if (day.month != today.add(const Duration(days: 10)).month) {
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('${day.day}').last);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(container.read(examsProvider)['Mobile'], day);
    expect(find.text('Mobile exam in 12 days'), findsOneWidget);

    // The pencil opens it too; remove it.
    await tester.tap(find.byIcon(Icons.edit_calendar_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove exam'));
    await tester.pumpAndSettle();
    expect(container.read(examsProvider).containsKey('Mobile'), isFalse);
    expect(find.textContaining('Mobile exam'), findsNothing);
  });
}
