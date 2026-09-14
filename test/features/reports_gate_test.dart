import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/finance_providers.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/app/reports_providers.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/domain/models/finance_report.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/sales_report.dart';
import 'package:xorder_pos/domain/repositories/repositories.dart';
import 'package:xorder_pos/features/admin/application/admin_session.dart';

/// `reports.view` gates the figures, on the provider every reader goes
/// through — so BO-6's tab inherits it instead of having to remember it.
///
/// Every person here holds their capabilities through a ROLE. A fixture with
/// bare capabilities would pass against a gate that read
/// `PosStaff.capabilities`, which is direct grants only — the bug this gate
/// is most likely to have.
void main() {
  const cashier = PosStaff(
    id: 4,
    name: 'Nour Adel',
    role: PosRole(
      id: 2,
      code: 'cashier',
      nameEn: 'Cashier',
      capabilities: {PosCapability.operate},
    ),
  );
  // The inventory manager's template: reports, and not every sale.
  const stockKeeper = PosStaff(
    id: 7,
    name: 'Karim Fathy',
    role: PosRole(
      id: 5,
      code: 'inventory',
      nameEn: 'Inventory manager',
      capabilities: {PosCapability.operate, PosCapability.reportsView},
    ),
  );

  final filter = ReportFilter.day(DateTime(2026, 9, 10));
  const topQuery = (by: ProductRanking.quantity);

  ProviderContainer containerFor(
    PosStaff? viewer,
    _Recording repository, {
    PosStaff? admin,
  }) {
    final container = ProviderContainer(
      overrides: [
        reportsRepositoryProvider.overrideWithValue(repository),
        signedInStaffProvider.overrideWith(() => _Viewer(viewer)),
        if (admin != null)
          adminSessionProvider.overrideWith(() => _InAdminMode(admin)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// A report's value, read the way a screen reads it: while listened to.
  /// The providers are `autoDispose`, and a bare `read` of one nobody listens
  /// to may be disposed before its future settles.
  Future<T> value<T>(
    ProviderContainer container,
    ProviderListenable<Future<T>> provider,
  ) {
    final subscription = container.listen(provider, (previous, next) {});
    addTearDown(subscription.close);
    return subscription.read();
  }

  test('nobody signed in reads no report, and the database is not asked', () async {
    final repository = _Recording();
    final container = containerFor(null, repository);

    expect(await value(container, salesReportProvider(filter).future), isNull);
    expect(
      await value(
        container,
        topProductsProvider((filter: filter, by: topQuery.by)).future,
      ),
      isEmpty,
    );
    expect(repository.calls, 0);
  });

  test('a cashier without reports.view reads no report', () async {
    final repository = _Recording();
    final container = containerFor(cashier, repository);

    expect(await value(container, salesReportProvider(filter).future), isNull);
    expect(repository.calls, 0);
  });

  test("Finance's taxes and payments ask the same gate (BO-9)", () async {
    final refused = _Recording();
    final cashierSees = containerFor(cashier, refused);
    expect(await value(cashierSees, taxReportProvider(filter).future), isNull);
    expect(
      await value(cashierSees, paymentLedgerProvider(filter).future),
      isNull,
    );
    expect(refused.calls, 0);

    final allowed = _Recording();
    final keeperSees = containerFor(stockKeeper, allowed);
    expect(
      await value(keeperSees, taxReportProvider(filter).future),
      isNotNull,
    );
    expect(
      await value(keeperSees, paymentLedgerProvider(filter).future),
      isNotNull,
    );
    expect(allowed.calls, 2);
  });

  test('reports.view through a role is enough, and the figures are not narrowed', () async {
    final repository = _Recording();
    final container = containerFor(stockKeeper, repository);

    expect(
      await value(container, salesReportProvider(filter).future),
      isNotNull,
    );
    expect(
      await value(
        container,
        topProductsProvider((filter: filter, by: topQuery.by)).future,
      ),
      hasLength(1),
    );
    // Without order.view_all, and still asked for the branch: §3a narrows
    // the drill-down, not the totals.
    expect(repository.filters.single.servedByStaffId, isNull);
  });

  // The Reports tab is inside Admin Mode, where the person reading is whoever
  // came through its door — not whoever is signed in at the till behind it.
  // The gate read the till's operator, so an owner who entered with a cashier
  // still on the till, or with nobody on it, was shown no report at all.
  test('in Admin Mode it is the administrator who is asked, not the till', () async {
    final repository = _Recording();
    final container = containerFor(cashier, repository, admin: stockKeeper);

    expect(await container.read(salesReportProvider(filter).future), isNotNull);
    expect(repository.calls, 1);
  });

  test('and an administrator without reports.view reads none, whoever is '
      'on the till', () async {
    final repository = _Recording();
    final container = containerFor(stockKeeper, repository, admin: cashier);

    expect(await container.read(salesReportProvider(filter).future), isNull);
    expect(repository.calls, 0);
  });
}

class _Viewer extends SignedInStaffController {
  _Viewer(this.staff);

  final PosStaff? staff;

  @override
  PosStaff? build() => staff;
}

class _InAdminMode extends AdminSessionController {
  _InAdminMode(this.staff);

  final PosStaff staff;

  @override
  AdminSession? build() =>
      AdminSession(staff: staff, startedAt: DateTime(2026, 9, 10, 9));
}

/// A test double. Never a default binding.
class _Recording implements ReportsRepository {
  int calls = 0;
  final filters = <ReportFilter>[];

  @override
  Future<SalesReport> sales(ReportFilter filter) async {
    calls++;
    filters.add(filter);
    return SalesReport(filter: filter, terminals: const [], days: const []);
  }

  @override
  Future<List<ProductSales>> topProducts(
    ReportFilter filter, {
    required ProductRanking by,
    int limit = 5,
  }) async {
    calls++;
    return const [
      ProductSales(
        menuItemId: 101,
        name: 'Koshari',
        quantity: 3,
        amount: Money(46000),
      ),
    ];
  }

  @override
  Future<TaxReport> taxes(ReportFilter filter) async {
    calls++;
    filters.add(filter);
    return TaxReport(
      filter: filter,
      rates: const [],
      unattributedRefunds: Money.zero,
    );
  }

  @override
  Future<PaymentLedger> payments(ReportFilter filter, {int limit = 500}) async {
    calls++;
    filters.add(filter);
    return PaymentLedger(filter: filter, entries: const [], truncated: false);
  }
}
