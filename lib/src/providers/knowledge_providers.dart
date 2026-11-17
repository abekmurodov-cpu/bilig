import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../data/bilig_file.dart';
import '../data/image_store.dart';
import '../data/knowledge_repository.dart';
import '../llm/llm_provider.dart';
import '../models/highlights.dart';
import '../models/knowledge_item.dart';
import '../practice/code_drills.dart';
import '../scheduler/spaced_repetition.dart';
import 'study_providers.dart';

/// Bound to the concrete repository in `main` via a ProviderScope override.
final knowledgeRepositoryProvider = Provider<KnowledgeRepository>((ref) {
  throw UnimplementedError('knowledgeRepositoryProvider must be overridden');
});

/// Bound to the concrete image store in `main` via a ProviderScope override.
final imageStoreProvider = Provider<ImageStore>((ref) {
  throw UnimplementedError('imageStoreProvider must be overridden');
});

final _schedulerProvider =
    Provider<SpacedRepetition>((ref) => const SpacedRepetition());

const _uuid = Uuid();

/// Owns the full list of knowledge items and all mutations to it.
class KnowledgeListNotifier extends AsyncNotifier<List<KnowledgeItem>> {
  KnowledgeRepository get _repo => ref.read(knowledgeRepositoryProvider);
  ImageStore get _images => ref.read(imageStoreProvider);

  @override
  Future<List<KnowledgeItem>> build() => _repo.getAll();

  Future<void> addItem({
    required String front,
    String? back,
    required KnowledgeType type,
    String? category,
    String? topic,
    Uint8List? imageBytes,
    String? quizQuestion,
    String? mcAnswer,
    List<String> mcDistractors = const [],
    List<String> highlights = const [],
    List<String> tags = const [],
  }) async {
    final now = DateTime.now();
    final id = _uuid.v4();
    if (imageBytes != null) {
      await _images.putBytes(id, imageBytes);
    }
    // Code notes get their fill-in-the-blank / reorder drills pre-generated
    // now (deterministically, no LLM) so those modes never cost API credits.
    // The code snippet lives in the answer/details field (back); the prompt
    // (front) is the description of what it does.
    final code = back?.trim() ?? '';
    final drills = type == KnowledgeType.code && code.isNotEmpty
        ? generateCodeDrills(code)
        : null;
    final item = KnowledgeItem(
      id: id,
      front: front.trim(),
      back: back?.trim().isEmpty ?? true ? null : back!.trim(),
      type: type,
      category: _existingCategory(category),
      topic: _existingTopic(category, topic),
      createdAt: now,
      dueDate: now, // due immediately so it appears in the first review
      hasImage: imageBytes != null,
      quizQuestion: quizQuestion,
      mcAnswer: mcAnswer,
      mcDistractors: mcDistractors,
      fillBlankTemplate: drills?.fillBlankTemplate,
      fillBlankAnswers: drills?.fillBlankAnswers ?? const [],
      reorderSegments: drills?.reorderSegments ?? const [],
      highlights: keptHighlights(highlights, front.trim(), back?.trim()),
      tags: tags,
    );
    await _save(item);
    await _refresh();
  }

  /// Saves several new notes at once (from a photo, a paste or an import),
  /// with one list refresh. A [category] is given to every note, or with
  /// [onlyMissing] only to notes that have none.
  Future<void> addDrafts(List<NoteDraft> drafts,
      {String? category, String? topic, bool onlyMissing = false}) async {
    final now = DateTime.now();
    final typed = _existingCategory(category);
    final typedTopic = _existingTopic(category, topic);
    for (final d in drafts) {
      final back = d.back?.trim();
      final code = d.type == KnowledgeType.code ? back ?? '' : '';
      final drills = code.isNotEmpty ? generateCodeDrills(code) : null;
      await _save(KnowledgeItem(
        id: _uuid.v4(),
        front: d.front.trim(),
        back: back == null || back.isEmpty ? null : back,
        type: d.type,
        category: onlyMissing
            ? (_existingCategory(d.category) ?? typed)
            : (typed ?? _existingCategory(d.category)),
        // The topic goes with the typed category only.
        topic: (onlyMissing ? d.category == null : typed != null) ? typedTopic : null,
        createdAt: now,
        dueDate: now,
        fillBlankTemplate: drills?.fillBlankTemplate,
        fillBlankAnswers: drills?.fillBlankAnswers ?? const [],
        reorderSegments: drills?.reorderSegments ?? const [],
        highlights: keptHighlights(d.highlights, d.front, back),
        tags: d.tags,
      ));
    }
    await _refresh();
  }

