import 'dart:math' as math;

import '../models/highlights.dart';
import '../models/knowledge_item.dart';
import '../models/note_format.dart';
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

/// How often words occur across all notes: words in many notes ("company",
/// "people") are general, words in few ("externality") are the subject's own.
class WordStats {
  WordStats(Iterable<KnowledgeItem> notes) {
    for (final n in notes) {
      count++;
      final words = {
        for (final m in _word.allMatches('${n.front} ${n.back ?? ''}'))
          m.group(0)!.toLowerCase(),
      };
      for (final w in words) {
        _notesWith[w] = (_notesWith[w] ?? 0) + 1;
      }
    }
  }

  final Map<String, int> _notesWith = {};
  int count = 0;

  /// 0 for a word in every note, up to about 1 for a word in one note.
  double rarity(String word) {
    if (count < 5) return 0.5; // too few notes to tell
    final inNotes = _notesWith[word.toLowerCase()] ?? 0;
    return math.log((count + 1) / (inNotes + 1)) / math.log(count + 1);
  }
}

/// Most blanks in one passage, from the student's highlights.
const int maxTextBlanks = 3;

/// Most blanks chosen without highlights: guessing more risks taking out
/// so much that the passage can't be recalled.
const int maxGuessedBlanks = 2;

/// Roughly one blank per this many words, so there is context left: the
/// student's own highlights may sit closer together than guessed words.
const int _wordsPerHighlight = 5;
const int _wordsPerGuess = 10;

/// Words left between two blanks, at least.
const int _gap = 3;

final _word = RegExp(r"[\p{L}\p{N}]+(?:['’‘ʻ\-][\p{L}\p{N}]+)*", unicode: true);

/// Builds the drill. Words to take out, best first:
///  1. the student's highlights;
///  2. the answers of the note's questions, when they appear in the text
///     (the AI already judged those the point of the note);
///  3. otherwise the words most likely to be the note's subject: rare across
///     the student's notes, names, numbers and abbreviations, never common
///     words like "something" and never words the cue already shows.
///
/// The words asked rotate with every review. Null when the note is too short
/// to leave enough around a blank to recall it from.
TextBlanks? textBlanks(KnowledgeItem item, {WordStats? stats}) {
  // Blanks go in the words alone: formatting marks and formulas would make
  // odd blanks.
  final back = plainText(item.back ?? '').trim();
  final front = plainText(item.front).trim();
  // The answer is the passage when there is one, with the front as its cue.
  final passages = [
    if (back.isNotEmpty) (cue: front.isEmpty ? null : front, text: back),
    (cue: back.isEmpty ? null : back, text: front),
  ];
  final turn = item.repetitions + item.lapses;
  final answers = [
    for (final q in item.quizVariants)
      if (q.answer.trim().isNotEmpty && _word.allMatches(q.answer).length <= 4)
        q.answer.trim().replaceAll(RegExp(r'[.!?]+$'), ''),
  ];
  for (final p in passages) {
    final cue = _CueWords(p.cue);
    for (final (phrases, most, density) in [
      (item.highlights, maxTextBlanks, _wordsPerHighlight),
      (answers, maxGuessedBlanks, _wordsPerGuess),
    ]) {
      final marks = [
        for (final m in highlightRanges(p.text, phrases))
          if (!cue.shows(p.text.substring(m.start, m.end))) m,
      ];
      final made = _build(p.cue, p.text, _choose(p.text, marks, turn, most, density));
      if (made != null) return made;
    }
  }
  for (final p in passages) {
    final ranked = _keyWords(p.text, _CueWords(p.cue), stats);
    final made = _build(
        p.cue, p.text, _choose(p.text, ranked, turn, maxGuessedBlanks, _wordsPerGuess));
    if (made != null) return made;
  }
  return null;
}

/// Picks from [ranked] (best first) as many blanks as the passage can
/// carry (one per [density] words), at most [most], spaced apart; the starting pick moves on with each
/// review. In text order.
List<Mark> _choose(String text, List<Mark> ranked, int turn, int most, int density) {
  if (ranked.isEmpty) return const [];
  final words = _word.allMatches(text).toList();
  final room = math.max(1, (words.length + density ~/ 2) ~/ density);
  final want = math.min(most, room);
  int wordIndex(Mark m) => words.indexWhere((w) => w.end > m.start);
  // Rotate among the best few, so reviews vary but stay on key words.
  final pool = ranked.take(math.max(want * 2, math.min(ranked.length, 3))).toList();
  final start = turn % pool.length;
  final chosen = <Mark>[];
  for (var k = 0; k < pool.length && chosen.length < want; k++) {
    final m = pool[(start + k) % pool.length];
    final at = wordIndex(m);
    if (chosen.any((c) => (wordIndex(c) - at).abs() <= _gap)) continue;
    chosen.add(m);
  }
  return chosen..sort((a, b) => a.start.compareTo(b.start));
}

/// Words of the cue, to keep from blanking what is shown right above.
class _CueWords {
  _CueWords(String? cue)
      : _words = {
          for (final m in _word.allMatches(cue ?? '')) m.group(0)!.toLowerCase(),
        };

