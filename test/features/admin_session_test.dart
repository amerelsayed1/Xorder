import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postgres/postgres.dart' show ServerException;
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/config/admin_mode_settings.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/core/security/pin_hash.dart';
import 'package:xorder_pos/data/fakes/fake_repositories.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/repositories/admin_repositories.dart';
import 'package:xorder_pos/domain/repositories/repositories.dart';
import 'package:xorder_pos/features/admin/application/admin_session.dart';
import 'package:xorder_pos/features/admin/presentation/admin_messages.dart';

import '../support/fakes.dart';

/// The rules of Admin Mode, without a screen in front of them.
///
/// The widgets only ask; [AdminSessionController] decides. So the decisions
/// are pinned here, where a screen that forgot to ask could not hide one.
void main() {
  late ProviderContainer container;
  late AdminSessionController admin;
  late MemorySecretStore kept;
  late DateTime now;

  ProviderContainer build([List<Override> overrides = const []]) {
    kept = MemorySecretStore('test-credential');
    now = DateTime.utc(2026, 9, 12, 20);
    final built = ProviderContainer(
      overrides: [
        ...fakeRepositoryOverrides(),
        adminDbSecretStoreProvider.overrideWithValue(kept),
        adminClockProvider.overrideWithValue(() => now),
        ...overrides,
      ],
    );
    addTearDown(built.dispose);
    return built;
  }

  setUp(() {
    container = build();
    admin = container.read(adminSessionProvider.notifier);
  });

  List<AuditEntry> ledger() =>
      (container.read(auditRepositoryProvider) as FakeAuditRepository).entries;

  FakePasswords passwords() =>
      (container.read(staffDirectoryRepositoryProvider)
              as FakeStaffDirectoryRepository)
          .passwords;

  /// The owner's first entry, whole: the PIN, then the password it makes
  /// him choose. Every fake account starts with none, as every real one did
  /// the day migration 55 ran.
  Future<AdminSignIn> enterAsOwner() async {
    expect(
      await admin.signIn(username: 'amer', secret: '4321'),
      isA<AdminMustSetPassword>(),
    );
    return admin.setPassword(
      password: testAdminPassword,
      confirm: testAdminPassword,
    );
  }

  group('who gets in', () {
    test('the owner, by PIN the first time — and only once a password is '
        'chosen', () async {
      expect(
        await admin.signIn(username: 'amer', secret: '4321'),
        isA<AdminMustSetPassword>(),
      );
      expect(container.read(adminSessionProvider), isNull);
      expect(container.read(adminDbCredentialProvider), isNull);
      expect(ledger(), isEmpty, reason: 'nobody is in yet');

      expect(
        await admin.setPassword(
          password: testAdminPassword,
          confirm: testAdminPassword,
        ),
        isA<AdminSignedIn>(),
      );
      expect(container.read(adminSessionProvider)!.staff.name, 'Amer M.');
      expect(container.read(adminDbCredentialProvider), 'test-credential');
      expect(ledger().single.action, AuditAction.adminEntered);
      expect(passwords().passwordOf('amer'), testAdminPassword);
    });

    test('not a cashier with their right PIN — and it is written down', () async {
      expect(
        await admin.signIn(username: 'rana', secret: '1234'),
        isA<AdminSignInRefused>(),
      );
      expect(container.read(adminSessionProvider), isNull);
      expect(container.read(adminDbCredentialProvider), isNull);
      expect(ledger().single.action, AuditAction.adminRefused);
      expect(ledger().single.actorName, 'Rana A.');
    });

    test('not a wrong PIN, which names nobody to write down', () async {
      expect(
        await admin.signIn(username: 'amer', secret: '1234'),
        isA<AdminSignInRefused>(),
      );
      expect(ledger(), isEmpty);
    });

    test('not a PIN without the name', () async {
      expect(
        await admin.signIn(username: '', secret: '4321'),
        isA<AdminSignInRefused>(),
      );
    });

    test('not when the ledger cannot record the entry', () async {
      (container.read(auditRepositoryProvider) as FakeAuditRepository)
          .failWith = StateError('ledger down');
      expect(await enterAsOwner(), isA<AdminSignInUnreachable>());
      expect(container.read(adminSessionProvider), isNull);
      expect(container.read(adminDbCredentialProvider), isNull);
    });

    test('not when the branch database does not answer', () async {
      container = build([
        sessionRepositoryProvider.overrideWithValue(const _Unreachable()),
      ]);
      admin = container.read(adminSessionProvider.notifier);
      expect(
        await admin.signIn(username: 'amer', secret: '4321'),
        isA<AdminSignInUnreachable>(),
      );
    });
  });

  group('too many wrong PINs', () {
    Future<AdminSignIn> wrongPin([String username = 'amer']) =>
        admin.signIn(username: username, secret: '0000');

    Future<void> wrongPins(int times, [String username = 'amer']) async {
      for (var i = 0; i < times; i++) {
        await wrongPin(username);
      }
    }

    test('each refusal says how many tries are left', () async {
      expect(((await wrongPin()) as AdminSignInRefused).attemptsLeft, 4);
      expect(((await wrongPin()) as AdminSignInRefused).attemptsLeft, 3);
    });

    test('the fifth shuts the door, and a right PIN is not even checked', () async {
      await wrongPins(4);
      expect(
        ((await wrongPin()) as AdminSignInLockedOut).wait,
        const Duration(seconds: 30),
      );

      now = now.add(const Duration(seconds: 29));
      expect(
        await admin.signIn(username: 'amer', secret: '4321'),
        isA<AdminSignInLockedOut>(),
      );
      expect(container.read(adminSessionProvider), isNull);
      expect(container.read(adminDbCredentialProvider), isNull);
    });

    test('and opens again once the wait is over', () async {
      await wrongPins(5);
      now = now.add(const Duration(seconds: 30));
      // Checked, and right: what comes next is the password step, not the
      // lockout.
      expect(
        await admin.signIn(username: 'amer', secret: '4321'),
        isA<AdminMustSetPassword>(),
      );
    });

    test("the count is the terminal's, not the username's", () async {
      // Per username, walking the PINs would be trying every name in turn.
      await wrongPins(2);
      await wrongPins(2, 'nobody');
      expect(await wrongPin('rana'), isA<AdminSignInLockedOut>());
    });

    test('each lockout in a row waits twice as long, up to fifteen minutes', () async {
      final waits = <Duration>[];
      for (var i = 0; i < 7; i++) {
        await wrongPins(4);
        final shut = (await wrongPin()) as AdminSignInLockedOut;
        waits.add(shut.wait);
        now = now.add(shut.wait);
      }
      expect(waits, const [
        Duration(seconds: 30),
        Duration(minutes: 1),
        Duration(minutes: 2),
        Duration(minutes: 4),
        Duration(minutes: 8),
        Duration(minutes: 15),
        Duration(minutes: 15),
      ]);
    });

    test('a PIN that gets somebody in clears the count and the backoff', () async {
      await wrongPins(5);
      now = now.add(const Duration(seconds: 30));
      await wrongPins(3);
      expect(await enterAsOwner(), isA<AdminSignedIn>());
      await admin.end(AdminSessionEnd.exited);

      expect(
        ((await wrongPin()) as AdminSignInRefused).attemptsLeft,
        4,
        reason: 'the count starts again',
      );
      await wrongPins(3);
      expect(
        ((await wrongPin()) as AdminSignInLockedOut).wait,
        const Duration(seconds: 30),
        reason: 'and so does the backoff',
      );
    });

    test('the lockout is written down against the username being tried', () async {
      await wrongPins(5);
      final shut = ledger().where((e) => e.action == AuditAction.adminLockedOut);
      expect(shut.single.actorName, 'Amer M.');
    });

    test('and not at all when the username names nobody', () async {
      await wrongPins(5, 'nobody');
      expect(ledger(), isEmpty);
    });

    test('said in both languages, in Latin digits', () {
      for (final s in const <AppStrings>[EnStrings(), ArStrings()]) {
        for (final text in [
          s.adminSignInAttemptsLeft(1),
          s.adminSignInAttemptsLeft(4),
          s.adminSignInLockedOut(30),
          s.adminSignInLockedOut(900),
        ]) {
          expect(RegExp('[٠-٩]').hasMatch(text), isFalse, reason: text);
        }
      }
      expect(const EnStrings().adminSignInLockedOut(900), contains('15 minutes'));
      expect(const ArStrings().adminSignInLockedOut(900), contains('15 دقيقة'));
      expect(
        const ArStrings().adminSignInAttemptsLeft(4),
        startsWith(const ArStrings().adminSignInRefused),
      );
    });
  });

  group('the back-office database password', () {
    test('a till that never kept it asks, once, after the PIN', () async {
      kept.value = null;
      expect(
        await admin.signIn(username: 'amer', secret: '4321'),
        isA<AdminNeedsDatabasePassword>(),
      );
      expect(container.read(adminSessionProvider), isNull);
    });

    test('a wrong one is refused and not kept', () async {
      kept.value = null;
      expect(
        await admin.signIn(
          username: 'amer',
          secret: '4321',
          databasePassword: 'not-it',
        ),
        isA<AdminDatabasePasswordRefused>(),
      );
      expect(kept.value, isNull);
    });

    test('a right one gets in and is kept for next time', () async {
      kept.value = null;
      expect(
        await admin.signIn(
          username: 'amer',
          secret: '4321',
          databasePassword: 'test-credential',
        ),
        // Past the door's first half: an account with no password yet is
        // asked to choose one next, and the database password is kept by
        // then because it is what that write runs on.
        isA<AdminMustSetPassword>(),
      );
      expect(kept.value, 'test-credential');
    });

    test('a kept one that stopped working is asked for again', () async {
      kept.value = 'changed-since';
      expect(
        await admin.signIn(username: 'amer', secret: '4321'),
        isA<AdminNeedsDatabasePassword>(),
      );
    });

    test('is never asked of somebody the PIN did not let in', () async {
      kept.value = null;
      expect(
        await admin.signIn(username: 'rana', secret: '1234'),
        isA<AdminSignInRefused>(),
      );
    });
  });

  group('the end of it', () {
    setUp(() async {
      await enterAsOwner();
    });

    test('Exit forgets the credential and says so', () async {
      await admin.end(AdminSessionEnd.exited);
      expect(container.read(adminSessionProvider), isNull);
      expect(container.read(adminDbCredentialProvider), isNull);
      expect(ledger().first.action, AuditAction.adminExited);
      expect(ledger().first.after, {'how': 'exited'});
    });

    test('a timeout is its own row', () async {
      await admin.end(AdminSessionEnd.timedOut);
      expect(ledger().first.action, AuditAction.adminTimedOut);
    });

    test('it ends even when the ledger does not answer', () async {
      (container.read(auditRepositoryProvider) as FakeAuditRepository)
          .failWith = StateError('ledger down');
      await admin.end(AdminSessionEnd.left);
      expect(container.read(adminSessionProvider), isNull);
      expect(container.read(adminDbCredentialProvider), isNull);
    });

    test('ending twice writes one row', () async {
      await admin.end(AdminSessionEnd.exited);
      await admin.end(AdminSessionEnd.left);
      expect(
        ledger().where((e) => e.action == AuditAction.adminExited),
        hasLength(1),
      );
    });

    test('it is idle after the timeout, and not a moment before', () {
      now = now.add(const Duration(minutes: 4, seconds: 59));
      expect(admin.isIdle, isFalse);
      now = now.add(const Duration(seconds: 1));
      expect(admin.isIdle, isTrue);
    });

    test('a touch starts the count again', () {
      now = now.add(const Duration(minutes: 4));
      admin.touch();
      now = now.add(const Duration(minutes: 4));
      expect(admin.isIdle, isFalse);
    });

    test('the timeout is this till\'s setting', () async {
      await container
          .read(adminModeSettingsProvider.notifier)
          .save(const AdminModeSettings(timeoutMinutes: 1));
      now = now.add(const Duration(minutes: 1));
      expect(admin.isIdle, isTrue);
    });
  });

  group('the Admin Mode password', () {
    Future<AdminSignIn> choose(String password, [String? again]) =>
        admin.setPassword(password: password, confirm: again ?? password);

    test('once chosen it opens the door, and the PIN no longer does', () async {
      await enterAsOwner();
      await admin.end(AdminSessionEnd.exited);

      expect(
        await admin.signIn(username: 'amer', secret: '4321'),
        isA<AdminSignInRefused>().having((r) => r.attemptsLeft, 'left', 4),
      );
      expect(
        ledger().where((e) => e.action == AuditAction.adminRefused),
        isEmpty,
        reason: 'a PIN for a password account is a wrong guess, not a name',
      );
      expect(
        await admin.signIn(username: 'amer', secret: testAdminPassword),
        isA<AdminSignedIn>(),
      );
      expect(container.read(adminSessionProvider)!.staff.username, 'amer');
    });

    test('a wrong password and an unknown username are the same refusal',
        () async {
      await enterAsOwner();
      await admin.end(AdminSessionEnd.exited);
      final before = ledger().length;

      final wrong = await admin.signIn(
        username: 'amer',
        secret: 'not the password at all',
      );
      final unknown = await admin.signIn(
        username: 'nobody',
        secret: 'not the password at all',
      );
      expect(wrong, isA<AdminSignInRefused>());
      expect(unknown, isA<AdminSignInRefused>());
      expect(
        (wrong as AdminSignInRefused).attemptsLeft,
        (unknown as AdminSignInRefused).attemptsLeft + 1,
        reason: 'one count for both: the terminal\'s',
      );
      expect(ledger(), hasLength(before), reason: 'neither names anybody');
    });

    test('wrong passwords shut the door as wrong PINs do', () async {
      await enterAsOwner();
      await admin.end(AdminSessionEnd.exited);
      for (var i = 0; i < 4; i++) {
        await admin.signIn(username: 'amer', secret: 'wrong password $i');
      }
      expect(
        ((await admin.signIn(username: 'amer', secret: 'wrong password 5'))
                as AdminSignInLockedOut)
            .wait,
        const Duration(seconds: 30),
      );
      expect(
        await admin.signIn(username: 'amer', secret: testAdminPassword),
        isA<AdminSignInLockedOut>(),
        reason: 'shut means the right password is not checked either',
      );
    });

    test('the step cannot be reached without the PIN', () async {
      expect(await choose(testAdminPassword), isA<AdminPasswordStepExpired>());
      expect(passwords().passwordOf('amer'), isNull);
      expect(container.read(adminSessionProvider), isNull);
    });

    test('backing out spends the PIN step', () async {
      await admin.signIn(username: 'amer', secret: '4321');
      admin.cancelPasswordStep();
      expect(await choose(testAdminPassword), isA<AdminPasswordStepExpired>());
      expect(passwords().passwordOf('amer'), isNull);
    });

    test('and it lasts no longer than Admin Mode would', () async {
      await admin.signIn(username: 'amer', secret: '4321');
      now = now.add(const Duration(minutes: 5));
      expect(await choose(testAdminPassword), isA<AdminPasswordStepExpired>());
      expect(container.read(adminSessionProvider), isNull);
    });

    test('a weak one is refused, and the step stays open for a better one',
        () async {
      await admin.signIn(username: 'amer', secret: '4321');

      expect(
        await choose('4321'),
        isA<AdminPasswordRejected>().having(
          (r) => r.problem,
          'problem',
          PasswordProblem.sameAsPin,
        ),
      );
      expect(
        await choose('nine char'),
        isA<AdminPasswordRejected>().having(
          (r) => r.problem,
          'problem',
          PasswordProblem.tooShort,
        ),
      );
      expect(
        await choose(testAdminPassword, 'correct horse batteries'),
        isA<AdminPasswordMismatch>(),
      );
      expect(container.read(adminSessionProvider), isNull);
      expect(container.read(adminDbCredentialProvider), isNull);

      expect(await choose(testAdminPassword), isA<AdminSignedIn>());
    });

    test('its refusals are said in both languages, in Latin digits', () {
      const en = EnStrings();
      const ar = ArStrings();
      for (final problem in PasswordProblem.values) {
        final english = AdminText.passwordProblem(en, problem);
        final arabic = AdminText.passwordProblem(ar, problem);
        expect(arabic, isNot(english), reason: problem.name);
        expect(RegExp('[٠-٩]').hasMatch(arabic), isFalse, reason: arabic);
      }
      // The number is the rule's own, in both.
      expect(AdminText.passwordProblem(en, PasswordProblem.tooShort), contains('10'));
      expect(AdminText.passwordProblem(ar, PasswordProblem.tooShort), contains('10'));
      expect(
        AdminText.refusal(ar, const OwnerPasswordIsTheirs()),
        contains('المالك'),
      );
    });

    test('a supervisor the owner let in sets their own, as the owner does',
        () async {
      expect(
        await admin.signIn(username: 'nour', secret: '2468'),
        isA<AdminMustSetPassword>(),
      );
      expect(await choose('nour-password-1'), isA<AdminSignedIn>());
      expect(container.read(adminSessionProvider)!.staff.username, 'nour');
      expect(passwords().passwordOf('amer'), isNull, reason: 'only their own');
    });
  });

  group('the schema, at the first password', () {
    test('is brought up once, before the password is written', () async {
      final seen = <String?>[];
      var upgrades = 0;
      container = build([
        schemaUpgraderProvider.overrideWithValue(() async {
          upgrades++;
          seen.add(passwords().passwordOf('amer'));
          return const [55];
        }),
      ]);
      admin = container.read(adminSessionProvider.notifier);

      expect(await enterAsOwner(), isA<AdminSignedIn>());
      expect(upgrades, 1, reason: 'not again on the way in');
      expect(seen, [null], reason: 'the column the password goes in is 54');
    });

    test('an upgrade that failed, and a write that failed with it, still let '
        'the owner in this once', () async {
      container = build([
        schemaUpgraderProvider.overrideWithValue(
          () async => throw StateError('relation does not exist'),
        ),
        staffDirectoryRepositoryProvider.overrideWithValue(
          _WriteFails(roles: FakeRolesRepository()),
        ),
      ]);
      admin = container.read(adminSessionProvider.notifier);

      // Backup is behind this door; a broken upgrade must not lock it away.
      expect(await enterAsOwner(), isA<AdminSignedIn>());
      expect(container.read(schemaUpgradeFailureProvider), isNotNull);
    });

    for (final (name, error, refusal) in [
      (
        'a server that stopped answering',
        PosDbException(PosDbFailure.tcp, 'connection refused'),
        isA<AdminSignInUnreachable>(),
      ),
      (
        'a write the database refused',
        PosDbException(PosDbFailure.query, 'permission denied for pos_users'),
        isA<AdminDatabaseRefused>(),
      ),
      ('anything else', StateError('boom'), isA<AdminDatabaseRefused>()),
    ]) {
      test('but a failed upgrade is no key on its own: $name keeps them out',
          () async {
        // It used to be: once the upgrade had failed, ANY failure of the
        // write let them in on the PIN alone.
        container = build([
          schemaUpgraderProvider.overrideWithValue(
            () async => throw StateError('relation does not exist'),
          ),
          staffDirectoryRepositoryProvider.overrideWithValue(
            _WriteFails(roles: FakeRolesRepository(), error: error),
          ),
        ]);
        admin = container.read(adminSessionProvider.notifier);

        expect(await enterAsOwner(), refusal);
        expect(container.read(adminSessionProvider), isNull);
        expect(container.read(adminDbCredentialProvider), isNull);
        expect(
          ledger().where((e) => e.action == AuditAction.adminEntered),
          isEmpty,
          reason: 'no row naming anybody who did not get in',
        );
      });
    }

    test('a write that fails on an up-to-date schema keeps them out', () async {
      container = build([
        staffDirectoryRepositoryProvider.overrideWithValue(
          _WriteFails(roles: FakeRolesRepository()),
        ),
      ]);
      admin = container.read(adminSessionProvider.notifier);

      expect(await enterAsOwner(), isA<AdminDatabaseRefused>());
      expect(container.read(adminSessionProvider), isNull);
      expect(
        container.read(adminDbCredentialProvider),
        isNull,
        reason: 'held for the write, and given back when it did not happen',
      );
    });
  });

  group("the technician's reset", () {
    test("clears the owner's password with the database password, typed",
        () async {
      await enterAsOwner();
      await admin.end(AdminSessionEnd.exited);

      expect(
        await admin.technicianClearPassword(
          username: 'AMER ',
          databasePassword: 'test-credential',
        ),
        isA<TechnicianResetDone>().having((r) => r.name, 'name', 'Amer M.'),
      );
      expect(passwords().passwordOf('amer'), isNull);
      // Back to the PIN, once, and the password step after it.
      expect(
        await admin.signIn(username: 'amer', secret: '4321'),
        isA<AdminMustSetPassword>(),
      );
    });

    test('a wrong database password clears nothing, and counts', () async {
      await enterAsOwner();
      await admin.end(AdminSessionEnd.exited);

      for (var i = 0; i < 4; i++) {
        expect(
          await admin.technicianClearPassword(
            username: 'amer',
            databasePassword: 'guess $i',
          ),
          isA<TechnicianResetDatabasePasswordRefused>(),
        );
      }
      expect(
        await admin.technicianClearPassword(
          username: 'amer',
          databasePassword: 'guess 5',
        ),
        isA<TechnicianResetLockedOut>(),
      );
      expect(passwords().passwordOf('amer'), testAdminPassword);
      expect(
        await admin.signIn(username: 'amer', secret: testAdminPassword),
        isA<AdminSignInLockedOut>(),
        reason: 'the same door, the same five',
      );
    });

    test('says so when nobody by that name has one', () async {
      expect(
        await admin.technicianClearPassword(
          username: 'nobody',
          databasePassword: 'test-credential',
        ),
        isA<TechnicianResetNobody>(),
      );
    });
  });

  group('checkStaffPin', () {
    test('asks for the capability it is given', () async {
      final sessions = FakeSessionRepository();
      expect(
        await checkStaffPin(
          sessions,
          username: 'amer',
          pin: '4321',
          capability: PosCapability.terminalManage,
        ),
        isA<StaffVerified>(),
      );
      expect(
        await checkStaffPin(
          sessions,
          username: 'nour',
          pin: '2468',
          capability: PosCapability.terminalManage,
        ),
        isA<StaffRefused>().having(
          (r) => r.identified?.username,
          'identified',
          'nour',
        ),
      );
    });

    // A database from before Admin Mode: migration 46, which gives the owner
    // role `admin.enter`, runs at this door — after a sign-in. Found on a real
    // till on 14 Sep 2026: the owner's right PIN was refused, twice, for want
    // of a grant only their getting in could make.
    test('the owner gets in before migration 46 has given their role the key',
        () async {
      const owner = PosStaff(
        id: 1,
        name: 'Amer M.',
        username: 'amer',
        role: PosRole(
          id: 1,
          code: SystemRoles.ownerCode,
          nameEn: 'Owner',
          capabilities: {PosCapability.staffManage},
        ),
      );
      expect(owner.can(PosCapability.adminEnter), isFalse, reason: 'premise');
      expect(
        await checkStaffPin(
          const _Returns(owner),
          username: 'amer',
          pin: '1234',
          capability: PosCapability.adminEnter,
        ),
        isA<StaffVerified>(),
      );
      // Only that key: anything else is asked of the role as it stands.
      expect(
        await checkStaffPin(
          const _Returns(owner),
          username: 'amer',
          pin: '1234',
          capability: PosCapability.terminalManage,
        ),
        isA<StaffRefused>(),
      );
    });

    test('and nobody else does, whatever else they hold', () async {
      for (final code in [SystemRoles.managerCode, SystemRoles.supervisorCode]) {
        final staff = PosStaff(
          id: 2,
          name: 'Nour S.',
          username: 'nour',
          role: PosRole(
            id: 2,
            code: code,
            nameEn: code,
            capabilities: const {PosCapability.staffManage},
          ),
        );
        expect(
          await checkStaffPin(
            _Returns(staff),
            username: 'nour',
            pin: '2468',
            capability: PosCapability.adminEnter,
          ),
          isA<StaffRefused>(),
          reason: code,
        );
      }
      // Nor an owner whose account has been switched off.
      const retired = PosStaff(
        id: 1,
        name: 'Amer M.',
        username: 'amer',
        isActive: false,
        role: PosRole(
          id: 1,
          code: SystemRoles.ownerCode,
          nameEn: 'Owner',
          capabilities: {PosCapability.staffManage},
        ),
      );
      expect(
        await checkStaffPin(
          const _Returns(retired),
          username: 'amer',
          pin: '1234',
          capability: PosCapability.adminEnter,
        ),
        isA<StaffRefused>(),
      );
    });

    test('says unreachable rather than refused when nothing answers', () async {
      expect(
        await checkStaffPin(
          const _Unreachable(),
          username: 'amer',
          pin: '4321',
          capability: PosCapability.adminEnter,
        ),
        isA<StaffUnreachable>(),
      );
    });
  });

  test('settings that were never saved are the defaults, and read back', () {
    expect(AdminModeSettings.fromJson(const {}), AdminModeSettings.standard);
    const chosen = AdminModeSettings(
      shortcut: AdminShortcut.ctrlAltS,
      timeoutMinutes: 15,
    );
    expect(AdminModeSettings.fromJson(chosen.toJson()), chosen);
    expect(
      AdminModeSettings.fromJson(const {'timeout_minutes': 0}).timeoutMinutes,
      AdminModeSettings.defaultTimeoutMinutes,
      reason: 'no file, hand-edited or newer, is how Admin Mode stops locking',
    );
  });
}

