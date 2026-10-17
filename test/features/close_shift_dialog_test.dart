import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/ui/tokens.dart';
import 'package:xorder_pos/data/fakes/fake_repositories.dart';
import 'package:xorder_pos/domain/models/catalog.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/pos_settings.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/domain/services/ticket_engine.dart';
import 'package:xorder_pos/features/shift/presentation/shift_dialogs.dart';

/// The close-shift dialog and the tickets still parked when it opens (S3-5).
///
/// The audit watched a shift closed with an 80.00 ticket parked and a close
/// dialog that listed every count and said nothing about it. Now the dialog
/// says how many are open, what they come to, and which they are — and still
/// lets the owner close over them, because the day close is where a parked
/// ticket is a blocker and a drawer still has to be counted tonight.
void main() {
  const grill = Product(
    id: 101,
    categoryId: 1,
    nameEn: 'Mixed Grill',
    price: Money(38500),
  );
  const drink = Product(
    id: 501,
    categoryId: 5,
    nameEn: 'Soft Drink',
    price: Money(2500),
  );

  final onTable = TicketEngine.addLine(
    Ticket(
      id: 'on-table',
      orderType: OrderType.dineIn,
      tableId: 4,
      tableLabel: 'T4',
    ),
    grill,
  ).ticket!;
  final held = TicketEngine.addLine(
    Ticket(id: 'held', orderType: OrderType.takeaway),
    drink,
  ).ticket!;

  final shift = PosShift(
    id: 7,
    openedAt: DateTime(2026, 10, 16, 9),
    openingFloat: const Money(20000),
    openedByName: 'Amer M.',
    openedById: 1,
  );

  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1440, 900);
    view.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  Future<void> open(
    WidgetTester tester, {
    required OpenTickets parked,
    String locale = 'en',
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          shiftRepositoryProvider.overrideWithValue(FakeShiftRepository()),
          auditRepositoryProvider.overrideWithValue(FakeAuditRepository()),
          cashPolicyProvider.overrideWithValue(CashPolicy.defaults),
          signedInStaffProvider.overrideWith(_Owner.new),
          openTicketsProvider.overrideWith(() => _Parked(parked)),
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
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => CloseShiftDialog.show(context, shift: shift),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  final warning = find.byKey(const Key('close-shift-open-tickets'));

  testWidgets('two parked tickets are named, with their totals', (
    tester,
  ) async {
    await open(
      tester,
      parked: OpenTickets(onTables: {4: onTable}, held: [held]),
    );

    expect(warning, findsOneWidget);
    // The count and the sum, in one line, above the figures.
    final total = TicketEngine.totalOf([onTable, held]);
    expect(
      find.text(
        '2 tickets are still open, ${total.format(withCurrency: true)} in '
        'all — they are not in this count.',
      ),
      findsOneWidget,
    );
    // And each one: the table, or "Held" for the one with none, and what it
    // comes to — the engine's figure, service and VAT included.
    expect(find.text('T4'), findsOneWidget);
    expect(find.text('Held'), findsOneWidget);
    expect(find.text(onTable.totals.total.format()), findsOneWidget);
    expect(find.text(held.totals.total.format()), findsOneWidget);

    // Still closable: a warning, not a refusal.
    final close = tester.widget<InkWell>(
      find
          .ancestor(
            of: find.text('Close shift'),
            matching: find.byType(InkWell),
          )
          .first,
    );
    expect(close.onTap, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('one ticket is stated in the singular', (tester) async {
    await open(tester, parked: OpenTickets(held: [held]));

    expect(
      find.textContaining('1 ticket is still open'),
      findsOneWidget,
    );
  });

  testWidgets('nothing parked, no warning', (tester) async {
    await open(tester, parked: const OpenTickets());

    expect(warning, findsNothing);
    expect(find.textContaining('still open'), findsNothing);
    expect(find.text('Close shift'), findsOneWidget);
  });

  testWidgets('and in Arabic, without overflowing', (tester) async {
    await open(
      tester,
      locale: 'ar',
      parked: OpenTickets(onTables: {4: onTable}, held: [held]),
    );

    expect(warning, findsOneWidget);
    expect(find.text('معلّقة'), findsOneWidget);
    expect(find.textContaining('تذاكر مفتوحة'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _Owner extends SignedInStaffController {
  @override
  PosStaff? build() => const PosStaff(
    id: 1,
    name: 'Amer M.',
    capabilities: {
      PosCapability.operate,
      PosCapability.shiftClose,
      PosCapability.shiftViewExpectedCash,
      PosCapability.cashVarianceView,
    },
  );
}

/// The floor and the counter as the test left them — no database to hydrate
/// from, and nothing to write through to.
class _Parked extends OpenTicketsController {
  _Parked(this.parked);

  final OpenTickets parked;

  @override
  OpenTickets build() => parked;
}
