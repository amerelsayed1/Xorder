import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/domain/models/order_record.dart';
import 'package:shared_module/domain/models/permissions.dart';
import 'package:shared_module/domain/models/refund.dart';
import 'package:shared_module/domain/models/refund_history.dart';
import 'package:shared_module/domain/models/shift.dart';
import 'package:shared_module/domain/models/ticket.dart';
import 'package:shared_module/features/history/history_scope.dart';

/// The rules under Sales › Invoices, Returns and Cancelled orders, with no
/// screen and no database: which statuses a preset locks on, what the two
/// strips add up, and whose refunds a person may read.
void main() {
  OrderRecord sale(int id, OrderStatus status, int total) => OrderRecord(
    id: id,
    clientTransactionId: 'txn-$id',
    invoiceNumber: 'INV-$id',
    status: status,
    orderType: OrderType.takeaway,
    occurredAt: DateTime(2026, 9, 14, 12),
    subtotal: Money(total),
    discount: Money.zero,
    service: Money.zero,
    vat: Money.zero,
    total: Money(total),
    paidTotal: Money(status == OrderStatus.voided ? 0 : total),
  );

  RefundRecord refund(int id, int total, {int? servedBy}) => RefundRecord(
    id: id,
    orderId: 100 + id,
    invoiceNumber: 'INV-$id',
    occurredAt: DateTime(2026, 9, 14, 12),
    total: Money(total),
    kind: RefundKind.partial,
    lineCount: 1,
    servedByStaffId: servedBy,
  );

  group('HistoryPreset', () {
    test('Invoices locks the list to the statuses that took money', () {
      final locked = HistoryPreset.invoices.statuses!;
      expect(locked, {
        for (final s in OrderStatus.values)
          if (s.tookMoney) s,
      });
      expect(locked, containsAll([OrderStatus.paid, OrderStatus.partiallyRefunded]));
      // Not a void, not a sale given back in full.
      expect(locked, isNot(contains(OrderStatus.voided)));
      expect(locked, isNot(contains(OrderStatus.refunded)));
    });

    test('Cancelled orders locks it to voids; Orders locks nothing', () {
      expect(HistoryPreset.voided.statuses, {OrderStatus.voided});
      expect(HistoryPreset.all.statuses, isNull);
    });

    test('a preset replaces the statuses and nothing else', () {
      final query = OrderHistoryQuery(
        from: DateTime(2026, 9, 1),
        to: DateTime(2026, 9, 2),
        statuses: const {OrderStatus.refunded},
        servedByStaffId: 4,
        search: 'A-1',
      );
      expect(HistoryPreset.all.apply(query), query);
      expect(
        HistoryPreset.voided.apply(query),
        query.copyWith(statuses: const {OrderStatus.voided}),
      );
    });
  });

  test('the struck-through total is what the dead rows came to, and is '
      'left out of the live one', () {
    final summary = OrderHistorySummary.of([
      sale(1, OrderStatus.voided, 5000),
      sale(2, OrderStatus.voided, 7000),
      sale(3, OrderStatus.paid, 10000),
    ]);
    expect(summary.count, 3);
    expect(summary.dead, 2);
    expect(summary.deadTotal.minor, 12000);
    expect(summary.total.minor, 10000);
  });

  group('RefundHistorySummary', () {
    test('counts every refund and sums every total', () {
      final summary = RefundHistorySummary.of([
        refund(1, 5000),
        refund(2, 20000),
        refund(3, 1000),
      ]);
      expect(summary.count, 3);
      expect(summary.total.minor, 26000);
      expect(RefundHistorySummary.of(const []), RefundHistorySummary.empty);
    });
  });

  group('RefundHistoryQuery', () {
    test('value equality, so a rebuild is not a new read', () {
      expect(
        RefundHistoryQuery(from: DateTime(2026, 9, 1), search: 'A'),
        RefundHistoryQuery(from: DateTime(2026, 9, 1), search: 'A'),
      );
    });

    test('unpaged drops the cursor and the page size', () {
      const paged = RefundHistoryQuery(search: 'A', afterRefundId: 9, limit: 3);
      expect(paged.unpaged, const RefundHistoryQuery(search: 'A'));
    });
  });

  group('HistoryScope.scopeRefunds', () {
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

    test('narrows a cashier to their own sales, overwriting any other', () {
      expect(
        HistoryScope.scopeRefunds(
          const RefundHistoryQuery(servedByStaffId: 9),
          cashier,
        )!.servedByStaffId,
        cashier.id,
      );
    });

    test('leaves the branch to order.view_all, held through the role', () {
      expect(
        HistoryScope.scopeRefunds(const RefundHistoryQuery(), supervisor),
        const RefundHistoryQuery(),
      );
    });

    test('reads nothing for nobody', () {
      expect(HistoryScope.scopeRefunds(const RefundHistoryQuery(), null), isNull);
    });
  });
}
