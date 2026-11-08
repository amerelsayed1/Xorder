import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart' show PosDbFailure;
import 'package:xorder_pos/features/licensing/domain/license.dart';
import 'package:xorder_pos/features/setup/application/setup_controller.dart';
import 'package:xorder_pos/features/setup/domain/setup_state.dart';

import 'package:xorder_pos_test_support/fakes.dart';

/// The offline first-install step, now two screens in one step
/// (pos-setup-owner-step): which button does what, how Back behaves, and what
/// happens when the PIN was typed twice differently or the administrator
/// account cannot be reached.
void main() {
  late ProviderContainer container;
  late SetupController controller;

  final claims = LicenseClaims(
    licenseId: 'lic',
    tenantSlug: 'mahsoub',
    tenantName: 'Mahsoub Grill',
    issuedAt: DateTime.utc(2026, 1, 1),
    expiresAt: DateTime.utc(2027, 1, 1),
    modes: const {DeploymentMode.offline},
  );

  /// An offline till on the first-install step, page [page], with the owner
  /// fields given. The database port is closed, so a build can only fail — and
  /// fail the way a wrong address does, without needing any database.
  void arrive({
    OwnerPage page = OwnerPage.databaseAccess,
    String admin = '',
    String name = '',
    String username = '',
    String pin = '',
    String confirm = '',
    bool bootstrapped = false,
    DeploymentConfig? deployment,
  }) {
    container = ProviderContainer(overrides: fakeRepositoryOverrides());
    addTearDown(container.dispose);
    controller = container.read(setupProvider.notifier);
    controller.state = container
        .read(setupProvider)
        .copyWith(
          step: SetupStep.account,
          deployment:
              deployment ??
              const DeploymentConfig(
                mode: DeploymentMode.offline,
                databaseHost: '127.0.0.1',
                databasePort: 1,
              ),
          claims: claims,
          ownerPage: page,
          adminDatabasePassword: admin,
          ownerName: name,
          ownerUsername: username,
          ownerPin: pin,
          ownerPinConfirm: confirm,
          bootstrapped: bootstrapped,
        );
  }

  SetupDraft draft() => container.read(setupProvider);

  group('the footer\'s one button on the first install', () {
    test('page one: on to the owner, even with no password — a local '
        'PostgreSQL that trusts this machine has none', () {
      arrive();
      expect(draft().footerAction, FooterAction.toOwnerPage);
      expect(draft().adminDatabasePassword, isEmpty);
      expect(draft().footerEnabled, isTrue);

      controller.setAdminDatabasePassword('secret');
      expect(draft().footerEnabled, isTrue);
    });

    test('page two: create, once every field is filled in', () {
      arrive(page: OwnerPage.ownerAccount);
      expect(draft().footerAction, FooterAction.createDatabase);
      expect(draft().footerEnabled, isFalse);

      arrive(
        page: OwnerPage.ownerAccount,
        name: 'Rana',
        username: 'owner',
        pin: '1234',
        confirm: '1234',
      );
      expect(draft().footerEnabled, isTrue);

      // A missing confirmation is not "filled in".
      arrive(
        page: OwnerPage.ownerAccount,
        name: 'Rana',
        username: 'owner',
        pin: '1234',
      );
      expect(draft().footerEnabled, isFalse);
    });

    test('once the database exists it is the wizard\'s own Continue again', () {
      arrive(page: OwnerPage.ownerAccount, bootstrapped: true);
      expect(draft().footerAction, FooterAction.next);
      expect(draft().footerEnabled, draft().canAdvance);
      expect(draft().canAdvance, isTrue);
    });

    test('pressing it on page one moves on, in the same step', () {
      arrive();

      controller.footerPressed();

      expect(draft().ownerPage, OwnerPage.ownerAccount);
      expect(draft().step, SetupStep.account, reason: 'still the same step');
    });

    test('pressing it on page two with a field missing does nothing', () {
      arrive(page: OwnerPage.ownerAccount, name: 'Rana');

      controller.footerPressed();

      expect(draft().busy, isFalse);
      expect(draft().error, isNull);
      expect(draft().bootstrapped, isFalse);
    });

    test('a second press while the build runs starts nothing', () {
      arrive(
        page: OwnerPage.ownerAccount,
        admin: 'x',
        name: 'Rana',
        username: 'owner',
        pin: '1234',
        confirm: '1234',
      );
      controller.state = draft().copyWith(busy: true);

      controller.footerPressed();

      expect(draft().busy, isTrue, reason: 'unchanged: nothing was started');
      expect(draft().error, isNull);
    });

    test('other steps and other modes are exactly what they were', () {
      arrive();
      // A child tablet signs in to its main device; a cloud till pairs.
      controller.state = draft().copyWith(
        deployment: const DeploymentConfig(
          mode: DeploymentMode.offline,
          role: TerminalRole.child,
        ),
      );
      expect(draft().isFirstInstall, isFalse);
      expect(draft().footerAction, FooterAction.next);
      expect(draft().footerEnabled, draft().canAdvance);

      controller.state = draft().copyWith(
        deployment: const DeploymentConfig(
          mode: DeploymentMode.cloud,
          baseUrl: 'https://xorder.io',
          tenantSlug: 'mahsoub',
        ),
      );
      expect(draft().isFirstInstall, isFalse);
      expect(draft().footerAction, FooterAction.next);

      controller.state = draft().copyWith(step: draft().visibleSteps.last);
      expect(draft().footerAction, FooterAction.finish);
    });
  });

  group('arriving at the step', () {
    test('Continue from the connection step starts on the first page', () {
      arrive(page: OwnerPage.ownerAccount);
      controller.state = draft().copyWith(
        step: SetupStep.deployment,
        databasePassword: 'till-secret',
      );
      expect(draft().canAdvance, isTrue);

      controller.next();

      expect(draft().step, SetupStep.account);
      expect(draft().ownerPage, OwnerPage.databaseAccess);
    });
  });

  group('which failures send the person back to the first page', () {
    test('the administrator account and the road to it do; nothing else', () {
      const toFirstPage = {
        PosDbFailure.auth,
        PosDbFailure.missingRole,
        PosDbFailure.permissionDenied,
        PosDbFailure.dns,
        PosDbFailure.tcp,
        PosDbFailure.tls,
      };
      for (final failure in PosDbFailure.values) {
        expect(
          SetupController.isAdminAccessFailure(failure),
          toFirstPage.contains(failure),
          reason: '$failure',
        );
      }
    });
  });

  group('Back', () {
    test('from the owner\'s page is the first page, not the previous step', () {
      arrive(page: OwnerPage.ownerAccount, admin: 'secret', name: 'Rana');

      controller.back();

      expect(draft().step, SetupStep.account);
      expect(draft().ownerPage, OwnerPage.databaseAccess);
      expect(draft().adminDatabasePassword, 'secret', reason: 'kept');
      expect(draft().ownerName, 'Rana', reason: 'kept');
    });

    test('from the first page is the previous step, as before', () {
      arrive(admin: 'secret');

      controller.back();

      expect(draft().step, isNot(SetupStep.account));
    });
  });

  group('the PIN, twice', () {
    test('the confirmation is digits only and never longer than the PIN', () {
      arrive();
      controller.setOwnerPinConfirm('12a3 4567');
      expect(draft().ownerPinConfirm, '1234');
    });

    test('two different PINs build nothing, and say so', () async {
      arrive(
        page: OwnerPage.ownerAccount,
        admin: 'secret',
        name: 'Rana',
        username: 'owner',
        pin: '1234',
        confirm: '1235',
      );

      await controller.bootstrapDatabase();

      expect(draft().error, container.read(stringsProvider).pinsDoNotMatch);
      expect(draft().busy, isFalse);
      expect(draft().bootstrapped, isFalse);
      expect(draft().ownerPage, OwnerPage.ownerAccount, reason: 'stays put');
    });
  });

  group('when the administrator account cannot be reached', () {
    test('it is the first page again, with the error there and nothing '
        'typed lost', () async {
      arrive(
        page: OwnerPage.ownerAccount,
        admin: 'wrong',
        name: 'Rana',
        username: 'owner',
        pin: '1234',
        confirm: '1234',
      );

      await controller.bootstrapDatabase();

      expect(draft().ownerPage, OwnerPage.databaseAccess);
      expect(draft().error, isNotNull);
      expect(draft().busy, isFalse);
      expect(draft().bootstrapped, isFalse);
      expect(draft().adminDatabasePassword, 'wrong');
      expect(draft().ownerName, 'Rana');
      expect(draft().ownerUsername, 'owner');
      expect(draft().ownerPin, '1234');
      expect(draft().ownerPinConfirm, '1234');
    });
  });
}
