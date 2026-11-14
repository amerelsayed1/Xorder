import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/core/ui/tokens.dart';
import 'package:shared_module/core/ui/widgets/item_name.dart';
import 'package:shared_module/domain/models/catalog.dart';
import 'package:shared_module/domain/models/ticket.dart';
import 'package:shared_module/features/sale/widgets/cart_panel.dart';
import 'package:shared_module/features/sale/widgets/product_grid.dart';

/// Item names are cut at the end they are read from, never in the middle.
///
/// **The bug under test (audit S4-2).** A name in the other script from the
/// till — an Arabic menu on an English till, or the reverse — was laid out in
/// the till's direction, and the bidi algorithm put the ellipsis in the middle
/// of the word with the halves swapped. Nothing here measures glyphs: the
/// property that fixes it is that the `Text` carries the name's own direction
/// with an end ellipsis, and that is what is asserted on every call site.
void main() {
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1440, 1200);
    view.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  Widget app(String locale, Widget child) => MaterialApp(
    locale: Locale(locale),
    theme: buildPosTheme(PosPalette.light),
    localizationsDelegates: const [
      AppLocalizations(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  Text textOf(WidgetTester tester, String name) =>
      tester.widget<Text>(find.text(name));

  /// Pumped to settle: the localisation delegate loads asynchronously and
  /// the first frame under `MaterialApp` is empty until it has.
  Future<void> show(WidgetTester tester, String locale, Widget child) async {
    await tester.pumpWidget(app(locale, child));
    await tester.pumpAndSettle();
  }

  group('scriptDirectionOf', () {
    test('reads Arabic right to left and Latin left to right', () {
      expect(scriptDirectionOf('شاورما فراخ'), TextDirection.rtl);
      expect(scriptDirectionOf('Mixed Grill'), TextDirection.ltr);
    });

    test('goes by the first strong character, not the first character', () {
      // A size or a number in front of the name does not decide it.
      expect(scriptDirectionOf('330 مل كولا'), TextDirection.rtl);
      expect(scriptDirectionOf('2× Pepsi'), TextDirection.ltr);
    });

    test('has no opinion on a string with no letters', () {
      expect(scriptDirectionOf('330'), isNull);
      expect(scriptDirectionOf('—'), isNull);
      expect(scriptDirectionOf(''), isNull);
    });
  });

  group('ItemName', () {
    testWidgets('an Arabic name on an English till reads right to left, '
        'ellipsised at its end', (tester) async {
      await show(
        tester,
        'en',
        SizedBox(
          width: 120,
          child: ItemName(
            'شاورما فراخ سبيشال بالجبنة والصوص',
            maxLines: 2,
            style: PosText.ui(size: 14, color: Colors.black),
          ),
        ),
      );

      final text = textOf(tester, 'شاورما فراخ سبيشال بالجبنة والصوص');
      expect(text.textDirection, TextDirection.rtl);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(text.maxLines, 2);
      // Aligned to the column's edge, not the name's — a column of names on
      // an English till keeps lining up on the left.
      expect(text.textAlign, TextAlign.left);
    });

    testWidgets('an English name on an Arabic till reads left to right', (
      tester,
    ) async {
      await show(
        tester,
        'ar',
        SizedBox(
          width: 120,
          child: ItemName(
            'Classic Cheeseburger Deluxe',
            style: PosText.ui(size: 14, color: Colors.black),
          ),
        ),
      );

      final text = textOf(tester, 'Classic Cheeseburger Deluxe');
      expect(text.textDirection, TextDirection.ltr);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(text.maxLines, 1);
      expect(text.textAlign, TextAlign.right);
    });

    testWidgets('a name with no letters follows the till', (tester) async {
      await show(
        tester,
        'ar',
        ItemName('330', style: PosText.ui(color: Colors.black)),
      );
      expect(textOf(tester, '330').textDirection, TextDirection.rtl);
    });
  });

  group('on the sale screen', () {
    const arabicOnly = Product(
      id: 1,
      categoryId: 11,
      // A menu typed in Arabic into the English field — common, and the
      // case the audit photographed.
      nameEn: 'شاورما فراخ سبيشال بالجبنة',
      price: Money(9500),
    );
    const englishOnly = Product(
      id: 2,
      categoryId: 11,
      nameEn: 'Classic Cheeseburger Deluxe',
      price: Money(12000),
    );

    testWidgets('the cart line gives an Arabic name its own direction and '
        'two lines before the ellipsis', (tester) async {
      await tester.pumpWidget(
        app(
          'en',
          CartPanel(
            ticket: Ticket(
              id: 'txn-1',
              orderType: OrderType.takeaway,
              lines: [TicketLine(product: arabicOnly, quantity: 1)],
            ),
            cashierName: 'Nour Adel',
            online: true,
            onQuantityChanged: (_, _) {},
            onHold: () {},
            onVoid: () {},
            onCharge: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final text = textOf(tester, arabicOnly.nameEn);
      expect(text.textDirection, TextDirection.rtl);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(text.maxLines, 2);
    });

    testWidgets('the product tile does the same, and the reverse on an '
        'Arabic till', (tester) async {
      await tester.pumpWidget(
        app(
          'ar',
          Row(
            children: [
              for (final product in [arabicOnly, englishOnly])
                SizedBox(
                  width: 150,
                  height: PosSize.productTile,
                  child: ProductTile(
                    product: product,
                    barColor: Colors.black,
                    inCart: false,
                    onTap: () {},
                  ),
                ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final arabic = textOf(tester, arabicOnly.nameEn);
      expect(arabic.textDirection, TextDirection.rtl);
      expect(arabic.overflow, TextOverflow.ellipsis);
      expect(arabic.maxLines, 2);

      final english = textOf(tester, englishOnly.nameEn);
      expect(english.textDirection, TextDirection.ltr);
      expect(english.overflow, TextOverflow.ellipsis);
      expect(english.maxLines, 2);
    });
  });
}
