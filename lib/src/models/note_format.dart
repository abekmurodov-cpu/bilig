/// The formatting a note may use, Markdown style:
///
/// - `**bold**`, `*italic*` or `_italic_`, `~~struck~~`, `` `code` ``
/// - `$x^2$` inline formulas and `$$ … $$` formula blocks (LaTeX)
/// - `# Heading` (up to three levels), `> quote`, `---`
/// - `- item` / `* item` / `• item` lists and `1. item` numbered lists,
///   indented by two spaces for a sub-item
/// - fenced code blocks: ```` ``` ```` (optionally with a language)
///
/// Notes are stored as typed; this parses them for display. [plainText]
/// gives the words alone, for search, blanks and checking answers.
library;

sealed class NoteBlock {
  const NoteBlock();
}

class ParagraphBlock extends NoteBlock {
  const ParagraphBlock(this.inlines);
  final List<Inline> inlines;
}

class HeadingBlock extends NoteBlock {
  const HeadingBlock(this.level, this.inlines);
  final int level;
  final List<Inline> inlines;
}

class ListItemBlock extends NoteBlock {
  const ListItemBlock(this.inlines, {this.number, this.depth = 0});

  /// The number of a numbered item; null for a bullet.
  final int? number;
  final int depth;
  final List<Inline> inlines;
}

class QuoteBlock extends NoteBlock {
  const QuoteBlock(this.inlines);
  final List<Inline> inlines;
}

class CodeBlock extends NoteBlock {
  const CodeBlock(this.code, {this.language});
  final String code;
  final String? language;
}

class MathBlock extends NoteBlock {
  const MathBlock(this.tex);
  final String tex;
}

class DividerBlock extends NoteBlock {
  const DividerBlock();
}

/// A run of text with its styling.
class Inline {
  const Inline(this.text,
      {this.bold = false,
      this.italic = false,
      this.strike = false,
      this.code = false,
      this.math = false});

  final String text;
  final bool bold;
  final bool italic;
  final bool strike;
  final bool code;

  /// [text] is a LaTeX formula.
  final bool math;

  Inline styled({bool? bold, bool? italic, bool? strike}) => Inline(text,
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      strike: strike ?? this.strike,
      code: code,
      math: math);
}

final _fence = RegExp(r'^\s*```\s*([\w+#.-]*)\s*$');
final _heading = RegExp(r'^(#{1,3})\s+(.*)$');
final _bullet = RegExp(r'^(\s*)[-*•]\s+(.*)$');
final _numbered = RegExp(r'^(\s*)(\d{1,3})[.)]\s+(.*)$');
final _quote = RegExp(r'^>\s?(.*)$');
final _rule = RegExp(r'^\s*(?:---+|\*\*\*+|___+)\s*$');

/// Whether [text] uses any formatting (else it can be shown as typed).
bool hasFormatting(String text) {
  if (RegExp(r'\*\*|~~|`|\$[^\s$](?:[^$\n]*[^\s$])?\$(?!\d)|(^|\n)\s*(#{1,3}\s|[-*•]\s|\d{1,3}[.)]\s|>|```|---)')
      .hasMatch(text)) {
    return true;
  }
  return RegExp(r'(^|[\s(])[*_][^\s*_][^*_\n]*[*_](?=$|[\s.,;:!?)])').hasMatch(text);
}

/// The blocks of [text].
List<NoteBlock> parseNote(String text) {
  final lines = text.replaceAll('\r\n', '\n').split('\n');
  final blocks = <NoteBlock>[];
  final paragraph = <String>[];
  void flush() {
    if (paragraph.isEmpty) return;
    blocks.add(ParagraphBlock(parseInline(paragraph.join('\n'))));
    paragraph.clear();
  }

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final fence = _fence.firstMatch(line);
    if (fence != null) {
      flush();
      final code = <String>[];
      var j = i + 1;
      while (j < lines.length && !_fence.hasMatch(lines[j])) {
        code.add(lines[j]);
        j++;
      }
      final language = fence.group(1)!;
      blocks.add(CodeBlock(code.join('\n'), language: language.isEmpty ? null : language));
      i = j; // past the closing fence (or the end)
      continue;
    }
    final trimmed = line.trim();
    if (trimmed.startsWith(r'$$')) {
      flush();
      final rest = trimmed.substring(2);
      if (rest.endsWith(r'$$') && rest.length >= 2) {
        blocks.add(MathBlock(rest.substring(0, rest.length - 2).trim()));
        continue;
      }
      final tex = <String>[if (rest.isNotEmpty) rest];
      var j = i + 1;
      while (j < lines.length && !lines[j].trim().endsWith(r'$$')) {
        tex.add(lines[j]);
        j++;
      }
      if (j < lines.length) {
        final last = lines[j].trim();
        tex.add(last.substring(0, last.length - 2));
      }
      blocks.add(MathBlock(tex.join('\n').trim()));
      i = j;
      continue;
    }
    if (trimmed.isEmpty) {
      flush();
      continue;
    }
    if (_rule.hasMatch(line)) {
      flush();
      blocks.add(const DividerBlock());
      continue;
    }
    final heading = _heading.firstMatch(trimmed);
    if (heading != null) {
      flush();
      blocks.add(HeadingBlock(heading.group(1)!.length, parseInline(heading.group(2)!)));
      continue;
    }
    final bullet = _bullet.firstMatch(line);
    if (bullet != null) {
      flush();
      blocks.add(ListItemBlock(parseInline(bullet.group(2)!),
          depth: (bullet.group(1)!.length ~/ 2).clamp(0, 3)));
      continue;
    }
    final numbered = _numbered.firstMatch(line);
    if (numbered != null) {
      flush();
      blocks.add(ListItemBlock(parseInline(numbered.group(3)!),
          number: int.parse(numbered.group(2)!),
          depth: (numbered.group(1)!.length ~/ 2).clamp(0, 3)));
      continue;
    }
    final quote = _quote.firstMatch(trimmed);
    if (quote != null) {
      flush();
      blocks.add(QuoteBlock(parseInline(quote.group(1)!)));
      continue;
    }
    paragraph.add(line);
  }
  flush();
  return blocks;
}

