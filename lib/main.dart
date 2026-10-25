import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'core/config/terminal_config.dart';
import 'data/cloud/device_token_vault.dart';
import 'data/config/file_secret_store.dart';
import 'data/config/installed_role.dart';
import 'data/config/legacy_secret_migration.dart';
import 'data/config/secret_store.dart';
import 'data/config/terminal_config_store.dart';
import 'data/postgres/pos_database.dart';

const _minimumWindow = Size(1024, 700);
const _initialWindow = Size(1440, 900);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (_isDesktop) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: _initialWindow,
        minimumSize: _minimumWindow,
        title: 'XOrder POS',
        titleBarStyle: TitleBarStyle.normal,
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }

  final configStore = FileTerminalConfigStore();
  final saved = await configStore.read();

  // DPAPI on Windows, the Keychain on macOS (ADR-006); plaintext only on a
  // development machine. One instance for the whole process.
  final secrets = SecretStore.forPlatform();

  // An older build's `secrets.json`, moved into that store once and wiped.
  // Before the first read, so the reads below find the migrated values. It
  // never throws: a failure leaves the file exactly as it was, and the next
  // launch tries again.
  final migration = await LegacySecretMigration(target: secrets).run();
  _reportMigration(migration);

  final credentials = MutablePosDbCredentials(
    store: KeyedSecretStore(secrets, FileSecretStore.databasePasswordKey),
  );
  await credentials.restore();

  // The cloud device token (POS-BE-011 Option C) lives in the same store
  // under its own key, and is restored the same way: once, before the first
  // frame, so the sync loop finds it synchronously.
  final deviceTokens = DeviceTokenVault(
    store: KeyedSecretStore(secrets, FileSecretStore.deviceTokenKey),
  );
  await deviceTokens.restore();

  // What the Windows installer said this machine is. Read here, before the
  // first frame, because the wizard decides which screen it opens on from it
  // synchronously; a file read from inside `build()` would paint the wrong
  // wizard for a frame and then swap it.
  final installedRole = await const FileInstalledRole().read();

  runApp(
    ProviderScope(
      overrides: [
        installedRoleProvider.overrideWithValue(installedRole),
        terminalBootProvider.overrideWithValue(
          TerminalBoot(
            config: saved,
            hasDatabaseCredential: credentials.isSet,
            // Asked after `restore()`, because that read is what makes a broken
            // keystore visible at all. A migration the store refused counts
            // too: the passwords it could not take are not where the till
            // will look for them.
            credentialStoreUnavailable:
                credentials.storeUnavailable || migration.storeRefused,
          ),
        ),
        terminalConfigStoreProvider.overrideWithValue(configStore),
        posDbCredentialsStoreProvider.overrideWithValue(credentials),
        deviceTokenVaultProvider.overrideWithValue(deviceTokens),
        secretStoreProvider.overrideWithValue(secrets),
      ],
      child: const XorderPosApp(),
    ),
  );
}

bool get _isDesktop =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;

/// One line per migration outcome that a technician might need, and none for
/// the ordinary boot. Key names only, never values.
void _reportMigration(LegacySecretMigrationResult result) {
  switch (result) {
    case LegacySecretsNotApplicable() || NoLegacySecrets():
      return;
    case LegacySecretsMigrated(:final keys):
      debugPrint('secrets: moved ${keys.join(', ')} into the OS store');
    case LegacySecretsNotWiped(:final keys, :final cause):
      debugPrint(
        'secrets: moved ${keys.join(', ')} into the OS store, but '
        'secrets.json could not be wiped ($cause); retrying next launch',
      );
    case LegacySecretsUnreadable(:final cause):
      debugPrint('secrets: secrets.json left untouched, unreadable: $cause');
    case LegacySecretsNotMigrated(:final cause, :final restoredAfterwards):
      debugPrint(
        'secrets: secrets.json left untouched, the OS store refused: $cause'
        '${restoredAfterwards ? '' : ' (and refused the roll-back)'}',
      );
  }
}
