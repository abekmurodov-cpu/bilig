import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge/src/models/note_format.dart';

void main() {
  test('blocks: headings, lists, quotes, code and formulas', () {
    final blocks = parseNote('# Title\nSome **bold** text\n- one\n  - nested\n1. first\n'
        '> quoted\n```py\nprint(1)\n```\n\$\$a^2\$\$\n---');
    expect(blocks.map((b) => b.runtimeType.toString()), [
      'HeadingBlock', 'ParagraphBlock', 'ListItemBlock', 'ListItemBlock', 'ListItemBlock',
      'QuoteBlock', 'CodeBlock', 'MathBlock', 'DividerBlock',
    ]);
    expect((blocks[3] as ListItemBlock).depth, 1);
    expect((blocks[4] as ListItemBlock).number, 1);
    expect((blocks[6] as CodeBlock).language, 'py');
    expect((blocks[6] as CodeBlock).code, 'print(1)');
    expect((blocks[7] as MathBlock).tex, 'a^2');
  });

  test('inline styles', () {
    final runs = parseInline(r'A **bold *both*** `x = 1` and $E=mc^2$ ~~gone~~');
    String describe(Inline r) =>
        '${r.text}:${r.bold ? 'b' : ''}${r.italic ? 'i' : ''}${r.code ? 'c' : ''}${r.math ? 'm' : ''}${r.strike ? 's' : ''}';
    expect(runs.map(describe).where((d) => !d.startsWith(' ')).toList(),
        ['A :', 'bold :b', 'both:bi', 'x = 1:c', 'E=mc^2:m', 'gone:s']);
  });

  test('ordinary text is left alone', () {
    for (final text in [
      r'It costs $5 and $10.',
      'snake_case_name and 2 * 3 * 4',
      'The year 1945. The war ended.',
      "O'zbekiston va o‘zbek tili",
    ]) {
      expect(plainText(text), text, reason: text);
    }
    expect(hasFormatting(r'It costs $5 and $10.'), isFalse);
  });

  test('plain text drops the marks', () {
    expect(plainText('**Mitochondria** make *ATP*\n- fast\n- small'),
        'Mitochondria make ATP\nfast\nsmall');
    expect(plainText(r'Speed: $v = d/t$'), 'Speed: v = d/t');
  });
}
