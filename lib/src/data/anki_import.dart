import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../llm/llm_provider.dart';
import '../models/knowledge_item.dart';
import 'sqlite_reader.dart';

/// Reads an Anki deck package (.apkg / .colpkg) into notes. The first field
/// becomes the prompt and the second the answer; the deck becomes the
/// category; Anki tags are kept. Cloze notes ("{{c1::Paris}} is the capital
/// of France") become a note with the cloze answers highlighted, so Bilig
/// asks them as fill-in-the-blanks.
///
/// Handles both the legacy format and the newer zstd-compressed one.
List<NoteDraft> importAnkiPackage(Uint8List package) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(package);
  } catch (_) {
    throw const FormatException('Not an Anki package');
  }
  final Uint8List db;
  final newest = archive.findFile('collection.anki21b');
  if (newest != null) {
    db = ZstdDecoder().decodeBytes(newest.content);
  } else {
    final legacy =
        archive.findFile('collection.anki21') ?? archive.findFile('collection.anki2');
    if (legacy == null) throw const FormatException('No Anki collection inside');
    db = legacy.content;
  }
  return _readCollection(SqliteReader(db));
}

List<NoteDraft> _readCollection(SqliteReader db) {
  // Deck names by id: a table in new collections, JSON in old ones.
  final decks = <int, String>{};
  if (db.hasTable('decks')) {
    for (final row in db.table('decks')) {
      decks[row[0] as int] = '${row[1]}'.replaceAll('\x1f', '::');
    }
  } else if (db.hasTable('col')) {
    final raw = db.table('col').first[10];
    if (raw is String && raw.isNotEmpty) {
      for (final e in (jsonDecode(raw) as Map).entries) {
        decks[int.parse('${e.key}')] = '${(e.value as Map)['name']}';
      }
    }
  }
  final deckOfNote = <int, int>{};
  for (final card in db.table('cards')) {
    deckOfNote.putIfAbsent(card[1] as int, () => card[2] as int);
  }

  final out = <NoteDraft>[];
  final seen = <String>{};
  for (final row in db.table('notes')) {
    final fields = '${row[6]}'.split('\x1f');
    final deck = decks[deckOfNote[row[0]]];
    final category = deck == null || deck == 'Default' ? null : deck.split('::').last;
    final tags = [
      for (final t in '${row[5] ?? ''}'.trim().split(RegExp(r'\s+')))
        if (t.isNotEmpty && t.toLowerCase() != 'leech') t.replaceAll('::', '/'),
    ];
    final draft = _noteFrom(fields, category: category, tags: tags);
    if (draft == null || !seen.add(draft.front.toLowerCase())) continue;
    out.add(draft);
  }
  return out;
}

final _cloze = RegExp(r'\{\{c\d+::(.*?)(?:::(.*?))?\}\}', dotAll: true);

NoteDraft? _noteFrom(List<String> fields,
    {String? category, List<String> tags = const []}) {
  if (fields.isEmpty) return null;
  final first = fields[0];
  final second = fields.length > 1 ? stripHtml(fields[1]) : '';
  if (_cloze.hasMatch(first)) {
    final answers = [for (final m in _cloze.allMatches(first)) stripHtml(m.group(1)!)];
    final text = stripHtml(first.replaceAllMapped(_cloze, (m) => m.group(1)!));
    if (text.isEmpty) return null;
    return NoteDraft(
      front: text,
      back: second.isEmpty ? null : second,
      type: KnowledgeType.fact,
      category: category,
      highlights: [for (final a in answers) if (a.isNotEmpty) a],
      tags: tags,
    );
  }
  final front = stripHtml(first);
  if (front.isEmpty) return null;
  return NoteDraft(
    front: front,
    back: second.isEmpty ? null : second,
    type: front.endsWith('?') ? KnowledgeType.question : KnowledgeType.concept,
    category: category,
    tags: tags,
  );
}

/// Reads text exported from Anki ("Notes in Plain Text"), Quizlet or a
/// spreadsheet: one note per line, prompt and answer separated by a tab (or
/// the separator an Anki "#separator:" header names, or a comma/semicolon
/// when there are no tabs). Anki's "#" header lines are skipped.
List<NoteDraft> importDelimitedText(String text, {String? category}) {
  var separator = '';
  final lines = <String>[];
  for (final line in const LineSplitter().convert(text)) {
    if (line.startsWith('#')) {
      final m = RegExp(r'^#separator:(\w+)', caseSensitive: false).firstMatch(line);
      if (m != null) {
        separator = switch (m.group(1)!.toLowerCase()) {
          'tab' => '\t',
          'comma' => ',',
          'semicolon' => ';',
          'pipe' => '|',
          'space' => ' ',
          final other => other,
        };
      }
      continue;
    }
    if (line.trim().isNotEmpty) lines.add(line);
  }
  if (separator.isEmpty) {
    separator = lines.any((l) => l.contains('\t'))
        ? '\t'
        : (lines.every((l) => l.contains(';')) ? ';' : ',');
  }
  final out = <NoteDraft>[];
  final seen = <String>{};
  for (final line in lines) {
    final fields = _splitCsv(line, separator);
    final draft = _noteFrom(fields, category: category);
    if (draft == null || !seen.add(draft.front.toLowerCase())) continue;
    out.add(draft);
  }
  return out;
}

/// Splits one line on [separator], honouring "double-quoted" fields.
List<String> _splitCsv(String line, String separator) {
  final out = <String>[];
  final field = StringBuffer();
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == '"') {
      if (quoted && i + 1 < line.length && line[i + 1] == '"') {
        field.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (!quoted && line.startsWith(separator, i)) {
      out.add(field.toString());
      field.clear();
      i += separator.length - 1;
    } else {
      field.write(ch);
    }
  }
  out.add(field.toString());
  return out;
}

const _entities = {
  'nbsp': ' ', 'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'",
  'mdash': '—', 'ndash': '–', 'hellip': '…', 'laquo': '«', 'raquo': '»',
};

/// Plain text from an Anki field: line breaks kept, tags, sounds and images
/// dropped, entities decoded.
String stripHtml(String html) {
  var text = html
      .replaceAll(RegExp(r'\[sound:[^\]]*\]'), '')
      .replaceAll(RegExp(r'<\s*br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</\s*(div|p|li)\s*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '');
  text = text.replaceAllMapped(RegExp(r'&(#x?[0-9a-fA-F]+|\w+);'), (m) {
    final name = m.group(1)!;
    if (name.startsWith('#x') || name.startsWith('#X')) {
      return String.fromCharCode(int.tryParse(name.substring(2), radix: 16) ?? 32);
    }
    if (name.startsWith('#')) {
      return String.fromCharCode(int.tryParse(name.substring(1)) ?? 32);
    }
    return _entities[name.toLowerCase()] ?? m.group(0)!;
  });
  return text
      .split('\n')
      .map((l) => l.replaceAll(RegExp(r'[ \t\u00A0]+'), ' ').trim())
      .where((l) => l.isNotEmpty)
      .join('\n')
      .trim();
}
