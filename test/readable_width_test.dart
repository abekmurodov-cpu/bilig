import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge/src/ui/theme.dart';

void main() {
  Widget list() => ListView(children: [
        for (var i = 0; i < 100; i++) SizedBox(height: 50, child: Text('row $i')),
      ]);

  double offset(WidgetTester tester) =>
      tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels;

  Future<void> wheel(WidgetTester tester, Offset at) async {
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(at));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 200)));
    await tester.pump();
  }

  testWidgets('the margins beside ReadableWidth scroll the list', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ReadableWidth(child: list()))));

    await wheel(tester, const Offset(40, 400));
    expect(offset(tester), 200, reason: 'left margin');
    await wheel(tester, const Offset(1380, 400));
    expect(offset(tester), 400, reason: 'right margin');
    await wheel(tester, const Offset(700, 400));
    expect(offset(tester), 600, reason: 'the list itself, scrolled once');
  });

  testWidgets('ReadableBuilder makes the list full-width', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ReadableBuilder(
          builder: (context, gutter) => ListView(padding: gutter, children: [
            for (var i = 0; i < 100; i++) SizedBox(height: 50, child: Text('row $i')),
          ]),
        ),
      ),
    ));
    expect(tester.getSize(find.byType(ListView)).width, 1400);
    expect(tester.getTopLeft(find.text('row 0')).dx, (1400 - 760) / 2);
    await wheel(tester, const Offset(40, 400));
    expect(offset(tester), 200);
  });
}
