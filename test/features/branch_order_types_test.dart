import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/domain/repositories/repositories.dart';

import '../support/fakes.dart';

ProviderContainer _withBranch(List<String> types) {
  final container = ProviderContainer(overrides: [
    ...fakeRepositoryOverrides(),
    branchesProvider.overrideWith((ref) async => [
          PosBranch(id: 3, name: 'Main', code: 'MAIN', supportedOrderTypes: types),
        ]),
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
}
