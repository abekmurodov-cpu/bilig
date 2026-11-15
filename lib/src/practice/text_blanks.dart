import '../models/highlights.dart';
import '../models/knowledge_item.dart';
import 'answer_matching.dart';
import 'code_drills.dart';

/// A fill-in-the-blank drill for an ordinary (non-code) note: a passage of
/// the note with a few key words taken out, typed back in place.
class TextBlanks {
  const TextBlanks({required this.cue, required this.template, required this.answers});

  /// Shown above the passage so the blanks can be recalled (the note's front
  /// when the passage is its answer); null when the passage is the front.
  final String? cue;

  /// The passage with [fillBlankPlaceholder]s where the words were.
  final String template;
  final List<String> answers;
}

/// Most blanks in one passage.
const int maxTextBlanks = 3;

final _word = RegExp(r"[\p{L}\p{N}]+(?:['’‘\-][\p{L}\p{N}]+)*", unicode: true);

/// Short, common words that make poor blanks, in the three app languages.
const Set<String> _common = {
  'about', 'after', 'again', 'because', 'before', 'being', 'between', 'could',
  'every', 'other', 'their', 'there', 'these', 'those', 'through', 'under',
  'where', 'which', 'while', 'would', 'should', 'without', 'within',
  'bilan', 'uchun', 'hamda', 'lekin', 'ammo', 'qilib', 'bo‘lgan', 'bo\'lgan',
  'kerak', 'mumkin', 'bunda', 'shunday', 'qanday', 'hamma', 'barcha',
  'который', 'которая', 'которые', 'которое', 'потому', 'также', 'между',
  'когда', 'чтобы', 'этого', 'этому', 'может', 'можно', 'после', 'перед',
  'через', 'только', 'тоже', 'очень',
};

/// Builds the drill from the note's highlights, or, when it has none in the
/// passage, from its longest uncommon words (names and numbers first), so
/// every note with a sentence or two can be practised this way.
///
/// The words asked rotate with every review. Null when the note is too short
/// to leave enough around the blanks to recall them from.
TextBlanks? textBlanks(KnowledgeItem item) {
  final back = item.back?.trim() ?? '';
  final front = item.front.trim();
  // The answer is the passage when there is one, with the front as its cue.
  final passages = [
    if (back.isNotEmpty) (cue: front.isEmpty ? null : front, text: back),
    (cue: back.isEmpty ? null : back, text: front),
  ];
  final turn = item.repetitions + item.lapses;
  for (final p in passages) {
    final marks = highlightRanges(p.text, item.highlights);
    if (marks.isNotEmpty) {
      final made = _build(p.cue, p.text, _rotate(marks, turn, maxTextBlanks));
      if (made != null) return made;
    }
  }
  for (final p in passages) {
    // Twice as many candidates as blanks, so reviews rotate through them.
    final words = _keyWords(p.text);
    final made = _build(p.cue, p.text, _rotate(words, turn, (words.length + 1) ~/ 2));
    if (made != null) return made;
  }
  return null;
}

/// [count] of [marks], starting further along with each review, in text
/// order.
List<Mark> _rotate(List<Mark> marks, int turn, int count) {
  if (marks.length <= count) return marks;
  final start = (turn * count) % marks.length;
  return [
    for (var k = 0; k < count; k++) marks[(start + k) % marks.length],
  ]..sort((a, b) => a.start.compareTo(b.start));
}

/// The words worth blanking, ranked: numbers and mid-sentence capitals
/// (names, terms) first, then the longest. One blank per eight words or so.
List<Mark> _keyWords(String text) {
  final words = _word.allMatches(text).toList();
  if (words.length < 4) return const [];
  final want = (words.length / 8).ceil().clamp(1, maxTextBlanks);
  int score(RegExpMatch m) {
    final w = m.group(0)!;
    var s = w.length;
    if (RegExp(r'\d').hasMatch(w)) s += 6;
    final first = w[0];
    final sentenceStart =
        m.start == 0 || RegExp(r'[.!?:\n]\s*$').hasMatch(text.substring(0, m.start));
    if (!sentenceStart && first != first.toLowerCase()) s += 4;
    return s;
  }

  final seen = <String>{};
  final candidates = [
    for (final m in words)
      if ((m.group(0)!.length >= 5 || RegExp(r'\d').hasMatch(m.group(0)!)) &&
          !_common.contains(m.group(0)!.toLowerCase()) &&
          seen.add(m.group(0)!.toLowerCase()))
        m,
  ]..sort((a, b) => score(b).compareTo(score(a)));
  return [
    for (final m in candidates.take(want * 2)) (start: m.start, end: m.end),
  ]..sort((a, b) => a.start.compareTo(b.start));
}

TextBlanks? _build(String? cue, String text, List<Mark> marks) {
  if (marks.isEmpty) return null;
  final buf = StringBuffer();
  final answers = <String>[];
  var cursor = 0;
  for (final m in marks) {
    buf.write(text.substring(cursor, m.start));
    buf.write(fillBlankPlaceholder(answers.length));
    answers.add(text.substring(m.start, m.end));
    cursor = m.end;
  }
  buf.write(text.substring(cursor));
  final template = buf.toString();
  // Enough left around the blanks to recall them from (or a cue to go on).
  final left = _word.allMatches(template.replaceAll(fillBlankPlaceholderPattern, ' ')).length;
  if (left < (cue == null ? 3 : 1)) return null;
  return TextBlanks(cue: cue, template: template, answers: answers);
}

/// Whether a typed word fills a blank: the same word, ignoring case and
/// punctuation, allowing a small typo in longer words.
bool blankMatches(String guess, String answer) {
  final g = normalizeAnswer(guess);
  final a = normalizeAnswer(answer);
  if (g.isEmpty) return false;
  if (g == a) return true;
  return a.length >= 5 && similarity(g, a) >= 0.8;
}
