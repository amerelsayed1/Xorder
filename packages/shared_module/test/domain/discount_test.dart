import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/domain/models/discount.dart';
import 'package:shared_module/domain/models/ticket.dart';

/// What a configured discount comes to, and when it is on offer.
///
/// Pure, and deliberately so: every rule here decides what a customer pays, and
/// none of it may live somewhere that needs a widget or a clock to test.
void main() {
  Discount percentage(
    int bp, {
    Money? cap,
    DiscountScope scope = DiscountScope.item,
  }) => Discount(
    id: 1,
    code: 'pct',
    nameEn: 'Percentage',
    kind: DiscountKind.percentage,
    scope: scope,
    valueBp: bp,
    maxDiscount: cap,
  );

  Discount fixed(int minor, {DiscountScope scope = DiscountScope.order}) =>
      Discount(
        id: 2,
        code: 'fix',
        nameEn: 'Fixed',
        kind: DiscountKind.fixed,
        scope: scope,
        valueMinor: Money(minor),
      );

  group('amountOn', () {
    test('a percentage takes its share', () {
      // 100.00 at 10% = 10.00
      expect(percentage(1000).amountOn(const Money(10000)).minor, 1000);
    });

    test('a fractional percentage rounds half-up', () {
      // 33.33 at 12.5% = 4.16625 → 4.17
      expect(percentage(1250).amountOn(const Money(3333)).minor, 417);
    });

    test('a fixed amount ignores the base', () {
      expect(fixed(2500).amountOn(const Money(10000)).minor, 2500);
    });

    test('a cap applies before anything else sees the number', () {
      // 20% of 500.00 is 100.00, capped at 50.00. The cap is part of what the
      // discount IS — a caller that forgot it would undercharge.
      expect(
        percentage(
          2000,
          cap: const Money(5000),
        ).amountOn(const Money(50000)).minor,
        5000,
      );
    });

    test('a cap below the computed amount does not raise it', () {
      // 20% of 100.00 is 20.00, under a 50.00 cap. The cap is a ceiling, never
      // a target.
      expect(
        percentage(
          2000,
          cap: const Money(5000),
        ).amountOn(const Money(10000)).minor,
        2000,
      );
    });

    test('never exceeds the thing it comes off', () {
      // A discount larger than the goods is a negative sale, and the database
      // refuses to hold one — so the engine must never produce one.
      expect(fixed(20000).amountOn(const Money(10000)).minor, 10000);
    });

    test('100% takes everything and no more', () {
      expect(percentage(10000).amountOn(const Money(12345)).minor, 12345);
    });

    test('a zero base yields nothing', () {
      expect(percentage(2000).amountOn(const Money(0)).minor, 0);
      expect(fixed(2500).amountOn(const Money(0)).minor, 0);
    });

    test('the currency and exponent survive', () {
      final kwd = Discount(
        id: 3,
        code: 'k',
        nameEn: 'K',
        kind: DiscountKind.percentage,
        scope: DiscountScope.order,
        valueBp: 1000,
      );

      final amount = kwd.amountOn(
        const Money(25000, currency: 'KWD', exponent: 3),
      );
      expect(amount.minor, 2500);
      expect(amount.exponent, 3);
      expect(amount.format(), '2.500');
    });
  });

  group('isLiveAt', () {
    final tuesdayNoon = DateTime(2026, 9, 8, 12);

    Discount window({
      DateTime? starts,
      DateTime? ends,
      Set<int> days = const {},
      int? from,
      int? to,
      bool active = true,
    }) => Discount(
      id: 4,
      code: 'w',
      nameEn: 'W',
      kind: DiscountKind.percentage,
      scope: DiscountScope.order,
      valueBp: 1000,
      startsAt: starts,
      endsAt: ends,
      daysOfWeek: days,
      timeFrom: from,
      timeTo: to,
      isActive: active,
    );

    test('an unrestricted discount is always on', () {
      expect(window().isLiveAt(tuesdayNoon), isTrue);
    });

    test('an inactive discount never is', () {
      expect(window(active: false).isLiveAt(tuesdayNoon), isFalse);
    });

    test('before it starts, and after it ends', () {
      final d = window(
        starts: DateTime(2026, 9, 9),
        ends: DateTime(2026, 9, 20),
      );
      expect(d.isLiveAt(tuesdayNoon), isFalse);
      expect(d.isLiveAt(DateTime(2026, 9, 10)), isTrue);
      expect(d.isLiveAt(DateTime(2026, 9, 21)), isFalse);
    });

    test('the end is exclusive, the start inclusive', () {
      final d = window(
        starts: DateTime(2026, 9, 8),
        ends: DateTime(2026, 9, 9),
      );
      expect(d.isLiveAt(DateTime(2026, 9, 8)), isTrue);
      expect(d.isLiveAt(DateTime(2026, 9, 9)), isFalse);
    });

    test('days of week, with empty meaning every day', () {
      // Tuesday is 2 under ISO-8601.
      expect(window(days: {2}).isLiveAt(tuesdayNoon), isTrue);
      expect(window(days: {1, 3}).isLiveAt(tuesdayNoon), isFalse);
      expect(window(days: {}).isLiveAt(tuesdayNoon), isTrue);
    });

    test('a time window inside one day', () {
      // 11:00–15:00, a lunch offer.
      final lunch = window(from: 11 * 60, to: 15 * 60);
      expect(lunch.isLiveAt(tuesdayNoon), isTrue);
      expect(lunch.isLiveAt(DateTime(2026, 9, 8, 10, 59)), isFalse);
      expect(
        lunch.isLiveAt(DateTime(2026, 9, 8, 15)),
        isFalse,
        reason: 'end is exclusive',
      );
    });

    test('a window that crosses midnight is not a mistake', () {
      // 22:00–02:00. Treating `from > to` as an error would quietly switch
      // every late-night offer off between midnight and closing — which is
      // most of when it is meant to run.
      final lateNight = window(from: 22 * 60, to: 2 * 60);
      expect(lateNight.isLiveAt(DateTime(2026, 9, 8, 23)), isTrue);
      expect(lateNight.isLiveAt(DateTime(2026, 9, 8, 1)), isTrue);
      expect(lateNight.isLiveAt(DateTime(2026, 9, 8, 12)), isFalse);
      expect(lateNight.isLiveAt(DateTime(2026, 9, 8, 2)), isFalse);
    });
  });

  group('targets', () {
    test('no targets means everything', () {
      const targets = DiscountTargets();
      expect(targets.isUnrestricted, isTrue);
      expect(targets.allowsOrderType(OrderType.delivery), isTrue);
      expect(targets.allowsProduct(productId: 99, categoryId: 7), isTrue);
    });

    test('an order type restriction', () {
      const targets = DiscountTargets(orderTypes: {OrderType.dineIn});
      expect(targets.allowsOrderType(OrderType.dineIn), isTrue);
      expect(targets.allowsOrderType(OrderType.delivery), isFalse);
    });

    test('a category restriction', () {
      const targets = DiscountTargets(categoryIds: {7});
      expect(targets.allowsProduct(productId: 1, categoryId: 7), isTrue);
      expect(targets.allowsProduct(productId: 1, categoryId: 8), isFalse);
    });

    test('naming both a product and a category means either', () {
      // "10% off Grills" and "10% off the Mixed Grill" are both things a
      // business says, and one naming both means either.
      const targets = DiscountTargets(categoryIds: {7}, productIds: {42});
      expect(targets.allowsProduct(productId: 42, categoryId: 9), isTrue);
      expect(targets.allowsProduct(productId: 1, categoryId: 7), isTrue);
      expect(targets.allowsProduct(productId: 1, categoryId: 9), isFalse);
    });

    test('an order-type restriction alone does not restrict products', () {
      const targets = DiscountTargets(orderTypes: {OrderType.dineIn});
      expect(targets.allowsProduct(productId: 1, categoryId: 1), isTrue);
    });
  });

  group('AppliedDiscount', () {
    test('a null line key means the whole order', () {
      const order = AppliedDiscount(
        nameSnapshot: 'Manager comp',
        kind: DiscountKind.fixed,
        amount: Money(5000),
        appliedByStaffId: 4,
      );
      expect(order.isOrderLevel, isTrue);

      const line = AppliedDiscount(
        nameSnapshot: 'Staff meal',
        kind: DiscountKind.percentage,
        amount: Money(1000),
        appliedByStaffId: 4,
        lineKey: '7:12,14',
      );
      expect(line.isOrderLevel, isFalse);
    });

    test('an approver on the record is what makes it an approved discount', () {
      const unapproved = AppliedDiscount(
        nameSnapshot: 'Staff meal',
        kind: DiscountKind.fixed,
        amount: Money(1000),
        appliedByStaffId: 4,
      );
      expect(unapproved.wasApproved, isFalse);

      const approved = AppliedDiscount(
        nameSnapshot: 'Staff meal',
        kind: DiscountKind.fixed,
        amount: Money(1000),
        appliedByStaffId: 4,
        approvedByName: 'Hana Mostafa',
      );
      // An approved discount with no approver recorded is indistinguishable
      // from one nobody approved.
      expect(approved.wasApproved, isTrue);
    });
  });

  group('wire values', () {
    test('round-trip, and an unknown value is null rather than a guess', () {
      expect(DiscountKind.fromWire('percentage'), DiscountKind.percentage);
      expect(DiscountKind.fromWire('fixed'), DiscountKind.fixed);
      expect(DiscountKind.fromWire('half_off'), isNull);

      expect(DiscountScope.fromWire('order'), DiscountScope.order);
      expect(DiscountScope.fromWire('item'), DiscountScope.item);
      expect(DiscountScope.fromWire('everything'), isNull);
    });
  });
}
