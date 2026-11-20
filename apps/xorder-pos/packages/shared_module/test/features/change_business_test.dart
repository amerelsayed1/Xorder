import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/app/password_sign_in.dart';
import 'package:shared_module/app/providers.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/data/cloud/device_token_vault.dart';
import 'package:shared_module/data/config/file_secret_store.dart';
import 'package:shared_module/data/config/setup_progress_store.dart';
import 'package:shared_module/data/config/terminal_config_store.dart';
import 'package:shared_module/features/licensing/data/file_license_store.dart';
import 'package:shared_module/features/licensing/data/licence_check_store.dart';
import 'package:shared_module/data/fakes/fake_repositories.dart';
import 'package:shared_module/data/sqlite/sqlite_database.dart';
import 'package:shared_module/domain/models/shift.dart';

import 'package:xorder_pos_test_support/fakes.dart';

/// tablet-cloud-onboarding, Stage 5 (Q4, BR-6; AC-8, AC-9): "Change business"
/// deletes this tablet's business, so the action itself — not a hidden button —
/// refuses, before touching anything.
class _Platform implements PlatformPasswordCheck {
  _Platform([this.verdict = PasswordVerdict.verified]);

  PasswordVerdict verdict;
  final asked = <(String, String)>[];

  @override
  Future<PasswordVerdict> verify({
    required String username,
    required String password,
  }) async {
    asked.add((username, password));
    return verdict;
  }
}

class _Orders extends FakeOrdersRepository {
  _Orders(this.pending);
  final int pending;

  @override
  Future<int> pendingSyncCount() async => pending;
}

class _Queue extends FakeSyncQueueRepository {
  _Queue(this.heldCount);
  final int heldCount;

  @override
  Future<int> heldSyncCount() async => heldCount;
}

