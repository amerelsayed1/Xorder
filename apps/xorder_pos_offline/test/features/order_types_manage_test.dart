import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/app/providers.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/core/ui/tokens.dart';
import 'package:shared_module/domain/models/order_type_config.dart';
import 'package:shared_module/domain/models/permissions.dart';
import 'package:shared_module/domain/models/shift.dart';
import 'package:shared_module/domain/models/ticket.dart';
import 'package:shared_module/domain/repositories/admin_repositories.dart';
import 'package:xorder_pos_offline/features/admin/presentation/management_order_types_pane.dart';
import 'package:shared_module/features/licensing/domain/license.dart';

import 'package:xorder_pos_test_support/staff.dart';

/// XORD-002 — the order-types pane: who may choose, and what the licence covers.
void main() {
  LicenseClaims licence(Set<String> features) => LicenseClaims(
    licenseId: 'L1',
    tenantSlug: 'cafe',
    tenantName: 'Cafe',
    issuedAt: DateTime.utc(2026, 1, 1),
    expiresAt: DateTime.utc(2030, 1, 1),
    features: features,
  );

  Future<_Recorder> pump(
    WidgetTester tester, {
    required PosStaff admin,
    Set<String> features = const {'pos'},
  }) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repository = _Recorder();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogAdminRepositoryProvider.overrideWithValue(repository),
          orderTypesAllProvider.overrideWith((ref) async => OrderTypeConfig.seeded),
          licenceClaimsProvider.overrideWith((ref) async => licence(features)),
        ],
        child: MaterialApp(
          theme: buildPosTheme(PosPalette.light),
          home: Scaffold(body: ManagementOrderTypesPane(admin: admin)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  Switch switchOf(WidgetTester tester, OrderType type) => tester.widget<Switch>(
    find.byKey(Key('order-type-active-${type.wire}')),
  );

  final chooser = staffWith({PosCapability.orderTypesManage});

  testWidgets('somebody who may choose can switch a type', (tester) async {
    final repository = await pump(tester, admin: chooser);

    expect(switchOf(tester, OrderType.delivery).onChanged, isNotNull);
    await tester.tap(find.byKey(const Key('order-type-active-delivery')));
    await tester.pumpAndSettle();

    expect(repository.saved.single.type, OrderType.delivery);
  });

  testWidgets('somebody without the key sees the list and cannot change it', (
    tester,
  ) async {
    // Holds settings.manage — the key this pane used to answer to — and not the
    // new one. They may look; they may not change.
    final repository = await pump(
      tester,
      admin: staffWith({PosCapability.settingsManage}),
    );

    for (final type in OrderType.values) {
      expect(switchOf(tester, type).onChanged, isNull, reason: type.wire);
    }
    expect(repository.saved, isEmpty);
  });

  testWidgets('a type the licence does not cover but that is on stays listed, to be switched off', (
    tester,
  ) async {
    await pump(
      tester,
      admin: chooser,
      // Names dine-in and takeaway only; the seeded rows are all on.
      features: const {'pos', 'dine_in', 'pickup'},
    );

    // Delivery is on in the seed, so it stays listed to be switched OFF.
    expect(find.byKey(const Key('order-type-active-delivery')), findsOneWidget);
    expect(find.byKey(const Key('order-type-active-dine_in')), findsOneWidget);
  });

  testWidgets('and a licence that covers nothing else hides the rows that are off', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final off = [
      for (final c in OrderTypeConfig.seeded)
        OrderTypeConfig(
          type: c.type,
          nameEn: c.nameEn,
          nameAr: c.nameAr,
          requiresTable: c.requiresTable,
          isActive: c.type == OrderType.dineIn || c.type == OrderType.takeaway,
          sortOrder: c.sortOrder,
        ),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogAdminRepositoryProvider.overrideWithValue(_Recorder()),
          orderTypesAllProvider.overrideWith((ref) async => off),
          licenceClaimsProvider.overrideWith(
            (ref) async => licence(const {'pos', 'dine_in', 'pickup'}),
          ),
        ],
        child: MaterialApp(
          theme: buildPosTheme(PosPalette.light),
          home: Scaffold(body: ManagementOrderTypesPane(admin: chooser)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('order-type-active-delivery')), findsNothing);
    expect(find.byKey(const Key('order-type-active-dine_in')), findsOneWidget);
    expect(find.byKey(const Key('order-type-active-takeaway')), findsOneWidget);
  });

  testWidgets('the licence set is handed to the repository, which enforces it', (
    tester,
  ) async {
    final repository = await pump(
      tester,
      admin: chooser,
      features: const {'pos', 'dine_in'},
    );

    await tester.tap(find.byKey(const Key('order-type-active-dine_in')));
    await tester.pumpAndSettle();

    expect(repository.lastEntitled, {OrderType.dineIn, OrderType.driveThru});
  });
}

class _Recorder implements CatalogAdminRepository {
  final saved = <OrderTypeConfig>[];
  Set<OrderType>? lastEntitled;

  @override
  Future<AdminResult<OrderTypeConfig>> saveOrderType(
    OrderTypeConfig config, {
    required PosStaff by,
    Set<OrderType>? entitled,
  }) async {
    saved.add(config);
    lastEntitled = entitled;
    return AdminResult.done(config);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
