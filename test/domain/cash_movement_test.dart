import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/domain/models/business_day.dart';

/// Money into and out of the drawer that is not a sale.
///
/// The claim under test is the one the schema also makes: **amounts are always
/// positive and the kind carries the direction.** Storing a pay-out as a
/// negative would be negated twice by anything that reads the kind, and the two
/// conventions would coexist for as long as it took somebody to write the
/// second reader.
void main() {
  CashMovement movement({
    int id = 1,
    CashMovementKind kind = CashMovementKind.payIn,
    int amount = 5000,
  }) => CashMovement(
    id: id,
    kind: kind,
    amount: Money(amount),
    occurredAt: DateTime(2026, 9, 8, 14),
  );

  group('direction', () {
    test('the kind says which way, not the sign', () {
      expect(CashMovementKind.payIn.isInflow, isTrue);
      expect(CashMovementKind.payIn.isOutflow, isFalse);
      expect(CashMovementKind.payOut.isOutflow, isTrue);
      expect(CashMovementKind.payOut.isInflow, isFalse);

      // Adjusting the float upward is money arriving.
      expect(CashMovementKind.floatAdjust.isInflow, isTrue);

      // Opening the drawer is neither.
      expect(CashMovementKind.drawerOpen.isInflow, isFalse);
      expect(CashMovementKind.drawerOpen.isOutflow, isFalse);
    });

    test('signed applies the direction exactly once', () {
      // The one place the sign is applied, so no caller has to remember which
      // way a pay-out points.
      expect(movement(kind: CashMovementKind.payIn).signed.minor, 5000);
      expect(movement(kind: CashMovementKind.payOut).signed.minor, -5000);
      expect(movement(kind: CashMovementKind.floatAdjust).signed.minor, 5000);
    });

    test('an opening moves nothing whatever it carries', () {
      // The database refuses a drawer_open with an amount; if one arrives
      // anyway, it must not become money.
      expect(
        movement(kind: CashMovementKind.drawerOpen, amount: 900).signed.minor,
        0,
      );
    });

    test('every kind round-trips, and matches migration 14\'s CHECK', () {
      expect(CashMovementKind.values.map((k) => k.wire).toSet(), {
        'pay_in',
        'pay_out',
        'drawer_open',
        'float_adjust',
      });
      for (final kind in CashMovementKind.values) {
        expect(CashMovementKind.fromWire(kind.wire), kind);
      }
      expect(CashMovementKind.fromWire('tip_out'), isNull);
    });
  });

  group('totals', () {
    test('in and out are both positive; the names carry the direction', () {
      final totals = CashMovementTotals.of([
        movement(id: 1, kind: CashMovementKind.payIn, amount: 10000),
        movement(id: 2, kind: CashMovementKind.payOut, amount: 3000),
        movement(id: 3, kind: CashMovementKind.payOut, amount: 2000),
      ]);

      expect(totals.paidIn.minor, 10000);
      expect(totals.paidOut.minor, 5000);
      expect(totals.net.minor, 5000);
    });

    test('a float adjustment counts as money in', () {
      final totals = CashMovementTotals.of([
        movement(kind: CashMovementKind.floatAdjust, amount: 2000),
      ]);
      expect(totals.paidIn.minor, 2000);
    });

    test('drawer openings are counted, not totalled', () {
      // Not money, but the number a manager looks at hardest.
      final totals = CashMovementTotals.of([
        movement(id: 1, kind: CashMovementKind.drawerOpen, amount: 0),
        movement(id: 2, kind: CashMovementKind.drawerOpen, amount: 0),
        movement(id: 3, kind: CashMovementKind.payIn, amount: 1000),
      ]);

      expect(totals.drawerOpens, 2);
      expect(totals.paidIn.minor, 1000);
      expect(totals.net.minor, 1000);
    });

    test('a drawer that only opened nets nothing', () {
      final totals = CashMovementTotals.of([
        movement(kind: CashMovementKind.drawerOpen, amount: 0),
      ]);
      expect(totals.net.minor, 0);
      expect(totals.paidIn.minor, 0);
      expect(totals.paidOut.minor, 0);
    });

    test('an empty shift totals to nothing rather than throwing', () {
      final totals = CashMovementTotals.of(const []);
      expect(totals.net.minor, 0);
      expect(totals.drawerOpens, 0);
      expect(totals.movements, isEmpty);
    });

    test('paying out more than was paid in nets negative', () {
      // A drawer can legitimately end a shift lighter than it started —
      // a bank drop is exactly that.
      final totals = CashMovementTotals.of([
        movement(id: 1, kind: CashMovementKind.payIn, amount: 1000),
        movement(id: 2, kind: CashMovementKind.payOut, amount: 9000),
      ]);
      expect(totals.net.minor, -8000);
    });
  });

  group('the business day', () {
    test('is open until it is closed', () {
      final day = BusinessDay(
        id: 1,
        date: DateTime(2026, 9, 8),
        openedAt: DateTime(2026, 9, 8, 6),
      );
      expect(day.isOpen, isTrue);
      expect(
        BusinessDay(
          id: 1,
          date: DateTime(2026, 9, 8),
          openedAt: DateTime(2026, 9, 8, 6),
          closedAt: DateTime(2026, 9, 9, 2),
        ).isOpen,
        isFalse,
      );
    });

    test('a clear check needs no force', () {
      final check = DayCloseCheck(
        day: BusinessDay(
          id: 1,
          date: DateTime(2026, 9, 8),
          openedAt: DateTime(2026, 9, 8, 6),
        ),
        blockers: const [],
      );
      expect(check.isClear, isTrue);
      expect(check.needsForce, isFalse);
    });

    test('any blocker means a force', () {
      final check = DayCloseCheck(
        day: BusinessDay(
          id: 1,
          date: DateTime(2026, 9, 8),
          openedAt: DateTime(2026, 9, 8, 6),
        ),
        blockers: const [
          DayBlocker(kind: DayBlockerKind.openShift, count: 1),
        ],
      );
      expect(check.isClear, isFalse);
      expect(check.needsForce, isTrue);
    });
  });
}
