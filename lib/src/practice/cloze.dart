import '../models/knowledge_item.dart';
import 'answer_matching.dart';

/// The blank shown in place of the hidden key idea.
const String clozeBlank = '_____';

final _sentenceBreak = RegExp(r'(?<=[.!?])\s+|\n+');

/// A fill-in-the-blank question built on the device from the note's
/// highlights, with no AI: the sentence holding a highlighted idea, with that
/// idea blanked out ("The _____ runs in the mitochondria" → "Krebs cycle").
/// Wrong options are other highlights (this note's first, then its
/// category's, then any); there may be fewer than needed for multiple choice.
///
/// The highlight asked rotates with every review, like AI questions do.
/// Null when no highlight leaves a sentence worth asking about.
QuizVariant? clozeQuiz(KnowledgeItem item, Iterable<KnowledgeItem> others) {
  final highlights = item.highlights;
  if (highlights.isEmpty) return null;
  final sentences = [
    for (final s in '${item.front}\n${item.back ?? ''}'.split(_sentenceBreak))
      if (s.trim().isNotEmpty) s.trim(),
  ];
  final start = (item.repetitions + item.lapses) % highlights.length;
  for (var k = 0; k < highlights.length; k++) {
    final phrase = highlights[(start + k) % highlights.length];
    final needle = phrase.toLowerCase();
    for (final sentence in sentences) {
      final at = sentence.toLowerCase().indexOf(needle);
      if (at < 0) continue;
      final answer = sentence.substring(at, at + phrase.length);
      final blanked = sentence.replaceAll(
          RegExp(RegExp.escape(phrase), caseSensitive: false), clozeBlank);
      // Enough left around the blank to recall it from.
      final rest = blanked.replaceAll(clozeBlank, ' ').trim();
      if (RegExp(r'[\p{L}\p{N}]+', unicode: true).allMatches(rest).length < 3) {
        continue;
      }
      return QuizVariant(
        question: blanked,
        answer: answer,
        distractors: _clozeOptions(item, answer, blanked, others),
      );
    }
  }
  return null;
}

List<String> _clozeOptions(KnowledgeItem item, String answer, String question,
    Iterable<KnowledgeItem> others) {
  final key = normalizeAnswer(answer);
  // An option already visible in the question is obviously not the blank.
  final visible = normalizeAnswer(question);
  final sameCategory = [
    for (final o in others)
      if (o.id != item.id && o.category == item.category) ...o.highlights,
  ];
  final rest = [
    for (final o in others)
      if (o.id != item.id && o.category != item.category) ...o.highlights,
  ];
  final seen = {key};
  final out = <String>[];
  for (final candidate in [...item.highlights, ...sameCategory, ...rest]) {
    final c = normalizeAnswer(candidate);
    if (c.isEmpty || c.contains(key) || key.contains(c)) continue;
    if (visible.contains(c)) continue;
    if (similarity(c, key) >= 0.8 || !seen.add(c)) continue;
    out.add(candidate);
    if (out.length == 3) break;
  }
  return out;
}
