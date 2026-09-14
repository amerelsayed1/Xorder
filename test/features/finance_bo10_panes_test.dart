import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/app/reports_providers.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/ui/tokens.dart';
import 'package:xorder_pos/core/ui/widgets/mono_amount.dart';
import 'package:xorder_pos/data/fakes/fake_repositories.dart';
import 'package:xorder_pos/domain/models/business_day.dart';
import 'package:xorder_pos/domain/models/finance_report.dart';
import 'package:xorder_pos/domain/models/order_record.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/sales_report.dart';
import 'package:xorder_pos/domain/models/supplier.dart';
import 'package:xorder_pos/domain/models/supplier_invoice.dart';
import 'package:xorder_pos/domain/models/ticket.dart' show OrderType;
import 'package:xorder_pos/domain/repositories/repositories.dart';
import 'package:xorder_pos/features/admin/presentation/management_finance_panes.dart';
import 'package:xorder_pos/features/admin/presentation/management_purchasing_pane.dart';
import 'package:xorder_pos/features/admin/presentation/management_screen.dart';

import '../support/fakes.dart';

// Who reads Finance, each holding what they hold through a ROLE —
// `PosStaff.capabilities` is direct grants only.
const _owner = PosStaff(
  id: 1,
  name: 'Amer M.',
  username: 'amer',
  role: FakeSessionRepository.owner,
);
// The figures, and not the buying.
const _accountant = PosStaff(
  id: 6,
  name: 'Samir B.',
  role: PosRole(
    id: 6,
    code: 'accountant',
    nameEn: 'Accountant',
    capabilities: {PosCapability.reportsView},
  ),
);
const _cashier = PosStaff(
  id: 4,
  name: 'Rana A.',
  role: PosRole(
    id: 2,
    code: 'cashier',
    nameEn: 'Cashier',
    capabilities: {PosCapability.operate},
  ),
);

Money _egp(int minor) => Money(minor, currency: 'EGP', exponent: 2);

/// Two drawer pay-outs; the second is the one supplier payment S13 took out
/// of POS-01's drawer, so it is S13's and not counted on its own.
final _payOuts = [
  CashMovement(
    id: 2,
    kind: CashMovementKind.payOut,
    amount: _egp(3000),
    occurredAt: DateTime(2026, 9, 13, 16),
    note: 'Nile Dairy — I2',
    reasonName: 'Supplier payment',
    terminalName: 'POS-01',
  ),
  CashMovement(
    id: 1,
    kind: CashMovementKind.payOut,
    amount: _egp(1500),
    occurredAt: DateTime(2026, 9, 13, 10),
    reasonName: 'Petty expense',
    reasonNameAr: 'مصروف نثري',
    note: 'Gas cylinder',
    terminalName: 'POS-01',
  ),
];

SupplierPayment _payment(
  int id,
  int amount,
  DateTime at, {
  int? movement,
  DateTime? voided,
  String? invoice,
}) => SupplierPayment(
  id: id,
  supplierId: 1,
  supplierName: 'Nile Dairy',
  amount: _egp(amount),
  method: movement == null
      ? SupplierPaymentMethod.bankTransfer
      : SupplierPaymentMethod.cash,
  paidAt: at,
  cashMovementId: movement,
  voidedAt: voided,
  invoiceId: invoice == null ? null : 1,
  invoiceNumber: invoice,
);

SupplierInvoice _bill(int id, int total, DateTime due, {int paid = 0}) =>
    SupplierInvoice(
      id: id,
      supplierId: 1,
      supplierName: 'Nile Dairy',
      number: 'I$id',
      total: _egp(total),
      paid: _egp(paid),
      issuedAt: DateTime(2026, 9, 12, 9),
      dueAt: due,
    );

