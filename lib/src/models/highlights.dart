/// Highlights are stored as the marked text itself (see
/// [KnowledgeItem.highlights]); these helpers find them in a note's text and
/// edit the list as the student marks and unmarks words.
library;

/// A marked stretch of text, [start] inclusive to [end] exclusive.
typedef Mark = ({int start, int end});

final _word = RegExp(r"[\p{L}\p{N}_]+(?:['’\-][\p{L}\p{N}_]+)*", unicode: true);

/// Every word in [text], as ranges.
List<Mark> wordRanges(String text) =>
    [for (final m in _word.allMatches(text)) (start: m.start, end: m.end)];

/// Where each of [phrases] occurs in [text] (case-insensitive), per phrase.
Map<String, List<Mark>> _occurrences(String text, List<String> phrases) {
  final lower = text.toLowerCase();
  final result = <String, List<Mark>>{};
  for (final phrase in phrases) {
    final needle = phrase.toLowerCase();
    if (needle.isEmpty) continue;
    final found = <Mark>[];
    var from = 0;
    while (true) {
      final at = lower.indexOf(needle, from);
      if (at < 0) break;
      found.add((start: at, end: at + needle.length));
      from = at + needle.length;
    }
    result[phrase] = found;
  }
  return result;
}

/// The marked parts of [text], sorted, with overlapping ones merged.
List<Mark> highlightRanges(String text, List<String> phrases) {
  final all = [
    for (final marks in _occurrences(text, phrases).values) ...marks,
  ]..sort((a, b) => a.start.compareTo(b.start));
  final merged = <Mark>[];
  for (final m in all) {
    if (merged.isNotEmpty && m.start <= merged.last.end) {
      final last = merged.removeLast();
      merged.add((start: last.start, end: m.end > last.end ? m.end : last.end));
    } else {
      merged.add(m);
    }
  }
  return merged;
}

bool _overlaps(Mark a, Mark b) => a.start < b.end && b.start < a.end;

/// Drops repeats (ignoring case) and phrases contained in a longer one.
List<String> _tidy(List<String> phrases) {
  final out = <String>[];
  for (final p in phrases) {
    final lower = p.toLowerCase();
    if (lower.trim().isEmpty) continue;
    if (out.any((o) => o.toLowerCase().contains(lower))) continue;
    out.removeWhere((o) => lower.contains(o.toLowerCase()));
    out.add(p);
  }
  return out;
}

/// Tapping [word] in [text] with the marker: unmarks it if it is marked
/// (the whole marked phrase), otherwise marks it — joined with marked words
/// right next to it, so tapping "Krebs" then "cycle" marks "Krebs cycle".
List<String> toggleWord(String text, List<String> phrases, Mark word) {
  final occ = _occurrences(text, phrases);
  final hit = [
    for (final e in occ.entries)
      if (e.value.any((m) => _overlaps(m, word))) e.key,
  ];
  if (hit.isNotEmpty) {
    return [for (final p in phrases) if (!hit.contains(p)) p];
  }
  var start = word.start, end = word.end;
  final joined = <String>{};
  // Grow over neighbours separated only by spaces, until nothing changes.
  var grew = true;
  while (grew) {
    grew = false;
    for (final e in occ.entries) {
      for (final m in e.value) {
        final before = m.end <= start && text.substring(m.end, start).trim().isEmpty;
        final after = m.start >= end && text.substring(end, m.start).trim().isEmpty;
        if ((before || after) && !joined.contains(e.key)) {
          joined.add(e.key);
          if (m.start < start) start = m.start;
          if (m.end > end) end = m.end;
          grew = true;
        }
      }
    }
  }
  return _tidy([
    for (final p in phrases) if (!joined.contains(p)) p,
    text.substring(start, end),
  ]);
}

/// Marks a selected stretch of text (trimmed of spaces and punctuation at
/// the ends). Returns [phrases] unchanged when nothing is left to mark.
List<String> addPhrase(List<String> phrases, String selected) {
  final phrase = selected
      .replaceAll(RegExp(r'^[\s\p{P}]+|[\s\p{P}]+$', unicode: true), '')
      .replaceAll(RegExp(r'\s+'), ' ');
  if (phrase.isEmpty) return phrases;
  return _tidy([...phrases, phrase]);
}

/// Unmarks every phrase that overlaps [selection] of [text].
List<String> removeAt(String text, List<String> phrases, Mark selection) {
  final occ = _occurrences(text, phrases);
  return [
    for (final p in phrases)
      if (!(occ[p] ?? const []).any((m) => _overlaps(m, selection))) p,
  ];
}

/// The highlights still found in a note after its text changed.
List<String> keptHighlights(List<String> phrases, String front, String? back) {
  final text = '$front\n${back ?? ''}'.toLowerCase();
  return [for (final p in phrases) if (text.contains(p.toLowerCase())) p];
}
