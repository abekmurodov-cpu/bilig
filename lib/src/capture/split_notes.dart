import '../llm/llm_provider.dart';
import '../models/knowledge_item.dart';

/// Most notes made from one paste.
const int maxLocalDrafts = 60;

final _bullet = RegExp(r'^\s*(?:[-*•▪◦–]|\d+[.)]|[a-zA-Z][.)])\s+');
final _separator = RegExp(r'\s+[—–-]\s+|\s*:\s+|\s+=\s+');

/// Splits pasted text into notes without any AI, one per line (or per
/// "Q: … / A: …" pair). A line like "Term — definition", "Term: definition"
/// or "Question? Answer" becomes a cue and its answer; other lines become a
/// note with no answer yet.
List<NoteDraft> splitLocally(String text) {
  final lines = [
    for (final l in text.split(RegExp(r'\r?\n')))
      if (l.trim().isNotEmpty) l.replaceFirst(_bullet, '').trim(),
  ];
  final out = <NoteDraft>[];
  final seen = <String>{};
  void add(String front, String? back) {
    front = front.trim();
    back = back?.trim();
    if (front.isEmpty || !seen.add(front.toLowerCase())) return;
    final type = front.endsWith('?')
        ? KnowledgeType.question
        : (back != null && front.split(RegExp(r'\s+')).length <= 6
            ? KnowledgeType.concept
            : KnowledgeType.fact);
    out.add(NoteDraft(
        front: front, back: back == null || back.isEmpty ? null : back, type: type));
  }

  final qa = RegExp(r'^(?:Q|Savol|Вопрос)\s*[:.]\s*', caseSensitive: false);
  final aa = RegExp(r'^(?:A|Javob|Ответ)\s*[:.]\s*', caseSensitive: false);
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (qa.hasMatch(line)) {
      final next = i + 1 < lines.length ? lines[i + 1] : '';
      final hasAnswer = aa.hasMatch(next);
      add(line.replaceFirst(qa, ''), hasAnswer ? next.replaceFirst(aa, '') : null);
      if (hasAnswer) i++;
      continue;
    }
    final q = line.indexOf('?');
    if (q > 0 && q < line.length - 1) {
      add(line.substring(0, q + 1), line.substring(q + 1));
      continue;
    }
    final sep = _separator.firstMatch(line);
    // Only a short cue before the separator: "x: y" mid-sentence isn't one.
    if (sep != null &&
        sep.start > 0 &&
        line.substring(0, sep.start).split(RegExp(r'\s+')).length <= 8) {
      add(line.substring(0, sep.start), line.substring(sep.end));
      continue;
    }
    add(line, null);
  }
  return out.take(maxLocalDrafts).toList();
}
