import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/app/providers.dart';
import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/core/ui/tokens.dart';
import 'package:shared_module/data/fakes/fake_repositories.dart';
import 'package:shared_module/domain/models/catalog.dart';
import 'package:shared_module/domain/models/shift.dart';
import 'package:shared_module/domain/models/ticket.dart';
import 'package:shared_module/features/sale/sale_screen.dart';
import 'package:shared_module/features/sale/widgets/cart_panel.dart';

import 'package:xorder_pos_test_support/fakes.dart';

/// Two wordings on the sale screen the audit flagged (S4-2).
///
/// The shift label was "SHIFT #0001" in English on the Arabic till — the
/// word travelled with the number out of the domain model. And the totals
/// block printed "Service 0%" and "VAT 0%" on every ticket whose rates were
/// nought, which is every takeaway and every branch that charges no tax.
void main() {
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1440, 1000);
    view.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  const delegates = <LocalizationsDelegate<dynamic>>[
    AppLocalizations(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  group('the shift label', () {
    /// The sale screen with one shift open on the till, in [locale].
    Future<void> pump(WidgetTester tester, String locale) async {
      final shifts = FakeShiftRepository();
      await shifts.open(
        by: const PosStaff(id: 1, name: 'Rana A.'),
        openingFloat: Money.zero,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...fakeRepositoryOverrides(english: locale == 'en'),
            // Replaces the harness's own: the later override wins.
            shiftRepositoryProvider.overrideWithValue(shifts),
          ],
          child: MaterialApp(
            locale: Locale(locale),
            localizationsDelegates: delegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: buildPosTheme(),
            home: SaleScreen(
              onLock: () {},
              onTables: () {},
              onOrders: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('reads in Arabic on an Arabic till', (tester) async {
      await pump(tester, 'ar');

      expect(find.text('SHIFT #0001', findRichText: true), findsNothing);
      final label = const ArStrings().shiftLabel('0001');
      expect(label, startsWith('الوردية'));
      expect(find.text(label, findRichText: true), findsOneWidget);
    });

    testWidgets('keeps the English form on an English till', (tester) async {
      await pump(tester, 'en');
      expect(find.text('SHIFT #0001', findRichText: true), findsOneWidget);
    });

    test('the number stays Western in both languages', () {
      // A shift number is read out to a manager over the phone and typed
      // into a report filter; both languages show the same four digits.
      expect(const EnStrings().shiftLabel('0001'), contains('0001'));
      expect(const ArStrings().shiftLabel('0001'), contains('0001'));
      expect(const ArStrings().shiftLabel('0001'), isNot(contains('٠٠٠١')));
    });

    test('the model hands over the digits and keeps its own reference', () {
      final shift = PosShift(
        id: 7,
        openedAt: DateTime(2026),
        openingFloat: Money.zero,
        openedByName: 'Rana A.',
      );
      expect(shift.number, '0007');
      expect(shift.reference, 'SHIFT #0007');
    });
  });

  group('the totals block', () {
    const dish = Product(
      id: 1,
      categoryId: 11,
      nameEn: 'Mixed Grill',
      price: Money(10000),
    );

    Future<void> pump(
      WidgetTester tester,
      Ticket ticket, {
      String locale = 'en',
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(locale),
          theme: buildPosTheme(PosPalette.light),
          localizationsDelegates: delegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: CartPanel(
              ticket: ticket,
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

    Ticket ticket(OrderType type, TaxConfig config) => Ticket(
      id: 'txn-1',
      orderType: type,
      taxConfig: config,
      lines: [TicketLine(product: dish, quantity: 1)],
    );

    testWidgets('hides a service line and a VAT line whose rate is nought', (
      tester,
    ) async {
      const strings = EnStrings();
      await pump(
        tester,
        ticket(
          OrderType.dineIn,
          const TaxConfig(serviceBp: 0, vatBp: 0, serviceDineInOnly: false),
        ),
      );

      expect(find.text(strings.servicePercent('0')), findsNothing);
      expect(find.text(strings.vatPercent('0')), findsNothing);
      // The rows around them are untouched.
      expect(find.text(strings.subtotal), findsOneWidget);
      expect(find.text(strings.totalCaps), findsOneWidget);
    });

    testWidgets('keeps both lines when the rates are real', (tester) async {
      const strings = EnStrings();
      await pump(tester, ticket(OrderType.dineIn, const TaxConfig()));

      expect(find.text(strings.servicePercent('12')), findsOneWidget);
      expect(find.text(strings.vatPercent('14')), findsOneWidget);
    });

    testWidgets('a takeaway with VAT shows VAT and no service line', (
      tester,
    ) async {
      const strings = EnStrings();
      await pump(tester, ticket(OrderType.takeaway, const TaxConfig()));

      expect(find.text(strings.vatPercent('14')), findsOneWidget);
      expect(find.textContaining('Service'), findsNothing);
    });

    testWidgets('an empty ticket at a real rate still lists the line', (
      tester,
    ) async {
      // The rule is about the RATE. A zero amount on an empty ticket keeps
      // its row, so the block does not jump as the first item lands.
      const strings = EnStrings();
      await pump(
        tester,
        Ticket(id: 'txn-1', orderType: OrderType.dineIn),
      );

      expect(find.text(strings.servicePercent('12')), findsOneWidget);
      expect(find.text(strings.vatPercent('14')), findsOneWidget);
    });

    testWidgets('and the same in Arabic', (tester) async {
      const strings = ArStrings();
      await pump(
        tester,
        ticket(OrderType.takeaway, const TaxConfig(serviceBp: 0, vatBp: 0)),
        locale: 'ar',
      );

      expect(find.text(strings.servicePercent('0')), findsNothing);
      expect(find.text(strings.vatPercent('0')), findsNothing);
      expect(find.text(strings.subtotal), findsOneWidget);
    });
  });
}
