import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/ui/tokens.dart';
import 'package:xorder_pos/domain/models/catalog.dart';
import 'package:xorder_pos/domain/models/discount.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/domain/services/ticket_engine.dart';
import 'package:xorder_pos/features/sale/widgets/cart_panel.dart';

/// Cart density, and the line note.
///
/// **The rule under test is what compact does NOT drop.** Everything a cashier
/// or a customer needs in order to dispute the ticket — a note, a discount, a
/// void reason, a struck-through price — survives at both densities. A density
/// that hid a reason would make the screen and the ledger disagree at exactly
/// the moment somebody was arguing about them.
void main() {
  Product item(int id) => Product(
    id: id,
    categoryId: 11,
    nameEn: 'Item $id',
    price: const Money(1000),
  );

  Ticket ticket({int lines = 3, List<AppliedDiscount> discounts = const []}) =>
      Ticket(
        id: 'txn-1',
        orderType: OrderType.takeaway,
        taxConfig: const TaxConfig(serviceBp: 0, vatBp: 0),
        lines: [for (var i = 1; i <= lines; i++) TicketLine(product: item(i), quantity: 1)],
        discounts: discounts,
      );

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

  Future<void> pump(
    WidgetTester tester,
    Ticket t, {
    CartDensity density = CartDensity.comfortable,
    ValueChanged<String>? onEditNote,
    String locale = 'en',
  }) async {
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
            ticket: t,
            cashierName: 'Nour Adel',
            online: true,
            density: density,
            onEditNote: onEditNote,
            onQuantityChanged: (_, _) {},
            onSendRound: () {},
            onVoid: () {},
            onCharge: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  double rowHeight(WidgetTester tester, String name) => tester
      .getSize(
        find
            .ancestor(of: find.text(name), matching: find.byType(Container))
            .first,
      )
      .height;

  group('density', () {
    testWidgets('compact rows are shorter than comfortable ones', (
      tester,
    ) async {
      await pump(tester, ticket());
      final comfortable = rowHeight(tester, 'Item 1');

      await pump(tester, ticket(), density: CartDensity.compact);
      final compact = rowHeight(tester, 'Item 1');

      expect(compact, lessThan(comfortable));
    });

    testWidgets('compact fits more lines in the same space', (tester) async {
      // The whole point: a mid-sized full-service check of 9 to 14 lines has to
      // be readable without scrolling past the total.
      await pump(tester, ticket(lines: 12), density: CartDensity.compact);
      final compactTop = tester.getTopLeft(find.text('Item 1')).dy;
      final compactBottom = tester.getBottomLeft(find.text('Item 8')).dy;

      await pump(tester, ticket(lines: 12));
      final roomyTop = tester.getTopLeft(find.text('Item 1')).dy;
      final roomyBottom = tester.getBottomLeft(find.text('Item 8')).dy;

      expect(compactBottom - compactTop, lessThan(roomyBottom - roomyTop));
    });

    testWidgets('a note survives compact', (tester) async {
      var t = ticket(lines: 1);
      t = TicketEngine.setLineNote(t, t.lines.single.key, 'No onions').ticket!;

      await pump(tester, t, density: CartDensity.compact);
      // Hiding it to save eight pixels is how a customer gets the onions they
      // asked not to have.
      expect(find.text('No onions'), findsOneWidget);
    });

    testWidgets('a discount and its approver survive compact', (tester) async {
      final t = ticket(lines: 1);
      final key = t.lines.single.key;

      await pump(
        tester,
        ticket(
          lines: 1,
          discounts: [
            AppliedDiscount(
              nameSnapshot: 'Staff meal',
              kind: DiscountKind.percentage,
              amount: const Money(200),
              appliedByStaffId: 4,
              lineKey: key,
              approvedByName: 'Hana Mostafa',
            ),
          ],
        ),
        density: CartDensity.compact,
      );

      // One row, naming both — the approver is what answers the question a
      // cashier cannot answer at the till.
      expect(find.textContaining('Staff meal'), findsOneWidget);
      expect(find.textContaining('Hana Mostafa'), findsOneWidget);
    });

    testWidgets('a void reason survives compact', (tester) async {
      var t = ticket(lines: 1);
      t = t.copyWith(
        lines: [t.lines.single.copyWith(stage: LineStage.sent)],
      );
      t = TicketEngine.voidLine(
        t,
        t.lines.single.key,
        by: 4,
        now: DateTime(2026, 9, 8),
        note: 'Dropped by the runner',
      ).ticket!;

      await pump(tester, t, density: CartDensity.compact);
      expect(find.text('VOID'), findsOneWidget);
      expect(find.text('Dropped by the runner'), findsOneWidget);
    });

    testWidgets('the switch threshold is seven', (tester) async {
      // Seven is what fits comfortably, so the eighth line is exactly the one
      // that would otherwise fall off the bottom.
      expect(CartDensity.switchAbove, 7);
    });
  });

  group('the note affordance', () {
    testWidgets('is absent when the caller offers no handler', (tester) async {
      await pump(tester, ticket(lines: 1));
      expect(find.text('✎'), findsNothing);
    });

    testWidgets('names the line it was pressed on', (tester) async {
      String? asked;
      await pump(
        tester,
        ticket(lines: 2),
        onEditNote: (key) => asked = key,
      );

      await tester.tap(find.text('✎').last);
      await tester.pumpAndSettle();
      expect(asked, TicketLine.keyFor(item(2), const []));
    });

    testWidgets('is not offered on a line the kitchen already has', (
      tester,
    ) async {
      // The quantity controls are draft-only and the note sits with them. A
      // note added after the round went out would never reach the kitchen,
      // and a control that silently does nothing is worse than none.
      var t = ticket(lines: 1);
      t = t.copyWith(
        lines: [t.lines.single.copyWith(stage: LineStage.sent)],
      );

      await pump(tester, t, onEditNote: (_) {});
      expect(find.text('✎'), findsNothing);
    });
  });

  group('TicketEngine.setLineNote', () {
    test('sets the note', () {
      final t = ticket(lines: 1);
      final after =
          TicketEngine.setLineNote(t, t.lines.single.key, 'No onions').ticket!;
      expect(after.lines.single.note, 'No onions');
    });

    test('trims, and an empty note clears rather than stores nothing', () {
      var t = ticket(lines: 1);
      final key = t.lines.single.key;
      t = TicketEngine.setLineNote(t, key, '  No onions  ').ticket!;
      expect(t.lines.single.note, 'No onions');

      // An empty string in the column reads as "somebody typed something" when
      // nobody did.
      t = TicketEngine.setLineNote(t, key, '   ').ticket!;
      expect(t.lines.single.note, isNull);
    });

    test('keeps everything else on the line', () {
      var t = ticket(lines: 1);
      final key = t.lines.single.key;
      t = TicketEngine.overridePrice(
        t,
        key,
        const Money(800),
        by: 4,
        now: DateTime(2026, 9, 8),
      ).ticket!;
      t = TicketEngine.setLineNote(t, key, 'No onions').ticket!;

      // A note must not quietly restore the menu price.
      expect(t.lines.single.isRepriced, isTrue);
      expect(t.lines.single.unitPrice.minor, 800);
    });

    test('a line that is not there is refused', () {
      final result = TicketEngine.setLineNote(ticket(), '999:', 'hello');
      expect(result.refusal, isA<LineNotOnTicket>());
    });

    test('writes no event, because a note changes nobody’s bill', () {
      final t = ticket(lines: 1);
      final after =
          TicketEngine.setLineNote(t, t.lines.single.key, 'No onions').ticket!;
      // An audit ledger that recorded every typo in "no onions" would bury the
      // rows that matter.
      expect(after.lineEvents, isEmpty);
    });
  });
}