  /// Brings in notes from a .bilig file. A backup restores: notes already
  /// here keep whichever copy was changed last. A shared file adds copies
  /// with fresh ids and no progress, skipping notes already present (same
  /// prompt in the same category). Returns how many notes were added and
  /// how many were updated.
  Future<({int added, int updated})> importFile(BiligFile file) async {
    final current = {
      for (final i in state.asData?.value ?? const <KnowledgeItem>[]) i.id: i,
    };
    String key(KnowledgeItem i) =>
        '${i.front.trim().toLowerCase()}\u0000${i.category?.trim().toLowerCase()}';
    final present = {for (final i in current.values) key(i)};
    var added = 0, updated = 0;
    for (final note in file.notes) {
      KnowledgeItem? save;
      if (file.kind == BiligFileKind.share) {
        if (!present.add(key(note))) continue;
        save = KnowledgeItem.fromMap(
            {...BiligFile.withoutProgress(note).toMap(), 'id': _uuid.v4()});
        added++;
      } else {
        final mine = current[note.id];
        if (mine == null) {
          save = note;
          added++;
        } else if (note.updatedAt.isAfter(mine.updatedAt)) {
          save = note;
          updated++;
        }
      }
      if (save == null) continue;
      final image = file.images[note.id];
      if (image != null) await _images.putBase64(save.id, image);
      // Files carry every image their notes have.
      await _save(save.copyWith(hasImage: image != null));
    }
    await _refresh();
    return (added: added, updated: updated);
  }

  /// Deletes every note carrying one of [tags] (e.g. the sample notes).
  Future<int> deleteTagged(Set<String> tags) async {
    final doomed = [
      for (final i in state.asData?.value ?? const <KnowledgeItem>[])
        if (i.tags.any((t) => tags.contains(t.toLowerCase()))) i.id,
    ];
    for (final id in doomed) {
      await _delete(id);
      await _images.delete(id);
    }
    await _refresh();
    return doomed.length;
  }

  /// Persists an already-built item (bumping [updatedAt] for sync). Used by the
  /// practice flow to cache a generated answer / multiple-choice quiz.
  Future<void> persist(KnowledgeItem item) async {
    await _save(item.copyWith(updatedAt: DateTime.now()));
    await _refresh();
  }

  /// Persists several items with a single list refresh (for batch AI results).
  Future<void> persistAll(Iterable<KnowledgeItem> items) async {
    final now = DateTime.now();
    for (final item in items) {
      await _save(item.copyWith(updatedAt: now));
    }
    await _refresh();
  }

  /// Attaches (or replaces) an image on an existing note.
  Future<void> setImage(KnowledgeItem item, Uint8List bytes) async {
    await _images.putBytes(item.id, bytes);
    await _save(item.copyWith(hasImage: true, updatedAt: DateTime.now()));
    await _refresh();
  }

  /// Removes a note's image.
  Future<void> removeImage(KnowledgeItem item) async {
    await _images.delete(item.id);
    await _save(item.copyWith(hasImage: false, updatedAt: DateTime.now()));
    await _refresh();
  }

  /// Records a review outcome, reschedules the item (around its category's
  /// exam, if one is coming), counts it for the day, and persists it.
  Future<void> grade(KnowledgeItem item, ReviewGrade grade) async {
    final exam = ref.read(examsProvider.notifier).upcoming(item.category);
    final updated =
        ref.read(_schedulerProvider).schedule(item, grade, examDate: exam);
    await _save(updated);
    await ref
        .read(activityProvider.notifier)
        .record(correct: grade != ReviewGrade.again);
    await _refresh();
  }

