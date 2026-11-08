import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/data/fakes/fake_repositories.dart';
import 'package:xorder_pos/domain/models/order_record.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/features/history/history_scope.dart';

/// Own sales only (plan 17 §5).
///
/// Every person here gets their capabilities through a ROLE. `PosStaff.
/// capabilities` is direct grants only, and a fixture with bare capabilities
/// would pass against a rule that read that field — which is the bug the rule
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
  const supervisor = PosStaff(
    id: 9,
    name: 'Hana Mostafa',
    role: PosRole(
      id: 3,
      code: 'supervisor',
      nameEn: 'Supervisor',
      capabilities: {PosCapability.operate, PosCapability.orderViewAll},
    ),
  );

  OrderRecord order(int id, {int? servedBy}) => OrderRecord(
    id: id,
    clientTransactionId: 'txn-$id',
    invoiceNumber: 'INV-$id',
    status: OrderStatus.paid,
    orderType: OrderType.takeaway,
    occurredAt: DateTime(2026, 9, 10, 12),
    subtotal: const Money(1000),
    discount: Money.zero,
    service: Money.zero,
    vat: Money.zero,
    total: const Money(1000),
    servedByStaffId: servedBy,
  );

  group('HistoryScope.scope', () {
    test('nobody signed in reads nothing', () {
      expect(HistoryScope.scope(const OrderHistoryQuery(), null), isNull);
    });

    test('a cashier is narrowed to their own sales', () {
      final scoped = HistoryScope.scope(const OrderHistoryQuery(), cashier);
      expect(scoped!.servedByStaffId, cashier.id);
    });

    test('and cannot ask for somebody else by naming them', () {
      // A query that arrives already asking for another seller is overwritten,
      // not honoured — the picker being hidden is not the rule.
      final scoped = HistoryScope.scope(
        const OrderHistoryQuery(servedByStaffId: 9),
        cashier,
      );
      expect(scoped!.servedByStaffId, cashier.id);
    });

    test('a role carrying order.view_all sees the branch', () {
      // Through the role, not a direct grant: `capabilities` is empty here,
      // and a rule reading it would narrow this supervisor to their own sales.
      expect(supervisor.capabilities, isEmpty);
      final scoped = HistoryScope.scope(const OrderHistoryQuery(), supervisor);
      expect(scoped!.servedByStaffId, isNull);
    });

    test('and may still pick one cashier', () {
      final scoped = HistoryScope.scope(
        const OrderHistoryQuery(servedByStaffId: 4),
        supervisor,
      );
      expect(scoped!.servedByStaffId, 4);
    });
  });

  group('HistoryScope.mayOpen', () {
    test('a cashier opens their own sale and no one else\'s', () {
      expect(HistoryScope.mayOpen(order(1, servedBy: 4), cashier), isTrue);
      expect(HistoryScope.mayOpen(order(2, servedBy: 9), cashier), isFalse);
    });

    test('a sale with no recorded seller is nobody\'s own', () {
      expect(HistoryScope.mayOpen(order(3), cashier), isFalse);
      expect(HistoryScope.mayOpen(order(3), supervisor), isTrue);
    });
  });

  group('the providers apply it', () {
    ProviderContainer containerFor(PosStaff? viewer) {
      final repository = FakeOrderHistoryRepository(
        orders: [order(1, servedBy: 4), order(2, servedBy: 9)],
        details: {
          for (final o in [order(1, servedBy: 4), order(2, servedBy: 9)])
            o.id: OrderRecordDetail(
              order: o,
              lines: const [],
              payments: const [],
              discounts: const [],
            ),
        },
      );
      final container = ProviderContainer(
        overrides: [
          orderHistoryRepositoryProvider.overrideWithValue(repository),
          signedInStaffProvider.overrideWith(() => _Viewer(viewer)),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('a cashier\'s list holds none of anybody else\'s sales', () async {
      final container = containerFor(cashier);
      final orders = await container.read(
        orderHistoryProvider(const OrderHistoryQuery()).future,
      );
      expect(orders.map((o) => o.servedByStaffId), everyElement(4));
      expect(orders, isNotEmpty);
    });

    test('a cashier\'s figures are their own sales\' (BO-3)', () async {
      // The strip is a second road to the same rows, and the scope is on the
      // road: a total of the branch over a list of one person's sales would
      // tell the cashier what the list may not.
      final container = containerFor(cashier);
      final summary = await container.read(
        orderHistorySummaryProvider(const OrderHistoryQuery()).future,
      );
      expect(summary.count, 1);
      expect(summary.total.minor, 1000);
    });

    test('a supervisor\'s figures are the branch\'s', () async {
      final container = containerFor(supervisor);
      final summary = await container.read(
        orderHistorySummaryProvider(const OrderHistoryQuery()).future,
      );
      expect(summary.count, 2);
      expect(summary.total.minor, 2000);
    });

    test('an unattended till is told nothing, not zero of something', () async {
      final container = containerFor(null);
      expect(
        await container.read(
          orderHistorySummaryProvider(const OrderHistoryQuery()).future,
        ),
        OrderHistorySummary.empty,
      );
    });

    test('a supervisor\'s list holds everybody\'s', () async {
      final container = containerFor(supervisor);
      final orders = await container.read(
        orderHistoryProvider(const OrderHistoryQuery()).future,
      );
      expect(orders.map((o) => o.id).toSet(), {1, 2});
    });

    test('a cashier cannot open another\'s sale by its id', () async {
      final container = containerFor(cashier);
      expect(await container.read(orderDetailProvider(2).future), isNull);
      expect(await container.read(orderDetailProvider(1).future), isNotNull);
    });

    test('an unattended till lists nothing', () async {
      final container = containerFor(null);
      final orders = await container.read(
        orderHistoryProvider(const OrderHistoryQuery()).future,
      );
      expect(orders, isEmpty);
    });
  });
}

class _Viewer extends SignedInStaffController {
  _Viewer(this.staff);

  final PosStaff? staff;

  @override
  PosStaff? build() => staff;
}
