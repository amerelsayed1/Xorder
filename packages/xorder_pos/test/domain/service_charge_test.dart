import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/domain/models/catalog.dart';
import 'package:xorder_pos/domain/models/service_charge.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/domain/services/ticket_engine.dart';

/// What a business adds on top of the food (§38).
///
/// The thing that had to stay true through this change is that a business
/// which has configured nothing is charged exactly what it was before — so the
/// first group is arithmetic, and it is the reason the 31 Wave A money goldens
/// still pass untouched.
void main() {
  const product = Product(
    id: 1,
    categoryId: 1,
    nameEn: 'Grill',
    price: Money(10000),
  );

  Ticket ticket(TaxConfig config, {OrderType type = OrderType.dineIn}) =>
      TicketEngine.addLine(
        Ticket(id: 'txn-1', orderType: type, taxConfig: config),
        product,
      ).ticket!;

  ServiceCharge charge({
    int id = 1,
    String name = 'Service',
    int? rateBp = 1200,
    int? fixedMinor,
    Set<OrderType> orderTypes = const {},
    bool isTaxable = true,
    bool isAutomatic = true,
    bool isActive = true,
  }) => ServiceCharge(
    id: id,
    nameEn: name,
    rateBp: rateBp,
    fixedMinor: fixedMinor,
    orderTypes: orderTypes,
    isTaxable: isTaxable,
    isAutomatic: isAutomatic,
    isActive: isActive,
  );

  group('a business that has configured nothing', () {
    test('is charged exactly what it was', () {
      // The single rate and the dine-in-only rule, untouched.
      const config = TaxConfig(serviceBp: 1200, vatBp: 1400);
      expect(ticket(config).totals.service.minor, 1200);
      expect(
        ticket(config, type: OrderType.takeaway).totals.service.minor,
        0,
      );
    });

    test('and the service it is charged is still taxed', () {
      const config = TaxConfig(serviceBp: 1200, vatBp: 1400);
      // 100.00 + 12.00 service, at 14%.
      expect(ticket(config).totals.vat.minor, 1568);
    });
  });

  group('a configured charge takes over', () {
    test('the old single rate stops applying', () {
      // Not both. A business that configures charges has said what it wants,
      // and adding the legacy rate underneath would be charging twice.
      final config = TaxConfig(
        serviceBp: 1200,
        vatBp: 1400,
        serviceCharges: [charge(rateBp: 1000)],
      );
      expect(ticket(config).totals.service.minor, 1000);
    });

    test('a fixed amount is a fixed amount, not a percentage of anything', () {
      final config = TaxConfig(
        vatBp: 1400,
        serviceCharges: [charge(rateBp: null, fixedMinor: 1500)],
      );
      expect(ticket(config).totals.service.minor, 1500);
    });

    test('two charges are two roundings, because they are two lines', () {
      // 33.33 at 12% is 4.00 (3.9996 rounds up); at 5% it is 1.67 (1.6665).
      // A customer checking the bill checks each line, so each rounds.
      const small = Product(
        id: 2,
        categoryId: 1,
        nameEn: 'Small',
        price: Money(3333),
      );
      final config = TaxConfig(
        vatBp: 0,
        serviceCharges: [
          charge(rateBp: 1200),
          charge(id: 2, name: 'Cover', rateBp: 500),
        ],
      );
      final settled = TicketEngine.addLine(
        Ticket(id: 't', orderType: OrderType.dineIn, taxConfig: config),
        small,
      ).ticket!;

      expect(settled.totals.service.minor, 400 + 167);
    });

    test('an inactive charge is not charged', () {
      final config = TaxConfig(
        vatBp: 0,
        serviceCharges: [charge(isActive: false)],
      );
      expect(ticket(config).totals.service.minor, 0);
    });

    test('a manual charge is not added automatically', () {
      // It is one the cashier adds by hand — a screen this model is ready for
      // and nothing yet offers.
      final config = TaxConfig(
        vatBp: 0,
        serviceCharges: [charge(isAutomatic: false)],
      );
      expect(ticket(config).totals.service.minor, 0);
    });
  });

  group('which orders it applies to', () {
    test('no order types named means every one', () {
      // A business that has not thought about it gets a charge that applies.
      // One that silently applied to nothing would be one somebody configured
      // and never saw.
      final config = TaxConfig(vatBp: 0, serviceCharges: [charge()]);
      for (final type in OrderType.values) {
        expect(
          ticket(config, type: type).totals.service.minor,
          1200,
          reason: type.wire,
        );
      }
    });

    test('a named set is the only set', () {
      final config = TaxConfig(
        vatBp: 0,
        serviceCharges: [charge(orderTypes: {OrderType.delivery})],
      );
      expect(
        ticket(config, type: OrderType.delivery).totals.service.minor,
        1200,
      );
      expect(ticket(config, type: OrderType.dineIn).totals.service.minor, 0);
    });

    test('two charges can cover different order types', () {
      // The shape the single `serviceDineInOnly` flag could not express.
      final config = TaxConfig(
        vatBp: 0,
        serviceCharges: [
          charge(orderTypes: {OrderType.dineIn}),
          charge(
            id: 2,
            name: 'Delivery',
            rateBp: null,
            fixedMinor: 2000,
            orderTypes: {OrderType.delivery},
          ),
        ],
      );

      expect(ticket(config, type: OrderType.dineIn).totals.service.minor, 1200);
      expect(
        ticket(config, type: OrderType.delivery).totals.service.minor,
        2000,
      );
      expect(
        ticket(config, type: OrderType.takeaway).totals.service.minor,
        0,
      );
    });
  });

  group('tax on the charge', () {
    test('a taxable charge joins the VAT base', () {
      final config = TaxConfig(
        vatBp: 1400,
        serviceCharges: [charge(rateBp: 1200)],
      );
      // 100.00 + 12.00, at 14%.
      expect(ticket(config).totals.vat.minor, 1568);
    });

    test('a non-taxable charge stays out of it entirely', () {
      // Not taxed at zero — those are different statements on a filing. A
      // delivery fee collected for an aggregator is not the business's
      // revenue to tax.
      final config = TaxConfig(
        vatBp: 1400,
        serviceCharges: [charge(rateBp: null, fixedMinor: 2000, isTaxable: false)],
      );
      final totals = ticket(config).totals;

      expect(totals.vat.minor, 1400, reason: 'the food only');
      expect(totals.service.minor, 2000, reason: 'and the fee is still charged');
      expect(totals.total.minor, 10000 + 2000 + 1400);
    });

    test('a taxable and an untaxed charge on one bill', () {
      final config = TaxConfig(
        vatBp: 1400,
        serviceCharges: [
          charge(rateBp: 1200),
          charge(
            id: 2,
            name: 'Delivery',
            rateBp: null,
            fixedMinor: 2000,
            isTaxable: false,
          ),
        ],
      );
      final totals = ticket(config).totals;

      expect(totals.service.minor, 1200 + 2000);
      expect(totals.vat.minor, 1568, reason: 'the fee is not in the base');
      expect(totals.total.minor, 10000 + 3200 + 1568);
    });
  });

  group('the model itself', () {
    test('a charge is a rate or an amount, and knows which', () {
      expect(charge().isFixed, isFalse);
      expect(charge(rateBp: null, fixedMinor: 500).isFixed, isTrue);
    });

    test('a fixed charge takes the ticket\'s currency, not a default', () {
      // A Kuwaiti business's 5.000 KWD fee must not arrive as EGP.
      const dinar = Money(0, currency: 'KWD', exponent: 3);
      final amount = charge(rateBp: null, fixedMinor: 5000).on(dinar);
      expect(amount.currency, 'KWD');
      expect(amount.exponent, 3);
      expect(amount.format(), '5.000');
    });

    test('a name falls back rather than blanking in Arabic', () {
      expect(charge(name: 'Service').displayName('ar'), 'Service');
    });
  });
}
