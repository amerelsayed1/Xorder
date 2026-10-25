@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/ui/theme.dart';
import 'package:xorder_pos/data/postgres/local_bootstrap.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/features/licensing/domain/license.dart';
import 'package:xorder_pos/features/setup/application/setup_controller.dart';
import 'package:xorder_pos/features/setup/domain/setup_state.dart';
import 'package:xorder_pos/features/setup/presentation/setup_wizard.dart';

import '../support/fakes.dart';
import 'pg_fixture.dart';

/// The two installers, pointed at a restaurant that already has an owner.
///
/// `seedOwner` (the wizard) and `pos_migrate --seed` both write the owner
/// straight into `pos_staff`, past `PostgresStaffDirectoryRepository`. Given a
/// different username they used to make a second owner in silence; migration
/// 42 made the database refuse, and neither caller expected it — the CLI died
/// on a driver error and the wizard showed one in its error bar. What each says
/// instead is pinned here: who the owner is, and the two ways forward.
///
/// The rule itself, gone round in raw SQL, is `one_owner_test.dart`'s. This
/// file is about the callers.
void main() {
  if (PgFixture.host == null) {
    test('installer owner (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  const slug = 'installer-owner';
  const restaurant = 'Installer Owner';
  final databaseName = PgFixture.nameFor('installer_owner');

  late PgFixture pg;
  late PosDatabase db;
  late LocalBootstrap bootstrap;
  late int restaurantId;
  late int branchId;
  late int ownerRoleId;

  setUp(() async {
    pg = await PgFixture.open('installer_owner');
    db = pg.database;
    bootstrap = LocalBootstrap(db);
    await bootstrap.migrate(pg.config);
    await db.query(pg.config, 'DELETE FROM pos_restaurants');

    // The first install, already done: a restaurant whose owner is Amer.
    restaurantId = await bootstrap.seedRestaurant(
      pg.config,
      slug: slug,
      name: restaurant,
    );
    branchId = await bootstrap.seedBranch(
      pg.config,
      restaurantId: restaurantId,
      name: 'Main',
      code: 'MAIN',
    );
    ownerRoleId = (await bootstrap.seedSystemRoles(
      pg.config,
      restaurantId,
    )).ids[SystemRoles.ownerCode]!;
    await bootstrap.seedOwner(
      pg.config,
      restaurantId: restaurantId,
      branchId: branchId,
      roleId: ownerRoleId,
      name: 'Amer',
      username: 'amer',
      pin: '4321',
    );
  });

  tearDown(() => pg.close());

  /// Who is on the owner role, and whether they are active, as stored.
  Future<Map<String, bool>> owners() async {
    final rows = await db.query(
      pg.config,
      'SELECT s.name, s.is_active FROM pos_staff s '
      'JOIN pos_roles r ON r.id = s.role_id '
      "WHERE s.restaurant_id = @r AND r.code = 'owner' ORDER BY s.id",
      parameters: {'r': restaurantId},
    );
    return {for (final row in rows) row[0]! as String: row[1]! as bool};
  }

  group('seedOwner', () {
    Future<OwnerSeed> seed(String name, String username, {int? restaurant}) =>
        bootstrap.seedOwner(
          pg.config,
          restaurantId: restaurant ?? restaurantId,
          branchId: branchId,
          roleId: ownerRoleId,
          name: name,
          username: username,
          pin: '9999',
        );

    test('a second owner under another username is refused, as data', () async {
      // A value, not the trigger's exception: both callers have to put it into
      // words, and one of them has to do so in Arabic.
      expect(
        await seed('Nour', 'nour'),
        isA<AnotherOwnerActive>()
            .having((r) => r.name, 'name', 'Amer')
            .having((r) => r.username, 'username', 'amer'),
      );
      expect(await owners(), {'Amer': true});
    });

    test('the owner again, by username, changes nothing — PIN included', () async {
      Future<Object?> pinHash() async => (await db.query(
        pg.config,
        "SELECT pin_hash FROM pos_staff WHERE username = 'amer'",
      )).first[0];

      final before = await pinHash();
      expect(await seed('Someone Else', 'amer'), isA<OwnerAlreadyHere>());
      expect(await pinHash(), before);
      expect(await owners(), {'Amer': true});
    });

    test('a disabled owner is not counted, so the handover it offers works',
        () async {
      await db.query(
        pg.config,
        "UPDATE pos_staff SET is_active = false WHERE username = 'amer'",
      );
      expect(await seed('Nour', 'nour'), isA<OwnerCreated>());
      expect(await owners(), {'Amer': false, 'Nour': true});
    });

    test("another restaurant's owner is not this one's", () async {
      final other = await bootstrap.seedRestaurant(
        pg.config,
        slug: 'installer-owner-2',
        name: 'Elsewhere',
      );
      final otherRole = (await bootstrap.seedSystemRoles(
        pg.config,
        other,
      )).ids[SystemRoles.ownerCode]!;

      expect(
        await bootstrap.seedOwner(
          pg.config,
          restaurantId: other,
          branchId: branchId,
          roleId: otherRole,
          name: 'Nour',
          username: 'nour',
          pin: '9999',
        ),
        isA<OwnerCreated>(),
      );
    });
  });

  group('pos_migrate --seed', () {
    Future<ProcessResult> seed({
      required String name,
      required String username,
    }) => Process.run(
      'dart',
      [
        'run', 'bin/pos_migrate.dart', //
        '--host', PgFixture.host!, '--port', '${PgFixture.port}', //
        '--database', databaseName, '--no-verify-tls', //
        '--user', PgFixture.user, //
        '--seed', '--restaurant', restaurant, '--slug', slug, '--pin', '9999',
        '--staff', name, '--staff-username', username,
      ],
      environment: {'POS_PG_PASSWORD': PgFixture.password},
    );

    Future<int> terminals() async => (await db.query(
      pg.config,
      'SELECT count(*) FROM pos_terminals WHERE restaurant_id = @r',
      parameters: {'r': restaurantId},
    )).first[0]! as int;

    test('refuses a second owner, says who and what to do, exits non-zero',
        () async {
      final result = await seed(name: 'Nour', username: 'nour');
      final said = 'exit ${result.exitCode}\n${result.stdout}${result.stderr}';

      // Not 1, which is what every connection failure exits with: a script
      // that wraps this should be able to tell "the database is down" from
      // "a person has a decision to make".
      expect(result.exitCode, 65, reason: said);
      expect(
        '${result.stderr}',
        allOf(
          contains('Amer'),
          // Sign in as them: the flag to re-run with, spelled out.
          contains('--staff-username amer'),
          // Or hand over.
          contains('disable Amer'),
          isNot(contains('Could not migrate')),
        ),
        reason: said,
      );
      expect(await owners(), {'Amer': true});
      expect(
        await terminals(),
        0,
        reason: 'a refused seed must not hand out a setup code',
      );
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('and re-running the way it says to, as the owner, works', () async {
      final result = await seed(name: 'Amer', username: 'amer');
      final said = 'exit ${result.exitCode}\n${result.stdout}${result.stderr}';

      expect(result.exitCode, 0, reason: said);
      expect('${result.stdout}', contains('PIN left unchanged'), reason: said);
      expect(await owners(), {'Amer': true});
      expect(await terminals(), 1, reason: 'and the till gets its setup code');
    }, timeout: const Timeout(Duration(minutes: 3)));
  });

  group('the setup wizard', () {
    Future<ProviderContainer> wizard(WidgetTester tester, String language) async {
      tester.view
        ..physicalSize = const Size(1440, 900)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = ProviderContainer(overrides: fakeRepositoryOverrides());
      addTearDown(container.dispose);
      container.read(localeProvider.notifier).apply(language);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildPosTheme(),
            home: SetupWizard(onFinished: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // A second machine, being set up for the same restaurant by somebody
      // who typed their own name into "the first person".
      final controller = container.read(setupProvider.notifier);
      controller.state = container.read(setupProvider).copyWith(
        step: SetupStep.deployment,
        claims: LicenseClaims(
          licenseId: 'lic',
          tenantSlug: slug,
          tenantName: restaurant,
          issuedAt: DateTime.utc(2026, 1, 1),
          expiresAt: DateTime.utc(2027, 1, 1),
        ),
        deployment: DeploymentConfig(
          mode: DeploymentMode.offline,
          databaseHost: PgFixture.host!,
          databasePort: PgFixture.port,
          databaseName: databaseName,
          databaseUser: PgFixture.user,
          adminDatabaseUser: PgFixture.user,
          allowInsecureLan: true,
        ),
        adminDatabasePassword: PgFixture.password,
        ownerName: 'Nour',
        ownerUsername: 'nour',
        ownerPin: '4821',
      );
      await tester.pumpAndSettle();
      return container;
    }

    for (final language in ['en', 'ar']) {
      testWidgets('says who the owner is and what to do ($language)', (
        tester,
      ) async {
        final container = await wizard(tester, language);

        // Real sockets, so outside the fake clock.
        await tester.runAsync(
          () => container.read(setupProvider.notifier).bootstrapDatabase(),
        );
        await tester.pumpAndSettle();

        expect(
          find.text(
            AppStrings.of(Locale(language)).ownerAlreadyExists('Amer', 'amer'),
          ),
          findsOneWidget,
        );
        final after = container.read(setupProvider);
        expect(after.busy, isFalse);
        expect(after.bootstrapped, isFalse, reason: 'the step did not finish');
        expect(await tester.runAsync(owners), {'Amer': true});
      });
    }
  });
}
