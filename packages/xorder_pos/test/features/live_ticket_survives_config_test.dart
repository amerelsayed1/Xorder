import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/domain/models/catalog.dart';
import 'package:xorder_pos/domain/models/dining_table.dart';
import 'package:xorder_pos/domain/models/service_charge.dart';
import 'package:xorder_pos/domain/models/tax.dart';
import 'package:xorder_pos/domain/models/ticket.dart';

import 'package:xorder_pos_test_support/fakes.dart';

const _burger = Product(id: 101, categoryId: 1, nameEn: 'Burger', price: Money(9500));

void main() {
  test('the platform rates arrive WITHOUT destroying the live ticket', () {
    // The bug this pins: TicketController.build() watched the tax config, so
    // the moment the platform's rates finished loading the notifier rebuilt
    // and the cashier's seated table and every line on it vanished mid-sale.
    final container = ProviderContainer(overrides: [
      ...fakeRepositoryOverrides(),
      moneyConfigProvider.overrideWith((ref) async => const TaxConfig()),
    ]);
    addTearDown(container.dispose);

    final tickets = container.read(ticketProvider.notifier);
    tickets.attachTable(const DiningTable(id: 12, label: 'T12', seats: 4));
    tickets.addProduct(_burger, quantity: 2);

    final before = container.read(ticketProvider);
    expect(before.tableId, 12);
    expect(before.lines, hasLength(1));

    // A config change of any kind must fold onto the ticket, never replace it.
    container.read(ticketProvider.notifier).state =
        container.read(ticketProvider).copyWith(
              taxConfig: const TaxConfig(serviceBp: 1000, vatBp: 1400,
                  source: TaxSource.server),
            );

    final after = container.read(ticketProvider);
    expect(after.id, before.id, reason: 'same sale, same idempotency key');
    expect(after.tableId, 12, reason: 'the party is still seated');
    expect(after.lines, hasLength(1), reason: 'their food is still on the bill');
    expect(after.taxConfig.serviceBp, 1000);
    expect(after.taxConfig.source, TaxSource.server);
  });

  test('TaxConfig compares by value, so an unchanged config is a no-op', () {
    expect(const TaxConfig(), const TaxConfig());
    expect(const TaxConfig(vatBp: 1400), isNot(const TaxConfig(vatBp: 1500)));
    expect(const TaxConfig(source: TaxSource.server),
        isNot(const TaxConfig(source: TaxSource.deviceConfig)));
  });

  test('TaxConfig sees a change of mode, groups or charges (R-SALE-2)', () {
    // It used to compare the four scalars only, so the controller's
    // `previous == next` guard read each of these as "nothing changed" and
    // the live ticket kept pricing under the old rules.
    const zero = TaxGroup(id: 2, nameEn: 'Zero-rated', rateBp: 0);
    const fee = ServiceCharge(id: 6, nameEn: 'Delivery', fixedMinor: 2500);

    expect(const TaxConfig(taxMode: TaxMode.inclusive),
        isNot(const TaxConfig()));
    expect(const TaxConfig().withTaxGroups(const [zero]),
        isNot(const TaxConfig()));
    expect(const TaxConfig().withServiceCharges(const [fee]),
        isNot(const TaxConfig()));

    // Fresh lists with the same contents are the same config, or every sync
    // pass would rewrite the ticket.
    final a = const TaxConfig().withTaxGroups([zero]).withServiceCharges([fee]);
    final b = const TaxConfig().withTaxGroups([zero]).withServiceCharges([fee]);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });
}
