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
import 'package:xorder_pos/domain/models/tax.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/domain/repositories/admin_repositories.dart';
import 'package:xorder_pos/data/postgres/postgres_tender_types_repository.dart';
import 'package:xorder_pos/domain/repositories/repositories.dart';
import 'package:xorder_pos/features/admin/presentation/admin_pane_bits.dart';
import 'package:xorder_pos/features/admin/presentation/management_charges_pane.dart';
import 'package:xorder_pos/features/admin/presentation/management_taxes_pane.dart';
import 'package:xorder_pos/features/admin/presentation/management_tenders_pane.dart';

/// Who owns each of the three money panes.
///
/// **One pane used to hold all three subjects and one ownership rule.** The tax
/// rates are the platform's on a cloud till — the bootstrap seeder writes
/// `pos_money_config` — so the pane disappeared; then Wave D put payment methods
/// and service charges in it, which are local on both deployments, and a cloud
/// business was left unable to say how it takes money. That was patched by
/// gating half a pane, and is now settled properly: three panes, and each one
/// the platform owns says so. Since POS-BE-013 that is two of them — the bundle
/// delivers payment methods too, and the drain sends a payment only on a
/// tender the platform sent.
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

  late _Catalogue catalogue;

  Future<void> pump(
    WidgetTester tester, {
    required bool authors,
    required Widget pane,
    TaxConfig? stored,
    List<TaxGroup>? groups,
    void Function()? onGroupsRead,
  }) async {
    catalogue = _Catalogue();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogAdminRepositoryProvider.overrideWithValue(
            authors ? catalogue : null,
          ),
          if (stored != null)
            moneyConfigProvider.overrideWith((ref) async => stored),
          if (groups != null)
            taxGroupsAllProvider.overrideWith((ref) async {
              onGroupsRead?.call();
              return groups;
            }),
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

    testWidgets('is shown how it takes money, and told whose that is', (
      tester,
    ) async {
      // **This test used to assert the opposite** — that a cloud till could
      // add a payment method. The button was there and did nothing (the admin
      // repository is null on cloud), and a method made on the till would be
      // one the platform had never heard of. POS-BE-013 makes the platform the
      // author; the pane now says so and operates nothing.
      await pump(
        tester,
        authors: false,
        pane: const ManagementTendersPane(admin: admin),
      );
      expect(find.text('PAYMENT METHODS'), findsOneWidget);
      expect(find.byType(PlatformOwnedNotice), findsOneWidget);
      expect(find.textContaining('dashboard'), findsOneWidget);
      expect(
        find.byKey(const Key('tender-new')),
        findsNothing,
        reason: 'a button that cannot save is a lie',
      );
      final row = tester.widget<InkWell>(
        find
            .ancestor(of: find.text('Cash'), matching: find.byType(InkWell))
            .first,
      );
      expect(row.onTap, isNull, reason: 'listed, and not operable');
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
      expect(find.byKey(const Key('tender-new')), findsOneWidget);
      expect(
        find.byType(PlatformOwnedNotice),
        findsNothing,
        reason: 'offline, these are this terminal\'s',
      );
    });
  });

  testWidgets('saving a rate does not reset tax-inclusive mode', (
    tester,
  ) async {
    // **The bug this test exists for charged customers twice.**
    // `saveMoneyConfig` replaces the whole payload and the codec writes
    // `tax_mode` into it, so a `TaxConfig` built in the pane without that field
    // silently reset an inclusive business to exclusive — and every ticket
    // afterwards added 14% on top of prices that already contained it. Nothing
    // on any screen sets the mode, which is exactly why saving an unrelated rate
    // must not change it.
    await pump(
      tester,
      authors: true,
      pane: const ManagementTaxesPane(admin: admin),
      stored: const TaxConfig(
        serviceBp: 1200,
        vatBp: 1400,
        taxMode: TaxMode.inclusive,
      ),
    );

    await tester.enterText(find.byKey(const Key('rate-vat')), '15');
    await tester.tap(find.byKey(const Key('rates-save')));
    await tester.pumpAndSettle();

    expect(catalogue.saved?.vatBp, 1500, reason: 'the change was saved');
    expect(
      catalogue.saved?.taxMode,
      TaxMode.inclusive,
      reason: 'and the mode came through untouched',
    );
  });

  // ── XORD-027: the VAT box and the rate the till charges ────────────────────
  //
  // `TaxConfig.defaultTaxGroup` prefers the stored default group over `vatBp`,
  // and every offline setup seeds one at 14%. The box edited only `vatBp`, so a
  // business that typed 0 went on charging 14% — and the box, which read
  // `vatBp` back, showed the 0 it had been given.
  const standard = TaxGroup(id: 1, nameEn: 'VAT', rateBp: 1400, isDefault: true);
  const zeroGroup = TaxGroup(id: 1, nameEn: 'VAT', rateBp: 0, isDefault: true);

  String boxText(WidgetTester tester) => tester
      .widget<TextField>(find.byKey(const Key('rate-vat')))
      .controller!
      .text;

  testWidgets('the VAT box shows the rate the till charges, the default '
      "group's, not the stale one beside it", (tester) async {
    await pump(
      tester,
      authors: true,
      pane: const ManagementTaxesPane(admin: admin),
      stored: const TaxConfig(serviceBp: 1200, vatBp: 1400),
      groups: const [zeroGroup],
    );

    expect(
      boxText(tester),
      '0',
      reason: 'the group is at 0 and that is what a ticket is taxed at',
    );
  });

  testWidgets('with no default group the box shows the single rate, as before', (
    tester,
  ) async {
    await pump(
      tester,
      authors: true,
      pane: const ManagementTaxesPane(admin: admin),
      stored: const TaxConfig(serviceBp: 1200, vatBp: 1500),
      groups: const [],
    );

    expect(boxText(tester), '15');
  });

  testWidgets('typing 0 over a 14% group saves 0 and re-reads the groups', (
    tester,
  ) async {
    var reads = 0;
    await pump(
      tester,
      authors: true,
      pane: const ManagementTaxesPane(admin: admin),
      stored: const TaxConfig(serviceBp: 1200, vatBp: 1400),
      groups: const [standard],
      onGroupsRead: () => reads++,
    );
    expect(boxText(tester), '14');
    expect(reads, 1);

    await tester.enterText(find.byKey(const Key('rate-vat')), '0');
    await tester.tap(find.byKey(const Key('rates-save')));
    await tester.pumpAndSettle();

    expect(catalogue.saved?.vatBp, 0);
    expect(
      reads,
      greaterThan(1),
      reason: 'saving moves the default group, and the running till prices '
          'from the group — without a re-read it charges 14% until restart',
    );
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
  TaxConfig? saved;

  @override
  Future<AdminResult<TaxConfig>> saveMoneyConfig(
    TaxConfig config, {
    required PosStaff by,
  }) async {
    saved = config;
    return AdminResult.done(config);
  }

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
