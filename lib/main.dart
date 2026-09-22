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

  final credentials = MutablePosDbCredentials(
    store: FileSecretStore(key: FileSecretStore.databasePasswordKey),
  );
  await credentials.restore();

  // The cloud device token (POS-BE-011 Option C) lives in the same secrets
  // file under its own key, and is restored the same way: once, before the
  // first frame, so the sync loop finds it synchronously.
  final deviceTokens = DeviceTokenVault(
    store: FileSecretStore(key: FileSecretStore.deviceTokenKey),
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
            // keystore visible at all.
            credentialStoreUnavailable: credentials.storeUnavailable,
          ),
        ),
        terminalConfigStoreProvider.overrideWithValue(configStore),
        posDbCredentialsStoreProvider.overrideWithValue(credentials),
        deviceTokenVaultProvider.overrideWithValue(deviceTokens),
      ],
      child: const XorderPosApp(),
    ),
  );
}

bool get _isDesktop =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;
