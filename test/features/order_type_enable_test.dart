import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/ui/tokens.dart';
import 'package:xorder_pos/domain/models/order_type_config.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/domain/repositories/admin_repositories.dart';
import 'package:xorder_pos/features/admin/presentation/management_order_types_pane.dart';

/// Turning a kind of order off, from the pane that lists them.
///
/// It was always possible — the row's editor has the switch — and that is one
/// tap too deep for the thing a restaurant changes most: Ramadan starts and
/// delivery goes on, the dining room closes for a refit and seating goes off.
/// A pane you have to open a row inside to answer "what do we sell today" reads
/// as a pane that cannot answer it.
void main() {
  const admin = PosStaff(
    id: 1,
    name: 'Rana A.',
    username: 'rana',
    // A role, not bare capabilities: `PosStaff.capabilities` is direct grants
    // only, and the pane asks what this person may actually do.
    role: PosRole(
      id: 1,
      code: 'manager',
      nameEn: 'Manager',
      capabilities: {PosCapability.staffManage, PosCapability.catalogManage},
    ),
  );

  Future<_RecordingCatalogAdmin> pump(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repository = _RecordingCatalogAdmin();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogAdminRepositoryProvider.overrideWithValue(repository),
          orderTypesAllProvider.overrideWith(
            (ref) async => OrderTypeConfig.seeded,
          ),
        ],
        child: MaterialApp(
          theme: buildPosTheme(PosPalette.light),
          home: const Scaffold(
            body: ManagementOrderTypesPane(admin: admin),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  testWidgets('every type carries its own switch', (tester) async {
    await pump(tester);

    for (final type in OrderType.values) {
      expect(
        find.byKey(Key('order-type-active-${type.wire}')),
        findsOneWidget,
        reason: type.wire,
      );
    }
  });

  testWidgets('turning one off saves it off, and changes nothing else', (
    tester,
  ) async {
    final repository = await pump(tester);
    final before = OrderTypeConfig.seeded.firstWhere(
      (c) => c.type == OrderType.delivery,
    );

    await tester.tap(find.byKey(const Key('order-type-active-delivery')));
    await tester.pumpAndSettle();

    expect(repository.saved, hasLength(1));
    final saved = repository.saved.single;
    expect(saved.type, OrderType.delivery);
    expect(saved.isActive, isFalse);
    // The switch says one thing about this row and must not quietly restate
    // the rest of it: a name typed in Arabic, or an address requirement, is
    // not something a manager turning delivery off has asked to change.
    expect(saved.nameEn, before.nameEn);
    expect(saved.nameAr, before.nameAr);
    expect(saved.requiresTable, before.requiresTable);
    expect(saved.requiresCustomer, before.requiresCustomer);
    expect(saved.requiresAddress, before.requiresAddress);
    expect(saved.sortOrder, before.sortOrder);
  });

  testWidgets('and a terminal whose catalogue is the platform cannot', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // No admin repository: a cloud till's catalogue is authored on the
          // platform, and the pane already says so at the top.
          catalogAdminRepositoryProvider.overrideWithValue(null),
          orderTypesAllProvider.overrideWith(
            (ref) async => OrderTypeConfig.seeded,
          ),
        ],
        child: MaterialApp(
          theme: buildPosTheme(PosPalette.light),
          home: const Scaffold(
            body: ManagementOrderTypesPane(admin: admin),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final toggle = tester.widget<Switch>(
      find.byKey(const Key('order-type-active-delivery')),
    );
    expect(toggle.onChanged, isNull, reason: 'shown, and not operable');
  });
}

/// Records what the pane asked to save, and refuses to pretend about the rest.
class _RecordingCatalogAdmin implements CatalogAdminRepository {
  final saved = <OrderTypeConfig>[];

  @override
  Future<AdminResult<OrderTypeConfig>> saveOrderType(
    OrderTypeConfig config, {
    required PosStaff by,
  }) async {
    saved.add(config);
    return AdminResult.done(config);
  }

  /// Everything else on this interface throws if the pane reaches for it, which
  /// is the point: this stub is the save path and nothing more.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
