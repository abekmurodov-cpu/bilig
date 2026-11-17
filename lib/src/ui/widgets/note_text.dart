import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../../models/note_format.dart';
import 'code_highlighter.dart';
import 'markable_text.dart';

const String _mono = 'monospace';

/// A note's text as formatted: headings, lists, quotes, code blocks, bold
/// and italic, and formulas typeset from LaTeX. Highlighted key ideas are
/// marked wherever they appear in the words.
class NoteText extends StatelessWidget {
  const NoteText({
    super.key,
    required this.text,
    this.highlights = const [],
    this.style,
    this.textAlign = TextAlign.start,
    this.selectable = false,
  });

  final String text;
  final List<String> highlights;
  final TextStyle? style;
  final TextAlign textAlign;

  /// Lets the reader select and copy the text.
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = style ?? theme.textTheme.bodyLarge!;
    final blocks = parseNote(text);
    final center = textAlign == TextAlign.center;
    final children = <Widget>[];
    for (final block in blocks) {
      if (children.isNotEmpty) children.add(SizedBox(height: (base.fontSize ?? 16) * 0.55));
      children.add(_block(context, block, base));
    }
    final column = Column(
      crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
    return selectable ? SelectionArea(child: column) : column;
  }

  Widget _block(BuildContext context, NoteBlock block, TextStyle base) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final size = base.fontSize ?? 16;
    switch (block) {
      case ParagraphBlock(:final inlines):
        return _rich(context, inlines, base);
      case HeadingBlock(:final level, :final inlines):
        final scale = switch (level) { 1 => 1.35, 2 => 1.2, _ => 1.08 };
        return _rich(context, inlines,
            base.copyWith(fontSize: size * scale, fontWeight: FontWeight.w700, height: 1.25));
      case ListItemBlock(:final inlines, :final number, :final depth):
        final marker = number != null
            ? '$number.'
            : const ['•', '◦', '▪', '•'][depth.clamp(0, 3)];
        return Padding(
          padding: EdgeInsets.only(left: depth * size * 1.2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: textAlign == TextAlign.center ? MainAxisSize.min : MainAxisSize.max,
            children: [
              SizedBox(
                width: size * (number != null ? 1.8 : 1.2),
                child: Text(marker,
                    style: base.copyWith(
                        color: scheme.primary, fontWeight: FontWeight.w700)),
              ),
              Flexible(child: _rich(context, inlines, base, align: TextAlign.start)),
            ],
          ),
        );
      case QuoteBlock(:final inlines):
        return Container(
          padding: EdgeInsets.fromLTRB(size * 0.8, size * 0.2, 0, size * 0.2),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: scheme.primary.withValues(alpha: 0.5), width: 3)),
          ),
          child: _rich(context, inlines,
              base.copyWith(fontStyle: FontStyle.italic, color: scheme.onSurfaceVariant),
              align: TextAlign.start),
        );
      case CodeBlock(:final code):
        final codeStyle = TextStyle(
            fontFamily: _mono, fontSize: size * 0.8, height: 1.45, color: scheme.onSurface);
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(10),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text.rich(TextSpan(children: highlightCode(code, codeStyle)),
                textAlign: TextAlign.start),
          ),
        );
      case MathBlock(:final tex):
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: size * 0.2),
            child: _math(tex, base.copyWith(fontSize: size * 1.15), display: true),
          ),
        );
      case DividerBlock():
        return Divider(color: scheme.outlineVariant);
    }
  }

  Widget _rich(BuildContext context, List<Inline> inlines, TextStyle base, {TextAlign? align}) {
    final scheme = Theme.of(context).colorScheme;
    final spans = <InlineSpan>[];
    for (final run in inlines) {
      if (run.math) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _math(run.text, base),
        ));
        continue;
      }
      var style = base;
      if (run.bold) style = style.copyWith(fontWeight: FontWeight.w700);
      if (run.italic) style = style.copyWith(fontStyle: FontStyle.italic);
      if (run.strike) style = style.copyWith(decoration: TextDecoration.lineThrough);
      if (run.code) {
        style = style.copyWith(
          fontFamily: _mono,
          fontSize: (base.fontSize ?? 16) * 0.88,
          backgroundColor: scheme.surfaceContainerHighest,
          color: scheme.onSurface,
        );
      }
      spans.addAll(_marked(context, run.text, style));
    }
    return Text.rich(TextSpan(children: spans), textAlign: align ?? textAlign);
  }

  /// [text] with the highlighted phrases in it marked.
  List<TextSpan> _marked(BuildContext context, String text, TextStyle style) {
    if (highlights.isEmpty) return [TextSpan(text: text, style: style)];
    final lower = text.toLowerCase();
    final marks = <(int, int)>[];
    for (final phrase in highlights) {
      final needle = plainText(phrase).toLowerCase();
      if (needle.isEmpty) continue;
      var from = 0;
      while (true) {
        final at = lower.indexOf(needle, from);
        if (at < 0) break;
        marks.add((at, at + needle.length));
        from = at + needle.length;
      }
    }
    if (marks.isEmpty) return [TextSpan(text: text, style: style)];
    marks.sort((a, b) => a.$1.compareTo(b.$1));
    final marked = style.copyWith(backgroundColor: markerColor(context));
    final out = <TextSpan>[];
    var cursor = 0;
    for (final (start, end) in marks) {
      if (start < cursor) continue;
      if (start > cursor) out.add(TextSpan(text: text.substring(cursor, start), style: style));
      out.add(TextSpan(text: text.substring(start, end), style: marked));
      cursor = end;
    }
    if (cursor < text.length) out.add(TextSpan(text: text.substring(cursor), style: style));
    return out;
  }

  Widget _math(String tex, TextStyle style, {bool display = false}) => Math.tex(
        tex,
        mathStyle: display ? MathStyle.display : MathStyle.text,
        textStyle: style,
        onErrorFallback: (_) => Text(
          display ? '\$\$$tex\$\$' : '\$$tex\$',
          style: style.copyWith(fontFamily: _mono, fontSize: (style.fontSize ?? 16) * 0.85),
        ),
      );
}

/// A note's text: formatted when it uses formatting, otherwise as typed
/// with its highlights, where the marker works by selecting words. While
/// marking, the text is shown as typed so words can be tapped.
class NoteBody extends StatelessWidget {
  const NoteBody({
    super.key,
    required this.text,
    this.highlights = const [],
    this.style,
    this.textAlign,
    this.marking = false,
    this.onChanged,
  });

  final String text;
  final List<String> highlights;
  final TextStyle? style;
  final TextAlign? textAlign;
  final bool marking;
  final ValueChanged<List<String>>? onChanged;

  @override
  Widget build(BuildContext context) {
    if (marking || !hasFormatting(text)) {
      return MarkableText(
        text: text,
        highlights: highlights,
        style: style,
        textAlign: textAlign,
        marking: marking,
        onChanged: onChanged,
      );
    }
    return NoteText(
      text: text,
      highlights: highlights,
      style: style,
      textAlign: textAlign ?? TextAlign.start,
      selectable: onChanged != null,
    );
  }
}