  /// Takes back a grade: restores [before] (the note as it was) and
  /// uncounts the review.
  Future<void> undoGrade(KnowledgeItem before, ReviewGrade grade) async {
    // Only the review is undone; anything else that changed on the note
    // since (e.g. questions written meanwhile) stays.
    final current = [
      for (final i in state.asData?.value ?? const <KnowledgeItem>[])
        if (i.id == before.id) i,
    ].firstOrNull ?? before;
    final old = before.toMap();
    await _save(KnowledgeItem.fromMap({
      ...current.toMap(),
      for (final k in KnowledgeItem.reviewFields) k: old[k],
      'updatedAt': DateTime.now().toIso8601String(),
    }));
    await ref
        .read(activityProvider.notifier)
        .record(correct: grade != ReviewGrade.again, undo: true);
    await _refresh();
  }

  /// Edits a note's content fields and persists it, bumping [updatedAt] so the
  /// change wins during sync.
  Future<void> updateItem(
    KnowledgeItem item, {
    required String front,
    String? back,
    required KnowledgeType type,
    String? category,
    String? topic,
    List<String>? tags,
  }) async {
    final contentChanged = item.front != front.trim() ||
        (item.back ?? '') != (back?.trim() ?? '') ||
        item.type != type;
    final newFront = front.trim();
    final newBack = back?.trim().isEmpty ?? true ? null : back!.trim();
    // AI questions written for the old wording would now be wrong; the
    // student's own questions are theirs to keep or change.
    final base = contentChanged
        ? item.withoutAiQuizzes().copyWith(badQuestions: const [])
        : item;
    final updated = base
        .copyWith(
          front: newFront,
          back: newBack,
          type: type,
          highlights: keptHighlights(item.highlights, newFront, newBack),
          tags: tags,
          updatedAt: DateTime.now(),
        )
        .withPlace(_existingCategory(category), _existingTopic(category, topic));
    await _save(updated);
    await _refresh();
  }

  /// Sets the note's marked key ideas. The AI's questions are rewritten
  /// around them (the student's own questions stay).
  Future<void> setHighlights(KnowledgeItem item, List<String> highlights) async {
    final updated = item.withoutAiQuizzes().copyWith(
      highlights: highlights,
      updatedAt: DateTime.now(),
    );
    await _save(updated);
    await _refresh();
  }

  Future<void> delete(String id) async {
    await deleteMany({id});
  }

  /// Deletes the notes with [ids] at once, keeping what [restore] needs to
  /// bring them back (the Undo after a delete).
  Future<DeletedNotes> deleteMany(Set<String> ids) async {
    final notes = <KnowledgeItem>[];
    final images = <String, String>{};
    for (final item in state.asData?.value ?? const <KnowledgeItem>[]) {
      if (!ids.contains(item.id)) continue;
      notes.add(item);
      final image = item.hasImage ? _images.getBase64(item.id) : null;
      if (image != null) images[item.id] = image;
      await _delete(item.id);
      await _images.delete(item.id);
    }
    await _refresh();
    return DeletedNotes(notes, images);
  }

  /// Brings deleted notes back as they were.
  Future<void> restore(DeletedNotes deleted) async {
    final now = DateTime.now();
    for (final item in deleted.notes) {
      final image = deleted.images[item.id];
      if (image != null) await _images.putBase64(item.id, image);
      await _save(item.copyWith(updatedAt: now));
    }
    await _refresh();
  }

  /// [typed] as a category: blank is none, and a name that only differs in
  /// case or spacing from one in use ("biology " for "Biology") is that one,
  /// so a category isn't split in two by a typo.
  String? _existingCategory(String? typed) {
    final name = typed?.trim().replaceAll(RegExp(r'\s+'), ' ') ?? '';
    if (name.isEmpty) return null;
    final key = name.toLowerCase();
    for (final item in state.asData?.value ?? const <KnowledgeItem>[]) {
      final c = item.category?.trim();
      if (c != null && c.toLowerCase() == key) return c;
    }
    return name;
  }

  /// [typed] as a topic of [category], matched to one already in use there
  /// like [_existingCategory]; none without a category.
  String? _existingTopic(String? category, String? typed) {
    final inCategory = _existingCategory(category);
    final name = typed?.trim().replaceAll(RegExp(r'\s+'), ' ') ?? '';
    if (inCategory == null || name.isEmpty) return null;
    final key = name.toLowerCase();
    for (final item in state.asData?.value ?? const <KnowledgeItem>[]) {
      final t = item.topic?.trim();
      if (item.category == inCategory && t != null && t.toLowerCase() == key) return t;
    }
    return name;
  }