/// In the range: an invoice, two live payments and a voided one.
/// Expenses with the ledger: 1,500 + 10,000 + 3,000 = 14,500. Without it:
/// 1,500 + 3,000 = 4,500.
final _spending = SupplierSpending(
  invoices: [_bill(5, 2000, DateTime(2026, 9, 15))],
  payments: [
    _payment(13, 3000, DateTime(2026, 9, 13, 16), movement: 2, invoice: 'I2'),
    _payment(11, 10000, DateTime(2026, 9, 12, 15), invoice: 'I1'),
    _payment(
      14,
      1000,
      DateTime(2026, 9, 12, 12),
      voided: DateTime(2026, 9, 12, 13),
    ),
  ],
  drawerMovementIds: const {2},
);

/// Against the 14th: 5,000 overdue, 4,000 today, 2,000 this week, 9,000
/// later — 20,000 owed.
final _unpaid = [
  _bill(2, 8000, DateTime(2026, 9, 13), paid: 3000),
  _bill(3, 4000, DateTime(2026, 9, 14)),
  _bill(5, 2000, DateTime(2026, 9, 15)),
  _bill(9, 9000, DateTime(2026, 10, 30)),
];

ShiftSummary _summary(
  int id,
  int float, {
  required int cash,
  int card = 0,
  required int paidIn,
  required int paidOut,
}) => ShiftSummary(
  shift: PosShift(
    id: id,
    openedAt: DateTime(2026, 9, 14, 8 + id),
    openingFloat: Money(float),
    openedByName: 'Hoda K.',
    openedById: 9,
  ),
  saleCount: 2,
  gross: Money(cash + card),
  tenders: [
    ShiftTenderTotal(
      label: 'Cash',
      count: 1,
      amount: Money(cash),
      countsAsCash: true,
    ),
    if (card > 0)
      ShiftTenderTotal(
        label: 'Card',
        count: 1,
        amount: Money(card),
        countsAsCash: false,
      ),
  ],
  movements: CashMovementTotals(
    paidIn: Money(paidIn),
    paidOut: Money(paidOut),
    drawerOpens: 0,
    movements: const [],
  ),
);

/// 20,000 + 11,400 + 5,000 − 7,800 = 28,600 and 10,000 + 3,500 + 1,200 −
/// 1,900 = 12,800: 41,400 expected across the two.
final _drawers = [
  OpenDrawer(
    terminalId: 't1',
    terminalName: 'POS-01',
    summary: _summary(1, 20000, cash: 11400, card: 5000, paidIn: 5000, paidOut: 7800),
  ),
  OpenDrawer(
    terminalId: 't2',
    terminalName: 'POS-02',
    summary: _summary(2, 10000, cash: 3500, paidIn: 1200, paidOut: 1900),
  ),
];

final _sale = OrderRecord(
  id: 7,
  clientTransactionId: 'c7',
  invoiceNumber: 'INV-0007',
  status: OrderStatus.paid,
  orderType: OrderType.dineIn,
  occurredAt: DateTime(2026, 9, 13, 12),
  businessDate: DateTime(2026, 9, 13),
  subtotal: _egp(11400),
  discount: _egp(0),
  service: _egp(0),
  vat: _egp(0),
  total: _egp(11400),
  paidTotal: _egp(11400),
);

// ── Test doubles. Never a default binding. ──────────────────────────────────

class _Drawers extends Fake implements CashMovementsRepository {
  final asked = <ReportFilter>[];

  @override
  Future<List<CashMovement>> between(
    ReportFilter filter, {
    Set<CashMovementKind> kinds = const {CashMovementKind.payOut},
  }) async {
    asked.add(filter);
    return _payOuts;
  }
}

class _Ledger extends Fake implements SupplierInvoicesRepository {
  var reads = 0;

  @override
  Future<SupplierSpending> spending(ReportFilter filter) async {
    reads++;
    return _spending;
  }

  @override
  Future<List<SupplierInvoice>> unpaid({int? supplierId}) async {
    reads++;
    return _unpaid;
  }

