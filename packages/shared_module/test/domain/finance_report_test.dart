import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/domain/models/branch_sales.dart';
import 'package:shared_module/domain/models/finance_report.dart';
import 'package:shared_module/domain/models/sales_report.dart';
import 'package:shared_module/domain/models/tax.dart';
import 'package:shared_module/domain/models/tender_method.dart';

/// Finance's pure rules (BO-9): the one split of a refund's tax, the periods,
/// and totals that are their rows.
void main() {
  group('a refund\'s tax, split across its sale\'s rates', () {
    test('in proportion, floored, the last rate taking what is left', () {
      // 2,800 and 150 of a sale's 2,950; 1,000 given back.
      expect(
        TaxEngine.refundShares(
          saleAmounts: [2800, 150],
          saleVat: 2950,
          refundVat: 1000,
        ),
        [949, 51],
      );
    });

    test('always sums to the refund, to the piastre', () {
      for (final refund in [0, 1, 7, 333, 1000, 2949, 2950]) {
        final shares = TaxEngine.refundShares(
          saleAmounts: [1400, 700, 333, 517],
          saleVat: 2950,
          refundVat: refund,
        );
        expect(shares.fold(0, (a, b) => a + b), refund, reason: '$refund');
        expect(shares.every((s) => s >= 0), isTrue, reason: '$refund');
      }
    });

    test('a zero-rated line is given nothing, and one rate takes all', () {
      expect(
        TaxEngine.refundShares(
          saleAmounts: [1400, 0],
          saleVat: 1400,
          refundVat: 700,
        ),
        [700, 0],
      );
      expect(
        TaxEngine.refundShares(saleAmounts: [700], saleVat: 700, refundVat: 50),
        [50],
      );
    });

    test('no rates, nothing to split; no VAT on the sale, the last takes it',
        () {
      expect(
        TaxEngine.refundShares(saleAmounts: [], saleVat: 0, refundVat: 300),
        isEmpty,
      );
      expect(
        TaxEngine.refundShares(saleAmounts: [0, 0], saleVat: 0, refundVat: 5),
        [0, 5],
      );
    });
  });

  group('the periods', () {
    // Monday 14 September 2026.
    final monday = DateTime(2026, 9, 14);
    (DateTime, DateTime) of(FinancePeriod period, DateTime today, int first) {
      final f = financeFilter(
        period,
        today: today,
        firstDayOfWeekIndex: first,
      );
      return (f.from, f.to);
    }

    test('today is the one business date', () {
      expect(of(FinancePeriod.today, monday, 0), (
        DateTime(2026, 9, 14),
        DateTime(2026, 9, 15),
      ));
    });

    test('the week starts where the locale starts it, and runs to today', () {
      // Sunday in English, Saturday in Arabic, Monday elsewhere.
      expect(of(FinancePeriod.thisWeek, monday, 0).$1, DateTime(2026, 9, 13));
      expect(of(FinancePeriod.thisWeek, monday, 6).$1, DateTime(2026, 9, 12));
      expect(of(FinancePeriod.thisWeek, monday, 1).$1, DateTime(2026, 9, 14));
      expect(of(FinancePeriod.thisWeek, monday, 0).$2, DateTime(2026, 9, 15));
      // A Saturday, in a week that starts on Saturday, is its own first day.
      expect(
        of(FinancePeriod.thisWeek, DateTime(2026, 9, 12), 6).$1,
        DateTime(2026, 9, 12),
      );
    });

    test('this month runs from the first to today; last month is whole', () {
      expect(of(FinancePeriod.thisMonth, monday, 0), (
        DateTime(2026, 9, 1),
        DateTime(2026, 9, 15),
      ));
      expect(of(FinancePeriod.lastMonth, monday, 0), (
        DateTime(2026, 8, 1),
        DateTime(2026, 9, 1),
      ));
      expect(
        of(FinancePeriod.lastMonth, DateTime(2026, 1, 5), 0),
        (DateTime(2025, 12, 1), DateTime(2026, 1, 1)),
        reason: 'January looks back into last year',
      );
    });

    test('a time of day does not move the range', () {
      expect(
        of(FinancePeriod.today, DateTime(2026, 9, 14, 23, 59), 0),
        of(FinancePeriod.today, monday, 0),
      );
    });
  });

  group('totals are their rows', () {
    final filter = ReportFilter.day(DateTime(2026, 9, 14));

    test('tax: charged is the rates, refunded includes what has no rate', () {
      final taxes = TaxReport(
        filter: filter,
        rates: const [
          TaxCollected(
            name: 'VAT',
            rateBp: 1400,
            orders: 3,
            base: Money(35000),
            charged: Money(4900),
            refunded: Money(2349),
          ),
          TaxCollected(
            name: 'Reduced',
            rateBp: 500,
            orders: 1,
            base: Money(3000),
            charged: Money(150),
            refunded: Money(51),
          ),
        ],
        unattributedRefunds: const Money(300),
      );
      expect(taxes.charged, const Money(5050));
      expect(taxes.refunded, const Money(2700));
      expect(taxes.net, const Money(2350));
      expect(taxes.rates.first.net, const Money(2551));
    });

    test('the ledger totals the payments it lists', () {
      PaymentEntry entry(int id, int amount, TenderKind kind) => PaymentEntry(
        paymentId: id,
        orderId: id,
        invoiceNumber: 'INV-$id',
        occurredAt: DateTime(2026, 9, 14, 12),
        terminalId: 't1',
        terminalName: 'POS-01',
        tenderTypeId: id,
        label: kind.name,
        kind: kind,
        countsAsCash: kind == TenderKind.cash,
        amount: Money(amount),
      );
      final ledger = PaymentLedger(
        filter: filter,
        entries: [
          entry(1, 12800, TenderKind.cash),
          entry(2, 5700, TenderKind.account),
        ],
        truncated: false,
      );
      expect(ledger.total, const Money(18500));
      expect(ledger.entries.last.bucket, PaymentBucket.onAccount);
      expect(ledger.entries.first.bucket, PaymentBucket.cash);
    });
  });
}
