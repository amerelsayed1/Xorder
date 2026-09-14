import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/domain/models/business_day.dart';
import 'package:xorder_pos/domain/models/finance_report.dart';
import 'package:xorder_pos/domain/models/order_record.dart';
import 'package:xorder_pos/domain/models/sales_report.dart';
import 'package:xorder_pos/domain/models/supplier_invoice.dart';
import 'package:xorder_pos/domain/models/ticket.dart' show OrderType;

/// BO-10's read models, without a database: the rules the Finance screens
/// and `test/data/finance_expenses_test.dart` both lean on.
void main() {
  final range = ReportFilter(
    from: DateTime(2026, 9, 1),
    to: DateTime(2026, 9, 15),
  );

  SupplierInvoice bill(int id, int total, DateTime due, {int paid = 0}) =>
      SupplierInvoice(
        id: id,
        supplierId: 1,
        supplierName: 'Nile Dairy',
        number: 'I$id',
        total: Money(total),
        paid: Money(paid),
        issuedAt: DateTime(2026, 8, 1),
        dueAt: due,
      );

  CashMovement payOut(int id, int amount, DateTime at) => CashMovement(
    id: id,
    kind: CashMovementKind.payOut,
    amount: Money(amount),
    occurredAt: at,
  );

  SupplierPayment payment(
    int id,
    int amount,
    DateTime at, {
    int? movement,
    DateTime? voided,
  }) => SupplierPayment(
    id: id,
    supplierId: 1,
    supplierName: 'Nile Dairy',
    amount: Money(amount),
    method: movement == null
        ? SupplierPaymentMethod.bankTransfer
        : SupplierPaymentMethod.cash,
    paidAt: at,
    cashMovementId: movement,
    voidedAt: voided,
  );

  OrderRecord sale(int id, DateTime at, {int total = 1000}) => OrderRecord(
    id: id,
    clientTransactionId: 'c$id',
    invoiceNumber: 'INV-$id',
    status: OrderStatus.paid,
    orderType: OrderType.dineIn,
    occurredAt: at,
    subtotal: Money(total),
    discount: Money.zero,
    service: Money.zero,
    vat: Money.zero,
    total: Money(total),
    paidTotal: Money(total),
  );

  group('bills due', () {
    final today = DateTime(2026, 9, 14);
    BillsDueBucket of(DateTime due, [DateTime? on]) =>
        billsDueBucket(due, businessDate: on ?? today);

    test('by the due date against the business date, never the instant', () {
      expect(of(DateTime(2026, 9, 13, 23, 59)), BillsDueBucket.overdue);
      expect(of(DateTime(2026, 9, 14)), BillsDueBucket.dueToday);
      expect(of(DateTime(2026, 9, 14, 23, 59)), BillsDueBucket.dueToday);
      expect(of(DateTime(2026, 9, 15)), BillsDueBucket.nextSevenDays);
      expect(of(DateTime(2026, 9, 21, 23, 59)), BillsDueBucket.nextSevenDays);
      expect(of(DateTime(2026, 9, 22)), BillsDueBucket.later);
      // The business date is a date: its time of day moves nothing.
      expect(
        of(DateTime(2026, 9, 14, 9), DateTime(2026, 9, 14, 23)),
        BillsDueBucket.dueToday,
      );
      // Counted on calendar dates across a month end.
      expect(
        of(DateTime(2026, 10, 7), DateTime(2026, 9, 30)),
        BillsDueBucket.nextSevenDays,
      );
      expect(
        of(DateTime(2026, 10, 8), DateTime(2026, 9, 30)),
        BillsDueBucket.later,
      );
    });

    test('each bill in one group, by what is still owed on it, and the '
        'groups summing to the total', () {
      final due = BillsDue.of([
        bill(1, 5000, DateTime(2026, 9, 1), paid: 1000),
        bill(2, 3000, DateTime(2026, 9, 14)),
        bill(3, 2000, DateTime(2026, 9, 20)),
        bill(4, 9000, DateTime(2026, 12, 1)),
      ], businessDate: today);

      expect([for (final b in BillsDueBucket.values) due.count(b)], [
        1,
        1,
        1,
        1,
      ]);
      expect([for (final b in BillsDueBucket.values) due.amount(b)], const [
        Money(4000),
        Money(3000),
        Money(2000),
        Money(9000),
      ]);
      expect(
        BillsDueBucket.values.fold(Money.zero, (sum, b) => sum + due.amount(b)),
        due.total,
      );
      expect(due.total, const Money(18000));
    });

    test('nothing owed is zero in every group, not an absent figure', () {
      final due = BillsDue.of(const [], businessDate: today);
      expect(due.total, Money.zero);
      for (final b in BillsDueBucket.values) {
        expect(due.amount(b), Money.zero);
      }
    });
  });

  group('expenses', () {
    test('a supplier paid out of a drawer is counted once, as the payment; a '
        'void is not counted', () {
      final report = ExpenseReport(
        filter: range,
        payOuts: [
          payOut(1, 1500, DateTime(2026, 9, 10, 9)),
          payOut(2, 3000, DateTime(2026, 9, 10, 16)),
          payOut(3, 1200, DateTime(2026, 9, 11, 10)),
        ],
        supplierFigures: SupplierFigures.included,
        suppliers: SupplierSpending(
          invoices: const [],
          payments: [
            payment(10, 3000, DateTime(2026, 9, 10, 16), movement: 2),
            payment(11, 10000, DateTime(2026, 9, 12)),
            payment(
              12,
              1200,
              DateTime(2026, 9, 11, 10),
              movement: 3,
              voided: DateTime(2026, 9, 11, 11),
            ),
          ],
          drawerMovementIds: const {2, 3},
        ),
      );

      expect([for (final p in report.drawerPayOuts) p.id], [1]);
      expect([for (final p in report.supplierPayments) p.id], [10, 11]);
      expect(report.payOutTotal, const Money(1500));
      expect(report.supplierTotal, const Money(13000));
      expect(report.total, const Money(14500));

      // The rows the total is made of, newest first, each once.
      expect(
        [for (final e in report.entries) (e.kind, e.sourceId)],
        [
          (FinanceTransactionKind.supplierPayment, 11),
          (FinanceTransactionKind.supplierPayment, 10),
          (FinanceTransactionKind.payOut, 1),
        ],
      );
      expect(
        report.entries.fold(Money.zero, (sum, e) => sum - e.amount),
        report.total,
      );
    });

    test('without the ledger every pay-out counts as itself', () {
      final report = ExpenseReport(
        filter: range,
        payOuts: [
          payOut(1, 1500, DateTime(2026, 9, 10)),
          payOut(2, 3000, DateTime(2026, 9, 10)),
        ],
        supplierFigures: SupplierFigures.onPlatform,
      );
      expect(report.supplierPayments, isEmpty);
      expect(report.total, const Money(4500));
    });
  });

  group('transactions', () {
    ExpenseReport expenses({
      List<CashMovement> payOuts = const [],
      SupplierSpending? suppliers,
    }) => ExpenseReport(
      filter: range,
      payOuts: payOuts,
      supplierFigures: suppliers == null
          ? SupplierFigures.notPermitted
          : SupplierFigures.included,
      suppliers: suppliers,
    );

    test('the four sources merged newest first, each signed as money moves '
        'for the restaurant', () {
      final list = FinanceTransactions.of(
        sales: [sale(7, DateTime(2026, 9, 10, 12), total: 11400)],
        salesCut: false,
        expenses: expenses(
          payOuts: [payOut(1, 1500, DateTime(2026, 9, 10, 13))],
          suppliers: SupplierSpending(
            invoices: [bill(5, 8000, DateTime(2026, 10, 1))],
            payments: [payment(9, 3000, DateTime(2026, 9, 10, 14))],
            drawerMovementIds: const {},
          ),
        ),
      );

      expect([for (final t in list.entries) t.kind], [
        FinanceTransactionKind.supplierPayment,
        FinanceTransactionKind.payOut,
        FinanceTransactionKind.sale,
        // Issued on 1 August — the oldest of the four.
        FinanceTransactionKind.supplierInvoice,
      ]);
      expect([for (final t in list.entries) t.amount], const [
        Money(-3000),
        Money(-1500),
        Money(11400),
        Money(-8000),
      ]);
      expect(list.truncated, isFalse);
    });

    test('cutting each source at the limit lists exactly the newest of all '
        'of them', () {
      // Six sales and six pay-outs, interleaved an hour apart; a limit of
      // four. The newest four of the union are two of each.
      final sales = [
        for (var i = 0; i < 6; i++) sale(i, DateTime(2026, 9, 10, 2 * i)),
      ];
      final payOuts = [
        for (var i = 0; i < 6; i++)
          payOut(100 + i, 100, DateTime(2026, 9, 10, 2 * i + 1)),
      ];
      List<OrderRecord> newestFirst(List<OrderRecord> rows) =>
          [...rows]..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));

      final cut = FinanceTransactions.of(
        sales: newestFirst(sales).take(4).toList(),
        salesCut: true,
        expenses: expenses(payOuts: payOuts),
        limit: 4,
      );
      final whole = FinanceTransactions.of(
        sales: sales,
        salesCut: false,
        expenses: expenses(payOuts: payOuts),
        limit: 4,
      );

      expect(
        [for (final t in cut.entries) (t.kind, t.sourceId)],
        [for (final t in whole.entries) (t.kind, t.sourceId)],
      );
      expect(
        [for (final t in cut.entries) t.sourceId],
        [105, 5, 104, 4],
      );
      expect(cut.truncated, isTrue);
      expect(whole.truncated, isTrue, reason: 'twelve rows, four listed');
    });

    test('a supplier invoice or payment states itself; a pay-out is recorded', () {
      final paidBill = SupplierInvoiceTransaction(
        bill(1, 5000, DateTime(2026, 9, 1), paid: 5000),
      );
      final partBill = SupplierInvoiceTransaction(
        bill(2, 5000, DateTime(2026, 9, 1), paid: 1000),
      );
      final openBill = SupplierInvoiceTransaction(
        bill(3, 5000, DateTime(2026, 9, 1)),
      );
      final voidPayment = SupplierPaymentTransaction(
        payment(4, 100, DateTime(2026, 9, 1), voided: DateTime(2026, 9, 2)),
      );
      expect(paidBill.status, FinanceTransactionStatus.paid);
      expect(partBill.status, FinanceTransactionStatus.partlyPaid);
      expect(openBill.status, FinanceTransactionStatus.unpaid);
      expect(voidPayment.status, FinanceTransactionStatus.voided);
      expect(
        PayOutTransaction(payOut(5, 100, DateTime(2026, 9, 1))).status,
        FinanceTransactionStatus.recorded,
      );
    });
  });
}
