import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/ui/tokens.dart';
import 'package:xorder_pos/data/fakes/fake_repositories.dart';
import 'package:xorder_pos/domain/models/order_record.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/refund.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/domain/repositories/admin_repositories.dart';
import 'package:xorder_pos/domain/services/authorization.dart';
import 'package:xorder_pos/features/admin/application/admin_session.dart';
import 'package:xorder_pos/features/admin/presentation/management_screen.dart';
import 'package:xorder_pos/features/history/presentation/order_history_screen.dart';
import 'package:xorder_pos/features/receipt/reprint_dialog.dart';

import '../support/fakes.dart';

// The two people who can come through the door in the fake session
// repository, as it returns them — each holding what they hold through a
// ROLE, because `PosStaff.capabilities` is direct grants only.
const _amer = PosStaff(
  id: 1,
  name: 'Amer M.',
  username: 'amer',
  role: FakeSessionRepository.owner,
);
// Let into Admin Mode by the owner, and holding nothing else of note —
// crucially not `order.view_all`.
const _nour = PosStaff(
  id: 3,
  name: 'Nour S.',
  username: 'nour',
  role: FakeSessionRepository.trustedSupervisor,
);
// The cashier at the till behind the back office. Rana shares Amer's id in
// the fakes, so the till-side tests below use Nour for the administrator.
const _rana = PosStaff(
  id: 1,
  name: 'Rana A.',
  username: 'rana',
  role: FakeSessionRepository.cashier,
);

final _today = DateTime.now();
DateTime _at(int hour) =>
    DateTime(_today.year, _today.month, _today.day, hour);

OrderRecord _order(int id, String invoice, int servedBy, int hour) =>
    OrderRecord(
      id: id,
      clientTransactionId: 'txn-$id',
      invoiceNumber: invoice,
      status: OrderStatus.paid,
      orderType: OrderType.takeaway,
      occurredAt: _at(hour),
      subtotal: const Money(26800),
      discount: Money.zero,
      service: Money.zero,
      vat: Money.zero,
      total: const Money(26800),
      paidTotal: const Money(26800),
      servedByStaffId: servedBy,
      terminalName: 'Counter',
      tenders: const [
        OrderRecordTender(tenderTypeId: 1, label: 'Cash'),
        OrderRecordTender(tenderTypeId: 2, label: 'Card'),
      ],
    );

/// Nour's, Rana's (who is Amer's id too) and somebody else's.
final _orders = [
  _order(1, 'NOUR-1', _nour.id, 10),
  _order(2, 'RANA-1', _rana.id, 11),
  _order(3, 'HANA-1', 9, 12),
];

FakeOrderHistoryRepository _repository() => FakeOrderHistoryRepository(
  orders: _orders,
  details: {
    for (final order in _orders)
      order.id: OrderRecordDetail(
        order: order,
        lines: const [
          OrderRecordLine(
            id: 1,
            lineKey: 'L1',
            name: 'Koshari',
            quantity: 1,
            unitPrice: Money(26800),
            lineTotal: Money(26800),
          ),
        ],
        payments: const [
          OrderRecordPayment(
            label: 'Cash',
            amount: Money(20000),
            tenderTypeId: 1,
          ),
          OrderRecordPayment(
            label: 'Card',
            amount: Money(6800),
            tenderTypeId: 2,
          ),
        ],
        discounts: const [],
      ),
  },
);

/// Everything both routes need, the same for both — so that where the rows
/// differ, the only thing that differed was the route.
Future<ProviderContainer> _container(
  FakeOrderHistoryRepository repository, {
  PosStaff? atTheTill,
}) async {
  final container = ProviderContainer(
    overrides: [
      ...fakeRepositoryOverrides(),
      orderHistoryRepositoryProvider.overrideWithValue(repository),
      // No day open: "Today" is the calendar date on both routes.
      businessDayProvider.overrideWith((ref) async => null),
      tenderTypesAllProvider.overrideWith((ref) async => const []),
      refundsForOrderProvider.overrideWith((ref, _) async => const <Refund>[]),
    ],
  );
  addTearDown(container.dispose);
  if (atTheTill != null) {
    container.read(signedInStaffProvider.notifier).signIn(atTheTill);
  }
  return container;
}

