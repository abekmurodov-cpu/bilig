import 'knowledge_item.dart';

/// Notes matching [query] (every word must appear somewhere in the note:
/// prompt, answer, category, tags or its questions; case- and
/// accent-insensitive), carrying every tag in [tags] and, when [categories]
/// isn't empty, in one of those categories ('' for notes without one) or
/// topics ([topicKey]s).
/// Prompt matches come first.
List<KnowledgeItem> searchNotes(List<KnowledgeItem> notes, String query,
    {Set<String> tags = const {}, Set<String> categories = const {}}) {
  final words = _fold(query).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  final wanted = {for (final t in tags) t.toLowerCase()};
  final hits = <(KnowledgeItem, int)>[];
  for (final note in notes) {
    if (categories.isNotEmpty) {
      final category = note.category?.trim() ?? '';
      final topic = note.topic;
      if (!categories.contains(category) &&
          (topic == null || !categories.contains(topicKey(category, topic)))) {
        continue;
      }
    }
    if (wanted.isNotEmpty) {
      final have = {for (final t in note.tags) t.toLowerCase()};
      if (!wanted.every(have.contains)) continue;
    }
    if (words.isEmpty) {
      hits.add((note, 0));
      continue;
    }
    final (front, all) = _folded[note] ??= (
      _fold(note.front),
      _fold([
        note.front,
        note.back ?? '',
        note.category ?? '',
        note.topic ?? '',
        ...note.tags,
        for (final q in note.quizVariants) '${q.question ?? ''} ${q.answer}',
      ].join(' \n ')),
    );
    if (!words.every(all.contains)) continue;
    hits.add((note, words.where(front.contains).length));
  }
  // Stable: more words in the prompt first, otherwise the given order.
  final indexed = [for (var i = 0; i < hits.length; i++) (hits[i], i)]
    ..sort((a, b) => b.$1.$2 != a.$1.$2 ? b.$1.$2 - a.$1.$2 : a.$2 - b.$2);
  return [for (final h in indexed) h.$1.$1];
}

/// Each note's searchable text, folded once per version of the note (notes
/// are immutable, so an edit is a new object): typing a query then only
/// compares strings.
final Expando<(String, String)> _folded = Expando('folded');

/// A topic as a search filter entry, alongside category names.
String topicKey(String category, String topic) => '$category\u001f$topic';

const _accents = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'é': 'e', 'è': 'e', 'ê': 'e',
  'ë': 'e', 'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i', 'ó': 'o', 'ò': 'o', 'ô': 'o',
  'ö': 'o', 'õ': 'o', 'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ñ': 'n', 'ç': 'c',
  'ё': 'е', 'ʻ': '', '‘': '', '’': '', "'": '', 'ʼ': '', '`': '',
};

/// Lowercase without accents or apostrophes, so "o‘zbek", "o'zbek" and
/// "ozbek" all match.
String _fold(String text) {
  final lower = text.toLowerCase();
  final out = StringBuffer();
  for (final ch in lower.split('')) {
    out.write(_accents[ch] ?? ch);
  }
  return out.toString();
}
