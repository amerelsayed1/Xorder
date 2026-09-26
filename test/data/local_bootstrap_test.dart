import 'package:flutter_test/flutter_test.dart';
import 'package:postgres/postgres.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/data/postgres/local_bootstrap.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';

/// The wizard's "this machine has no database yet" path, end to end, against a
/// real PostgreSQL. Opt-in: it creates and drops a database of its own.
void main() {
  const admin = DeploymentConfig(
    mode: DeploymentMode.offline,
    databaseHost: '127.0.0.1',
    databaseName: 'wizard_bootstrap_test',
    databaseUser: 'amerelsayed',
  );

  /// Self-cleaning, so the test is repeatable rather than passing once.
  Future<void> drop() async {
    final connection = await Connection.open(
      Endpoint(
        host: admin.databaseHost,
        port: admin.databasePort,
        database: 'postgres',
        username: admin.databaseUser,
      ),
      settings: const ConnectionSettings(sslMode: SslMode.disable),
    );
    try {
      await connection.execute('DROP DATABASE IF EXISTS "${admin.databaseName}"');
    } finally {
      await connection.close();
    }
  }

  setUp(drop);
  tearDown(drop);

  test('builds a sellable database from nothing', () async {
    final credentials = MutablePosDbCredentials()..set('unused-trust-auth');
    final database = PosDatabase(credentials: credentials);
    final bootstrap = LocalBootstrap(database);
    addTearDown(database.close);

    expect(
      await LocalBootstrap.createDatabase(admin, 'unused', admin.databaseName),
      isTrue,
      reason: 'the database did not exist yet',
    );

    final applied = await bootstrap.migrate(admin);
    expect(applied, isNotEmpty);

    final restaurantId =
        await bootstrap.seedRestaurant(admin, slug: 'probe', name: 'Probe');
    final branchId = await bootstrap.seedBranch(admin,
        restaurantId: restaurantId, name: 'Main', code: 'MAIN');
    final roles = await bootstrap.seedSystemRoles(admin, restaurantId);
    expect(roles.created, 4);

    expect(
      await bootstrap.seedOwner(admin,
          restaurantId: restaurantId,
          branchId: branchId,
          roleId: roles.ids['owner']!,
          name: 'Amer',
          username: 'owner',
          pin: '4321'),
      isA<OwnerCreated>(),
    );

    // Re-running is safe: every step is an upsert, and the PIN is NOT reset.
    // Compared field by field — a record holding a Map is not value-equal.
    final again = await bootstrap.seedSystemRoles(admin, restaurantId);
    expect(again.created, 0, reason: 'a re-run creates nothing');
    expect(again.ids, roles.ids, reason: 'and returns the same ids');
    expect(
      await bootstrap.seedOwner(admin,
          restaurantId: restaurantId,
          branchId: branchId,
          roleId: roles.ids['owner']!,
          name: 'Someone Else',
          username: 'owner',
          pin: '9999'),
      isA<OwnerAlreadyHere>(),
      reason: 'a re-run must never silently reset a PIN',
    );

    final staff = await database.query(admin,
        'SELECT name FROM pos_staff WHERE restaurant_id = @r',
        parameters: {'r': restaurantId});
    expect(staff.first[0], 'Amer', reason: 'the first name survived the re-run');
  }, timeout: const Timeout(Duration(minutes: 2)));

  /// The machine the wizard's own help text invites: a PostgreSQL somebody
  /// installed by hand, where none of the three install roles exist and the
  /// operator is told to type `postgres` in the administrator field.
  group('a PostgreSQL nobody\'s installer ever ran on', () {
    const till = 'wizard_bootstrap_test_till';

    Future<void> dropRole() async {
      final connection = await Connection.open(
        Endpoint(
          host: admin.databaseHost,
          port: admin.databasePort,
          database: 'postgres',
          username: admin.databaseUser,
        ),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );
      try {
        await connection.execute('DROP ROLE IF EXISTS "$till"');
      } finally {
        await connection.close();
      }
    }

    setUp(dropRole);
    tearDown(dropRole);

    test('an administrator role that is not there is a SENTENCE, not a driver',
        () async {
      // Verbatim what a Mac did on 26 Sep 2026: the wizard's first build step
      // opens its own connection, outside `PosDatabase`, so nothing used to
      // translate the driver's answer and `Severity.fatal 28000: role
      // "pos_admin" does not exist` went straight into the error bar of a
      // wizard being read in Arabic.
      try {
        await LocalBootstrap.createDatabase(
          admin.copyWith(databaseUser: 'pos_admin_that_is_not_here'),
          'whatever',
          admin.databaseName,
        );
        fail('a role that does not exist cannot create a database');
      } on PosDbException catch (error) {
        expect(error.failure, PosDbFailure.missingRole);
        expect(
          PosDbException.roleNamedIn(error.raw),
          'pos_admin_that_is_not_here',
          reason: 'the sentence names the role the driver named',
        );
      }
    }, timeout: const Timeout(Duration(minutes: 1)));

    test('the till gets the account it signs in with, once', () async {
      expect(
        await LocalBootstrap.ensureTillRole(
          admin,
          'unused-trust-auth',
          name: till,
          password: 'first-password',
        ),
        isTrue,
        reason: 'nobody had made it',
      );

      // Created, never changed — the rule `createRoles` states. A re-run that
      // reset the password would stop a till that is already selling with it.
      expect(
        await LocalBootstrap.ensureTillRole(
          admin,
          'unused-trust-auth',
          name: till,
          password: 'a-different-password',
        ),
        isFalse,
      );

      final credentials = MutablePosDbCredentials()..set('unused-trust-auth');
      final database = PosDatabase(credentials: credentials);
      addTearDown(database.close);
      final row = await database.query(
        admin.copyWith(databaseName: 'postgres'),
        'SELECT rolcanlogin FROM pg_roles WHERE rolname = @n',
        parameters: {'n': till},
      );
      expect(row.single[0], isTrue, reason: 'a till has to be able to log in');
    }, timeout: const Timeout(Duration(minutes: 1)));
  });
}
