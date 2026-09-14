import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/config/terminal_config.dart';
import 'package:xorder_pos/data/config/pos_db_secret_store.dart';
import 'package:xorder_pos/data/config/terminal_config_store.dart';
import 'package:xorder_pos/data/fakes/fake_repositories.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/domain/repositories/admin_repositories.dart';
import 'package:xorder_pos/features/licensing/data/licence_service.dart';

/// The `Fake…` repositories, bound explicitly.
///
/// These stopped being the app's default bindings when the till moved onto the
/// branch database. They had to: nothing distinguished a release build, so
/// every installation — including a real restaurant's — opened showing a
/// fictional menu, a fictional floor plan and a cashier who does not work
/// there, while the money path wrote real rows to a real database.
///
/// They remain exactly what a widget test wants: fast, deterministic, and
/// needing no server. So a test asks for them by name, which also means the
/// test says out loud that its data is invented — the thing the old default
/// binding never did.
///
/// A test that wants a real database wants `test/data/pg_fixture.dart` instead.
/// English, so the suite reads the copy it was written against.
///
/// The PRODUCT's default is Arabic — the restaurants it ships to are in Egypt —
/// and `test/core/localisation_test.dart` is what pins that. Everything else
/// asserts English strings, and a suite that had to be rewritten in Arabic to
/// change a default would make the default unchangeable. A test that is about
/// Arabic asks for it: `container.read(localeProvider.notifier).apply('ar')`.
class EnglishTerminal extends TerminalLocaleController {
  @override
  Locale build() => const Locale('en');
}

/// [english] false leaves the language alone, for the handful of tests that are
/// ABOUT it — a terminal opening in the language it was set up in, or a wizard
/// keeping it across a reset. Everything else takes English.
///
/// [schemaUpgrader] stands in for the migrations the back-office door applies.
/// Absent by default: there is no database in a widget test, and the real
/// upgrader would wait on a connection that never comes, so the door would
/// never open.
List<Override> fakeRepositoryOverrides({
  bool english = true,
  Future<List<int>> Function()? schemaUpgrader,
}) => [
      if (english) localeProvider.overrideWith(EnglishTerminal.new),
      schemaUpgraderProvider.overrideWithValue(schemaUpgrader),
      catalogRepositoryProvider.overrideWithValue(FakeCatalogRepository()),
      tablesRepositoryProvider.overrideWithValue(FakeTablesRepository()),
      sessionRepositoryProvider.overrideWithValue(FakeSessionRepository()),
      branchRepositoryProvider.overrideWithValue(FakeBranchRepository()),
      provisioningRepositoryProvider.overrideWithValue(FakeProvisioningRepository()),
      ordersRepositoryProvider.overrideWithValue(FakeOrdersRepository()),
      shiftRepositoryProvider.overrideWithValue(FakeShiftRepository()),
      hardwarePortsProvider.overrideWithValue(FakeHardwarePorts()),
      ...(() {
        // Roles and staff share one store, because a fake staff directory that
        // pointed at different role objects than the roles pane shows would let
        // a test pass while the screen it models could not work.
        final roles = FakeRolesRepository();
        return [
          rolesRepositoryProvider.overrideWithValue(roles),
          staffDirectoryRepositoryProvider
              .overrideWithValue(FakeStaffDirectoryRepository(roles: roles)),
          auditRepositoryProvider.overrideWithValue(FakeAuditRepository()),
        ];
      })(),
      // The branch server answering, as a test double. The back office's
      // status bar watches the same probe the till's top bar does, and the
      // real one opens a connection pool to `localhost` — a socket a widget
      // test on a fake clock can neither finish nor cancel.
      branchDatabaseProvider.overrideWith((ref) async => null),
      // No database in a widget test, so no copies and nowhere to write one.
      // The real binding writes `pos_backups` on the till's credential.
      backupRepositoryProvider.overrideWithValue(FakeBackupRepository()),
      unitsRepositoryProvider.overrideWithValue(FakeUnitsRepository()),
      stockItemsRepositoryProvider.overrideWithValue(FakeStockItemsRepository()),
      stockLevelsRepositoryProvider.overrideWithValue(FakeStockLevelsRepository()),
      // The development issuer, which self-signs. The app binds
      // `DefaultLicenceService` against the real embedded key, so a widget
      // test that wanted a working licence would otherwise have to sign one.
      licenceServiceProvider.overrideWithValue(FakeLicenceService()),
      // Setup persistence, in memory. The real store writes to the operator's
      // Application Support directory, which a widget test must never touch —
      // and could not anyway, since `path_provider` has no implementation in
      // the test harness.
      terminalConfigStoreProvider.overrideWithValue(InMemoryTerminalConfigStore()),
      // Admin Mode's database password, kept as the setup wizard keeps it, and
      // a database that accepts it. A widget test has no PostgreSQL to ask; a
      // test about the first-time question empties the store itself. Nobody is
      // IN Admin Mode at the start — that takes a username and PIN, which is
      // the point of it.
      adminDbSecretStoreProvider.overrideWithValue(
        MemorySecretStore('test-credential'),
      ),
      adminPasswordProbeProvider.overrideWithValue(
        (password) async =>
            password == 'test-credential' ? null : PosDbFailure.auth,
      ),
    ];

/// An offline terminal: one that authors its own catalogue, and so its own
/// buying and stock.
///
/// **Asked for by name, because the harness above is a cloud till.** It binds
/// no [CatalogAdminRepository], which is exactly how a cloud terminal answers
/// `catalogAdminRepositoryProvider` — and since CB-09 that hides Purchasing,
/// Items, Stock and Units along with Menu and Floor. A test about those panes
/// is a test about an offline till, and says so with this.
///
/// A bare mock: nothing that merely asks "does this till author?" calls it,
/// and a test that does write through it binds a recording double instead.
Override offlineTerminal() =>
    catalogAdminRepositoryProvider.overrideWithValue(_OfflineCatalogueAdmin());

class _OfflineCatalogueAdmin extends Mock implements CatalogAdminRepository {}

/// Through Admin Mode's door as the owner, for a test about what is behind it.
///
/// Typed, not injected: the door is the one way in, and a harness that could
/// put somebody past it would be a way round it that nothing tests. Amer's PIN
/// in [FakeSessionRepository] is 4321.
Future<void> enterAdminMode(
  WidgetTester tester, {
  String username = 'amer',
  String pin = '4321',
}) async {
  await tester.enterText(
    find.descendant(
      of: find.byKey(const Key('admin-username')),
      matching: find.byType(TextField),
    ),
    username,
  );
  await tester.enterText(find.byKey(const Key('admin-pin')), pin);
  await tester.tap(find.byKey(const Key('admin-open')));
  await tester.pumpAndSettle();
}

/// A secret store in memory: what `secrets.json` holds, without the file.
class MemorySecretStore implements PosDbSecretStore {
  MemorySecretStore([this.value]);

  String? value;

  @override
  Object? get lastFailure => null;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;

  @override
  Future<void> clear() async => value = null;
}

/// The saved terminal configuration, held in memory for the length of a test.
///
/// A test double, never a binding: the app writes a real file, and the one time
/// it did not — when nothing wrote one at all — the wizard ran on every launch.
class InMemoryTerminalConfigStore implements TerminalConfigStore {
  SavedTerminalConfig? saved;

  int writes = 0;

  @override
  Future<SavedTerminalConfig?> read() async => saved;

  @override
  Future<void> write(SavedTerminalConfig config) async {
    saved = config;
    writes++;
  }

  @override
  Future<void> clear() async => saved = null;
}
