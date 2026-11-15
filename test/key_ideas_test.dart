import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:knowledge/src/data/settings_repository.dart';
import 'package:knowledge/src/l10n/app_strings.dart';
import 'package:knowledge/src/llm/llm_provider.dart';
import 'package:knowledge/src/llm/prompted_llm.dart';
import 'package:knowledge/src/models/knowledge_item.dart';
import 'package:knowledge/src/practice/cloze.dart';
import 'package:knowledge/src/practice/practice_models.dart';
import 'package:knowledge/src/providers/knowledge_providers.dart';
import 'package:knowledge/src/providers/settings_providers.dart';
import 'package:knowledge/src/ui/practice/practice_session_screen.dart';

import 'widget_test.dart' show FakeRepository;

/// Replies with a fixed text to every prompt.
class CannedLlm extends PromptedLlm {
  CannedLlm(this.reply);
  final String reply;
  String? lastPrompt;

  @override
  Future<String> complete(String prompt,
      {bool json = false, List<Attachment> attachments = const []}) async {
    lastPrompt = prompt;
    return reply;
  }

  @override
  String get displayName => 'canned';
}

KnowledgeItem note(String id, String front,
    {String? back, List<String> highlights = const [], String? category, int reps = 0}) {
  final now = DateTime(2026, 11, 15);
  return KnowledgeItem(
    id: id,
    front: front,
    back: back,
    type: KnowledgeType.fact,
    category: category,
    createdAt: now,
    dueDate: now,
    repetitions: reps,
    highlights: highlights,
  );
}

void main() {
  group('fill-in-the-blank from highlights', () {
    final krebs = note('k', 'Cell respiration',
        back: 'The Krebs cycle runs in the mitochondria. It produces NADH and FADH2.',
        highlights: const ['Krebs cycle', 'NADH'],
        category: 'Bio');

    test('blanks the highlighted idea in its sentence', () {
      final quiz = clozeQuiz(krebs, const [])!;
      expect(quiz.question, 'The _____ runs in the mitochondria.');
      expect(quiz.answer, 'Krebs cycle');
    });

    test('asks a different highlight after each review', () {
      final quiz = clozeQuiz(
          note('k', krebs.front, back: krebs.back, highlights: krebs.highlights, reps: 1),
          const [])!;
      expect(quiz.question, 'It produces _____ and FADH2.');
      expect(quiz.answer, 'NADH');
    });

    test('skips a highlight that leaves too little to go on', () {
      expect(clozeQuiz(note('m', 'Mitochondria', highlights: const ['Mitochondria']), const []),
          isNull);
    });

    test('wrong options: own highlights, then same category, then others', () {
      final others = [
        note('a', 'x', highlights: const ['photosynthesis'], category: 'Chem'),
        note('b', 'y', highlights: const ['glycolysis', 'krebs cycles'], category: 'Bio'),
      ];
      expect(clozeQuiz(krebs, others)!.distractors,
          ['NADH', 'glycolysis', 'photosynthesis'],
          reason: '"krebs cycles" is too close to the answer');
    });

    test('no option that already shows in the sentence', () {
      final item = note('k', 'Respiration',
          back: 'The Krebs cycle produces NADH.', highlights: const ['Krebs cycle', 'NADH']);
      expect(clozeQuiz(item, const [])!.distractors, isEmpty);
    });
  });

  group('suggested key ideas', () {
    final item = note('k', 'The Krebs cycle runs in the mitochondria');

    test('keeps only phrases really in the note, at most four', () async {
      final llm = CannedLlm('{"highlights": ["Krebs cycle", "krebs cycle", '
          '"powerhouse of the cell", "mitochondria.", "runs", "The", "cycle"]}');
      expect(await llm.suggestHighlights(item),
          ['Krebs cycle', 'mitochondria', 'runs', 'The']);
      expect(llm.lastPrompt, contains('EXACTLY'));
    });

    test('an unusable reply is a bad response', () async {
      expect(CannedLlm('sure!').suggestHighlights(item),
          throwsA(isA<LlmException>()
              .having((e) => e.kind, 'kind', LlmErrorKind.badResponse)));
    });
  });

  testWidgets('without any AI, a note with highlights is asked as a blank',
      (tester) async {
    Hive.init(Directory.systemTemp.createTempSync().path);
    late SettingsRepository settings;
    await tester.runAsync(() async => settings = await SettingsRepository.open());
    final item = note('k', 'Cell respiration',
        back: 'The Krebs cycle runs in the mitochondria.',
        highlights: const ['Krebs cycle', 'mitochondria', 'ATP synthase', 'Cell']);
    final repo = FakeRepository();
    await repo.save(item);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        knowledgeRepositoryProvider.overrideWithValue(repo),
        settingsRepositoryProvider.overrideWithValue(settings),
      ],
      child: MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        home: PracticeSessionScreen(
          config: const PracticeConfig(
              method: PracticeMethod.multipleChoice, scope: PracticeScope.all),
          queue: [item],
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('The _____ runs in the mitochondria.'), findsOneWidget);
    await tester.tap(find.text('Krebs cycle'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect((await repo.getAll()).single.lastCorrect, isTrue);
  });
}
