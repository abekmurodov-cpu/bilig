import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge/src/data/anki_import.dart';
import 'package:knowledge/src/data/bilig_file.dart';
import 'package:knowledge/src/data/image_store.dart';
import 'package:knowledge/src/data/sample_notes.dart';
import 'package:knowledge/src/l10n/app_strings.dart';
import 'package:knowledge/src/models/knowledge_item.dart';
import 'package:knowledge/src/models/note_search.dart';
import 'package:knowledge/src/practice/cloze.dart';
import 'package:knowledge/src/providers/knowledge_providers.dart';
import 'package:hive_ce/hive_ce.dart';

import 'key_ideas_test.dart' show note;
import 'widget_test.dart' show FakeRepository;

void main() {
  group('Anki import', () {
    for (final name in ['legacy', 'new']) {
      test('$name .apkg: fields, decks, tags, cloze, long and many notes', () {
        final drafts =
            importAnkiPackage(File('test/fixtures/$name.apkg').readAsBytesSync());
        expect(drafts, hasLength(304));
        final q = drafts.first;
        expect(q.front, 'What is the powerhouse of the cell?');
        expect(q.back, 'Mitochondria\n(makes ATP)');
        expect(q.type, KnowledgeType.question);
        expect(q.category, 'Biology');
        expect(q.tags, ['biology', 'exam1']);

        final cloze = drafts[1];
        expect(cloze.front, 'Paris is the capital of France.');
        expect(cloze.highlights, ['Paris', 'France']);
        expect(cloze.back, 'Extra & info');

        expect(drafts[2].back, 'Water moving across a membrane');
        expect(drafts[3].back, 'x' * 9000, reason: 'read across overflow pages');
        expect(drafts[3].category, isNull, reason: 'the Default deck is no category');
        expect(drafts.last.front, 'Term 299');
      });
    }

    test('a non-Anki file is refused', () {
      expect(() => importAnkiPackage(Uint8List.fromList([1, 2, 3])),
          throwsA(isA<FormatException>()));
    });

    test('plain text exports: Anki headers, tabs, quotes; Quizlet commas', () {
      final anki = importDelimitedText('#separator:tab\n#html:true\n'
          'Capital of Italy\tRome\n"Quoted, with comma"\t"He said ""hi"""\n');
      expect([for (final d in anki) '${d.front}|${d.back}'],
          ['Capital of Italy|Rome', 'Quoted, with comma|He said "hi"']);
      final quizlet = importDelimitedText('hund,dog\nkatze,cat\n');
      expect(quizlet.map((d) => d.back), ['dog', 'cat']);
    });
  });

  test('tags are cleaned when typed', () {
    expect(KnowledgeItem.parseTags('#Exam, week 3,exam,, ##hard'), ['Exam', 'week 3', 'hard']);
  });

  group('search', () {
    final notes = [
      note('a', 'Mitochondria', back: 'Makes ATP', category: 'Bio'),
      note('b', 'ATP synthase', back: 'An enzyme'),
      note('c', 'O‘zbekiston poytaxti', back: 'Toshkent'),
    ];

    test('every word must match; prompt matches come first', () {
      expect(searchNotes(notes, 'atp').map((n) => n.id), ['b', 'a']);
      expect(searchNotes(notes, 'atp bio').map((n) => n.id), ['a']);
      expect(searchNotes(notes, 'nothing'), isEmpty);
    });

    test('apostrophes and case are ignored', () {
      expect(searchNotes(notes, "o'zbekiston").single.id, 'c');
      expect(searchNotes(notes, 'OZBEKISTON').single.id, 'c');
    });

    test('tags filter', () {
      final tagged = [
        ...notes,
        note('d', 'Tagged', back: 'x').copyWith(tags: ['Exam1']),
      ];
      expect(searchNotes(tagged, '', tags: {'exam1'}).single.id, 'd');
    });
  });

  test('sample notes: every language, highlights found in the text, blanks work',
      () {
    for (final language in AppLanguage.values) {
      final samples = sampleNotes(language);
      expect(samples, hasLength(8));
      for (final s in samples) {
        expect(s.tags.single, isIn(sampleTags));
        for (final h in s.highlights) {
          expect('${s.front}\n${s.back}'.toLowerCase(), contains(h.toLowerCase()),
              reason: '${language.name}: "$h" in ${s.front}');
        }
        if (s.highlights.isNotEmpty) {
          expect(clozeQuiz(s, samples), isNotNull, reason: s.front);
        }
      }
    }
  });

  group('.bilig files', () {
    late ImageStore images;
    setUpAll(() async {
      Hive.init(Directory.systemTemp.createTempSync().path);
      images = ImageStore(await Hive.openBox<String>('img_test'));
    });

    Future<ProviderContainer> store(List<KnowledgeItem> notes) async {
      final repo = FakeRepository();
      for (final n in notes) {
        await repo.save(n);
      }
      final c = ProviderContainer(overrides: [
        knowledgeRepositoryProvider.overrideWithValue(repo),
        imageStoreProvider.overrideWithValue(images),
      ]);
      await c.read(knowledgeListProvider.future);
      return c;
    }

    test('a backup round-trips and restoring keeps the newer copy', () async {
      final old = note('a', 'Old wording', back: 'x');
      final newer = old.copyWith(front: 'New wording', updatedAt: DateTime(2030));
      final file = BiligFile.decode(BiligFile(
        kind: BiligFileKind.backup,
        notes: [newer, note('b', 'Only in backup')],
        images: const {'b': 'aGk='},
      ).encode());
      final c = await store([old]);
      addTearDown(c.dispose);
      final result = await c.read(knowledgeListProvider.notifier).importFile(file);
      expect((result.added, result.updated), (1, 1));
      final byId = {for (final n in c.read(knowledgeListProvider).requireValue) n.id: n};
      expect(byId['a']!.front, 'New wording');
      expect(byId['b']!.hasImage, isTrue);
      expect(images.getBase64('b'), 'aGk=');
    });

    test('a shared category arrives fresh, as copies, without duplicates', () async {
      final mine = note('m', 'Osmosis', category: 'Bio');
      final theirs = note('x', 'Mitochondria', back: 'ATP', category: 'Bio')
          .copyWith(repetitions: 9, lapses: 3, lastReviewedAt: DateTime(2026), stability: 40)
          .putQuiz(const QuizVariant(question: 'Q?', answer: 'A', distractors: ['B']));
      final c = await store([mine]);
      addTearDown(c.dispose);
      final file = BiligFile(
          kind: BiligFileKind.share,
          title: 'Bio',
          notes: [theirs, note('y', 'osmosis', category: 'Bio')]);
      final result = await c
          .read(knowledgeListProvider.notifier)
          .importFile(BiligFile.decode(file.encode()));
      expect(result.added, 1, reason: 'Osmosis is already there');
      final added =
          c.read(knowledgeListProvider).requireValue.firstWhere((n) => n.front == 'Mitochondria');
      expect(added.id, isNot('x'));
      expect((added.repetitions, added.lapses, added.lastReviewedAt, added.stability),
          (0, 0, null, null));
      expect(added.quizVariants.single.question, 'Q?', reason: 'questions travel along');
    });
  });
}
