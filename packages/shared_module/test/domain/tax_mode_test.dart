import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/domain/models/catalog.dart';
import 'package:shared_module/domain/models/discount.dart';
import 'package:shared_module/domain/models/ticket.dart';
import 'package:shared_module/domain/services/ticket_engine.dart';

/// Tax-inclusive pricing (§37).
///
/// **The expensive mistake this guards is charging the tax twice.** In
/// inclusive mode the rate is already inside the price, so adding it again
/// would take 14% more from every customer — an error that looks like a
/// rounding difference on one line and like a month of overcharging on a
/// return. Every test here checks the total as well as the tax.
void main() {
  /// 114.00 at 14% contains exactly 14.00 — chosen so the arithmetic is
  /// checkable by eye rather than by running it.
  const priced = Product(
    id: 1,
    categoryId: 1,
    nameEn: 'Grill',
    price: Money(11400),
  );

  Ticket ticket(TaxConfig config, {Product product = priced}) =>
      TicketEngine.addLine(
        Ticket(id: 'txn-1', orderType: OrderType.takeaway, taxConfig: config),
        product,
      ).ticket!;

  group('exclusive — what every business is on today', () {
    const config = TaxConfig(serviceBp: 0, vatBp: 1400);

    test('the rate goes on top', () {
      final totals = ticket(config).totals;
      expect(totals.subtotal.minor, 11400);
      expect(totals.vat.minor, 1596);
      expect(totals.total.minor, 12996);
    });

    test('is the default when nobody has been asked', () {
      expect(const TaxConfig().taxMode, TaxMode.exclusive);
      expect(const TaxConfig().isInclusive, isFalse);
    });
  });

  group('inclusive — the rate is already inside', () {
    const config = TaxConfig(
      serviceBp: 0,
      vatBp: 1400,
      taxMode: TaxMode.inclusive,
    );

    test('the customer pays the menu price, not more', () {
      // The whole point. 114.00 on the menu is 114.00 at the till.
      final totals = ticket(config).totals;
      expect(totals.total.minor, 11400);
    });

    test('and the tax is extracted rather than added', () {
      final totals = ticket(config).totals;
      expect(totals.vat.minor, 1400, reason: '114.00 contains 14.00 at 14%');
    });

    test('the filing gets the net base, not the gross', () {
      // What a return wants is the amount before tax; reporting the gross
      // would overstate revenue by the tax on it.
      final line = ticket(config).totals.taxLines.single;
      expect(line.base.minor, 10000);
      expect(line.amount.minor, 1400);
      expect(line.rateBp, 1400);
    });

    test('a service charge is inclusive too', () {
      const withService = TaxConfig(
        serviceBp: 1000,
        serviceDineInOnly: false,
        vatBp: 1400,
        taxMode: TaxMode.inclusive,
      );
      final totals = ticket(withService).totals;

      // 114.00 + 11.40 service = 125.40, all of it inclusive.
      expect(totals.service.minor, 1140);
      expect(totals.total.minor, 12540);
      expect(totals.vat.minor, 1540, reason: '125.40 contains 15.40');
    });

    test('a discount comes off before the tax is extracted', () {
      final discounted = TicketEngine.applyOrderDiscount(
        ticket(config),
        const Discount(
          id: 1,
          code: 'staff',
          nameEn: 'Staff',
          kind: DiscountKind.fixed,
          scope: DiscountScope.order,
          valueMinor: Money(1400),
        ),
        now: DateTime(2026, 9, 8),
        appliedBy: 1,
      ).ticket!;
      final totals = discounted.totals;

      expect(totals.total.minor, 10000);
      expect(totals.vat.minor, 1228, reason: '100.00 contains 12.28 at 14%');
    });

    test('a zero rate takes nothing out', () {
      const free = TaxConfig(
        serviceBp: 0,
        vatBp: 0,
        taxMode: TaxMode.inclusive,
      );
      final totals = ticket(free).totals;
      expect(totals.vat.minor, 0);
      expect(totals.total.minor, 11400);
    });
  });

  group('the arithmetic itself', () {
    test('extracting is not the same as adding', () {
      // Out by the square of the rate — small enough to survive a spot check,
      // large enough to matter over a month. This is why they are two methods.
      const gross = Money(11400);
      expect(gross.taxWithinBp(1400).minor, 1400);
      expect(gross.percentBp(1400).minor, 1596);
    });

    test('it rounds half-up, once', () {
      // 33.33 at 14% inclusive is 4.0928…, which rounds to 4.09.
      expect(const Money(3333).taxWithinBp(1400).minor, 409);
    });

    test('a zero rate extracts nothing', () {
      expect(const Money(11400).taxWithinBp(0).minor, 0);
    });

    test('it keeps the currency it was given', () {
      const dinar = Money(11400, currency: 'KWD', exponent: 3);
      final tax = dinar.taxWithinBp(1400);
      expect(tax.currency, 'KWD');
      expect(tax.exponent, 3);
    });
  });

  group('the wire value', () {
    test('round-trips', () {
      for (final mode in TaxMode.values) {
        expect(TaxMode.fromWire(mode.wire), mode);
      }
    });

    test('an unknown or absent mode is exclusive', () {
      // The mode every existing business is on, so a row this build cannot
      // read changes nobody's bill.
      expect(TaxMode.fromWire(null), TaxMode.exclusive);
      expect(TaxMode.fromWire('compound'), TaxMode.exclusive);
    });
  });
}
