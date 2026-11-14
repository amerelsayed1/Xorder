import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/app/providers.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/domain/models/catalog.dart';
import 'package:shared_module/domain/models/tax.dart';
import 'package:shared_module/domain/models/ticket.dart';

import 'package:xorder_pos_test_support/fakes.dart';

/// The business's named rates reach the ticket.
///
/// **This is the half that was missing.** `pos_tax_groups` has been seeded since
/// the installer wrote it and `pos_products.tax_group_id` has pointed at it since
/// Wave M; the domain has been taxing per group correctly all along —
/// `tax_lines_test.dart` proves it. What nothing did was *load* the groups, so
/// `TaxConfig.taxGroups` arrived empty on every till, `defaultTaxGroup` answered
/// every lookup, and a bottle of water a business had marked zero-rated was
/// charged the standard rate anyway.
void main() {
  const standard = TaxGroup(
    id: 1,
    nameEn: 'VAT',
    rateBp: 1400,
    isDefault: true,
  );
  const zero = TaxGroup(id: 2, nameEn: 'Zero-rated', rateBp: 0);

  ProviderContainer withGroups(List<TaxGroup> groups, {TaxConfig? stored}) {
    final container = ProviderContainer(
      overrides: [
        ...fakeRepositoryOverrides(),
        taxGroupsProvider.overrideWith((ref) async => groups),
        if (stored != null) moneyConfigProvider.overrideWith((ref) async => stored),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('with no groups configured, nothing changes', () async {
    // The property that lets this ship: a business that has configured none is
    // charged exactly what it was.
    final container = withGroups(const []);
    await container.read(taxGroupsProvider.future);

    expect(container.read(taxConfigProvider).taxGroups, isEmpty);
    expect(
      container.read(taxConfigProvider).defaultTaxGroup.rateBp,
      container.read(taxConfigProvider).vatBp,
      reason: 'the single rate still answers every lookup',
    );
  });

  test('configured groups arrive on the tax config', () async {
    final container = withGroups(const [standard, zero]);
    await container.read(taxGroupsProvider.future);

    final config = container.read(taxConfigProvider);
    expect(config.taxGroups, hasLength(2));
    expect(config.defaultTaxGroup.id, 1, reason: 'the one marked default');
    expect(config.groupFor(2).rateBp, 0);
  });

  test('a zero-rated item is charged zero, which is the whole point', () async {
    // Before the loader this test would have failed by charging 14%: `groupFor`
    // would not have found group 2 and would have fallen back to the default.
    final container = withGroups(const [standard, zero]);
    await container.read(taxGroupsProvider.future);
    final config = container.read(taxConfigProvider);

    expect(config.groupFor(2).rateBp, 0);
    expect(
      const Money(10000).percentBp(config.groupFor(2).rateBp),
      Money.zero,
    );
    expect(
      const Money(10000).percentBp(config.groupFor(null).rateBp),
      const Money(1400),
      reason: 'and an item that names no group still pays the fallback',
    );
  });

  test('an unknown group id falls back rather than throwing', () async {
    // A product pointing at a group this till has not loaded — a retired one, or
    // a row a newer build wrote. Charging the fallback is the only safe answer:
    // refusing to price it would refuse the sale.
    final container = withGroups(const [standard, zero]);
    await container.read(taxGroupsProvider.future);

    expect(container.read(taxConfigProvider).groupFor(999).isDefault, isTrue);
  });

  test('the service charges and the groups both fold in', () async {
    // Two separate lists on the same object, and each is layered on
    // independently — so configuring one must not clear the other.
    final container = withGroups(const [standard, zero]);
    await container.read(taxGroupsProvider.future);

    final config = container.read(taxConfigProvider);
    expect(config.taxGroups, hasLength(2));
    expect(config.serviceBp, isNotNull, reason: 'the rate survived');
  });

  group('what a ticket is taxed at (XORD-027)', () {
    // 100.00 of food, no service, so the VAT is the whole story.
    Future<int> vatFor(
      List<TaxGroup> groups, {
      required TaxConfig stored,
    }) async {
      final container = withGroups(groups, stored: stored);
      await container.read(taxGroupsProvider.future);
      await container.read(moneyConfigProvider.future);
      return Ticket(
        id: 'txn-1',
        orderType: OrderType.takeaway,
        taxConfig: container.read(taxConfigProvider),
        lines: [
          TicketLine(
            product: const Product(
              id: 1,
              categoryId: 1,
              nameEn: 'Item',
              price: Money(10000),
            ),
            quantity: 1,
          ),
        ],
      ).totals.vat.minor;
    }

    test('a default group at 0 charges nothing, whatever vatBp says', () async {
      expect(
        await vatFor(
          const [TaxGroup(id: 1, nameEn: 'VAT', rateBp: 0, isDefault: true)],
          stored: const TaxConfig(serviceBp: 0, vatBp: 1400),
        ),
        0,
      );
    });

    test('and vatBp at 0 does not override a default group at 14%', () async {
      // The mechanism behind the bug, pinned so nobody rediscovers it: the
      // group wins. This is why `saveMoneyConfig` has to move the group, and
      // why the pane reads its figure from the group.
      expect(
        await vatFor(
          const [standard],
          stored: const TaxConfig(serviceBp: 0, vatBp: 0),
        ),
        1400,
      );
    });

    test('with no groups, vatBp is the rate', () async {
      expect(
        await vatFor(const [], stored: const TaxConfig(serviceBp: 0, vatBp: 0)),
        0,
      );
      expect(
        await vatFor(
          const [],
          stored: const TaxConfig(serviceBp: 0, vatBp: 1500),
        ),
        1500,
      );
    });
  });
}
