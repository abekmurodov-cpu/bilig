import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge/src/models/knowledge_item.dart';
import 'package:knowledge/src/llm/prompted_llm.dart';
import 'package:knowledge/src/models/note_search.dart';
import 'package:knowledge/src/practice/answer_matching.dart';
import 'package:knowledge/src/practice/practice_models.dart';
import 'package:knowledge/src/practice/text_blanks.dart';
import 'package:knowledge/src/providers/knowledge_providers.dart';

import 'widget_test.dart' show FakeRepository;

KnowledgeItem note(String id, String front,
    {String? back,
    List<String> highlights = const [],
    String? category,
    KnowledgeType type = KnowledgeType.fact,
    int reps = 0}) {
  final now = DateTime(2026, 11, 16);
  return KnowledgeItem(
    id: id,
    front: front,
    back: back,
    type: type,
    category: category,
    createdAt: now,
    dueDate: now,
    repetitions: reps,
    highlights: highlights,
  );
}

String filled(TextBlanks b) {
  var out = b.template;
  for (var i = 0; i < b.answers.length; i++) {
    out = out.replaceAll('«$i»', b.answers[i]);
  }
  return out;
}

void main() {
  group('fill in the blank on any note', () {
    test('blanks the highlights in the answer, with the prompt as the cue', () {
      final b = textBlanks(note('p', 'Photosynthesis',
          back: 'Plants make glucose and oxygen in the chloroplasts.',
          highlights: const ['glucose', 'chloroplasts']))!;
      expect(b.cue, 'Photosynthesis');
      expect(b.answers, ['glucose', 'chloroplasts']);
      expect(b.template, 'Plants make «0» and oxygen in the «1».');
      expect(filled(b), 'Plants make glucose and oxygen in the chloroplasts.');
    });

    test('without highlights it picks key words: names and numbers first', () {
      final b = textBlanks(note('w', 'World War II',
          back: 'It ended in 1945 after Germany and then Japan surrendered to the Allies.'))!;
      expect(b.answers, isNotEmpty);
      expect(b.answers.length, lessThanOrEqualTo(maxTextBlanks));
      expect(b.answers, contains('1945'));
      expect(filled(b), contains('surrendered'));
    });

    test('never blanks vague words, the cue\'s words, or too much', () {
      final spill = note('t', 'Technology Spillover',
          back: 'When a tech company invents something great (like microchips or AI), '
              'other companies learn from it and improve too. This is a Technology '
              'Spillover (a positive externality).');
      final others = [
        spill,
        for (var i = 0; i < 8; i++)
          note('o$i', 'Market $i',
              back: 'Many companies compete, and something about prices changes.'),
      ];
      final stats = WordStats(others);
      for (var reps = 0; reps < 4; reps++) {
        final b = textBlanks(note('t', spill.front, back: spill.back, reps: reps),
            stats: stats)!;
        expect(b.answers.length, lessThanOrEqualTo(2));
        for (final a in b.answers) {
          expect(['something', 'great', 'companies', 'Technology', 'Spillover'],
              isNot(contains(a)));
        }
      }
      final first = textBlanks(spill, stats: stats)!;
      expect(first.answers, contains('externality'));
    });

    test('question answers found in the text are blanked first', () {
      final b = textBlanks(note('q', 'TCP',
              back: 'TCP opens a connection with a three-way handshake of SYN, SYN-ACK and ACK.')
          .copyWith(quizQuestion: 'How does TCP open a connection?', mcAnswer: 'A three-way handshake'))!;
      expect(b.answers, isNotEmpty);
    });

    test('works in Uzbek and Russian text', () {
      final uz = textBlanks(note('u', 'Amudaryo',
          back: 'Amudaryo Pomir tog‘laridan boshlanib, Orol dengiziga quyiladi.'))!;
      expect(uz.answers, isNotEmpty);
      final ru = textBlanks(note('r', 'Митохондрии',
          back: 'Часть клетки, которая превращает пищу в энергию.'))!;
      expect(ru.answers, isNot(contains('которая')));
    });

    test('a note with only a prompt blanks the prompt itself', () {
      final b = textBlanks(note('f', 'The Amazon is the largest rainforest on Earth.'))!;
      expect(b.cue, isNull);
      expect(b.answers, isNotEmpty);
    });

    test('too short to recall anything from gives nothing', () {
      expect(textBlanks(note('s', 'Tokyo')), isNull);
    });

    test('the words asked rotate with reviews', () {
      const back = 'Mitochondria convert glucose into adenosine triphosphate '
          'through cellular respiration inside eukaryotic organisms.';
      final first = textBlanks(note('m', 'Mitochondria', back: back))!.answers;
      final later = textBlanks(note('m', 'Mitochondria', back: back, reps: 1))!.answers;
      expect(later, isNot(equals(first)));
    });

    test('typed words are forgiven small typos, not other words', () {
      expect(blankMatches('Chloroplast', 'chloroplasts'), isTrue);
      expect(blankMatches('glucose', 'Glucose'), isTrue);
      expect(blankMatches('oxygen', 'glucose'), isFalse);
      expect(blankMatches('кожа', 'Кожа'), isTrue);
      expect(blankMatches('', 'ATP'), isFalse);
    });

    test('practice queue takes ordinary notes, and code notes with code', () {
      final all = [
        note('a', 'Osmosis', back: 'Water moving through a membrane towards more solute.'),
        note('b', 'Tokyo'),
        note('c', 'Loop over a list',
            back: 'for item in items:\n    print(item)', type: KnowledgeType.code),
      ];
      const config =
          PracticeConfig(method: PracticeMethod.fillBlank, scope: PracticeScope.all);
      final ids = config.buildQueue(all: all, due: const []).map((n) => n.id);
      expect(ids, containsAll(['a', 'c']));
      expect(ids, isNot(contains('b')));
    });
  });

  test('answers in Cyrillic are compared letter by letter', () {
    expect(normalizeAnswer('Кожа!'), 'кожа');
    expect(isAnswerCorrect('Токио', 'Токио.'), isTrue);
    expect(isAnswerCorrect('Париж', 'Токио'), isFalse);
  });

  group('categories', () {
    Future<ProviderContainer> store(List<KnowledgeItem> notes) async {
      final repo = FakeRepository();
      for (final n in notes) {
        await repo.save(n);
      }
      final c = ProviderContainer(overrides: [
        knowledgeRepositoryProvider.overrideWithValue(repo),
      ]);
      await c.read(knowledgeListProvider.future);
      return c;
    }

    test('a typed name joins the category it matches, ignoring case', () async {
      final c = await store([note('a', 'Osmosis', category: 'Biology')]);
      addTearDown(c.dispose);
      await c.read(knowledgeListProvider.notifier).addItem(
          front: 'Mitochondria', type: KnowledgeType.concept, category: '  biology ');
      await c.read(knowledgeListProvider.notifier).addItem(
          front: 'Rome', type: KnowledgeType.fact, category: 'History');
      expect(c.read(categoriesProvider), ['Biology', 'History']);
      final info = c.read(categoryInfoProvider);
      expect({for (final i in info) i.name: i.count}, {'Biology': 2, 'History': 1});
    });

    test('search can be narrowed to categories', () {
      final notes = [
        note('a', 'Osmosis', category: 'Biology'),
        note('b', 'Mitosis', category: 'Biology'),
        note('c', 'Osmanli', category: 'History'),
        note('d', 'Osmium'),
      ];
      List<String> ids(String q, Set<String> cats) =>
          [for (final n in searchNotes(notes, q, categories: cats)) n.id];
      expect(ids('', {'Biology'}), ['a', 'b']);
      expect(ids('osm', {'History', ''}), ['c', 'd']);
      expect(ids('osm', {}), ['a', 'c', 'd']);
    });
  });

  group('topics', () {
    Future<ProviderContainer> store(List<KnowledgeItem> notes) async {
      final repo = FakeRepository();
      for (final n in notes) {
        await repo.save(n);
      }
      final c = ProviderContainer(overrides: [
        knowledgeRepositoryProvider.overrideWithValue(repo),
      ]);
      await c.read(knowledgeListProvider.future);
      return c;
    }

    List<KnowledgeItem> all(ProviderContainer c) =>
        c.read(knowledgeListProvider).requireValue;

    test('a note keeps its topic through saving, and a topic needs a category', () async {
      final c = await store([note('a', 'Osmosis', category: 'Biology').withPlace('Biology', 'Cells')]);
      addTearDown(c.dispose);
      final store_ = c.read(knowledgeListProvider.notifier);
      await store_.addItem(
          front: 'Mitosis', type: KnowledgeType.concept, category: 'biology', topic: ' cells ');
      await store_.addItem(front: 'Loose', type: KnowledgeType.fact, topic: 'Cells');
      final byFront = {for (final n in all(c)) n.front: n};
      expect(byFront['Mitosis']!.category, 'Biology');
      expect(byFront['Mitosis']!.topic, 'Cells');
      expect(byFront['Loose']!.topic, isNull);
      expect(KnowledgeItem.fromMap(byFront['Mitosis']!.toMap()).topic, 'Cells');
      expect(c.read(topicInfoProvider)['Biology']!.single.count, 2);
    });

    test('moving, sorting and renaming', () async {
      final c = await store([
        note('a', 'Osmosis', category: 'Biology'),
        note('b', 'Mendel', category: 'Biology'),
        note('c', 'Rome', category: 'History'),
      ]);
      addTearDown(c.dispose);
      final s = c.read(knowledgeListProvider.notifier);
      await s.setTopics('Biology', {'a': 'Cells', 'b': 'Genetics'});
      await s.moveNotes({'c'}, 'Biology', 'genetics');
      var byId = {for (final n in all(c)) n.id: n};
      expect([byId['a']!.topic, byId['b']!.topic, byId['c']!.topic],
          ['Cells', 'Genetics', 'Genetics']);
      expect(byId['c']!.category, 'Biology');

      await s.rename('Biology', 'Heredity', topic: 'Genetics');
      await s.rename('Biology', 'Bio');
      byId = {for (final n in all(c)) n.id: n};
      expect(byId['b']!.category, 'Bio');
      expect(byId['b']!.topic, 'Heredity');
      expect(byId['a']!.topic, 'Cells');

      await s.rename('Bio', '', topic: 'Cells');
      expect({for (final n in all(c)) n.id: n}['a']!.topic, isNull);

      // Editing a note can clear its category.
      await s.updateItem(byId['c']!, front: 'Rome', type: KnowledgeType.fact, category: '');
      final c2 = {for (final n in all(c)) n.id: n}['c']!;
      expect((c2.category, c2.topic), (null, null));
    });

    test('practice and search narrow to one topic', () {
      final notes = [
        note('a', 'Osmosis', back: 'Water moves.', category: 'Bio').withPlace('Bio', 'Cells'),
        note('b', 'Mendel', back: 'Peas.', category: 'Bio').withPlace('Bio', 'Genetics'),
        note('c', 'Mitosis', back: 'Division.', category: 'Bio'),
      ];
      const config = PracticeConfig(
          method: PracticeMethod.flashcard,
          scope: PracticeScope.category,
          category: 'Bio',
          topic: 'Cells');
      expect(config.buildQueue(all: notes, due: const []).map((n) => n.id), ['a']);
      expect([for (final n in searchNotes(notes, '', categories: {topicKey('Bio', 'Genetics')})) n.id],
          ['b']);
      expect(searchNotes(notes, '', categories: {'Bio'}).length, 3);
    });

    test("the AI's topics are read by note number", () {
      final notes = [note('a', 'Osmosis'), note('b', 'Mendel'), note('c', 'Mitosis')];
      final topics = PromptedLlm.parseTopics(notes,
          '{"topics": [{"name": "Cells", "notes": [1, 3, 9]}, {"name": "Genetics", "notes": ["2"]}]}');
      expect(topics, {'a': 'Cells', 'c': 'Cells', 'b': 'Genetics'});
    });
  });
}
