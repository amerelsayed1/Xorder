import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/data/postgres/money_config_codec.dart';
import 'package:shared_module/domain/models/ticket.dart';

void main() {
  test('the platform authors the rates, and says so', () {
    final config = MoneyConfigCodec.toTaxConfig(const {
      'tax_rules': [
        {'id': 1, 'name': 'VAT', 'rate_bp': 1400, 'mode': 'exclusive'},
      ],
      'charges': [
        {
          'id': 1,
          'name': 'Service',
          'kind': 'percent',
          'rate_bp': 1000,
          'applies_to': {'order_types': ['dine_in']},
        },
      ],
    });

    expect(config.vatBp, 1400);
    expect(config.serviceBp, 1000);
    expect(config.serviceDineInOnly, isTrue);
    expect(config.source, TaxSource.server,
        reason: 'a receipt must be able to say the rates came from the server');
  });

  test('a tenant with no rules charges NOTHING, not the old default', () {
    // The bug this file exists to end: the till charged 12% service + 14% VAT
    // from device config while the platform charged none, so the customer paid
    // 27.68% more than the ledger recorded.
    final config = MoneyConfigCodec.toTaxConfig(const {
      'tax_rules': [],
      'charges': [],
      'tender_types': [
        {'id': 1, 'name': 'Cash'},
      ],
    });

    expect(config.serviceBp, 0);
    expect(config.vatBp, 0);
    expect(config.source, TaxSource.server);
  });

  test('an unscoped service charge applies to every order type', () {
    final config = MoneyConfigCodec.toTaxConfig(const {
      'charges': [
        {'kind': 'percent', 'rate_bp': 1200, 'applies_to': {'order_types': []}},
      ],
    });
    expect(config.serviceBp, 1200);
    expect(config.serviceDineInOnly, isFalse);
  });

  test('a float rate is refused rather than rounded into a bill', () {
    // Rates are basis points by contract. A float here is a violation, and
    // guessing what it meant is how a bill ends up a piastre wrong forever.
    final config = MoneyConfigCodec.toTaxConfig(const {
      'tax_rules': [
        {'rate_bp': 14.0},
      ],
    });
    expect(config.vatBp, 0);
  });

  test('garbage decodes to zero rates, never a throw', () {
    expect(MoneyConfigCodec.toTaxConfig(const {}).vatBp, 0);
    expect(
      MoneyConfigCodec.toTaxConfig(const {'tax_rules': 'nonsense'}).serviceBp,
      0,
    );
  });
}
