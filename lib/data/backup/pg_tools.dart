/// Finding `pg_dump` and `pg_restore`, and being honest when they are absent.
///
/// **The binary dependency is surfaced rather than assumed.** A backup button
/// that silently does nothing is worse than no button: the restaurant believes
/// it has copies. So the pane asks this class where the tools are, shows the
/// answer, and when the answer is "nowhere" it prints the places that were
/// looked in and what to install.
///
/// **Why a subprocess at all, rather than a Dart export.** A logical export
/// written by hand is exactly the "a table nothing reads" failure this codebase
/// has already been bitten by twice — it silently misses the table added last
/// month, and foreign-key ordering on restore is a solved problem somebody else
/// has already got right. `pg_restore --list` also hands us verification for
/// free, which a hand-rolled writer would have had to invent.
library;

import 'dart:io';

/// Where the tools are, and which version they are.
class PgToolset {
  const PgToolset({
    required this.pgDump,
    required this.pgRestore,
    required this.version,
  });

  /// Absolute paths. Absolute rather than the bare name even when they came off
  /// PATH, because the version reported below has to be the version that runs.
  final String pgDump;
  final String pgRestore;

  /// As `pg_dump --version` reports it — `16.11`, or the whole line when it
  /// does not parse. Shown on screen because the one restore failure that is
  /// not our bug is an old client against a newer server.
  final String version;

  /// The major version as an integer, or null when it did not parse.
  int? get majorVersion => int.tryParse(version.split('.').first);
}

/// Locating the PostgreSQL client tools on this machine.
abstract final class PgTools {
  /// Every directory that will be searched, in order.
  ///
  /// Public so the screen can print it. A message reading "pg_dump was not
  /// found" sends somebody to a search engine; one that lists the six places
  /// looked in sends them to the right folder.
  static List<String> searchPath() => [
    // Beside the app, first: the Windows installer bundles PostgreSQL and puts
    // its tools here, and that copy is the one known to match the server.
    '${File(Platform.resolvedExecutable).parent.path}'
        '${Platform.pathSeparator}pgsql${Platform.pathSeparator}bin',
    ...?Platform.environment['PATH']?.split(Platform.isWindows ? ';' : ':'),
    ..._wellKnown(),
  ].where((entry) => entry.trim().isNotEmpty).toList();

  /// The install locations a restaurant's machine actually has, per OS.
  ///
  /// Newest first: a machine with two PostgreSQL versions installed should dump
  /// with the newer client, because a newer `pg_dump` reads an older server and
  /// the reverse is refused outright.
  static List<String> _wellKnown() {
    // 13 is where a Windows install old enough to be in the field bottoms out;
    // 18 is a year ahead of this build, so the list does not need editing the
    // week PostgreSQL ships.
    const majors = [18, 17, 16, 15, 14, 13];

    if (Platform.isWindows) {
      final programFiles =
          Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
      return [
        // The EnterpriseDB installer, which is what "install PostgreSQL on
        // Windows" means to everybody who has not been told otherwise.
        for (final major in majors) '$programFiles\\PostgreSQL\\$major\\bin',
      ];
    }

    if (Platform.isMacOS) {
      return [
        for (final major in majors) '/opt/homebrew/opt/postgresql@$major/bin',
        for (final major in majors) '/usr/local/opt/postgresql@$major/bin',
        // Postgres.app keeps a directory per version it has ever installed.
        for (final major in majors)
          '/Applications/Postgres.app/Contents/Versions/$major/bin',
        for (final major in majors) '/Library/PostgreSQL/$major/bin',
        '/opt/homebrew/bin',
        '/usr/local/bin',
      ];
    }

    return [
      // Debian and Ubuntu put every installed version side by side here and
      // symlink only one of them into /usr/bin.
      for (final major in majors) '/usr/lib/postgresql/$major/bin',
      '/usr/bin',
      '/usr/local/bin',
    ];
  }

  static String _exe(String name) => Platform.isWindows ? '$name.exe' : name;

  /// The first directory holding **both** tools, with its version read off
  /// `pg_dump --version`.
  ///
  /// Both, not either: a machine with `pg_dump` and no `pg_restore` can take
  /// copies it cannot verify and cannot put back, which is the state this whole
  /// feature exists to keep a restaurant out of. Better to report nothing found
  /// than to offer half of it.
  ///
  /// Returns null when they are not there. Not a throw — "PostgreSQL's client
  /// tools are not installed" is a fact about the machine, not an error in the
  /// program, and the screen has a sentence prepared for it.
  static Future<PgToolset?> locate() async {
    for (final directory in searchPath()) {
      final dump = File('$directory${Platform.pathSeparator}${_exe('pg_dump')}');
      final restore = File(
        '$directory${Platform.pathSeparator}${_exe('pg_restore')}',
      );
      if (!dump.existsSync() || !restore.existsSync()) continue;

      final version = await _versionOf(dump.path);
      // Present but unrunnable — the wrong architecture, a broken symlink, a
      // permission. Keep looking rather than returning a toolset that fails on
      // the first backup.
      if (version == null) continue;

      return PgToolset(
        pgDump: dump.path,
        pgRestore: restore.path,
        version: version,
      );
    }
    return null;
  }

  /// `pg_dump (PostgreSQL) 16.11 (Homebrew)` → `16.11`.
  static Future<String?> _versionOf(String path) async {
    try {
      final run = await Process.run(path, const ['--version']);
      if (run.exitCode != 0) return null;
      final line = '${run.stdout}'.trim();
      final match = RegExp(r'(\d+(?:\.\d+)*)').firstMatch(line);
      return match?.group(1) ?? (line.isEmpty ? null : line);
    } on ProcessException {
      return null;
    }
  }
}