  // What the Purchasing pane reads when a row opens it.
  @override
  Future<List<SupplierInvoice>> all({int? supplierId, int limit = 200}) async =>
      const [];

  @override
  Future<List<SupplierPayment>> payments({
    int? supplierId,
    int limit = 200,
  }) async => const [];

  @override
  Future<List<SupplierBalance>> balances({DateTime? asOf}) async => const [];
}

class _Tills extends Fake implements ShiftRepository {
  var asked = 0;

  @override
  Future<List<OpenDrawer>> openDrawers() async {
    asked++;
    return _drawers;
  }

  @override
  Future<PosShift?> current() async => null;

  @override
  Future<ShiftActivity> activity() async => ShiftActivity.empty;
}

class _Books extends Fake implements ReportsRepository {
  @override
  Future<SalesReport> sales(ReportFilter filter) async => SalesReport(
    filter: filter,
    terminals: const [],
    days: [
      for (final date in filter.dates)
        ReportDay(
          date: date,
          orders: 0,
          gross: _egp(0),
          discounts: _egp(0),
          refunds: _egp(0),
          refundCount: 0,
        ),
    ],
  );

  @override
  Future<TaxReport> taxes(ReportFilter filter) async => TaxReport(
    filter: filter,
    rates: const [],
    unattributedRefunds: _egp(0),
  );
}

class _Viewer extends SignedInStaffController {
  _Viewer(this.staff);

  final PosStaff? staff;

  @override
  PosStaff? build() => staff;
}

typedef _Doubles = ({_Drawers drawers, _Ledger ledger, _Tills tills});

List<Override> _overrides(_Doubles doubles, {required bool offline}) => [
  ...fakeRepositoryOverrides(),
  if (offline) offlineTerminal(),
  reportsRepositoryProvider.overrideWithValue(_Books()),
  cashMovementsRepositoryProvider.overrideWithValue(doubles.drawers),
  supplierInvoicesRepositoryProvider.overrideWithValue(doubles.ledger),
  // Replaces the harness's `FakeShiftRepository`: the later override wins.
  shiftRepositoryProvider.overrideWithValue(doubles.tills),
  orderHistoryRepositoryProvider.overrideWithValue(
    FakeOrderHistoryRepository(orders: [_sale]),
  ),
  // Trading in the 14th, so "this month" is 1–14 September.
  businessDayProvider.overrideWith(
    (ref) async => BusinessDay(
      id: 1,
      date: DateTime.utc(2026, 9, 14),
      openedAt: DateTime(2026, 9, 14, 8),
    ),
  ),
];

