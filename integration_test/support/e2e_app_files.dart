import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:xorder_pos/data/config/terminal_config_store.dart';
import 'package:xorder_pos/data/config/file_secret_store.dart';
import 'package:xorder_pos/data/config/secret_store.dart';
import 'package:xorder_pos/features/licensing/data/file_license_store.dart';

/// Keeps the end-to-end suite from leaving a terminal behind.
///
/// This suite boots the real app with no overrides, on purpose — the credential
/// has to arrive through the wizard's own password field or the test proves
/// nothing about an installer. The cost is that finishing the wizard writes a
/// real `config.json` into Application Support, exactly as it would on a till.
///
/// On a developer's machine that file is not wanted, and on a machine that is
/// genuinely set up it must not be clobbered. So the suite snapshots whatever
/// was there and puts it back: absent stays absent, present comes back
/// unchanged.
abstract final class E2eAppFiles {
  /// Snapshot everything this suite installs, and put it back when it ends.
  ///
  /// Call from `setUp`. Registers its own tear-down.
  ///
  /// Both files matter, and the licence is the one that bites hardest: this
  /// suite activates a licence for its own throwaway tenant, so a run left the
  /// developer's machine holding `e2e-diner` — and since the wizard adopts the
  /// tenant off whatever licence is installed, the next real licence pasted in
  /// by hand was refused as belonging to the wrong business. The suite has to
  /// leave the machine as it found it.
  static Future<void> preserveTerminalConfig() async {
    final directory = await getApplicationSupportDirectory();

    await _preserve(
      File(p.join(directory.path, FileTerminalConfigStore.fileName)),
    );
    await _preserve(File(p.join(directory.path, FileLicenseStore.fileName)));
    await _preserve(File(p.join(directory.path, FileSecretStore.fileName)));
    await _preserveOsSecrets();

    // Every scenario begins as a genuinely new installation. Besides making
    // the suite deterministic, this lets it execute main() and prove the real
    // disk-backed boot path rather than relying on empty provider defaults.
    await clearInstallation();
  }

  /// Remove only the three files owned by terminal setup.
  ///
  /// Used for the second virtual machine in the pairing-code reuse scenario as
  /// well as at set-up. The snapshots registered above still restore the
  /// developer's original files when the test ends.
  static Future<void> clearInstallation() async {
    final directory = await getApplicationSupportDirectory();
    for (final name in [
      FileTerminalConfigStore.fileName,
      FileLicenseStore.fileName,
      FileSecretStore.fileName,
    ]) {
      final file = File(p.join(directory.path, name));
      if (file.existsSync()) await file.delete();
    }
    // On Windows and macOS the credentials are not in that file any more but
    // in DPAPI / the Keychain, and a second virtual machine that found the
    // first one's there would not be new at all.
    final secrets = SecretStore.forPlatform();
    if (secrets.protectedByOperatingSystem) await secrets.deleteAll();
  }

  /// The secrets the wizard writes, as they were before the suite, put back
  /// key by key afterwards. In the real store, because the suite boots the
  /// real `main()`: on a developer's Mac that is their login keychain, and
  /// leaving the e2e tenant's password there would replace their own till's.
  static Future<void> _preserveOsSecrets() async {
    final secrets = SecretStore.forPlatform();
    // The development store IS secrets.json, already preserved above.
    if (!secrets.protectedByOperatingSystem) return;
    const keys = [
      FileSecretStore.databasePasswordKey,
      FileSecretStore.deviceTokenKey,
      FileSecretStore.backupPasswordKey,
      FileSecretStore.adminPasswordKey,
    ];
    final before = {for (final key in keys) key: await secrets.read(key)};

    addTearDown(() async {
      for (final MapEntry(:key, :value) in before.entries) {
        if (value == null) {
          await secrets.delete(key);
        } else {
          await secrets.write(key, value);
        }
      }
    });
  }

  /// Absent stays absent; present comes back byte for byte.
  static Future<void> _preserve(File file) async {
    final before = file.existsSync() ? await file.readAsString() : null;

    addTearDown(() async {
      if (before == null) {
        if (file.existsSync()) await file.delete();
      } else {
        await file.writeAsString(before, flush: true);
      }
    });
  }
}