  final Set<String> _words;

  /// Whether every word of [phrase] is in the cue (or nearly: "spillovers"
  /// for "spillover").
  bool shows(String phrase) {
    final words = [for (final m in _word.allMatches(phrase)) m.group(0)!.toLowerCase()];
    return words.isNotEmpty && words.every(_has);
  }

  bool _has(String w) => _words.any((c) =>
      c == w || (math.min(c.length, w.length) >= 5 && (c.startsWith(w) || w.startsWith(c))));
}

/// Candidate words, best first.
List<Mark> _keyWords(String text, _CueWords cue, WordStats? stats) {
  final scored = <(Mark, double)>[];
  final seen = <String>{};
  for (final m in _word.allMatches(text)) {
    final w = m.group(0)!;
    final lower = w.toLowerCase();
    if (!seen.add(lower) || _common.contains(lower) || cue.shows(w)) continue;
    final hasDigit = RegExp(r'\d').hasMatch(w);
    final acronym = w.length >= 2 && w == w.toUpperCase() && w != w.toLowerCase();
    if (w.length < 5 && !hasDigit && !acronym) continue;
    var score = math.min(w.length, 12) / 4;
    score += 4 * (stats?.rarity(w) ?? 0.5);
    if (hasDigit) score += 3;
    if (acronym) score += 3;
    final sentenceStart =
        m.start == 0 || RegExp(r'[.!?:\n]\s*$').hasMatch(text.substring(0, m.start));
    if (!sentenceStart && w[0] != w[0].toLowerCase()) score += 2;
    // English adverbs and verb forms are rarely the point of a note.
    if (lower.endsWith('ly')) score -= 3;
    if (lower.endsWith('ing') || lower.endsWith('ed')) score -= 1;
    scored.add(((start: m.start, end: m.end), score));
  }
  scored.sort((a, b) => b.$2.compareTo(a.$2));
  return [for (final s in scored) s.$1];
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
  if (left < (cue == null ? 4 : 2)) return null;
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

/// Common and vague words that make poor blanks, in the app's languages.
const Set<String> _common = {
  // English
  'about', 'above', 'after', 'again', 'against', 'almost', 'along', 'already',
  'also', 'although', 'always', 'among', 'another', 'anyone', 'anything',
  'around', 'because', 'become', 'becomes', 'been', 'before', 'being',
  'below', 'between', 'both', 'called', 'cannot', 'could', 'different',
  'does', 'doing', 'during', 'each', 'either', 'else', 'enough', 'especially',
  'even', 'ever', 'every', 'everyone', 'everything', 'example', 'examples',
  'first', 'from', 'further', 'give', 'gives', 'good', 'great', 'have',
  'having', 'here', 'however', 'important', 'into', 'itself', 'just', 'known',
  'large', 'later', 'least', 'less', 'like', 'little', 'made', 'make',
  'makes', 'many', 'means', 'might', 'more', 'most', 'much', 'must', 'never',
  'next', 'nothing', 'often', 'only', 'other', 'others', 'over', 'part',
  'people', 'person', 'place', 'really', 'same', 'second', 'several',
  'should', 'show', 'shows', 'since', 'small', 'some', 'someone', 'something',
  'sometimes', 'still', 'such', 'take', 'takes', 'than', 'that', 'their',
  'them', 'then', 'there', 'these', 'they', 'thing', 'things', 'this',
  'those', 'though', 'through', 'together', 'under', 'until', 'used',
  'uses', 'using', 'usually', 'very', 'want', 'well', 'were', 'what', 'when',
  'where', 'whether', 'which', 'while', 'whole', 'with', 'within', 'without',
  'would', 'your', 'kind', 'ways', 'lots',
  // O‘zbekcha
  'bilan', 'uchun', 'hamda', 'lekin', 'qilib', 'bo‘lgan', "bo'lgan",
  'boʻlgan', 'kerak', 'mumkin', 'bunda', 'shunday', 'qanday', 'bunday',
  'hamma', 'barcha', 'boshqa', 'biror', 'nimadir', 'narsa', 'narsalar',
  'odatda', 'deyiladi', 'masalan', 'hisoblanadi', 'orqali', 'keyin',
  'oldin', 'ya’ni', 'yaʼni', 'chunki', 'sifatida', 'bo‘ladi', "bo'ladi",
  'boʻladi', 'qiladi', 'beradi', 'ularning', 'uning',
  // Русский
  'который', 'которая', 'которые', 'которое', 'которых', 'потому', 'также',
  'между', 'когда', 'чтобы', 'этого', 'этому', 'может', 'можно', 'после',
  'перед', 'через', 'только', 'тоже', 'очень', 'что-то', 'кто-то', 'другие',
  'другой', 'другая', 'другое', 'обычно', 'всегда', 'называется', 'например',
  'является', 'являются', 'такой', 'такие', 'такая', 'нужно', 'всего',
  'более', 'менее', 'часто', 'нечто', 'вещи', 'много', 'несколько', 'своих',
  'своей', 'тогда', 'потом', 'сейчас',
};
