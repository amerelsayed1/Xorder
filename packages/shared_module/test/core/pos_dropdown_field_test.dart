import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/core/ui/widgets/pos_widgets.dart';

/// README XORDER-007: a form's dropdown must look like the text fields around
/// it. Measured, because there are no golden files to compare against.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    String locale = 'en',
    bool enabled = true,
    ValueChanged<int?>? onChanged,
    List<Widget> extra = const [],
  }) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(locale),
        theme: buildPosTheme(),
        localizationsDelegates: const [
          AppLocalizations(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: AlignmentDirectional.topStart,
            child: SizedBox(
              width: 320,
              child: Column(
                children: [
                  TextField(
                    key: const Key('field'),
                    controller: TextEditingController(text: 'Hana'),
                    style: PosText.ui(size: 14, color: Colors.black),
                  ),
                  const SizedBox(height: 16),
                  PosDropdownField<int>(
                    dropKey: const Key('drop'),
                    value: 2,
                    style: PosText.ui(size: 14, color: Colors.black),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('Cashier')),
                      DropdownMenuItem(value: 2, child: Text('Supervisor')),
                    ],
                    onChanged: enabled ? (onChanged ?? (_) {}) : null,
                    disabledHint: const Text('Supervisor'),
                  ),
                  ...extra,
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Rect box(WidgetTester tester) =>
      tester.getRect(find.byType(InputDecorator).last);

  for (final locale in ['en', 'ar']) {
    group('in $locale', () {
      testWidgets('is as tall as the text field beside it', (tester) async {
        await pump(tester, locale: locale);

        expect(
          box(tester).height,
          closeTo(tester.getSize(find.byType(TextField)).height, 0.5),
        );
        expect(box(tester).width, 320, reason: 'a form row fills its width');
      });

      testWidgets('the value starts at the start edge, the arrow ends at '
          'the other', (tester) async {
        await pump(tester, locale: locale);
        final rect = box(tester);
        final value = tester.getRect(
          find.descendant(
            of: find.byKey(const Key('drop')),
            matching: find.text('Supervisor'),
          ),
        );
        final arrow = tester.getRect(
          find.descendant(
            of: find.byKey(const Key('drop')),
            matching: find.byType(Icon),
          ),
        );

        if (locale == 'en') {
          expect(value.left - rect.left, lessThan(24));
          expect(rect.right - arrow.right, lessThan(24));
          expect(arrow.center.dx, greaterThan(value.center.dx));
        } else {
          expect(rect.right - value.right, lessThan(24));
          expect(arrow.left - rect.left, lessThan(24));
          expect(arrow.center.dx, lessThan(value.center.dx));
        }
      });
    });
  }

  testWidgets('picking an item calls onChanged with it', (tester) async {
    int? picked;
    await pump(tester, onChanged: (v) => picked = v);

    await tester.tap(find.byKey(const Key('drop')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cashier').last);
    await tester.pumpAndSettle();

    expect(picked, 1);
  });

  testWidgets('without onChanged it is disabled and shows its disabled hint', (
    tester,
  ) async {
    await pump(tester, enabled: false);

    expect(find.text('Supervisor'), findsOneWidget);
    await tester.tap(find.byKey(const Key('drop')));
    await tester.pumpAndSettle();
    expect(find.text('Cashier'), findsNothing, reason: 'the menu did not open');
  });

  testWidgets('the inline setting is the compact frame, not the full width', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPosTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PosDropdownField<int>(
                  dropKey: const Key('inline'),
                  value: 5,
                  expanded: false,
                  dense: true,
                  style: PosText.ui(size: 14, color: Colors.black),
                  items: const [
                    DropdownMenuItem(value: 5, child: Text('5 minutes')),
                    DropdownMenuItem(value: 10, child: Text('10 minutes')),
                  ],
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final size = tester.getSize(find.byType(InputDecorator));
    expect(size.width, lessThan(320));
    expect(size.height, lessThan(48), reason: 'tighter than a form field');
  });
}