const _owner = PosStaff(
  id: 1,
  name: 'Amer',
  username: 'amer',
  role: FakeSessionRepository.owner,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late int wiped;
  late DeviceTokenVault vault;
  late Directory files;

  Future<Directory> here() async => files;

  setUp(() async {
    // Real files in a temporary folder, through the stores the app uses, as
    // the hard reset's own tests do: the wipe must not reach the real ones.
    files = await Directory.systemTemp.createTemp('xorder_change_business');
    addTearDown(() => files.delete(recursive: true));
    wiped = 0;
    vault = DeviceTokenVault();
    await vault.accept('xdt_old_business');
  });

  ProviderContainer harness({
    PosStaff? staff = _owner,
    PlatformPasswordCheck? platform,
    int pending = 0,
    int held = 0,
    PosShift? shift,
  }) {
    final container = ProviderContainer(
      overrides: [
        ...fakeRepositoryOverrides(),
        if (platform != null)
          platformPasswordCheckProvider.overrideWithValue(platform),
        ordersRepositoryProvider.overrideWithValue(_Orders(pending)),
        syncQueueRepositoryProvider.overrideWithValue(_Queue(held)),
        shiftProvider.overrideWith((ref) async => shift),
        deviceTokenVaultProvider.overrideWithValue(vault),
        changeBusinessWipeProvider.overrideWithValue(() async => wiped++),
        terminalConfigStoreProvider.overrideWithValue(
          FileTerminalConfigStore(directory: here),
        ),
        setupProgressStoreProvider.overrideWithValue(
          FileSetupProgressStore(directory: here),
        ),
        licenseStoreProvider.overrideWithValue(
          FileLicenseStore(directory: here),
        ),
        licenceCheckStoreProvider.overrideWithValue(
          FileLicenceCheckStore(directory: here),
        ),
        adminDbSecretStoreProvider.overrideWithValue(
          FileSecretStore(
            key: FileSecretStore.adminPasswordKey,
            directory: here,
          ),
        ),
        secretsFileProvider.overrideWithValue(
          FileSecretStore(
            key: FileSecretStore.databasePasswordKey,
            directory: here,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    if (staff != null) {
      container.read(signedInStaffProvider.notifier).signIn(staff);
    }
    return container;
  }

  Future<ChangeBusinessResult> change(
    ProviderContainer container, [
    String password = 'pw',
  ]) =>
      container.read(terminalResetProvider).changeBusiness(password: password);

  void expectUntouched(ChangeBusinessResult result, ChangeBusinessRefusal why) {
    expect(result.changed, isFalse);
    expect(result.refusal, why);
    expect(wiped, 0, reason: 'a refusal deletes nothing');
    expect(vault.isSet, isTrue, reason: 'the old business keeps its token');
  }

  group('refusals leave the tablet exactly as it was', () {
    test('nobody signed in', () async {
      final platform = _Platform();
      final result = await change(harness(staff: null, platform: platform));

      expectUntouched(result, ChangeBusinessRefusal.notPermitted);
      expect(platform.asked, isEmpty);
    });

    test('a cashier, who lacks terminal.manage', () async {
      final platform = _Platform();
      final result = await change(
        harness(
          platform: platform,
          staff: const PosStaff(
            id: 2,
            name: 'Rana A.',
            username: 'rana',
            role: FakeSessionRepository.cashier,
          ),
        ),
      );

      expectUntouched(result, ChangeBusinessRefusal.notPermitted);
      expect(platform.asked, isEmpty);
    });

    test('an app with no platform to check the password against', () async {
      expectUntouched(
        await change(harness()),
        ChangeBusinessRefusal.notAvailable,
      );
    });

    test('an open shift, before the password is even asked', () async {
      final platform = _Platform();
      final result = await change(
        harness(
          platform: platform,
          shift: PosShift(
            id: 3,
            openedAt: DateTime(2026, 11, 19, 9),
            openingFloat: const Money(0),
            openedByName: 'Amer',
          ),
        ),
      );

      expectUntouched(result, ChangeBusinessRefusal.shiftOpen);
      expect(platform.asked, isEmpty);
    });

    test('sales not yet sent', () async {
      final platform = _Platform();
      expectUntouched(
        await change(harness(platform: platform, pending: 2)),
        ChangeBusinessRefusal.unsyncedSales,
      );
      expect(platform.asked, isEmpty);
    });

    test('records the platform has held for a person', () async {
      expectUntouched(
        await change(harness(platform: _Platform(), held: 1)),
        ChangeBusinessRefusal.unsyncedSales,
      );
    });

    test('a wrong password', () async {
      expectUntouched(
        await change(
          harness(platform: _Platform(PasswordVerdict.rejected)),
          'bad',
        ),
        ChangeBusinessRefusal.wrongPassword,
      );
    });

    test('a password that cannot be checked is never a pass', () async {
      expectUntouched(
        await change(harness(platform: _Platform(PasswordVerdict.unreachable))),
        ChangeBusinessRefusal.cannotCheckPassword,
      );
    });

    test('a throttled sign-in', () async {
      expectUntouched(
        await change(harness(platform: _Platform(PasswordVerdict.throttled))),
        ChangeBusinessRefusal.throttled,
      );
    });
  });

  group('when every guard is met', () {
    test('the signed-in person\'s own password is what is checked', () async {
      final platform = _Platform();
      await change(harness(platform: platform), 'my-password');

      expect(platform.asked, [('amer', 'my-password')]);
    });

    test(
      'it wipes: the data file hook, the token, the session, the setup',
      () async {
        final container = harness(platform: _Platform());

        final result = await change(container);

        expect(result.changed, isTrue);
        expect(wiped, 1);
        expect(vault.isSet, isFalse, reason: 'the old token must not survive');
        expect(container.read(signedInStaffProvider), isNull);
        expect(container.read(setupCompleteProvider), isFalse);
        expect(
          container.read(deploymentProvider).tenantSlug ?? '',
          isEmpty,
          reason: 'the next business is not seeded with the last one',
        );
      },
    );
  });

  group('the data file', () {
    test('is deleted with its journal files, and nothing else', () async {
      final directory = await Directory.systemTemp.createTemp('xorder_change');
      addTearDown(() => directory.delete(recursive: true));
      for (final name in [
        'till.db',
        'till.db-wal',
        'till.db-shm',
        'till.db-journal',
        'notes.txt',
      ]) {
        await File('${directory.path}/$name').writeAsString('x');
      }

      await SqliteDatabase(
        path: '${directory.path}/till.db',
        key: () async => null,
      ).deleteFile();

      final left = [
        for (final e in directory.listSync()) e.uri.pathSegments.last,
      ];
      expect(left, ['notes.txt']);
    });

    test('a file that is already gone is not an error', () async {
      final directory = await Directory.systemTemp.createTemp('xorder_change');
      addTearDown(() => directory.delete(recursive: true));

      await SqliteDatabase(
        path: '${directory.path}/missing.db',
        key: () async => null,
      ).deleteFile();
    });
  });
}
