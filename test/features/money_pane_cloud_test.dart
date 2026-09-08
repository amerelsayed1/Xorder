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
import 'package:xorder_pos/features/admin/presentation/management_money_pane.dart';

/// What the Money pane shows when the platform owns half of it.
///
/// **This pane used to disappear entirely on a cloud till**, because its first
/// occupant — the tax rates — is written by the bootstrap seeder. Wave D then
/// put payment methods and service charges in the same pane, and those are
/// local on both deployments; a cloud restaurant was left unable to say how it
/// takes money. The fix gates the half that is actually the platform's.
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

  Future<void> pump(WidgetTester tester, {required bool authors}) async {
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
          home: const Scaffold(body: ManagementMoneyPane(admin: admin)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a cloud till can still say how it takes money', (tester) async {
    await pump(tester, authors: false);

    expect(find.text('PAYMENT METHODS'), findsOneWidget);
    expect(find.text('SERVICE CHARGES'), findsOneWidget);
    expect(find.byKey(const Key('tender-new')), findsOneWidget);
    expect(find.byKey(const Key('charge-new')), findsOneWidget);
  });

  testWidgets('but not what tax it charges — that is the platform\'s',
      (tester) async {
    await pump(tester, authors: false);

    expect(find.text('Save rates'), findsNothing);
    expect(
      find.textContaining('platform'),
      findsOneWidget,
      reason: 'and it says so rather than showing an empty half',
    );
  });

  testWidgets('an offline till gets both halves', (tester) async {
    await pump(tester, authors: true);

    expect(find.text('Save rates'), findsOneWidget);
    expect(find.text('PAYMENT METHODS'), findsOneWidget);
    expect(find.text('SERVICE CHARGES'), findsOneWidget);
  });

  testWidgets('the seeded payment methods are listed on either', (
    tester,
  ) async {
    for (final authors in [true, false]) {
      await pump(tester, authors: authors);
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
