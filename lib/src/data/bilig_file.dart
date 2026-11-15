import 'dart:convert';
import 'dart:typed_data';

import '../models/knowledge_item.dart';

/// What a .bilig file holds.
enum BiligFileKind {
  /// Every note with its review progress, for restoring.
  backup,

  /// One category without anyone's progress, to give to classmates.
  share,
}

/// A .bilig file: notes (and their images) as JSON. Used for backups and
/// for sharing a category with classmates.
class BiligFile {
  const BiligFile({
    required this.kind,
    required this.notes,
    this.images = const {},
    this.title,
  });

  final BiligFileKind kind;
  final List<KnowledgeItem> notes;

  /// Note id → base64 image.
  final Map<String, String> images;

  /// The shared category's name.
  final String? title;

  static const _format = 'bilig';
  static const _version = 1;

  Uint8List encode() => Uint8List.fromList(utf8.encode(jsonEncode({
        'format': _format,
        'version': _version,
        'kind': kind.name,
        'exportedAt': DateTime.now().toIso8601String(),
        if (title != null) 'title': title,
        'notes': [for (final n in notes) n.toMap()],
        'images': images,
      })));

  static BiligFile decode(Uint8List bytes) {
    final Object? data;
    try {
      data = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      throw const FormatException('Not a Bilig file');
    }
    if (data is! Map || data['format'] != _format) {
      throw const FormatException('Not a Bilig file');
    }
    final notes = <KnowledgeItem>[];
    for (final raw in (data['notes'] as List?) ?? const []) {
      try {
        notes.add(KnowledgeItem.fromMap(Map<String, dynamic>.from(raw as Map)));
      } catch (_) {
        // Skip a damaged note rather than refuse the whole file.
      }
    }
    return BiligFile(
      kind: data['kind'] == 'share' ? BiligFileKind.share : BiligFileKind.backup,
      notes: notes,
      images: {
        for (final e in ((data['images'] as Map?) ?? const {}).entries)
          '${e.key}': '${e.value}',
      },
      title: data['title'] as String?,
    );
  }

  /// A note as shared with someone else: content, questions and highlights,
  /// but none of the sender's progress or rejected questions.
  static KnowledgeItem withoutProgress(KnowledgeItem note, {DateTime? now}) {
    final at = (now ?? DateTime.now()).toIso8601String();
    return KnowledgeItem.fromMap({
      ...note.toMap(),
      for (final k in KnowledgeItem.reviewFields) k: null,
      'repetitions': 0,
      'easeFactor': 2.5,
      'intervalDays': 0,
      'lapses': 0,
      'dueDate': at,
      'createdAt': at,
      'updatedAt': at,
      'badQuestions': const <String>[],
    });
  }
}
