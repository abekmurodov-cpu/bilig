import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import 'note_text.dart';

/// Formatting buttons for a note field (bold, italic, lists, heading, code,
/// formula), each adding the Markdown marks around the selection, and a
/// preview of how the note will look.
class FormatBar extends StatefulWidget {
  const FormatBar({super.key, required this.controller});

  final TextEditingController controller;

  @override
  State<FormatBar> createState() => _FormatBarState();
}

class _FormatBarState extends State<FormatBar> {
  bool _preview = false;

  TextEditingController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_changed);
  }

  @override
  void dispose() {
    _c.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (_preview) setState(() {});
  }

  TextSelection get _selection {
    final s = _c.selection;
    return s.isValid ? s : TextSelection.collapsed(offset: _c.text.length);
  }

  /// Puts [before] and [after] around the selection; with nothing selected,
  /// inserts [placeholder] between them and selects it to type over.
  void _wrap(String before, String after, {String placeholder = ''}) {
    final s = _selection;
    final text = _c.text;
    final inner = s.isCollapsed ? placeholder : text.substring(s.start, s.end);
    final next = text.replaceRange(s.start, s.end, '$before$inner$after');
    _c.value = TextEditingValue(
      text: next,
      selection: TextSelection(
        baseOffset: s.start + before.length,
        extentOffset: s.start + before.length + inner.length,
      ),
    );
  }

  /// Starts each selected line (or the current one) with [prefix]; numbered
  /// lists count up.
  void _prefixLines(String Function(int index) prefix) {
    final s = _selection;
    final text = _c.text;
    final start = text.lastIndexOf('\n', s.start == 0 ? 0 : s.start - 1) + 1;
    var end = text.indexOf('\n', s.end);
    if (end < 0) end = text.length;
    final lines = text.substring(start, end).split('\n');
    final changed = [
      for (var i = 0; i < lines.length; i++) '${prefix(i)}${lines[i]}',
    ].join('\n');
    _c.value = TextEditingValue(
      text: text.replaceRange(start, end, changed),
      selection: TextSelection.collapsed(offset: start + changed.length),
    );
  }

  /// A block (code or formula) on lines of its own.
  void _block(String open, String close, String placeholder) {
    final s = _selection;
    final text = _c.text;
    final before = s.start > 0 && text[s.start - 1] != '\n' ? '\n' : '';
    final after = s.end < text.length && text[s.end] != '\n' ? '\n' : '';
    _wrap('$before$open\n', '\n$close$after', placeholder: placeholder);
  }

  Future<void> _formulaHelp() async {
    final strings = context.s;
    const examples = [
      r'x^2 + y^2 = z^2',
      r'\frac{a}{b}',
      r'\sqrt{b^2 - 4ac}',
      r'\sum_{i=1}^{n} x_i',
      r'\int_0^1 f(x)\,dx',
      r'\alpha, \beta, \Delta, \pi',
      r'P = \frac{\Delta Q}{\Delta t}',
    ];
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(strings.formulaHelp),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              strings.formulaHelpBlurb,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          for (final tex in examples)
            ListTile(
              title: NoteText(text: '\$$tex\$'),
              subtitle: Text(
                tex,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              onTap: () => Navigator.pop(context, tex),
            ),
        ],
      ),
    );
    if (picked != null) _wrap(r'$', r'$', placeholder: picked);
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.s;
    final scheme = Theme.of(context).colorScheme;
    Widget button(IconData icon, String tip, VoidCallback onTap) => IconButton(
      tooltip: tip,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, size: 20),
      onPressed: onTap,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      button(
                        Icons.format_bold,
                        strings.fmtBold,
                        () => _wrap(
                          '**',
                          '**',
                          placeholder: strings.fmtBold.toLowerCase(),
                        ),
                      ),
                      button(
                        Icons.format_italic,
                        strings.fmtItalic,
                        () => _wrap(
                          '*',
                          '*',
                          placeholder: strings.fmtItalic.toLowerCase(),
                        ),
                      ),
                      button(
                        Icons.title,
                        strings.fmtHeading,
                        () => _prefixLines((_) => '## '),
                      ),
                      button(
                        Icons.format_list_bulleted,
                        strings.fmtBullets,
                        () => _prefixLines((_) => '- '),
                      ),
                      button(
                        Icons.format_list_numbered,
                        strings.fmtNumbers,
                        () => _prefixLines((i) => '${i + 1}. '),
                      ),
                      button(Icons.code, strings.fmtCode, () {
                        final s = _selection;
                        final multiline =
                            !s.isCollapsed &&
                            _c.text.substring(s.start, s.end).contains('\n');
                        multiline
                            ? _block('```', '```', '')
                            : _wrap('`', '`', placeholder: 'code');
                      }),
                      button(
                        Icons.data_object,
                        strings.fmtCodeBlock,
                        () => _block('```', '```', ''),
                      ),
                      button(
                        Icons.functions,
                        strings.fmtFormula,
                        () => _wrap(r'$', r'$', placeholder: 'x^2'),
                      ),
                      button(
                        Icons.calculate_outlined,
                        strings.fmtFormulaBlock,
                        () => _block(r'$$', r'$$', r'\frac{a}{b}'),
                      ),
                      button(
                        Icons.help_outline,
                        strings.formulaHelp,
                        _formulaHelp,
                      ),
                    ],
                  ),
                ),
              ),
              // Always in reach, however narrow the bar.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: FilterChip(
                  label: Text(strings.preview),
                  avatar: Icon(
                    _preview ? Icons.visibility : Icons.visibility_outlined,
                    size: 16,
                  ),
                  showCheckmark: false,
                  selected: _preview,
                  visualDensity: VisualDensity.compact,
                  onSelected: (on) => setState(() => _preview = on),
                ),
              ),
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: !_preview
              ? const SizedBox(width: double.infinity)
              : Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    border: Border.all(color: scheme.outlineVariant),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: _c.text.trim().isEmpty
                      ? Text(
                          strings.previewEmpty,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        )
                      : NoteText(text: _c.text),
                ),
        ),
      ],
    );
  }
}