/// A branch server nothing is listening for.
class _Unreachable implements SessionRepository {
  const _Unreachable();

  static final _refused = PosDbException(PosDbFailure.tcp, 'connection refused');

  @override
  Future<PosSession> current() => throw _refused;

  @override
  Future<bool> verifyPin(String pin) => throw _refused;

  @override
  Future<PosStaff?> signIn(String pin) => throw _refused;

  @override
  Future<PosStaff?> signInAs({required String username, required String pin}) =>
      throw _refused;

  @override
  Future<PosStaff?> signInWithPassword({
    required String username,
    required String password,
  }) => throw _refused;
}

/// A directory holding one person, found by any username and PIN — the
/// question under test is what their ROLE lets them do, not who they are.
class _Returns implements SessionRepository {
  const _Returns(this.staff);

  final PosStaff staff;

  @override
  Future<PosSession> current() => throw UnimplementedError();

  @override
  Future<bool> verifyPin(String pin) async => true;

  @override
  Future<PosStaff?> signIn(String pin) async => staff;

  @override
  Future<PosStaff?> signInAs({
    required String username,
    required String pin,
  }) async => staff;

  @override
  Future<PosStaff?> signInWithPassword({
    required String username,
    required String password,
  }) async => staff;
}

/// The fake directory, with a password write the database refuses — a
/// column that is not there, or a constraint that says no.
class _WriteFails extends FakeStaffDirectoryRepository {
  _WriteFails({required super.roles, Object? error})
    : _error =
          error ??
          PosDbException(PosDbFailure.query, const _UndefinedColumn());

  final Object _error;

  @override
  Future<AdminResult<void>> setOwnPassword({
    required PosStaff by,
    required String password,
  }) => throw _error;
}

/// PostgreSQL's 42703, as the driver raises it for a database migration 55
/// has not reached. Its constructor is private to the driver, so this
/// answers the one question asked of it — the SQLSTATE — and nothing else.
class _UndefinedColumn implements ServerException {
  const _UndefinedColumn();

  @override
  String? get code => '42703';

  @override
  String toString() =>
      'column "password_hash" of relation "pos_users" does not exist';

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
