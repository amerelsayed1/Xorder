import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/core/ui/tokens.dart';
import 'package:shared_module/domain/models/catalog.dart';
import 'package:shared_module/domain/models/tax.dart';
import 'package:shared_module/domain/models/ticket.dart';
import 'package:shared_module/features/sale/widgets/cart_panel.dart';

/// The totals block of the cart reads as two columns — labels on the leading
/// edge, figures on the trailing one — in English and in Arabic.
///
/// The grand total used to float in from the trailing edge: its label was a
/// `Flexible` next to a `Spacer`, which split the free space between them, so
/// the figure stopped short of the rows above it by however much of the
/// label's half the word did not use. Nothing failed; the till just looked
/// crooked, and more so in Arabic where "الإجمالي" is shorter than "TOTAL".
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

  // VAT only: one extra row is enough to compare against, and the amounts
  // (10.00 / 1.40 / 11.40) are distinct so each finds exactly one Text.
  final ticket = Ticket(
    id: 'txn-1',
    orderType: OrderType.takeaway,
    taxConfig: const TaxConfig(serviceBp: 0, vatBp: 1400),
    lines: [
      TicketLine(
        product: const Product(
          id: 1,
          categoryId: 11,
          nameEn: 'Item 1',
          price: Money(1000),
        ),
        quantity: 1,
      ),
    ],
  );

  Future<void> pump(WidgetTester tester, String locale, {Ticket? order}) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(locale),
        theme: buildPosTheme(PosPalette.light),
        localizationsDelegates: const [
          AppLocalizations(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CartPanel(
            ticket: order ?? ticket,
            cashierName: 'Nour Adel',
            online: true,
            onQuantityChanged: (_, _) {},
            onHold: () {},
            onVoid: () {},
            onCharge: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // The label has to say the rate the ticket is taxed at — the default group's
  // once one exists. It used to read `vatBp`: "VAT 0%" beside 164.64 on a till
  // whose group was 14%, and "VAT 14%" beside nothing when the group was 0.
  group('the VAT row names the rate actually applied (XORD-027)', () {
    Ticket taxed({required int vatBp, required List<TaxGroup> groups}) =>
        Ticket(
          id: 'txn-1',
          orderType: OrderType.takeaway,
          taxConfig: TaxConfig(serviceBp: 0, vatBp: vatBp, taxGroups: groups),
          lines: ticket.lines,
        );

    testWidgets('a 14% group under a 0 single rate says 14%', (tester) async {
      await pump(
        tester,
        'en',
        order: taxed(
          vatBp: 0,
          groups: const [
            TaxGroup(id: 1, nameEn: 'VAT', rateBp: 1400, isDefault: true),
          ],
        ),
      );
      expect(find.text('VAT 14%'), findsOneWidget);
      expect(find.text('VAT 0%'), findsNothing);
    });

    testWidgets('a 0 group under a 14% single rate shows no VAT row', (
      tester,
    ) async {
      await pump(
        tester,
        'en',
        order: taxed(
          vatBp: 1400,
          groups: const [
            TaxGroup(id: 1, nameEn: 'VAT', rateBp: 0, isDefault: true),
          ],
        ),
      );
      expect(find.text('VAT 14%'), findsNothing);
      expect(find.textContaining('VAT'), findsNothing);
    });

    testWidgets('a fractional rate is not rounded in the label', (tester) async {
      await pump(
        tester,
        'en',
        order: taxed(
          vatBp: 0,
          groups: const [
            TaxGroup(id: 1, nameEn: 'VAT', rateBp: 1250, isDefault: true),
          ],
        ),
      );
      expect(find.text('VAT 12.5%'), findsOneWidget);
    });
  });

  for (final locale in ['en', 'ar']) {
    final rtl = locale == 'ar';

    // The edge a box ends on, reading in the language's own direction.
    double end(Rect r) => rtl ? r.left : r.right;
    double start(Rect r) => rtl ? r.right : r.left;

    group('totals alignment ($locale)', () {
      testWidgets('every figure ends on the same edge', (tester) async {
        await pump(tester, locale);
        final totals = ticket.totals;

        // `.last`: the single line costs the subtotal too, and the list comes
        // before the totals block in the tree.
        final subtotal = tester.getRect(
          find.text(totals.subtotal.format()).last,
        );
        final vat = tester.getRect(find.text(totals.vat.format()));
        final total = tester.getRect(find.text(totals.total.format()));

        expect(end(vat), closeTo(end(subtotal), 0.5));
        expect(
          end(total),
          closeTo(end(subtotal), 0.5),
          reason: 'the grand total figure floats off the column of figures',
        );
      });

      testWidgets('an empty order — the first thing a cashier sees — too', (
        tester,
      ) async {
        // Short figures leave the most free space beside the total's label,
        // which is exactly where the old Flexible + Spacer wasted it. Under
        // the test font the label is wide enough to hide that in a full
        // order, so this is the case that can fail.
        final empty = Ticket(
          id: 'txn-2',
          orderType: OrderType.takeaway,
          taxConfig: const TaxConfig(serviceBp: 0, vatBp: 0),
        );
        await pump(tester, locale, order: empty);

        // Two rows, two "0.00"s: subtotal first, grand total second.
        final zeros = find.text(empty.totals.total.format());
        expect(zeros, findsNWidgets(2));
        final subtotal = tester.getRect(zeros.first);
        final total = tester.getRect(zeros.last);

        expect(end(total), closeTo(end(subtotal), 0.5));
      });

      testWidgets('the currency sits past the figure, inside the panel', (
        tester,
      ) async {
        await pump(tester, locale);

        final figure = tester.getRect(find.text(ticket.totals.total.format()));
        // `.last`: every totals row carries the currency; the grand total's is
        // the last one in the tree.
        final currency = tester.getRect(find.text(ticket.currency).last);
        final panel = tester.getRect(find.byType(CartPanel));

        // After the figure in reading direction...
        if (rtl) {
          expect(currency.right, lessThanOrEqualTo(figure.left + 0.5));
          expect(currency.left, greaterThanOrEqualTo(panel.left));
        } else {
          expect(currency.left, greaterThanOrEqualTo(figure.right - 0.5));
          expect(currency.right, lessThanOrEqualTo(panel.right));
        }
      });

      testWidgets('subtotal and VAT carry the currency after the figure, as '
          'the total does', (tester) async {
        await pump(tester, locale);

        // Subtotal, VAT, grand total: three currency codes, in tree order.
        final codes = find.text(ticket.currency);
        expect(codes, findsNWidgets(3));

        final figures = [
          tester.getRect(find.text(ticket.totals.subtotal.format()).last),
          tester.getRect(find.text(ticket.totals.vat.format())),
        ];
        for (var i = 0; i < figures.length; i++) {
          final currency = tester.getRect(codes.at(i));
          if (rtl) {
            expect(currency.right, lessThanOrEqualTo(figures[i].left + 0.5));
          } else {
            expect(currency.left, greaterThanOrEqualTo(figures[i].right - 0.5));
          }
        }
      });

      testWidgets('labels share one leading edge', (tester) async {
        await pump(tester, locale);
        final s = AppStrings.of(Locale(locale));

        final subtotal = tester.getRect(find.text(s.subtotal));
        final total = tester.getRect(find.text(s.totalCaps));

        expect(start(total), closeTo(start(subtotal), 0.5));
      });
    });
  }
}