Future<void> _mount(
  WidgetTester tester,
  ProviderContainer container,
  Widget home, {
  String language = 'en',
  double width = 1440,
}) async {
  tester.view
    ..physicalSize = Size(width, 900)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      // A new container is a new scope. Unkeyed, a second mount in the same
      // test updates the first scope in place, and the new container never
      // gets the widget tree's vsync — its providers are then paced by bare
      // timers the test binding reports as still pending at the end.
      key: ObjectKey(container),
      container: container,
      child: MaterialApp(
        locale: Locale(language),
        localizationsDelegates: const [
          AppLocalizations(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildPosTheme(),
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// `/orders`, as the router builds it, with [person] signed in at the till.
Future<ProviderContainer> _ordersRoute(
  WidgetTester tester,
  FakeOrderHistoryRepository repository, {
  required PosStaff person,
}) async {
  final container = await _container(repository, atTheTill: person);
  await _mount(tester, container, OrderHistoryScreen(onClose: () {}));
  return container;
}

/// The back office through its door as [username], landing on Sales.
Future<ProviderContainer> _salesTab(
  WidgetTester tester,
  FakeOrderHistoryRepository repository, {
  required String username,
  required String pin,
  PosStaff? atTheTill,
  VoidCallback? onClose,
  String language = 'en',
  double width = 1440,
}) async {
  final container = await _container(repository, atTheTill: atTheTill);
  await _mount(
    tester,
    container,
    // Asked for by name: the door lands on Home since BO-4.
    ManagementScreen(
      onClose: onClose ?? () {},
      onReconfigure: () {},
      initialPane: ManagementPane.sales,
    ),
    language: language,
    width: width,
  );
  await enterAdminMode(tester, username: username, pin: pin);
  return container;
}

Set<String> _listed() => {
  for (final order in _orders)
    if (find.text(order.invoiceNumber).evaluate().isNotEmpty)
      order.invoiceNumber,
};

Future<void> _search(WidgetTester tester, String term) async {
  await tester.enterText(find.byType(TextField), term);
  // Past the screen's debounce.
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

/// The Sales tab (BO-2): `/orders`' own widget, inside the back office.
///
/// **The claim is sameness.** Sales is not a second screen over the sales
/// table; it is the history, re-hosted — so the test that matters is that the
/// same person with the same filters gets the same rows on both routes, and
/// that the one thing that changed is who "the same person" is: inside Admin
/// Mode, whoever came through the door, not whoever is signed in at the till
/// behind it.
void main() {
  group('the same rows as /orders, for the same person and filters', () {
    for (final (person, pin, expected) in [
      (_amer, '4321', {'NOUR-1', 'RANA-1', 'HANA-1'}),
      (_nour, '2468', {'NOUR-1'}),
    ]) {
      testWidgets(person.name, (tester) async {
        final orders = _repository();
        await _ordersRoute(tester, orders, person: person);
        final onRoute = [_listed(), orders.queries.last];
        await _search(tester, 'A-1');
        final onRouteFiltered = [_listed(), orders.queries.last];

        final sales = _repository();
        await _salesTab(
          tester,
          sales,
          username: person.username!,
          pin: pin,
          // Somebody else at the till, so a Sales tab that read the till's
          // operator would disagree with /orders and be caught.
          atTheTill: _rana,
        );
        expect(
          find.byKey(const ValueKey('back-office-pane-sales')),
          findsOneWidget,
        );
        expect([_listed(), sales.queries.last], onRoute);
        expect(_listed(), expected);
        await _search(tester, 'A-1');
        expect([_listed(), sales.queries.last], onRouteFiltered);
      });
    }
  });

  group('whose sales: history_scope, inside the back office', () {
    testWidgets('without order.view_all, the administrator\'s own sales only '
        '— not the cashier\'s at the till', (tester) async {
      // Through the role, as every fixture here: a rule that read
      // `capabilities` would get this wrong the other way.
      expect(
        Authorization.check(_nour, PosCapability.orderViewAll).isAllowed,
        isFalse,
      );
      final sales = _repository();
      await _salesTab(
        tester,
        sales,
        username: 'nour',
        pin: '2468',
        atTheTill: _rana,
      );

      expect(_listed(), {'NOUR-1'});
      expect(sales.queries, isNotEmpty);
      expect(
        sales.queries.map((q) => q.servedByStaffId),
        everyElement(_nour.id),
      );
      expect(find.byKey(OrderHistoryScreen.ownSalesKey), findsOneWidget);
      expect(find.byKey(OrderHistoryScreen.staffFilterKey), findsNothing);
    });

    testWidgets('with order.view_all through the role, the branch', (
      tester,
    ) async {
      final sales = _repository();
      await _salesTab(
        tester,
        sales,
        username: 'amer',
        pin: '4321',
        atTheTill: _rana,
      );

      expect(_listed(), {'NOUR-1', 'RANA-1', 'HANA-1'});
      expect(sales.queries.last.servedByStaffId, isNull);
      expect(find.byKey(OrderHistoryScreen.ownSalesKey), findsNothing);
    });

    testWidgets('a locked till — nobody signed in — still lists for the '
        'administrator', (tester) async {
      // Read through the till's operator, this was an empty list: an
      // unattended till reads nothing, and the owner is not at the till.
      await _salesTab(tester, _repository(), username: 'amer', pin: '4321');
      expect(_listed(), {'NOUR-1', 'RANA-1', 'HANA-1'});
    });

    testWidgets('the person acting is the administrator while Admin Mode '
        'lasts, and the till\'s again after', (tester) async {
      final container = await _salesTab(
        tester,
        _repository(),
        username: 'nour',
        pin: '2468',
        atTheTill: _rana,
      );
      expect(container.read(actingStaffProvider)?.username, 'nour');
      expect(container.read(signedInStaffProvider)?.username, 'rana');

      await tester.tap(find.byKey(const Key('admin-exit')));
      await tester.pumpAndSettle();
      expect(container.read(adminSessionProvider), isNull);
      expect(container.read(actingStaffProvider)?.username, 'rana');
    });
  });

  group('the widget, re-hosted', () {
    testWidgets('no way out of its own: the back office\'s Exit, and its Esc '
        'that leaves the field first', (tester) async {
      var closed = 0;
      await _salesTab(
        tester,
        _repository(),
        username: 'amer',
        pin: '4321',
        onClose: () => closed++,
      );
      const s = EnStrings();
      expect(find.text(s.close), findsNothing);
      expect(find.text(s.orderHistoryTitle), findsNothing);
      expect(find.byKey(const Key('admin-exit')), findsOneWidget);
      // The map's word for the page in the header (14 Sep 2026) — Orders,
      // as the history calls itself — and the history's own title bar not
      // drawn at all.
      expect(find.text(s.adminTitle(s.orderHistoryTitle)), findsOneWidget);

      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(closed, 0, reason: 'the first Esc only leaves the search field');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(closed, 1);
    });

    testWidgets('the payment method and till are on the row', (tester) async {
      await _salesTab(tester, _repository(), username: 'amer', pin: '4321');
      const s = EnStrings();
      expect(
        find.text('${s.tenderCash} + ${s.tenderCard}'),
        findsNWidgets(3),
      );
      expect(find.text('Counter'), findsNWidgets(3));
    });

    testWidgets('Print and Refund, under the administrator\'s permissions', (
      tester,
    ) async {
      const s = EnStrings();
      for (final (person, pin) in [(_amer, '4321'), (_nour, '2468')]) {
        await _salesTab(
          tester,
          _repository(),
          username: person.username!,
          pin: pin,
          atTheTill: _rana,
        );
        await tester.tap(find.text('NOUR-1'));
        await tester.pumpAndSettle();

        // Looking costs nothing, so it is there for anybody who can open it.
        expect(find.text(s.receiptPreviewAction), findsOneWidget);
        for (final (capability, label) in [
          (PosCapability.orderRefund, s.refundAction),
          (PosCapability.receiptReprint, s.receiptReprintAction),
        ]) {
          expect(
            find.text(label),
            Authorization.check(person, capability) is Denied
                ? findsNothing
                : findsOneWidget,
            reason: '${person.name}: $capability',
          );
        }
      }
    });

    testWidgets('a reprint from Sales is the owner\'s, with nobody at the '
        'till', (tester) async {
      // Asked of the till's operator, a locked till refused this outright:
      // nobody signed in holds nothing.
      final container = await _salesTab(
        tester,
        _repository(),
        username: 'amer',
        pin: '4321',
      );
      await tester.tap(find.text('NOUR-1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(const EnStrings().receiptReprintAction));
      await tester.pumpAndSettle();
      expect(find.byType(ReprintDialog), findsOneWidget);

      await tester.tap(find.text(const EnStrings().receiptReprintConfirm));
      await tester.pumpAndSettle();
      final reprints = [
        for (final entry
            in (container.read(auditRepositoryProvider) as FakeAuditRepository)
                .entries)
          if (entry.action == AuditAction.receiptReprinted) entry,
      ];
      expect(reprints, hasLength(1));
      expect(reprints.single.actorName, _amer.name);
    });
  });

  group('Arabic, at the 1100 breakpoint', () {
    // The bundled faces, not the test font, as `back_office_shell_test.dart`
    // measures the strip: the test font draws every glyph a full em wide, so
    // "nothing overflows at 1100 px" was a claim about a font no till ships.
    // It stopped holding when BO-6 gave the owner one more tab — on this
    // cloud till seven Arabic words, at 14 px an em, came to 1,136 px — while
    // the same strip in IBM Plex Sans Arabic still fits, which is what a
    // restaurant sees.
    setUpAll(() async {
      final ui = FontLoader(PosFonts.ui);
      for (final face in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
        ui.addFont(
          rootBundle.load('assets/fonts/IBMPlexSansArabic-$face.ttf'),
        );
      }
      await ui.load();
      final mono = FontLoader(PosFonts.mono);
      for (final face in ['Regular', 'Medium', 'SemiBold']) {
        mono.addFont(rootBundle.load('assets/fonts/IBMPlexMono-$face.ttf'));
      }
      await mono.load();
    });

    testWidgets('right to left, Arabic words, and a table that scrolls '
        'sideways rather than overflowing', (tester) async {
      await _salesTab(
        tester,
        _repository(),
        username: 'amer',
        pin: '4321',
        language: 'ar',
        width: PosSize.wideShellMin,
      );
      expect(tester.takeException(), isNull);

      const s = ArStrings();
      expect(find.text(s.adminTitle(s.orderHistoryTitle)), findsOneWidget);
      expect(find.byKey(OrderHistoryScreen.sidewaysKey), findsOneWidget);
      // The first rows in view, from the start edge — the right.
      final invoice = tester.getRect(find.text('NOUR-1'));
      expect(invoice.right, lessThanOrEqualTo(PosSize.wideShellMin));
      expect(invoice.left, greaterThanOrEqualTo(PosSize.historyDetail));
    });
  });
}
