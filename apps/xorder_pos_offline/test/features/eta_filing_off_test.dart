import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/services/eta_filing.dart';
import 'package:xorder_pos_offline/features/admin/presentation/management_screen.dart';

/// E-receipts, switched off.
///
/// Not needed by the businesses this is sold to yet (13 September 2026). What
/// is pinned is that "off" means off everywhere a business would feel it:
/// nothing queued, so nothing warns, and no pane about an obligation it does
/// not have.
void main() {
  const owner = PosStaff(
    id: 1,
    name: 'Amer M.',
    role: PosRole(
      id: 1,
      code: SystemRoles.ownerCode,
      nameEn: 'Owner',
      capabilities: SystemRoles.owner,
    ),
  );

  test('a default build does not file', () {
    expect(etaFilingEnabled, isFalse);
  });

  test('with filing off there is no queue, so no filer and no reconciler', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(etaFilingEnabledProvider), isFalse);
    expect(container.read(etaQueueRepositoryProvider), isNull);
    expect(container.read(etaFilerProvider), isNull);
    expect(container.read(etaReconcilerProvider), isNull);
  });

  test('and even an owner is not shown the Tax authority pane', () {
    final panes = managementPanesFor(
      admin: owner,
      authorsItsOwnCatalogue: true,
    );
    expect(panes, isNot(contains(ManagementPane.eta)));
    // The receipt profile stays: every slip still prints the name on it.
    expect(panes, contains(ManagementPane.receipt));
  });
}