  /// Moves the notes with [ids] to [category] and [topic] (a topic only
  /// with a category).
  Future<void> moveNotes(Set<String> ids, String? category, String? topic) async {
    final place = _existingCategory(category);
    final inTopic = _existingTopic(category, topic);
    final now = DateTime.now();
    for (final item in state.asData?.value ?? const <KnowledgeItem>[]) {
      if (!ids.contains(item.id)) continue;
      await _save(item.withPlace(place, inTopic).copyWith(updatedAt: now));
    }
    await _refresh();
  }

  /// Sets topics in [category] from [topicById] (note id → topic, or null
  /// for no topic); other notes are untouched.
  Future<void> setTopics(String category, Map<String, String?> topicById) async {
    final now = DateTime.now();
    for (final item in state.asData?.value ?? const <KnowledgeItem>[]) {
      if (item.category != category || !topicById.containsKey(item.id)) continue;
      final topic = topicById[item.id]?.trim();
      if (topic == item.topic) continue;
      await _save(item
          .withPlace(category, topic == null || topic.isEmpty ? null : topic)
          .copyWith(updatedAt: now));
    }
    await _refresh();
  }

  /// Renames a category (merging into one of that name if it exists), or
  /// with [topic], a topic within it. An empty [to] removes the topic.
  Future<void> rename(String category, String to, {String? topic}) async {
    final now = DateTime.now();
    final name = to.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (topic == null && name.isEmpty) return;
    final target = topic == null ? _existingCategory(name) : null;
    final newTopic = topic == null ? null : _existingTopic(category, name);
    for (final item in state.asData?.value ?? const <KnowledgeItem>[]) {
      if (item.category != category) continue;
      if (topic == null) {
        await _save(item.withPlace(target, item.topic).copyWith(updatedAt: now));
      } else if (item.topic == topic) {
        await _save(item.withPlace(category, newTopic).copyWith(updatedAt: now));
      }
    }
    if (topic == null && target != category) {
      final exams = ref.read(examsProvider.notifier);
      final date = ref.read(examsProvider)[category];
      if (date != null) {
        await exams.set(category, null);
        await exams.set(target!, date);
      }
    }
    await _refresh();
  }

  /// Changes saved since the list on screen was last updated.
  final Map<String, KnowledgeItem> _changed = {};
  final Set<String> _deleted = {};

  Future<void> _save(KnowledgeItem item) async {
    await _repo.save(item);
    _deleted.remove(item.id);
    _changed[item.id] = item;
  }

  Future<void> _delete(String id) async {
    await _repo.delete(id);
    _changed.remove(id);
    _deleted.add(id);
  }

  /// Shows what was saved: patched into the list in memory, rather than
  /// reading every note back from storage after each change (a grade, an
  /// edit), which got slow with thousands of notes.
  Future<void> _refresh() async {
    final current = state.asData?.value;
    if (current == null) {
      state = AsyncData(await _repo.getAll());
    } else {
      final known = <String>{};
      final next = <KnowledgeItem>[
        for (final item in current)
          if (!_deleted.contains(item.id)) ...[
            if (known.add(item.id)) _changed[item.id] ?? item,
          ],
      ];
      for (final item in _changed.values) {
        if (known.add(item.id)) next.add(item);
      }
      state = AsyncData(next);
    }
    _changed.clear();
    _deleted.clear();
  }
}

/// Notes just deleted, kept for Undo.
class DeletedNotes {
  const DeletedNotes(this.notes, this.images);

  final List<KnowledgeItem> notes;

  /// Note id → its image, base64.
  final Map<String, String> images;
}

final knowledgeListProvider =
    AsyncNotifierProvider<KnowledgeListNotifier, List<KnowledgeItem>>(
  KnowledgeListNotifier.new,
);

/// Items whose due date has arrived, oldest-due first — the review queue.
final dueItemsProvider = Provider<List<KnowledgeItem>>((ref) {
  final items = ref.watch(knowledgeListProvider).asData?.value ?? const [];
  final now = DateTime.now();
  final due = items.where((i) => i.isDue(now)).toList()
    ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  return due;
});

