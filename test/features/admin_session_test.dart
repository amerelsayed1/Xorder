import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/app/providers.dart';
import 'package:xorder_pos/core/config/admin_mode_settings.dart';
import 'package:xorder_pos/core/l10n/app_strings.dart';
import 'package:xorder_pos/data/fakes/fake_repositories.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/repositories/admin_repositories.dart';
import 'package:xorder_pos/domain/repositories/repositories.dart';
import 'package:xorder_pos/features/admin/application/admin_session.dart';

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

  group('who gets in', () {
    test('the owner, by username and PIN', () async {
      expect(
        await admin.signIn(username: 'amer', pin: '4321'),
        isA<AdminSignedIn>(),
      );
      expect(container.read(adminSessionProvider)!.staff.name, 'Amer M.');
      expect(container.read(adminDbCredentialProvider), 'test-credential');
      expect(ledger().single.action, AuditAction.adminEntered);
    });

    test('not a cashier with their right PIN — and it is written down', () async {
      expect(
        await admin.signIn(username: 'rana', pin: '1234'),
        isA<AdminSignInRefused>(),
      );
      expect(container.read(adminSessionProvider), isNull);
      expect(container.read(adminDbCredentialProvider), isNull);
      expect(ledger().single.action, AuditAction.adminRefused);
      expect(ledger().single.actorName, 'Rana A.');
    });

    test('not a wrong PIN, which names nobody to write down', () async {
      expect(
        await admin.signIn(username: 'amer', pin: '1234'),
        isA<AdminSignInRefused>(),
      );
      expect(ledger(), isEmpty);
    });

    test('not a PIN without the name', () async {
      expect(
        await admin.signIn(username: '', pin: '4321'),
        isA<AdminSignInRefused>(),
      );
    });

    test('not when the ledger cannot record the entry', () async {
      (container.read(auditRepositoryProvider) as FakeAuditRepository)
          .failWith = StateError('ledger down');
      expect(
        await admin.signIn(username: 'amer', pin: '4321'),
        isA<AdminSignInUnreachable>(),
      );
      expect(container.read(adminSessionProvider), isNull);
      expect(container.read(adminDbCredentialProvider), isNull);
    });

    test('not when the branch database does not answer', () async {
      container = build([
        sessionRepositoryProvider.overrideWithValue(const _Unreachable()),
      ]);
      admin = container.read(adminSessionProvider.notifier);
      expect(
        await admin.signIn(username: 'amer', pin: '4321'),
        isA<AdminSignInUnreachable>(),
      );
    });
  });

  group('too many wrong PINs', () {
    Future<AdminSignIn> wrongPin([String username = 'amer']) =>
        admin.signIn(username: username, pin: '0000');

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
        await admin.signIn(username: 'amer', pin: '4321'),
        isA<AdminSignInLockedOut>(),
      );
      expect(container.read(adminSessionProvider), isNull);
      expect(container.read(adminDbCredentialProvider), isNull);
    });

    test('and opens again once the wait is over', () async {
      await wrongPins(5);
      now = now.add(const Duration(seconds: 30));
      expect(
        await admin.signIn(username: 'amer', pin: '4321'),
        isA<AdminSignedIn>(),
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
      expect(
        await admin.signIn(username: 'amer', pin: '4321'),
        isA<AdminSignedIn>(),
      );
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
        await admin.signIn(username: 'amer', pin: '4321'),
        isA<AdminNeedsDatabasePassword>(),
      );
      expect(container.read(adminSessionProvider), isNull);
    });

    test('a wrong one is refused and not kept', () async {
      kept.value = null;
      expect(
        await admin.signIn(
          username: 'amer',
          pin: '4321',
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
          pin: '4321',
          databasePassword: 'test-credential',
        ),
        isA<AdminSignedIn>(),
      );
      expect(kept.value, 'test-credential');
    });

    test('a kept one that stopped working is asked for again', () async {
      kept.value = 'changed-since';
      expect(
        await admin.signIn(username: 'amer', pin: '4321'),
        isA<AdminNeedsDatabasePassword>(),
      );
    });

    test('is never asked of somebody the PIN did not let in', () async {
      kept.value = null;
      expect(
        await admin.signIn(username: 'rana', pin: '1234'),
        isA<AdminSignInRefused>(),
      );
    });
  });

  group('the end of it', () {
    setUp(() async {
      await admin.signIn(username: 'amer', pin: '4321');
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
}
