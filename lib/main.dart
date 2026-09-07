import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'core/config/terminal_config.dart';
import 'data/cloud/device_token_vault.dart';
import 'data/config/file_secret_store.dart';
import 'data/config/terminal_config_store.dart';
import 'data/postgres/pos_database.dart';

/// A POS terminal is a fixed installation, not a phone. The window is given a
/// minimum size that the three-pane shell actually fits in, so a cashier cannot
/// drag the till into a layout the design never covered.
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

  // Read the terminal's own configuration before the first frame.
  //
  // Before `runApp` rather than inside a provider because the router decides
  // where the first frame goes: a till that painted the setup wizard for one
  // frame every morning before redirecting to the start screen would read as
  // broken to the person opening the restaurant.
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

  runApp(
    ProviderScope(
      overrides: [
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
