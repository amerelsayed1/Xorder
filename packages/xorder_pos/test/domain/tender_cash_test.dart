import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/models/tender_method.dart';

/// Which tenders end up in the drawer.
///
/// This is the gap-closure plan's named Wave B risk, closed early. The drawer's
/// cash used to be found with `label.toLowerCase().contains('cash')`, which is
/// wrong in both directions — and catastrophically so the day a business
/// renames its payment methods into Arabic.
void main() {
  ShiftSummary summary(
    List<ShiftTenderTotal> tenders, {
    Money cashRefunded = Money.zero,
  }) => ShiftSummary(
    shift: PosShift(
      id: 1,
      openedAt: DateTime(2026, 9, 8, 9),
      openingFloat: const Money(20000),
      openedByName: 'Nour Adel',
    ),
    saleCount: tenders.length,
    gross: tenders.fold(Money.zero, (sum, t) => sum + t.amount),
    tenders: tenders,
    cashRefunded: cashRefunded,
  );

  group('what counts as cash', () {
    test('only the cash method does', () {
      expect(TenderMethod.isCash(1), isTrue);
      for (final id in [2, 3, 4]) {
        expect(TenderMethod.isCash(id), isFalse, reason: 'type $id');
      }
    });

    test('an unknown type does not', () {
      // Counting one as cash would manufacture a variance nobody can explain.
      expect(TenderMethod.isCash(99), isFalse);
      expect(TenderMethod.isCash(null), isFalse);
    });

    test('a label containing "cash" is not enough', () {
      // The old rule matched this. A cashback voucher never touched the drawer.
      const voucher = ShiftTenderTotal(
        label: 'Cashback voucher',
        count: 1,
        amount: Money(5000),
        typeId: 7,
      );
      expect(voucher.countsAsCash, isFalse);
    });

    test('an Arabic label for the cash method still counts', () {
      // The failure the old rule would have produced the day §37 made payment
      // methods configurable: every Arabic till reporting an expected drawer of
      // nothing but its float, a false variance on every single cash-up.
      const arabic = ShiftTenderTotal(
        label: 'نقدًا',
        count: 1,
        amount: Money(5000),
        typeId: 1,
      );
      expect(arabic.countsAsCash, isTrue);
    });
  });

  group('the expected drawer', () {
    test('is the float plus the cash taken, and nothing else', () {
      final s = summary(const [
        ShiftTenderTotal(
          label: 'Cash',
          count: 3,
          amount: Money(45000),
          typeId: 1,
        ),
        ShiftTenderTotal(
          label: 'Card',
          count: 2,
          amount: Money(30000),
          typeId: 2,
        ),
      ]);

      expect(s.cashTaken.minor, 45000);
      // Card never reaches the drawer, so counting it would manufacture a
      // 300.00 variance every shift.
      expect(s.expectedCash.minor, 20000 + 45000);
    });

    test('a shift that took no cash still expects its float', () {
      final s = summary(const [
        ShiftTenderTotal(
          label: 'Card',
          count: 2,
          amount: Money(30000),
          typeId: 2,
        ),
      ]);
      expect(s.cashTaken.minor, 0);
      expect(s.expectedCash.minor, 20000);
    });

    test('variance is what is over, not what is missing', () {
      final s = summary(const [
        ShiftTenderTotal(
          label: 'Cash',
          count: 1,
          amount: Money(10000),
          typeId: 1,
        ),
      ]);

      // 200 float + 100 taken = 300 expected.
      expect(s.varianceAgainst(const Money(31000)).minor, 1000);
      expect(s.varianceAgainst(const Money(29000)).minor, -1000);
      expect(s.varianceAgainst(const Money(30000)).minor, 0);
    });

    test('a tender with no recorded type is not cash', () {
      // Payments written before the type was carried. Under-stating the drawer
      // is caught by the count; over-stating it is a variance nobody can chase.
      final s = summary(const [
        ShiftTenderTotal(label: 'Cash', count: 1, amount: Money(10000)),
      ]);
      expect(s.cashTaken.minor, 0);
    });

    test('subtracts only cash refunds from the expected drawer', () {
      final s = summary(
        const [
          ShiftTenderTotal(
            label: 'Cash',
            count: 1,
            amount: Money(10000),
            typeId: 1,
          ),
        ],
        cashRefunded: const Money(2500),
      );

      expect(s.expectedCash.minor, 20000 + 10000 - 2500);
    });
  });
}