/// Label used to group notes with no category in the tree view.
const String kUngroupedCategory = 'Ungrouped';

/// All notes, newest first — the backing order for the paginated list view.
final notesSortedProvider = Provider<List<KnowledgeItem>>((ref) {
  final items = ref.watch(knowledgeListProvider).asData?.value ?? const [];
  final sorted = List.of(items)
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return sorted;
});

/// Notes grouped by category (uncategorized → [kUngroupedCategory]); one entry
/// per category becomes one tree in the tree view. Categories are alphabetical,
/// with [kUngroupedCategory] last.
final notesByCategoryProvider = Provider<Map<String, List<KnowledgeItem>>>(
    (ref) => groupByCategory(ref.watch(notesSortedProvider)));

/// [items] grouped by category, as in [notesByCategoryProvider].
Map<String, List<KnowledgeItem>> groupByCategory(List<KnowledgeItem> items) {
  final groups = <String, List<KnowledgeItem>>{};
  for (final item in items) {
    final key = (item.category == null || item.category!.trim().isEmpty)
        ? kUngroupedCategory
        : item.category!.trim();
    (groups[key] ??= <KnowledgeItem>[]).add(item);
  }
  final keys = groups.keys.toList()
    ..sort((a, b) {
      if (a == kUngroupedCategory) return 1;
      if (b == kUngroupedCategory) return -1;
      return a.toLowerCase().compareTo(b.toLowerCase());
    });
  return {for (final k in keys) k: groups[k]!};
}

/// Every tag in use with how many notes carry it, most used first.
final tagsProvider = Provider<List<(String, int)>>((ref) {
  final counts = <String, int>{};
  final names = <String, String>{};
  for (final item in ref.watch(notesSortedProvider)) {
    for (final tag in item.tags) {
      final key = tag.toLowerCase();
      names.putIfAbsent(key, () => tag);
      counts[key] = (counts[key] ?? 0) + 1;
    }
  }
  final out = [for (final e in counts.entries) (names[e.key]!, e.value)]
    ..sort((a, b) => b.$2 != a.$2 ? b.$2 - a.$2 : a.$1.compareTo(b.$1));
  return out;
});

/// A category in use: its name, how many notes it has and when one was last
/// added to it.
typedef CategoryInfo = ({String name, int count, DateTime lastUsed});

/// Every category, the most recently used first: the choices offered while
/// writing a note.
final categoryInfoProvider = Provider<List<CategoryInfo>>((ref) {
  final out = [
    for (final e in ref.watch(notesByCategoryProvider).entries)
      if (e.key != kUngroupedCategory)
        (
          name: e.key,
          count: e.value.length,
          lastUsed: e.value
              .map((n) => n.createdAt)
              .reduce((a, b) => a.isAfter(b) ? a : b),
        ),
  ]..sort((a, b) => b.lastUsed.compareTo(a.lastUsed));
  return out;
});

/// The topics of each category, most recently used first, with their notes.
final topicInfoProvider = Provider<Map<String, List<CategoryInfo>>>((ref) {
  final out = <String, List<CategoryInfo>>{};
  for (final e in ref.watch(notesByCategoryProvider).entries) {
    final byTopic = <String, List<KnowledgeItem>>{};
    for (final n in e.value) {
      final t = n.topic?.trim();
      if (t != null && t.isNotEmpty) (byTopic[t] ??= []).add(n);
    }
    if (byTopic.isEmpty) continue;
    out[e.key] = [
      for (final t in byTopic.entries)
        (
          name: t.key,
          count: t.value.length,
          lastUsed: t.value.map((n) => n.createdAt).reduce((a, b) => a.isAfter(b) ? a : b),
        ),
    ]..sort((a, b) => b.lastUsed.compareTo(a.lastUsed));
  }
  return out;
});

/// Distinct category names present in the store (excludes the synthetic
/// ungrouped bucket) — used to populate the practice "category" picker.
final categoriesProvider = Provider<List<String>>((ref) {
  final groups = ref.watch(notesByCategoryProvider);
  return groups.keys.where((k) => k != kUngroupedCategory).toList();
});
