import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/core/ui/tokens.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/service_charge.dart';
import 'package:xorder_pos/domain/repositories/admin_repositories.dart';
import 'package:xorder_pos/data/postgres/postgres_tender_types_repository.dart';
import 'package:xorder_pos/domain/repositories/repositories.dart';
import 'package:xorder_pos/features/admin/presentation/management_charges_pane.dart';
import 'package:xorder_pos/features/admin/presentation/management_taxes_pane.dart';
import 'package:xorder_pos/features/admin/presentation/management_tenders_pane.dart';

/// Who owns each of the three money panes.
///
/// **One pane used to hold all three subjects and one ownership rule.** The tax
/// rates are the platform's on a cloud till — the bootstrap seeder writes
/// `pos_money_config` — so the pane disappeared; then Wave D put payment methods
/// and service charges in it, which are local on both deployments, and a cloud
/// restaurant was left unable to say how it takes money. That was patched by
/// gating half a pane, and is now settled properly: three panes, and the one the
/// platform owns is the only one that says so.
void main() {
  const admin = PosStaff(
    id: 1,
    name: 'Mona',
    capabilities: {PosCapability.settingsManage, PosCapability.catalogManage},
  );

  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1440, 1600);
    view.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  Future<void> pump(
    WidgetTester tester, {
    required bool authors,
    required Widget pane,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogAdminRepositoryProvider.overrideWithValue(
            authors ? _Catalogue() : null,
          ),
          tenderTypesRepositoryProvider.overrideWithValue(
            const UnconfiguredTenderTypesRepository(),
          ),
          serviceChargesRepositoryProvider.overrideWithValue(
            const _Charges(),
          ),
        ],
        child: MaterialApp(
          theme: buildPosTheme(PosPalette.light),
          localizationsDelegates: const [
            AppLocalizations(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: pane),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('a cloud till', () {
    testWidgets('is told the tax is not its to change, and shown no boxes', (
      tester,
    ) async {
      await pump(
        tester,
        authors: false,
        pane: const ManagementTaxesPane(admin: admin),
      );

      expect(find.textContaining('platform'), findsOneWidget);
      expect(
        find.byKey(const Key('rates-save')),
        findsNothing,
        reason: 'a save button that always refused would be a lie',
      );
      expect(find.byKey(const Key('rate-vat')), findsNothing);
    });

    testWidgets('can still say how it takes money', (tester) async {
      await pump(
        tester,
        authors: false,
        pane: const ManagementTendersPane(admin: admin),
      );
      expect(find.text('PAYMENT METHODS'), findsOneWidget);
      expect(find.byKey(const Key('tender-new')), findsOneWidget);
    });

    testWidgets('and what it adds on top of the food', (tester) async {
      await pump(
        tester,
        authors: false,
        pane: const ManagementChargesPane(admin: admin),
      );
      expect(find.text('SERVICE CHARGES'), findsOneWidget);
      expect(find.byKey(const Key('charge-new')), findsOneWidget);
    });
  });

  group('an offline till', () {
    testWidgets('sets its own rates, and is told whether it has', (
      tester,
    ) async {
      await pump(
        tester,
        authors: true,
        pane: const ManagementTaxesPane(admin: admin),
      );

      expect(find.byKey(const Key('rates-save')), findsOneWidget);
      expect(find.byKey(const Key('rate-vat')), findsOneWidget);
      expect(find.byKey(const Key('rate-service')), findsOneWidget);
      expect(
        find.textContaining('platform'),
        findsNothing,
        reason: 'these rates are this terminal\'s',
      );
    });

    testWidgets('and gets the other two panes unchanged', (tester) async {
      await pump(
        tester,
        authors: true,
        pane: const ManagementTendersPane(admin: admin),
      );
      expect(find.text('PAYMENT METHODS'), findsOneWidget);
    });
  });

  testWidgets('the seeded payment methods are listed on either', (
    tester,
  ) async {
    for (final authors in [true, false]) {
      await pump(
        tester,
        authors: authors,
        pane: const ManagementTendersPane(admin: admin),
      );
      expect(find.text('Cash'), findsWidgets, reason: 'authors=$authors');
    }
  });
}

class _Catalogue implements CatalogAdminRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}

class _Charges implements ServiceChargesRepository {
  const _Charges();

  @override
  Future<List<ServiceCharge>> all({bool includeInactive = false}) async =>
      const [];

  @override
  Future<AdminResult<ServiceCharge>> save(
    ServiceCharge charge, {
    required PosStaff by,
  }) => throw UnimplementedError();
}