/// The styled runs of one line or paragraph.
List<Inline> parseInline(String text) {
  final out = <Inline>[];
  final plain = StringBuffer();
  void flushPlain() {
    if (plain.isEmpty) return;
    out.add(Inline(plain.toString()));
    plain.clear();
  }

  var i = 0;
  while (i < text.length) {
    final rest = text.substring(i);
    // `code` and $math$ hold their text as typed.
    if (rest.startsWith('`')) {
      final end = text.indexOf('`', i + 1);
      if (end > i + 1) {
        flushPlain();
        out.add(Inline(text.substring(i + 1, end), code: true));
        i = end + 1;
        continue;
      }
    }
    if (rest.startsWith(r'$') && !rest.startsWith(r'$$')) {
      final end = text.indexOf(r'$', i + 1);
      if (end > i + 1) {
        final tex = text.substring(i + 1, end);
        // "$5 and $10" is money, not a formula: no space inside the edges.
        if (tex.trim() == tex && !(end + 1 < text.length && RegExp(r'\d').hasMatch(text[end + 1]))) {
          flushPlain();
          out.add(Inline(tex, math: true));
          i = end + 1;
          continue;
        }
      }
    }
    final wrap = _wrapAt(text, i);
    if (wrap != null) {
      flushPlain();
      final (marker, end) = wrap;
      final inner = parseInline(text.substring(i + marker.length, end));
      for (final run in inner) {
        out.add(run.styled(
          bold: marker == '**' ? true : null,
          italic: marker == '*' || marker == '_' ? true : null,
          strike: marker == '~~' ? true : null,
        ));
      }
      i = end + marker.length;
      continue;
    }
    plain.write(text[i]);
    i++;
  }
  flushPlain();
  return out;
}

/// A `**…**`, `~~…~~`, `*…*` or `_…_` span starting at [i]: its marker and
/// where its closing marker starts. Single `*`/`_` only around words, so
/// "snake_case" and "2 * 3 * 4" stay as typed.
(String, int)? _wrapAt(String text, int i) {
  for (final marker in const ['**', '~~', '*', '_']) {
    if (!text.startsWith(marker, i)) continue;
    final from = i + marker.length;
    if (from >= text.length || text[from].trim().isEmpty) continue;
    if (marker.length == 1) {
      final before = i == 0 ? ' ' : text[i - 1];
      if (RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(before)) continue;
    }
    var end = text.indexOf(marker, from);
    while (end > 0) {
      final closesWord = text[end - 1].trim().isNotEmpty;
      final after = end + marker.length < text.length ? text[end + marker.length] : ' ';
      final wordAfter = RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(after);
      if (closesWord && (marker.length == 2 || !wordAfter)) {
        // "**bold *both***": the bold closes on the last two stars.
        if (marker == '**' && text.startsWith('*', end + 2)) end++;
        return (marker, end);
      }
      end = text.indexOf(marker, end + 1);
    }
  }
  return null;
}

/// [text] without its formatting marks: what it says, for search, blanks
/// and comparing answers. Formulas keep their LaTeX.
String plainText(String text) {
  if (!hasFormatting(text)) return text;
  final out = <String>[];
  for (final b in parseNote(text)) {
    out.add(switch (b) {
      ParagraphBlock(:final inlines) ||
      HeadingBlock(:final inlines) ||
      QuoteBlock(:final inlines) =>
        _plain(inlines),
      ListItemBlock(:final inlines) => _plain(inlines),
      CodeBlock(:final code) => code,
      MathBlock(:final tex) => tex,
      DividerBlock() => '',
    });
  }
  return out.where((l) => l.isNotEmpty).join('\n');
}

String _plain(List<Inline> inlines) => inlines.map((r) => r.text).join();
