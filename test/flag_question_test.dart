import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:knowledge/src/data/settings_repository.dart';
import 'package:knowledge/src/l10n/app_strings.dart';
import 'package:knowledge/src/models/knowledge_item.dart';
import 'package:knowledge/src/practice/practice_models.dart';
import 'package:knowledge/src/providers/knowledge_providers.dart';
import 'package:knowledge/src/providers/settings_providers.dart';
import 'package:knowledge/src/ui/practice/practice_session_screen.dart';

import 'widget_test.dart' show FakeRepository;

void main() {
  late SettingsRepository settings;
  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync().path);
    settings = await SettingsRepository.open();
  });

  testWidgets('flagging an answered question undoes its grade and drops it',
      (tester) async {
    final now = DateTime(2026, 11, 11);
    final note = KnowledgeItem(
      id: 'n',
      front: 'TCP opens a connection with a three-way handshake',
      type: KnowledgeType.fact,
      createdAt: now,
      dueDate: now,
      quizQuestion: 'How does TCP open a connection?',
      mcAnswer: 'A three-way handshake',
      mcDistractors: const ['A single SYN packet', 'A UDP broadcast', 'A TLS hello'],
      extraQuizzes: const [
        QuizVariant(
          question: 'Which packets make up a TCP handshake?',
          answer: 'SYN, SYN-ACK, ACK',
          distractors: ['SYN, ACK, FIN', 'GET, POST, PUT', 'HELLO, KEY, DONE'],
        ),
      ],
    );
    final repo = FakeRepository();
    await repo.save(note);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        knowledgeRepositoryProvider.overrideWithValue(repo),
        settingsRepositoryProvider.overrideWithValue(settings),
      ],
      child: MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        home: PracticeSessionScreen(
          config: const PracticeConfig(
            method: PracticeMethod.multipleChoice,
            scope: PracticeScope.all,
          ),
          queue: [note],
        ),
      ),
    ));
    await tester.pump();

    await tester.tap(find.text('A UDP broadcast'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect((await repo.getAll()).single.lapses, 1, reason: 'the wrong answer was graded');

    await tester.tap(find.byIcon(Icons.thumb_down_alt_outlined));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();

    final stored = (await repo.getAll()).single;
    expect(stored.lapses, 0);
    expect(stored.lastCorrect, isNull);
    expect(stored.practicePrompt, 'Which packets make up a TCP handshake?');
    expect(stored.badQuestions, ['How does TCP open a connection?']);
    expect(find.textContaining('doesn’t count'), findsOneWidget);
  });
}
