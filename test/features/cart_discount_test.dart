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
import 'package:xorder_pos/features/sale/widgets/cart_panel.dart';

/// How a discount reads on the ticket the customer is shown.
///
/// The split asserted here is the one the schema already makes: a line discount
/// belongs **inside its line**, an order discount belongs in the **totals
/// block**, and neither may be drawn where the other goes. A cashier has to be
/// able to point at the screen and say which item was reduced.
void main() {
  const burger = Product(
    id: 101,
    categoryId: 11,
    nameEn: 'Classic Burger',
    price: Money(10000),
  );
  const chips = Product(
    id: 102,
    categoryId: 11,
    nameEn: 'Chips',
    price: Money(2500),
  );

  Ticket ticket({
    List<AppliedDiscount> discounts = const [],
    List<TicketLine>? lines,
  }) => Ticket(
    id: 'txn-1',
    orderType: OrderType.takeaway,
    taxConfig: const TaxConfig(serviceBp: 0, vatBp: 0),
    lines:
        lines ??
        [
          TicketLine(product: burger, quantity: 2),
          TicketLine(product: chips, quantity: 1),
        ],
    discounts: discounts,
  );

  final burgerKey = TicketLine.keyFor(burger, const []);

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
    String? selected,
    ValueChanged<String>? onSelect,
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
            selectedLineKey: selected,
            onSelectLine: onSelect,
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

  group('a line discount', () {
    testWidgets('renders inside the line it came off', (tester) async {
      await pump(
        tester,
        ticket(
          discounts: [
            AppliedDiscount(
              nameSnapshot: 'Staff meal',
              kind: DiscountKind.percentage,
              amount: const Money(2000),
              appliedByStaffId: 4,
              lineKey: burgerKey,
            ),
          ],
        ),
      );

      expect(find.textContaining('Staff meal'), findsOneWidget);
      expect(find.text('-20.00'), findsOneWidget);
    });

    testWidgets('names the approver, so the question is already answered', (
      tester,
    ) async {
      await pump(
        tester,
        ticket(
          discounts: [
            AppliedDiscount(
              nameSnapshot: 'Manager comp',
              kind: DiscountKind.percentage,
              amount: const Money(2000),
              appliedByStaffId: 4,
              lineKey: burgerKey,
              approvedByName: 'Hana M.',
            ),
          ],
        ),
      );

      // A line reading "Discount 30%" invites the question the cashier cannot
      // answer at the till, in front of the customer.
      expect(find.textContaining('approved by Hana M.'), findsOneWidget);
    });

    testWidgets('an unapproved one says nothing about an approver', (
      tester,
    ) async {
      await pump(
        tester,
        ticket(
          discounts: [
            AppliedDiscount(
              nameSnapshot: 'Staff meal',
              kind: DiscountKind.percentage,
              amount: const Money(2000),
              appliedByStaffId: 4,
              lineKey: burgerKey,
            ),
          ],
        ),
      );

      expect(find.textContaining('approved by'), findsNothing);
    });

    testWidgets('only the discounted line carries one', (tester) async {
      await pump(
        tester,
        ticket(
          discounts: [
            AppliedDiscount(
              nameSnapshot: 'Staff meal',
              kind: DiscountKind.percentage,
              amount: const Money(2000),
              appliedByStaffId: 4,
              lineKey: burgerKey,
            ),
          ],
        ),
      );

      expect(find.textContaining('Staff meal'), findsOneWidget);
    });
  });

  group('an order discount', () {
    testWidgets('renders in the totals block, not inside a line', (
      tester,
    ) async {
      await pump(
        tester,
        ticket(
          discounts: [
            const AppliedDiscount(
              nameSnapshot: 'Ten off',
              kind: DiscountKind.percentage,
              amount: Money(2250),
              appliedByStaffId: 4,
            ),
          ],
        ),
      );

      // A discount that came off the whole bill has no line to belong to, and
      // drawing it under one would be a claim about what it discounted.
      expect(find.text('Ten off'), findsOneWidget);
      expect(find.text('-22.50'), findsOneWidget);
    });

    testWidgets('the total already reflects it', (tester) async {
      await pump(
        tester,
        ticket(
          discounts: [
            const AppliedDiscount(
              nameSnapshot: 'Ten off',
              kind: DiscountKind.percentage,
              amount: Money(2250),
              appliedByStaffId: 4,
            ),
          ],
        ),
      );

      // 225.00 of food less 22.50, with no service and no VAT in this fixture.
      expect(find.text('202.50'), findsWidgets);
    });
  });

  group('selection', () {
    testWidgets('reports the line that was tapped', (tester) async {
      String? picked;
      await pump(tester, ticket(), onSelect: (key) => picked = key);

      await tester.tap(find.text('Classic Burger'));
      await tester.pumpAndSettle();
      expect(picked, burgerKey);
    });

    testWidgets('a sent line can be selected too', (tester) async {
      // Line-level acts apply to what is already cooking as much as to what is
      // not — arguably more.
      String? picked;
      final t = ticket(
        lines: [
          TicketLine(
            product: burger,
            quantity: 1,
            stage: LineStage.sent,
            roundNumber: 1,
          ),
        ],
      );
      await pump(tester, t, onSelect: (key) => picked = key);

      await tester.tap(find.text('Classic Burger'));
      await tester.pumpAndSettle();
      expect(picked, burgerKey);
    });

    testWidgets('with no handler the rows are inert', (tester) async {
      await pump(tester, ticket());

      // The panel is used in places that have no notion of a selection; it must
      // not invent one.
      await tester.tap(find.text('Classic Burger'));
      await tester.pumpAndSettle();
    });
  });

  group('Arabic', () {
    testWidgets('the discount amount stays left to right', (tester) async {
      await pump(
        tester,
        ticket(
          discounts: [
            AppliedDiscount(
              nameSnapshot: 'وجبة موظفين',
              kind: DiscountKind.percentage,
              amount: const Money(2000),
              appliedByStaffId: 4,
              lineKey: burgerKey,
            ),
          ],
        ),
        locale: 'ar',
      );

      expect(
        Directionality.of(tester.element(find.text('-20.00'))),
        TextDirection.ltr,
      );
    });
  });

  group('a voided line', () {
    Ticket withVoid() => ticket(
      lines: [
        TicketLine(
          product: burger,
          quantity: 2,
          stage: LineStage.sent,
          roundNumber: 1,
          voided: LineVoid(
            byStaffId: 4,
            at: DateTime(2026, 9, 8, 12),
            reasonId: 2,
            note: 'Dropped by the runner',
          ),
        ),
        TicketLine(product: chips, quantity: 1, stage: LineStage.sent),
      ],
    );

    testWidgets('stays on the ticket, marked', (tester) async {
      await pump(tester, withVoid());

      // Removing it would leave the cashier unable to show a customer what
      // happened and what it cost.
      expect(find.text('Classic Burger'), findsOneWidget);
      expect(find.text('VOID'), findsOneWidget);
    });

    testWidgets('its price is struck through, not hidden', (tester) async {
      await pump(tester, withVoid());

      final price = tester.widget<Text>(find.text('200.00'));
      // The price is what the customer is being shown they are NOT paying.
      expect(price.style!.decoration, TextDecoration.lineThrough);
    });

    testWidgets('the reason is on the line, in the cashier\'s words', (
      tester,
    ) async {
      await pump(tester, withVoid());
      expect(find.text('Dropped by the runner'), findsOneWidget);
    });

    testWidgets('it is not in the total', (tester) async {
      await pump(tester, withVoid());

      // 200.00 of burger voided, 25.00 of chips left.
      expect(find.text('25.00'), findsWidgets);
    });

    testWidgets('a live line is not struck through', (tester) async {
      await pump(tester, withVoid());

      final price = tester.widget<Text>(find.text('25.00').first);
      expect(price.style?.decoration, isNot(TextDecoration.lineThrough));
    });
  });
}