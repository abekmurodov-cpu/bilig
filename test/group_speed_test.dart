import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:knowledge/src/data/image_store.dart';
import 'package:knowledge/src/data/settings_repository.dart';
import 'package:knowledge/src/llm/ai_log.dart';
import 'package:knowledge/src/llm/llm_provider.dart';
import 'package:knowledge/src/models/knowledge_item.dart';
import 'package:knowledge/src/providers/knowledge_providers.dart';
import 'package:knowledge/src/providers/settings_providers.dart';

import 'fallback_llm_test.dart' show NamedLlm;
import 'widget_test.dart' show FakeRepository;

KnowledgeItem note(String id, String front, {bool image = false}) {
  final now = DateTime(2026, 11, 16);
  return KnowledgeItem(
      id: id, front: front, type: KnowledgeType.fact, createdAt: now, dueDate: now, hasImage: image);
}

void main() {
  late ImageStore images;
  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync().path);
    images = ImageStore(await Hive.openBox<String>('img_speed'));
  });

  test('deleting many notes can be undone, images included', () async {
    final repo = FakeRepository();
    for (final n in [note('a', 'One', image: true), note('b', 'Two'), note('c', 'Three')]) {
      await repo.save(n);
    }
    await images.putBase64('a', 'aGk=');
    final c = ProviderContainer(overrides: [
      knowledgeRepositoryProvider.overrideWithValue(repo),
      imageStoreProvider.overrideWithValue(images),
    ]);
    addTearDown(c.dispose);
    await c.read(knowledgeListProvider.future);
    final store = c.read(knowledgeListProvider.notifier);
    final deleted = await store.deleteMany({'a', 'b'});
    expect(c.read(knowledgeListProvider).requireValue.map((n) => n.id), ['c']);
    expect(images.getBase64('a'), isNull);
    await store.restore(deleted);
    expect(c.read(knowledgeListProvider).requireValue.map((n) => n.id).toSet(), {'a', 'b', 'c'});
    expect(images.getBase64('a'), 'aGk=');
    // The list in memory matches what is stored.
    expect((await repo.getAll()).length, 3);
  });

  test('every AI request is logged with its outcome', () async {
    final c = ProviderContainer(overrides: [
      settingsRepositoryProvider.overrideWithValue(SettingsRepository.memory()),
    ]);
    addTearDown(c.dispose);
    final log = c.read(aiLogProvider.notifier);
    final ok = LoggedLlm(NamedLlm('main'), log.add);
    final failing = NamedLlm('backup')
      ..failWith = const LlmException(LlmErrorKind.rateLimited, 'Groq rate limit reached');
    final bad = LoggedLlm(failing, log.add);
    await ok.suggestCategory('x', null);
    await expectLater(bad.suggestCategory('x', null), throwsA(isA<LlmException>()));
    final entries = c.read(aiLogProvider);
    expect(entries.length, 2);
    expect(entries.first.error, 'Groq rate limit reached');
    expect(entries.first.kind, LlmErrorKind.rateLimited);
    expect(entries.last.ok, isTrue);
    expect(entries.first.task, 'suggestCategory');
  });
}
