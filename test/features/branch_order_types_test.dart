import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/domain/models/order_type_config.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/domain/repositories/repositories.dart';

import '../support/fakes.dart';

ProviderContainer _withBranch(List<String> types, {OrderTypeRules? rules}) {
  final container = ProviderContainer(overrides: [
    ...fakeRepositoryOverrides(),
    branchesProvider.overrideWith((ref) async => [
          PosBranch(id: 3, name: 'Main', code: 'MAIN', supportedOrderTypes: types),
        ]),
    if (rules != null)
      orderTypeConfigProvider.overrideWith((ref) async => rules),
  ]);
  addTearDown(container.dispose);
  container.read(terminalProfileProvider.notifier).apply(
        const TerminalProfile(
          restaurantId: 7,
          branchId: 3,
          branchCode: 'MAIN',
          terminalName: 'Till',
          terminalId: 'e6c0f0a2-0000-4000-8000-000000000009',
        ),
      );
  return container;
}

void main() {
  test('the till offers only what the branch supports', () async {
    final container = _withBranch(['dine_in', 'delivery']);
    await container.read(branchesProvider.future);

    // The cashier must never be shown a type the server will refuse at
    // settlement — that is a whole ticket rung up for nothing.
    expect(container.read(branchOrderTypesProvider),
        [OrderType.dineIn, OrderType.delivery]);
  });

  test('an empty list means everything, exactly as the server reads it', () async {
    // PosOrderService: `$supported !== [] && !in_array(...)` — empty allows
    // all. The client mirrors that rule rather than inventing its own.
    final container = _withBranch(const []);
    await container.read(branchesProvider.future);
    expect(container.read(branchOrderTypesProvider), OrderType.values);
  });

  test('an unknown wire value is dropped, never thrown on', () async {
    final container = _withBranch(['dine_in', 'teleportation']);
    await container.read(branchesProvider.future);
    expect(container.read(branchOrderTypesProvider), [OrderType.dineIn]);
  });

  test('a branch whose every value is unreadable can still sell', () async {
    final container = _withBranch(['nonsense']);
    await container.read(branchesProvider.future);
    expect(container.read(branchOrderTypesProvider), OrderType.values);
  });

  // What the back office left switched on. The repository's `all()` returns
  // only the active rows, so the rules the till holds are exactly these.
  OrderTypeRules switchedOn(List<OrderType> types) => OrderTypeRules([
        for (final config in OrderTypeConfig.seeded)
          if (types.contains(config.type)) config,
      ]);

  test('a type turned off in the back office is gone from the till', () async {
    // The bug: the bar read only the branch, so the switch changed nothing.
    final container = _withBranch(const [],
        rules: switchedOn([OrderType.dineIn, OrderType.takeaway]));
    await container.read(branchesProvider.future);
    await container.read(orderTypeConfigProvider.future);
    expect(container.read(branchOrderTypesProvider),
        [OrderType.dineIn, OrderType.takeaway]);
  });

  test('both filters apply — the branch list and the switch', () async {
    final container = _withBranch(['dine_in', 'delivery'],
        rules: switchedOn([OrderType.dineIn, OrderType.takeaway]));
    await container.read(branchesProvider.future);
    await container.read(orderTypeConfigProvider.future);
    expect(container.read(branchOrderTypesProvider), [OrderType.dineIn]);
  });

  test('nothing in common leaves the branch list, never nothing', () async {
    final container =
        _withBranch(['delivery'], rules: switchedOn([OrderType.dineIn]));
    await container.read(branchesProvider.future);
    await container.read(orderTypeConfigProvider.future);
    expect(container.read(branchOrderTypesProvider), [OrderType.delivery]);
  });

  test('a new ticket starts on a type the till offers', () async {
    final container = _withBranch(const [],
        rules: switchedOn([OrderType.takeaway, OrderType.delivery]));
    await container.read(branchesProvider.future);
    await container.read(orderTypeConfigProvider.future);
    expect(container.read(ticketProvider).orderType, OrderType.takeaway);
  });

  test('an empty ticket moves off a type that arrives switched off', () async {
    // The rules land after the first ticket is built, so the ticket is born on
    // dine in and has to be moved once the till learns dine in is off.
    final container = _withBranch(const [],
        rules: switchedOn([OrderType.takeaway, OrderType.delivery]));
    expect(container.read(ticketProvider).orderType, OrderType.dineIn);

    await container.read(branchesProvider.future);
    await container.read(orderTypeConfigProvider.future);
    container.read(branchOrderTypesProvider);
    expect(container.read(ticketProvider).orderType, OrderType.takeaway);
  });
}
