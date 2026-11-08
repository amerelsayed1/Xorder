import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/core/ui/tokens.dart';
import 'package:shared_module/core/ui/widgets/mono_amount.dart';

/// The property under test is not "does it show the number" — it is that the
/// number is laid out left-to-right **whatever the surrounding locale**, which
/// is the entire reason this widget exists instead of a styled `Text`.
void main() {
  Widget host(Widget child, {String locale = 'en'}) => MaterialApp(
    locale: Locale(locale),
    theme: buildPosTheme(PosPalette.light),
    localizationsDelegates: const [
      AppLocalizations(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: Center(child: child)),
  );

  /// Pump and settle, because `GlobalMaterialLocalizations` resolves
  /// asynchronously — a single frame renders an empty app and every finder
  /// below would look at nothing.
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    String locale = 'en',
  }) async {
    await tester.pumpWidget(host(child, locale: locale));
    await tester.pumpAndSettle();
  }

  /// The direction the amount's own `Text` is actually laid out in — read from
  /// the `Directionality` the widget establishes, not from the app's.
  TextDirection directionOf(WidgetTester tester, Finder text) =>
      Directionality.of(tester.element(text));

  group('MonoAmount', () {
    testWidgets('renders left-to-right in an English app', (tester) async {
      await pump(tester, const MonoAmount(Money(48650)));

      expect(find.text('486.50 EGP'), findsOneWidget);
      expect(directionOf(tester, find.text('486.50 EGP')), TextDirection.ltr);
    });

    testWidgets('stays left-to-right inside an Arabic, RTL app', (
      tester,
    ) async {
      await pump(tester, const MonoAmount(Money(48650)), locale: 'ar');

      // The app really is RTL — otherwise this test would pass for the wrong
      // reason and go on passing after the guarantee was removed.
      expect(
        Directionality.of(tester.element(find.byType(Scaffold))),
        TextDirection.rtl,
      );
      expect(directionOf(tester, find.text('486.50 EGP')), TextDirection.ltr);
    });

    testWidgets('keeps a negative amount left-to-right in Arabic', (
      tester,
    ) async {
      // The case that motivated the widget: in an RTL paragraph a bare `-50.00`
      // renders with its sign on the wrong end.
      await pump(tester, const MonoAmount(Money(-5000)), locale: 'ar');

      expect(find.text('-50.00 EGP'), findsOneWidget);
      expect(directionOf(tester, find.text('-50.00 EGP')), TextDirection.ltr);
    });

    testWidgets('a negative amount is coloured danger by default', (
      tester,
    ) async {
      await pump(tester, const MonoAmount(Money(-5000)));

      final style = tester.widget<Text>(find.text('-50.00 EGP')).style!;
      expect(style.color, PosPalette.light.danger);
    });

    testWidgets('an explicit colour wins over the negative treatment', (
      tester,
    ) async {
      await pump(tester, const MonoAmount(Money(-5000), color: Color(0xFF00FF00)));

      final style = tester.widget<Text>(find.text('-50.00 EGP')).style!;
      expect(style.color, const Color(0xFF00FF00));
    });

    testWidgets('shows the currency by default, and can be told not to', (
      tester,
    ) async {
      await pump(
        tester,
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MonoAmount(Money(1500)),
            MonoAmount(Money(2500), withCurrency: false),
          ],
        ),
      );

      expect(find.text('15.00 EGP'), findsOneWidget);
      expect(find.text('25.00'), findsOneWidget);
    });

    testWidgets('masks to a fixed length that does not leak the magnitude', (
      tester,
    ) async {
      await pump(
        tester,
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MonoAmount(Money(100), masked: true),
            MonoAmount(Money(1234000), masked: true),
          ],
        ),
      );

      // Two wildly different figures, one mask. A mask whose width tracked the
      // value would give a blind count away at a glance.
      final masks = tester.widgetList<Text>(find.byType(Text)).toList();
      expect(masks, hasLength(2));
      expect(masks.first.data, masks.last.data);
      expect(find.text('1.00'), findsNothing);
      expect(find.text('12,340.00'), findsNothing);
    });

    testWidgets('renders in mono', (tester) async {
      await pump(tester, const MonoAmount(Money(48650)));

      final style = tester.widget<Text>(find.text('486.50 EGP')).style!;
      expect(style.fontFamily, PosFonts.mono);
    });
  });

  group('MonoCode', () {
    testWidgets('an invoice number stays left-to-right in Arabic', (
      tester,
    ) async {
      await pump(tester, const MonoCode('INV-2481'), locale: 'ar');

      expect(directionOf(tester, find.text('INV-2481')), TextDirection.ltr);
    });
  });
}
