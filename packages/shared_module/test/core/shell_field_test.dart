import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/core/ui/tokens.dart';
import 'package:shared_module/core/ui/widgets/pos_widgets.dart';

/// A box on the shell draws one frame.
///
/// `border: InputBorder.none` looks like it removes a field's border and does
/// not: the theme's resting and focused borders still apply. Wrapped in a frame
/// of its own, the username box drew a heavy ink outline inside the thin one —
/// orange once focused — on the till's sign-in, the shift dialog and the back
/// office's door.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      theme: buildPosTheme(PosPalette.light),
      home: Scaffold(body: Center(child: SizedBox(width: 400, child: child))),
    ),
  );

  testWidgets('the username box is one frame: thin at rest, accent in focus', (
    tester,
  ) async {
    await pump(tester, UsernameField(controller: TextEditingController()));

    final decoration = tester
        .widget<InputDecorator>(find.byType(InputDecorator))
        .decoration;
    expect(
      (decoration.enabledBorder! as OutlineInputBorder).borderSide,
      PosPalette.light.shellBorder,
      reason: 'the resting frame is the thin shell line, not the heavy ink one',
    );
    expect(
      (decoration.focusedBorder! as OutlineInputBorder).borderSide.color,
      PosPalette.light.accent,
    );

    // And nothing around the box draws a second one.
    final framed = find.descendant(
      of: find.byType(UsernameField),
      matching: find.byWidgetPredicate(
        (w) =>
            w is DecoratedBox &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).border != null,
      ),
    );
    expect(framed, findsNothing);
  });

  testWidgets('an Arabic label is set in the Arabic face, and not tracked', (
    tester,
  ) async {
    await pump(tester, const MicroLabel('اسم المستخدم'));
    final style = tester.widget<Text>(find.byType(Text)).style!;
    expect(style.fontFamily, PosFonts.ui);
    expect(style.letterSpacing ?? 0, 0);
  });

  testWidgets('an English one stays in spaced capitals', (tester) async {
    await pump(tester, const MicroLabel('Username'));
    final text = tester.widget<Text>(find.byType(Text));
    expect(text.data, 'USERNAME');
    expect(text.style!.fontFamily, PosFonts.mono);
    expect(text.style!.letterSpacing, greaterThan(0));
  });
}
