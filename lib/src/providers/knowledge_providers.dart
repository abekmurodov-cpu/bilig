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
    await _repo.save(item);
    await _refresh();
  }

  /// Saves several new notes at once (from a photo, a paste or an import),
  /// with one list refresh. A [category] is given to every note, or with
  /// [onlyMissing] only to notes that have none.
  Future<void> addDrafts(List<NoteDraft> drafts,
      {String? category, bool onlyMissing = false}) async {
    final now = DateTime.now();
    final typed = _existingCategory(category);
    for (final d in drafts) {
      final back = d.back?.trim();
      final code = d.type == KnowledgeType.code ? back ?? '' : '';
      final drills = code.isNotEmpty ? generateCodeDrills(code) : null;
      await _repo.save(KnowledgeItem(
        id: _uuid.v4(),
        front: d.front.trim(),
        back: back == null || back.isEmpty ? null : back,
        type: d.type,
        category: onlyMissing
            ? (_existingCategory(d.category) ?? typed)
            : (typed ?? _existingCategory(d.category)),
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
      await _repo.save(save.copyWith(hasImage: image != null));
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
      await _repo.delete(id);
      await _images.delete(id);
    }
    await _refresh();
    return doomed.length;
  }

  /// Persists an already-built item (bumping [updatedAt] for sync). Used by the
  /// practice flow to cache a generated answer / multiple-choice quiz.
  Future<void> persist(KnowledgeItem item) async {
    await _repo.save(item.copyWith(updatedAt: DateTime.now()));
    await _refresh();
  }

  /// Persists several items with a single list refresh (for batch AI results).
  Future<void> persistAll(Iterable<KnowledgeItem> items) async {
    final now = DateTime.now();
    for (final item in items) {
      await _repo.save(item.copyWith(updatedAt: now));
    }
    await _refresh();
  }

  /// Attaches (or replaces) an image on an existing note.
  Future<void> setImage(KnowledgeItem item, Uint8List bytes) async {
    await _images.putBytes(item.id, bytes);
    await _repo.save(item.copyWith(hasImage: true, updatedAt: DateTime.now()));
    await _refresh();
  }

  /// Removes a note's image.
  Future<void> removeImage(KnowledgeItem item) async {
    await _images.delete(item.id);
    await _repo.save(item.copyWith(hasImage: false, updatedAt: DateTime.now()));
    await _refresh();
  }

  /// Records a review outcome, reschedules the item (around its category's
  /// exam, if one is coming), counts it for the day, and persists it.
  Future<void> grade(KnowledgeItem item, ReviewGrade grade) async {
    final exam = ref.read(examsProvider.notifier).upcoming(item.category);
    final updated =
        ref.read(_schedulerProvider).schedule(item, grade, examDate: exam);
    await _repo.save(updated);
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
    await _repo.save(KnowledgeItem.fromMap({
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
    final updated = base.copyWith(
      front: newFront,
      back: newBack,
      type: type,
      category: _existingCategory(category),
      highlights: keptHighlights(item.highlights, newFront, newBack),
      tags: tags,
      updatedAt: DateTime.now(),
    );
    await _repo.save(updated);
    await _refresh();
  }

  /// Sets the note's marked key ideas. The AI's questions are rewritten
  /// around them (the student's own questions stay).
  Future<void> setHighlights(KnowledgeItem item, List<String> highlights) async {
    final updated = item.withoutAiQuizzes().copyWith(
      highlights: highlights,
      updatedAt: DateTime.now(),
    );
    await _repo.save(updated);
    await _refresh();
  }

  Future<void> delete(String id) async {
    await _repo.delete(id);
    await _images.delete(id);
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

  Future<void> _refresh() async {
    state = AsyncData(await _repo.getAll());
  }
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

/// Distinct category names present in the store (excludes the synthetic
/// ungrouped bucket) — used to populate the practice "category" picker.
final categoriesProvider = Provider<List<String>>((ref) {
  final groups = ref.watch(notesByCategoryProvider);
  return groups.keys.where((k) => k != kUngroupedCategory).toList();
});
