/// The till's entry point, shared by the two apps (pos-split-apps, stage 2).
///
/// `apps/xorder_pos_cloud/lib/main.dart` and `apps/xorder_pos_offline/lib/main.dart`
/// each call [runPos] with their one mode and nothing else. Everything that used
/// to be `lib/main.dart` here is this file; what changed is that the mode is an
/// argument rather than a question the wizard asks, and that a configuration the
/// other app wrote is refused before the first frame (BR-8).
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'core/config/deployment.dart';
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

/// Start the till as the app for [mode].
///
/// The window, the macOS app menu and the About box carry
/// [DeploymentMode.productName]; `appModeProvider` carries the mode to the
/// wizard, the deployment default and the licence rules.
Future<void> runPos({required DeploymentMode mode}) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (_isDesktop) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        size: _initialWindow,
        minimumSize: _minimumWindow,
        title: mode.productName,
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
        appModeProvider.overrideWithValue(mode),
        installedRoleProvider.overrideWithValue(installedRole),
        terminalBootProvider.overrideWithValue(
          bootFor(
            saved: saved,
            appMode: mode,
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

/// What this app boots from, given what is on disk.
///
/// One app per machine (BR-8): a saved configuration in the other app's mode is
/// not this app's to open. It is left exactly where it is — the installer or a
/// technician removes it — and the boot carries only the fact that it exists,
/// as [TerminalBoot.otherAppMode], so the router can say which app owns this
/// machine. A child tablet is judged the same way: it runs its main device's
/// mode, and that is the app it should have been installed as.
///
/// Pure, so the rule is testable without a window.
TerminalBoot bootFor({
  required SavedTerminalConfig? saved,
  required DeploymentMode appMode,
  required bool hasDatabaseCredential,
  required bool credentialStoreUnavailable,
}) {
  if (saved != null && saved.deployment.mode != appMode) {
    return TerminalBoot(otherAppMode: saved.deployment.mode);
  }
  return TerminalBoot(
    config: saved,
    hasDatabaseCredential: hasDatabaseCredential,
    credentialStoreUnavailable: credentialStoreUnavailable,
  );
}

bool get _isDesktop =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;

/// One line per migration outcome that a technician might need, and none for
/// the ordinary boot. Key names only, never values.
///
/// **Exception types only, never `'$cause'`.** An unreadable `secrets.json`
/// fails as a `FormatException`, whose text quotes the file — and this line
/// lands in a log that gets attached to support tickets. The type says which
/// of the failures it was; the file itself is still there for a technician.
void _reportMigration(LegacySecretMigrationResult result) {
  switch (result) {
    case LegacySecretsNotApplicable() || NoLegacySecrets():
      return;
    case LegacySecretsMigrated(:final keys):
      debugPrint('secrets: moved ${keys.join(', ')} into the OS store');
    case LegacySecretsNotWiped(:final keys, :final cause):
      debugPrint(
        'secrets: moved ${keys.join(', ')} into the OS store, but '
        'secrets.json could not be wiped (${cause.runtimeType}); retrying '
        'next launch',
      );
    case LegacySecretsUnreadable(:final cause):
      debugPrint(
        'secrets: secrets.json left untouched, unreadable '
        '(${cause.runtimeType})',
      );
    case LegacySecretsNotMigrated(:final cause, :final restoredAfterwards):
      debugPrint(
        'secrets: secrets.json left untouched, ${cause.store} refused to '
        '${cause.operation} (${cause.cause.runtimeType})'
        '${restoredAfterwards ? '' : ' (and refused the roll-back)'}',
      );
  }
}
