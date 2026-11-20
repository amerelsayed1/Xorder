import 'dart:convert';
import 'dart:io';

import '../../core/config/deployment.dart';
import 'installer_credentials.dart';

/// The role the Windows installer chose for this machine.
///
/// The installer asks one question a tablet never hears: *"This machine keeps
/// the database"* or *"Till only"*. The first runs `provision.ps1` and leaves
/// `install-credentials.json`; the second installs the app and nothing else —
/// and until now left nothing behind, so the app opened the main-device
/// wizard on a machine with no PostgreSQL, and its cloud path landed on a
/// database screen with nothing to point at.
///
/// So "Till only" now writes `%ProgramData%\XOrder POS\install-role.json`,
/// `{"role": "client_terminal"}`, and this reads it: a desktop the installer
/// marked that way is a **child** of the main device (owner decision, 22 Sep
/// 2026), exactly as a tablet is — it opens on finding the main device, signs
/// in as a manager who already exists there, and registers as one more of the
/// licence's terminals. See [TerminalRole].
///
/// **Absent is a normal answer.** A developer's Mac, a machine set up by hand
/// and every install made before the marker existed have no file, and all of
/// them are what they always were: a main device. Only a saved `config.json`
/// outranks this — a terminal keeps the role it was set up with.
class InstalledRole {
  /// [TerminalRole.child] or [TerminalRole.main] when the file says so in as
  /// many words; null for anything else, so a half-understood file leaves the
  /// decision to the platform default rather than to a guess.
  static TerminalRole? tryParse(String contents) {
    final Object? decoded;
    try {
      decoded = jsonDecode(contents);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;

    return switch (decoded['role']) {
      final String wire when wire == TerminalRole.child.wire =>
        TerminalRole.child,
      final String wire when wire == TerminalRole.main.wire => TerminalRole.main,
      _ => null,
    };
  }
}

/// Where the app looks for [InstalledRole] — behind an interface for the
/// reason [InstallerCredentialsSource] is.
abstract interface class InstalledRoleSource {
  Future<TerminalRole?> read();
}

/// The marker the Windows installer wrote, beside its credentials file.
class FileInstalledRole implements InstalledRoleSource {
  /// [android] is for tests; the app leaves it null and asks the platform.
  const FileInstalledRole({this.android});

  final bool? android;

  /// Kept in step with `installer/xorder-pos.iss` by hand, and pinned by
  /// `test/tool/installer_consistency_test.dart`.
  static const fileName = 'install-role.json';

  @override
  Future<TerminalRole?> read() async {
    // A tablet is always a child of a desktop main device: it cannot host the
    // branch's PostgreSQL. There is no installer on Android to say so, and
    // "absent" would read as main (tablet-cloud-onboarding, Stage 7). The Cloud
    // app does not ask this question; it fixes its own role.
    if (android ?? Platform.isAndroid) return TerminalRole.child;

    final root = Platform.environment['ProgramData'];
    if (root == null || root.isEmpty) return null;

    final file = File(
      '$root${Platform.pathSeparator}${FileInstallerCredentials.directoryName}'
      '${Platform.pathSeparator}$fileName',
    );
    try {
      if (!await file.exists()) return null;
      return InstalledRole.tryParse(await file.readAsString());
    } on FileSystemException {
      return null;
    }
  }
}