Future<_Doubles> _pump(
  WidgetTester tester,
  Widget pane, {
  PosStaff viewer = _owner,
  bool offline = true,
  String language = 'en',
  double width = 1400,
}) async {
  // Tall, so every row of every table is laid out: a ListView builds only
  // what it shows, and a sum over rows that were never built is no sum.
  tester.view
    ..physicalSize = Size(width, 3200)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final doubles = (drawers: _Drawers(), ledger: _Ledger(), tills: _Tills());
  final container = ProviderContainer(
    overrides: [
      ..._overrides(doubles, offline: offline),
      signedInStaffProvider.overrideWith(() => _Viewer(viewer)),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
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
        home: Scaffold(body: pane),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return doubles;
}

Finder _in(String key, Finder f) =>
    find.descendant(of: find.byKey(Key(key)), matching: f);

/// The amounts drawn in the row keyed [key], in column order.
List<Money> _amounts(WidgetTester tester, Key key) => [
  for (final w in tester.widgetList<MonoAmount>(
    find.descendant(of: find.byKey(key), matching: find.byType(MonoAmount)),
  ))
    w.value,
];

/// Keys starting with [prefix], in the order they are drawn.
List<String> _keys(String prefix) => [
  for (final e in find
      .byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith(prefix),
      )
      .evaluate())
    (e.widget.key! as ValueKey<String>).value,
];

/// Column by column, the sum of the amounts in every row keyed [prefix]….
List<Money> _columnSums(WidgetTester tester, String prefix) {
  final rows = _keys(prefix);
  expect(rows, isNotEmpty, reason: prefix);
  List<Money>? sums;
  for (final key in rows) {
    final amounts = _amounts(tester, Key(key));
    sums = sums == null
        ? amounts
        : [for (var i = 0; i < amounts.length; i++) sums[i] + amounts[i]];
  }
  return sums!;
}

/// Finance's second half (BO-10): each figure is the rows under it, the
/// supplier ledger is in it only where it is this person's to read here, and
/// every row leads to its own place.
void main() {
  const s = EnStrings();

  // The bundled faces, not the test font, for the 1100 px claims below — as
  // `back_office_shell_test.dart` loads them.
  setUpAll(() async {
    final ui = FontLoader(PosFonts.ui);
    for (final face in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      ui.addFont(rootBundle.load('assets/fonts/IBMPlexSansArabic-$face.ttf'));
    }
    await ui.load();
    final mono = FontLoader(PosFonts.mono);
    for (final face in ['Regular', 'Medium', 'SemiBold']) {
      mono.addFont(rootBundle.load('assets/fonts/IBMPlexMono-$face.ttf'));
    }
    await mono.load();
  });

  group('Expenses', () {
    testWidgets('pay-outs plus supplier payments not voided, the pay-out a '
        'payment owns counted once — and the rows are the total', (
      tester,
    ) async {
      final doubles = await _pump(tester, const FinanceExpensesPane());

      // Newest first: S13 at 16:00 on the 13th, P1 at 10:00 that morning,
      // S11 the day before. P2 is S13's own and not listed; S14 is void.
      expect(_keys('finance-expense-'), [
        'finance-expense-supplierPayment-13',
        'finance-expense-payOut-1',
        'finance-expense-supplierPayment-11',
      ]);
      expect(
        _columnSums(tester, 'finance-expense-'),
        _amounts(tester, const Key('finance-expenses-total')),
      );
      expect(
        _amounts(tester, const Key('finance-expenses-total')),
        [_egp(14500)],
      );
      expect(
        _in('finance-tile-payouts', find.text(_egp(1500).format())),
        findsOneWidget,
      );
      expect(
        _in('finance-tile-supplier-payments', find.text(_egp(13000).format())),
        findsOneWidget,
      );
      // The label says exactly what the figure holds.
      expect(
        tester.widget<Text>(
          _in('finance-expenses-label', find.byType(Text)),
        ).data,
        s.financeExpensesWithSuppliers,
      );
      expect(find.text(s.financeCountedOnce), findsOneWidget);
      expect(
        _in('finance-expense-payOut-1', find.text('Petty expense · Gas cylinder')),
        findsOneWidget,
      );
      expect(doubles.ledger.reads, 1);
    });

    testWidgets('on a cloud till the ledger is not asked, and the label says '
        'pay-outs only, and why', (tester) async {
      final doubles = await _pump(
        tester,
        const FinanceExpensesPane(),
        offline: false,
      );

      expect(_keys('finance-expense-'), [
        'finance-expense-payOut-2',
        'finance-expense-payOut-1',
      ]);
      expect(
        _amounts(tester, const Key('finance-expenses-total')),
        [_egp(4500)],
      );
      expect(find.byKey(const Key('finance-tile-supplier-payments')), findsNothing);
      expect(
        tester.widget<Text>(
          _in('finance-expenses-label', find.byType(Text)),
        ).data,
        '${s.financeExpensesPayOutsOnly} ${s.financeSuppliersOnPlatform}',
      );
      expect(find.text(s.financeCountedOnce), findsNothing);
      expect(doubles.ledger.reads, 0);
    });

    testWidgets('without purchase.manage the same, for its own reason', (
      tester,
    ) async {
      final doubles = await _pump(
        tester,
        const FinanceExpensesPane(),
        viewer: _accountant,
      );
      expect(
        tester.widget<Text>(
          _in('finance-expenses-label', find.byType(Text)),
        ).data,
        '${s.financeExpensesPayOutsOnly} ${s.financeSuppliersNotPermitted}',
      );
      expect(
        _amounts(tester, const Key('finance-expenses-total')),
        [_egp(4500)],
      );
      expect(doubles.ledger.reads, 0);
    });

    testWidgets('without reports.view nothing is read at all', (tester) async {
      final doubles = await _pump(
        tester,
        const FinanceExpensesPane(),
        viewer: _cashier,
      );
      expect(find.text(s.financeNoFigures), findsOneWidget);
      expect(doubles.drawers.asked, isEmpty);
      expect(doubles.ledger.reads, 0);
    });
  });

  group('Overview', () {
    testWidgets('offline, with purchase.manage: the bills card, its groups '
        'adding up to the total, beside the recent expenses', (tester) async {
      final opened = <FinanceTarget>[];
      await _pump(
        tester,
        FinanceOverviewPane(links: (target) => () => opened.add(target)),
      );

      final groups = [
        for (final bucket in BillsDueBucket.values)
          ..._amounts(tester, Key('finance-bills-card-${bucket.name}')),
      ];
      expect(groups, [_egp(5000), _egp(4000), _egp(2000), _egp(9000)]);
      expect(
        _amounts(tester, const Key('finance-bills-card-total')),
        [groups.fold(_egp(0), (sum, m) => sum + m)],
      );
      expect(
        _amounts(tester, const Key('finance-bills-card-total')),
        [_egp(20000)],
      );

      // The headline figures, and what the expenses one is made of.
      expect(
        _in('finance-tile-expenses', find.text(_egp(14500).format())),
        findsOneWidget,
      );
      expect(
        _in('finance-tile-expenses', find.text(s.financeExpensesWithSuppliers)),
        findsOneWidget,
      );
      expect(
        _in('finance-tile-drawers', find.text(Money(41400).format())),
        findsOneWidget,
      );
      expect(
        _in('finance-tile-drawers', find.text(s.financeOpenDrawerCount(2))),
        findsOneWidget,
      );

      // The latest expenses, and the period's figure under them.
      expect(
        _amounts(tester, const Key('finance-recent-expenses-total')),
        [_egp(14500)],
      );

      // Every "View all" goes where it says.
      for (final (key, target) in [
        ('finance-open-expenses', FinanceTarget.expenses),
        ('finance-open-bills', FinanceTarget.bills),
        ('finance-open-transactions', FinanceTarget.transactions),
      ]) {
        await tester.tap(find.byKey(Key(key)));
        await tester.pump();
        expect(opened.last, target, reason: key);
      }
      expect(tester.takeException(), isNull);
    });

    for (final (name, viewer, offline) in [
      ('on a cloud till', _owner, false),
      ('without purchase.manage', _accountant, true),
    ]) {
      testWidgets('no bills card $name, and the ledger is not asked', (
        tester,
      ) async {
        final doubles = await _pump(
          tester,
          const FinanceOverviewPane(),
          viewer: viewer,
          offline: offline,
        );
        expect(find.byKey(const Key('finance-bills-card')), findsNothing);
        expect(find.byKey(const Key('finance-recent-expenses')), findsOneWidget);
        // Expenses still shown, as pay-outs only.
        expect(
          _in('finance-tile-expenses', find.text(_egp(4500).format())),
          findsOneWidget,
        );
        expect(doubles.ledger.reads, 0);
      });
    }

    testWidgets('a card with nowhere to go draws no link', (tester) async {
      await _pump(tester, const FinanceOverviewPane());
      expect(find.byKey(const Key('finance-open-bills')), findsNothing);
      expect(find.byKey(const Key('finance-open-transactions')), findsNothing);
    });
  });

  testWidgets('Drawers: each expected is the Z report\'s, the rows add up '
      'to the total, and it is as of the business date', (tester) async {
    final doubles = await _pump(tester, const FinanceDrawersPane());

    expect(_keys('finance-drawer-'), ['finance-drawer-1', 'finance-drawer-2']);
    expect(
      _amounts(tester, const Key('finance-drawer-1')),
      [Money(20000), Money(11400), Money(5000), Money(7800), Money(28600)],
    );
    expect(
      _columnSums(tester, 'finance-drawer-'),
      _amounts(tester, const Key('finance-drawers-total')),
    );
    expect(
      _amounts(tester, const Key('finance-drawers-total')).last,
      Money(41400),
    );
    expect(
      _in('finance-tile-drawers', find.text(Money(41400).format())),
      findsOneWidget,
    );
    // A snapshot of now: the business date, and no period to choose.
    expect(_in('finance-as-of', find.text('2026-09-14')), findsOneWidget);
    expect(find.byKey(const Key('finance-period-today')), findsNothing);
    expect(doubles.tills.asked, 1);
  });

  testWidgets('Bills due: the groups add up to the total owed, and the '
      'table\'s outstanding to the same', (tester) async {
    final opened = <FinanceTarget>[];
    await _pump(
      tester,
      FinanceBillsPane(links: (target) => () => opened.add(target)),
    );

    final groups = [
      for (final bucket in BillsDueBucket.values)
        ..._amounts(tester, Key('finance-bills-${bucket.name}')),
    ];
    expect(groups, [_egp(5000), _egp(4000), _egp(2000), _egp(9000)]);
    expect(
      _amounts(tester, const Key('finance-bills-total')),
      [groups.fold(_egp(0), (sum, m) => sum + m)],
    );
    expect(
      _columnSums(tester, 'finance-bill-'),
      _amounts(tester, const Key('finance-bills-table-total')),
    );
    expect(
      _amounts(tester, const Key('finance-bills-table-total')).last,
      _egp(20000),
    );
    expect(
      _in('finance-bill-2', find.text(s.financeBucketOverdue)),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('finance-bill-2')));
    await tester.pump();
    expect(opened, [FinanceTarget.supplierInvoices]);
  });

  testWidgets('Transactions: newest first, signed as money moves, and each '
      'row opens its own place', (tester) async {
    final opened = <FinanceTarget>[];
    await _pump(
      tester,
      FinanceTransactionsPane(links: (target) => () => opened.add(target)),
    );

    expect(_keys('finance-transaction-'), [
      'finance-transaction-supplierPayment-13',
      'finance-transaction-sale-7',
      'finance-transaction-payOut-1',
      'finance-transaction-supplierPayment-11',
      'finance-transaction-supplierPayment-14',
      'finance-transaction-supplierInvoice-5',
    ]);
    expect(
      _amounts(tester, const Key('finance-transaction-sale-7')),
      [_egp(11400)],
    );
    expect(
      _amounts(tester, const Key('finance-transaction-payOut-1')),
      [_egp(-1500)],
    );
    expect(
      _in('finance-transaction-supplierPayment-14', find.text(s.financeStatusVoided)),
      findsOneWidget,
    );
    // No total line: an invoice and its payment are two rows for one debt.
    expect(find.text(s.financeTotal), findsNothing);

    for (final (key, target) in [
      ('finance-transaction-sale-7', FinanceTarget.sales),
      ('finance-transaction-payOut-1', FinanceTarget.expenses),
      ('finance-transaction-supplierPayment-11', FinanceTarget.supplierPayments),
      ('finance-transaction-supplierInvoice-5', FinanceTarget.supplierInvoices),
    ]) {
      await tester.tap(find.byKey(Key(key)));
      await tester.pump();
      expect(opened.last, target, reason: key);
    }
  });

  group('inside the back office', () {
    Set<ManagementPane> showing() => {
      for (final element in find
          .byWidgetPredicate(
            (w) =>
                w.key is ValueKey<String> &&
                (w.key! as ValueKey<String>).value.startsWith(
                  'back-office-pane-',
                ),
          )
          .evaluate())
        ManagementPane.values.byName(
          (element.widget.key! as ValueKey<String>).value.substring(
            'back-office-pane-'.length,
          ),
        ),
    };

    testWidgets('a sale opens Sales; a supplier payment opens Purchasing on '
        'its payments', (tester) async {
      tester.view
        ..physicalSize = const Size(1440, 1400)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final doubles = (drawers: _Drawers(), ledger: _Ledger(), tills: _Tills());
      final container = ProviderContainer(
        overrides: _overrides(doubles, offline: true),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [
              AppLocalizations(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            theme: buildPosTheme(),
            home: ManagementScreen(
              onClose: () {},
              onReconfigure: () {},
              initialPane: ManagementPane.financeTransactions,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await enterAdminMode(tester, username: 'amer', pin: '4321');
      expect(showing(), {ManagementPane.financeTransactions});

      await tester.tap(find.byKey(const Key('finance-transaction-sale-7')));
      await tester.pumpAndSettle();
      expect(showing(), {ManagementPane.sales});

      await tester.tap(find.byKey(const Key('back-office-tab-finance')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('back-office-subnav-financeTransactions')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('finance-transaction-supplierPayment-11')),
      );
      await tester.pumpAndSettle();
      expect(showing(), {ManagementPane.purchasing});
      expect(
        tester
            .widget<ManagementPurchasingPane>(
              find.byType(ManagementPurchasingPane),
            )
            .initialTab,
        PurchasingTab.payments,
      );

      // And the strip's Purchasing, chosen afterwards, opens where it always
      // has — the row's choice of tab does not stick.
      await tester.tap(find.byKey(const Key('back-office-tab-finance')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('back-office-tab-purchasing')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ManagementPurchasingPane>(
              find.byType(ManagementPurchasingPane),
            )
            .initialTab,
        PurchasingTab.orders,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('in Arabic at 1100 px', () {
    testWidgets('the Overview lays out, the bills card on the left of the '
        'expenses — start is right — and figures stay left to right', (
      tester,
    ) async {
      await _pump(
        tester,
        FinanceOverviewPane(links: (target) => () {}),
        language: 'ar',
        width: PosSize.wideShellMin,
      );
      const ar = ArStrings();
      expect(tester.takeException(), isNull);
      expect(find.text(ar.financeBills), findsOneWidget);
      expect(find.text(s.financeBills), findsNothing);

      final expenses = tester.getRect(
        find.byKey(const Key('finance-recent-expenses')),
      );
      final bills = tester.getRect(find.byKey(const Key('finance-bills-card')));
      expect(expenses.left, greaterThan(bills.left));

      final amount = tester.widget<Directionality>(
        find
            .descendant(
              of: find.byKey(const Key('finance-bills-card-total')),
              matching: find.byType(Directionality),
            )
            .first,
      );
      expect(amount.textDirection, TextDirection.ltr);
      // The pay-out's reason in Arabic, from the row's own Arabic name.
      expect(
        find.textContaining('مصروف نثري'),
        findsWidgets,
      );
    });

    for (final (name, pane) in <(String, Widget)>[
      ('Expenses', const FinanceExpensesPane()),
      ('Drawers', const FinanceDrawersPane()),
      ('Bills due', const FinanceBillsPane()),
      ('Transactions', const FinanceTransactionsPane()),
    ]) {
      testWidgets('$name lays out without overflow', (tester) async {
        await _pump(tester, pane, language: 'ar', width: PosSize.wideShellMin);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
