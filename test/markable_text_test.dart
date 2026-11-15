import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge/src/ui/widgets/markable_text.dart';

void main() {
  testWidgets('with the marker on, tapping words marks them', (tester) async {
    List<String> highlights = const [];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => MarkableText(
            text: 'Mitochondria make ATP',
            highlights: highlights,
            marking: true,
            onChanged: (h) => setState(() => highlights = h),
          ),
        ),
      ),
    ));
    final text = find.byType(RichText).first;
    // Default test font: every glyph is 14px wide; "ATP" starts at char 18.
    await tester.tapAt(tester.getTopLeft(text) + const Offset(18 * 14 + 7, 7));
    await tester.pump();
    expect(highlights, ['ATP']);
    await tester.tapAt(tester.getTopLeft(text) + const Offset(13 * 14 + 7, 7));
    await tester.pump();
    expect(highlights, ['make ATP']);
  });
}
