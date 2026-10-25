import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/ui/tokens.dart';
import 'package:xorder_pos/domain/models/catalog.dart';
import 'package:xorder_pos/domain/models/discount.dart';
import 'package:xorder_pos/domain/models/reason_code.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/domain/repositories/repositories.dart';
import 'package:xorder_pos/features/sale/widgets/cart_panel.dart';
import 'package:xorder_pos/features/sale/widgets/price_override_dialog.dart';

/// Repricing a line, as the cashier and the customer see it.
///
/// The arithmetic and the ceiling are pinned in `price_override_test.dart`.
/// What is asserted here is what appears on screen: the struck-through menu
/// price that lets a cashier say "that was 50, it's 40", and a dialog that
/// cannot be confirmed without the reason it claims to require.
void main() {
  const grill = Product(
    id: 101,
    categoryId: 11,
    nameEn: 'Mixed Grill',
    nameAr: 'مشاوي مشكلة',
    price: Money(5000),
  );
  const bread = Modifier(
    id: 7,
    groupId: 3,
    nameEn: 'Extra bread',
    priceDelta: Money(1000),
  );

  TicketLine line({
    int quantity = 2,
    List<Modifier> modifiers = const [],
    PriceOverride? override,
  }) => TicketLine(
    product: grill,
    quantity: quantity,
    modifiers: modifiers,
    priceOverride: override,
  );

  PriceOverride override({int price = 4000, int original = 5000}) =>
      PriceOverride(
        price: Money(price),
        original: Money(original),
        byStaffId: 4,
        at: DateTime(2026, 9, 7, 13),
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

  Widget host(Widget child, {String locale = 'en'}) => ProviderScope(
    overrides: [
      reasonsRepositoryProvider.overrideWithValue(const _Reasons()),
    ],
    child: MaterialApp(
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
    ),
  );

  Future<void> pumpCart(
    WidgetTester tester,
    List<TicketLine> lines, {
    String locale = 'en',
  }) async {
    await tester.pumpWidget(
      host(
        CartPanel(
          ticket: Ticket(
            id: 'txn-1',
            orderType: OrderType.takeaway,
            taxConfig: const TaxConfig(serviceBp: 0, vatBp: 0),
            lines: lines,
          ),
          cashierName: 'Nour Adel',
          online: true,
          onQuantityChanged: (_, _) {},
          onHold: () {},
          onVoid: () {},
          onCharge: () {},
        ),
        locale: locale,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<PriceOverrideChoice? Function()> pumpDialog(
    WidgetTester tester,
    TicketLine on, {
    DiscountLimit? limit,
    String locale = 'en',
  }) async {
    PriceOverrideChoice? result;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await PriceOverrideDialog.show(
                context,
                line: on,
                limit: limit,
              );
            },
            child: const Text('open'),
          ),
        ),
        locale: locale,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () => result;
  }

  group('the cart line', () {
    testWidgets('strikes through the menu price above the agreed one', (
      tester,
    ) async {
      // The sentence a cashier reads to a customer. Without it a repriced line
      // is just a line at an odd price that nobody can explain later.
      await pumpCart(tester, [line(quantity: 2, override: override())]);

      expect(find.text('100.00 EGP'), findsOneWidget); // struck through
      expect(find.text('80.00 EGP'), findsWidgets); // charged

      final struck = tester.widget<Text>(find.text('100.00 EGP'));
      expect(struck.style?.decoration, TextDecoration.lineThrough);
    });

    testWidgets('marks the line so it can be picked out of a list', (
      tester,
    ) async {
      await pumpCart(tester, [line(override: override())]);
      expect(find.text('PRICE'), findsOneWidget);
    });

    testWidgets('a line at the menu price carries no mark and no strike', (
      tester,
    ) async {
      await pumpCart(tester, [line()]);
      expect(find.text('PRICE'), findsNothing);
      expect(find.text('100.00'), findsWidgets);
    });

    testWidgets('a voided repriced line reads as voided, not as repriced', (
      tester,
    ) async {
      // Two marks on one line would say two things happened. The void is the
      // one that matters — nobody is being charged either price.
      await pumpCart(tester, [
        TicketLine(
          product: grill,
          quantity: 2,
          priceOverride: override(),
          voided: LineVoid(byStaffId: 4, at: DateTime(2026, 9, 7)),
        ),
      ]);
      expect(find.text('PRICE'), findsNothing);
    });

    testWidgets('renders in Arabic without overflowing', (tester) async {
      await pumpCart(
        tester,
        [line(override: override())],
        locale: 'ar',
      );
      expect(find.text('سعر'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the dialog', () {
    testWidgets('opens on the price being charged now', (tester) async {
      // Type-over, not clear-then-type. An empty field asks "what price?"
      // without saying what the price is.
      await pumpDialog(tester, line());
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '50.00',
      );
    });

    testWidgets('shows the menu price struck through', (tester) async {
      await pumpDialog(tester, line(modifiers: const [bread]));
      // 50.00 plus 10.00 of bread — the whole unit price, which is what the
      // override replaces.
      expect(find.text('60.00'), findsWidgets);
    });

    testWidgets('shows the line total when there is more than one', (
      tester,
    ) async {
      await pumpDialog(tester, line(quantity: 3));
      expect(find.textContaining('3×'), findsOneWidget);
      expect(find.text('150.00 EGP'), findsOneWidget);
    });

    testWidgets('will not confirm without the reason it requires', (
      tester,
    ) async {
      final result = await pumpDialog(tester, line());
      await tester.enterText(find.byType(TextField).first, '40.00');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Change price'));
      await tester.pumpAndSettle();

      // A required field that has nowhere to go is how a required field
      // quietly becomes optional.
      expect(result(), isNull);
      expect(find.textContaining('reason'), findsWidgets);
    });

    testWidgets('hands back the price and the reason together', (tester) async {
      final result = await pumpDialog(tester, line());
      await tester.enterText(find.byType(TextField).first, '40.00');
      await tester.pumpAndSettle();
      await tester.tap(find.text(SystemReasons.seeded.first.nameEn));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Change price'));
      await tester.pumpAndSettle();

      final choice = result()!;
      expect(choice.price.minor, 4000);
      expect(choice.reason.reasonId, isNotNull);
    });

    testWidgets('refuses the price the line already has', (tester) async {
      final result = await pumpDialog(tester, line());
      await tester.tap(find.text(SystemReasons.seeded.first.nameEn));
      await tester.pumpAndSettle();

      // Still 50.00 — the pre-filled value.
      await tester.tap(find.text('Change price'));
      await tester.pumpAndSettle();
      expect(result(), isNull);
    });

    testWidgets('a comp is a real answer', (tester) async {
      final result = await pumpDialog(tester, line());
      await tester.enterText(find.byType(TextField).first, '0');
      await tester.pumpAndSettle();
      await tester.tap(find.text(SystemReasons.seeded.first.nameEn));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Change price'));
      await tester.pumpAndSettle();

      // Zero must not be read as "nothing happened".
      expect(result(), isNotNull);
      expect(result()!.price.minor, 0);
    });

    testWidgets('does not offer the menu price back on a plain line', (
      tester,
    ) async {
      // A permanently dead "back to menu price" on every other line is clutter
      // in a dialog already asking two questions.
      await pumpDialog(tester, line());
      expect(find.text('Back to menu price'), findsNothing);
    });

    testWidgets('offers the menu price back on a repriced line', (
      tester,
    ) async {
      await pumpDialog(tester, line(override: override()));
      expect(find.text('Back to menu price'), findsOneWidget);
    });

    testWidgets('restoring returns the menu price', (tester) async {
      final result = await pumpDialog(tester, line(override: override()));
      await tester.tap(find.text('Back to menu price'));
      await tester.pumpAndSettle();
      expect(result()!.price.minor, 5000);
    });
  });
}

class _Reasons implements ReasonsRepository {
  const _Reasons();

  @override
  Future<List<ReasonCode>> forScope(ReasonScope scope) async => [
    for (var i = 0; i < 3; i++)
      ReasonCode(
        id: i + 1,
        scope: scope,
        code: SystemReasons.seeded[i].code,
        nameEn: SystemReasons.seeded[i].nameEn,
        nameAr: SystemReasons.seeded[i].nameAr,
        sortOrder: i + 1,
      ),
  ];
}
