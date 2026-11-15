import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../models/highlights.dart';

/// The marker colour for highlighted key ideas.
Color markerColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0x66FFC107)
        : const Color(0xFFFFE58A);

/// [text] with its [highlights] drawn like a marker pen.
///
/// - Read-only when [onChanged] is null.
/// - With [marking], tapping a word marks or unmarks it (the quick way on a
///   phone).
/// - Otherwise the text is selectable and the selection menu offers
///   "Highlight" / "Remove highlight" (for exact phrases).
class MarkableText extends StatefulWidget {
  const MarkableText({
    super.key,
    required this.text,
    required this.highlights,
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
  State<MarkableText> createState() => _MarkableTextState();
}

class _MarkableTextState extends State<MarkableText> {
  final List<TapGestureRecognizer> _recognizers = [];

  void _clearRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _clearRecognizers();
    super.dispose();
  }

  TextSpan _span(BuildContext context) {
    _clearRecognizers();
    final text = widget.text;
    final marks = highlightRanges(text, widget.highlights);
    final words = widget.marking ? wordRanges(text) : const <Mark>[];
    final cuts = <int>{0, text.length};
    for (final m in [...marks, ...words]) {
      cuts
        ..add(m.start)
        ..add(m.end);
    }
    final sorted = cuts.toList()..sort();
    final marked = TextStyle(backgroundColor: markerColor(context));
    final recognizers = <Mark, TapGestureRecognizer>{};
    final children = <TextSpan>[];
    for (var i = 0; i + 1 < sorted.length; i++) {
      final start = sorted[i], end = sorted[i + 1];
      final isMarked = marks.any((m) => m.start <= start && end <= m.end);
      TapGestureRecognizer? recognizer;
      for (final w in words) {
        if (w.start <= start && end <= w.end) {
          recognizer = recognizers[w] ??= (TapGestureRecognizer()
            ..onTap = () =>
                widget.onChanged?.call(toggleWord(text, widget.highlights, w)));
          break;
        }
      }
      children.add(TextSpan(
        text: text.substring(start, end),
        style: isMarked ? marked : null,
        recognizer: recognizer,
      ));
    }
    _recognizers.addAll(recognizers.values);
    return TextSpan(style: widget.style, children: children);
  }

  @override
  Widget build(BuildContext context) {
    final span = _span(context);
    final onChanged = widget.onChanged;
    if (onChanged == null || widget.marking) {
      return Text.rich(span, textAlign: widget.textAlign);
    }
    return SelectableText.rich(
      span,
      textAlign: widget.textAlign,
      contextMenuBuilder: (context, state) {
        final selection = state.textEditingValue.selection;
        final items = [...state.contextMenuButtonItems];
        if (!selection.isCollapsed) {
          final range = (start: selection.start, end: selection.end);
          final marked = highlightRanges(widget.text, widget.highlights)
              .any((m) => m.start < range.end && range.start < m.end);
          items.insert(
            0,
            ContextMenuButtonItem(
              label: marked ? context.s.removeHighlight : context.s.highlight,
              onPressed: () {
                state.hideToolbar();
                onChanged(marked
                    ? removeAt(widget.text, widget.highlights, range)
                    : addPhrase(widget.highlights,
                        widget.text.substring(range.start, range.end)));
              },
            ),
          );
        }
        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: state.contextMenuAnchors,
          buttonItems: items,
        );
      },
    );
  }
}
