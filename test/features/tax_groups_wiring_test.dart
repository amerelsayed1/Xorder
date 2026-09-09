import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/domain/models/tax.dart';

import '../support/fakes.dart';

/// The restaurant's named rates reach the ticket.
///
/// **This is the half that was missing.** `pos_tax_groups` has been seeded since
/// the installer wrote it and `pos_products.tax_group_id` has pointed at it since
/// Wave M; the domain has been taxing per group correctly all along —
/// `tax_lines_test.dart` proves it. What nothing did was *load* the groups, so
/// `TaxConfig.taxGroups` arrived empty on every till, `defaultTaxGroup` answered
/// every lookup, and a bottle of water a restaurant had marked zero-rated was
/// charged the standard rate anyway.
void main() {
  const standard = TaxGroup(
    id: 1,
    nameEn: 'VAT',
    rateBp: 1400,
    isDefault: true,
  );
  const zero = TaxGroup(id: 2, nameEn: 'Zero-rated', rateBp: 0);

  ProviderContainer withGroups(List<TaxGroup> groups) {
    final container = ProviderContainer(
      overrides: [
        ...fakeRepositoryOverrides(),
        taxGroupsProvider.overrideWith((ref) async => groups),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('with no groups configured, nothing changes', () async {
    // The property that lets this ship: a restaurant that has configured none is
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
}
