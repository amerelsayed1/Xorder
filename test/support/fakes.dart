import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/config/terminal_config.dart';
import 'package:xorder_pos/data/config/terminal_config_store.dart';
import 'package:xorder_pos/data/fakes/fake_repositories.dart';
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
List<Override> fakeRepositoryOverrides({bool english = true}) => [
      if (english) localeProvider.overrideWith(EnglishTerminal.new),
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
      // No database in a widget test, so no copies and nowhere to write one.
      // The real binding writes `pos_backups` on the till's credential.
      backupRepositoryProvider.overrideWithValue(FakeBackupRepository()),
      // The development issuer, which self-signs. The app binds
      // `DefaultLicenceService` against the real embedded key, so a widget
      // test that wanted a working licence would otherwise have to sign one.
      licenceServiceProvider.overrideWithValue(FakeLicenceService()),
      // Setup persistence, in memory. The real store writes to the operator's
      // Application Support directory, which a widget test must never touch —
      // and could not anyway, since `path_provider` has no implementation in
      // the test harness.
      terminalConfigStoreProvider.overrideWithValue(InMemoryTerminalConfigStore()),
      // Past the back-office credential gate. Management asks for the
      // administrator database password before it opens, and a widget test
      // driving the fake repositories has no database to ask about — so the
      // container starts on the far side of that question rather than every
      // test typing through it.
      adminDbCredentialProvider.overrideWith(_CredentialedAdminDb.new),
    ];

/// An [AdminDbCredential] that starts supplied.
class _CredentialedAdminDb extends AdminDbCredential {
  @override
  String? build() => 'test-credential';
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
