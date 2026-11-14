import 'dart:convert';
import 'dart:io';

import '../../core/config/deployment.dart';
import '../postgres/pos_database.dart';
import 'pg_tools.dart';

/// Runs one external program and waits for it. A seam, so the rules below can
/// be tested without a PostgreSQL on the machine running the tests.
typedef ProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      Map<String, String>? environment,
    });

Future<ProcessResult> _runProcess(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
}) => Process.run(
  executable,
  arguments,
  environment: environment,
  // stdout is a table of contents we parse; stderr is diagnostics we show.
  // Neither is binary — the archive itself always goes to `--file`.
  stdoutEncoding: utf8,
  stderrEncoding: utf8,
);

/// The database an archive is read from, or restored into.
class BackupConnection {
  const BackupConnection({
    required this.host,
    required this.port,
    required this.database,
    required this.user,
    required this.verifyTls,
    this.password,
    this.pinnedCertificatePem,
  });

  /// The host, port and database the till itself connects to, as [user] —
  /// and the till's encryption rule, which [environment] passes on.
  ///
  /// Null when this terminal has no database to connect to.
  static BackupConnection? forDeployment(
    DeploymentConfig config, {
    required String user,
    String? password,
  }) {
    final host = PosDatabase.hostFor(config);
    if (host == null) return null;
    final tls = config.lanTls;
    return BackupConnection(
      host: host,
      port: config.databasePort,
      database: config.databaseName,
      user: user,
      password: password,
      verifyTls: tls.transport.encrypted,
      pinnedCertificatePem: tls.pin?.pem,
    );
  }

  final String host;
  final int port;
  final String database;
  final String user;

  /// Null where the server lets [user] in without one — `trust` on a
  /// developer's machine, or a `.pgpass` an installer wrote.
  final String? password;

  /// False only where the till itself connects without TLS: a private address
  /// the operator explicitly trusted. `PosDatabase` makes the same choice, and
  /// a backup that quietly went over the wire in the clear while the till
  /// verified its certificate would undo it.
  final bool verifyTls;

  /// The one certificate a paired till trusts — the same anchor `PosDatabase`
  /// gives the driver. Null on a till with no pin, which verifies against
  /// the operating system's roots where the tools are libpq 16 or newer, and
  /// against whatever libpq trusts by default below that.
  ///
  /// Without it libpq's `verify-full` looks for `~/.postgresql/root.crt`,
  /// finds nothing on a till, and refuses: every backup on a paired LAN till
  /// failed while the till itself connected fine. Falling back to `require`
  /// would have made them work by trusting any certificate on the switch —
  /// the exact hole pinning closes — so [PgArchive] writes this to a file for
  /// the length of one run instead.
  final String? pinnedCertificatePem;

  /// What the tools read their credentials and encryption from.
  Map<String, String> get environment => environmentWith();

  /// [environment], plus `PGSSLROOTCERT` when [rootCertificate] is the path
  /// [PgArchive] wrote [pinnedCertificatePem] to — or libpq's `system`, for
  /// an unpinned till whose tools understand it (see `PgArchive._trusting`).
  ///
  /// **The password never goes on the command line**, where every process on
  /// the machine can read it from the process table. And only when there is
  /// one: an empty `PGPASSWORD` is not "no password", it is a wrong one.
  Map<String, String> environmentWith({String? rootCertificate}) => {
    if (password case final secret? when secret.isNotEmpty)
      'PGPASSWORD': secret,
    'PGSSLMODE': verifyTls ? 'verify-full' : 'disable',
    if (verifyTls && rootCertificate != null) 'PGSSLROOTCERT': rootCertificate,
    // A server that is not there fails in ten seconds, not in the operating
    // system's two minutes with the day-close dialog frozen in front of it.
    'PGCONNECT_TIMEOUT': '10',
  };

  /// `--no-password`: a subprocess waiting on a prompt nobody can see is a till
  /// that appears to hang at midnight, forever.
  List<String> get arguments => [
    '--host',
    host,
    '--port',
    '$port',
    '--username',
    user,
    '--no-password',
  ];
}

enum ArchiveFailureKind {
  /// `pg_dump` did not run, or ran and failed — a wrong password, an
  /// unreachable server, an account that may not read a table.
  dumpFailed,

  /// The file cannot be read back in full. Whatever `pg_dump` said, it is not
  /// a backup.
  unreadable,

  /// `pg_restore` ran and failed. With `--single-transaction` the database is
  /// exactly as it was before the attempt.
  restoreFailed,
}

class ArchiveFailure implements Exception {
  const ArchiveFailure(this.kind, [this.detail, this.sizeBytes]);

  final ArchiveFailureKind kind;

  /// What PostgreSQL said, for a technician. Not operator copy.
  final String? detail;

  /// How big the file that failed its read-back was, before it was thrown
  /// away. Recorded, because "4.1 MB that could not be read" and "0 bytes"
  /// send somebody to different places.
  final int? sizeBytes;

  @override
  String toString() =>
      'ArchiveFailure(${kind.name}${detail == null ? '' : ': $detail'})';
}

/// `pg_dump` and `pg_restore`, run the way a backup has to be.
///
/// The product decisions — who may take one, what is recorded, when a restore
/// is refused — live in `BackupService`. This is only the part that talks to
/// the tools, and every rule in it is one that was found by a copy that looked
/// fine and was not.
class PgArchive {
  PgArchive(this.tools, {ProcessRunner? run}) : _run = run ?? _runProcess;

  final PgToolset tools;
  final ProcessRunner _run;

  /// One `pg_dump -Fc` of [from] into [to], kept only once it reads back.
  ///
  /// **Written to `.part`, renamed when proven.** A dump interrupted by a power
  /// cut would otherwise sit in the folder under a finished name, and the day it
  /// is needed is the day it turns out to be half a file.
  ///
  /// Returns the table of contents, which the caller checks for the tables a
  /// business cannot trade without.
  Future<String> dump({
    required BackupConnection from,
    required File to,
  }) async {
    final part = File('${to.path}.part');
    try {
      final dumped = await _trusting(
        ArchiveFailureKind.dumpFailed,
        from,
        (environment) => _start(ArchiveFailureKind.dumpFailed, tools.pgDump, [
          '--format=custom',
          '--file',
          part.path,
          ...from.arguments,
          '--dbname',
          from.database,
        ], environment: environment),
      );
      if (dumped.exitCode != 0) {
        throw ArchiveFailure(ArchiveFailureKind.dumpFailed, _tail(dumped.stderr));
      }

      final String contents;
      try {
        contents = await readBack(part);
      } on ArchiveFailure catch (failure) {
        throw ArchiveFailure(failure.kind, failure.detail, part.lengthSync());
      }
      await part.rename(to.path);
      return contents;
    } finally {
      if (part.existsSync()) await part.delete();
    }
  }

  /// Read [archive] the way a restore would, without restoring it anywhere.
  ///
  /// **Two reads, because one is not enough.** `--list` proves the table of
  /// contents names some data, and does not read every block: a dump missing
  /// its last few bytes — a USB drive pulled out as the copy finished — lists
  /// perfectly (measured).
  /// Converting the whole archive to SQL and throwing the SQL away reads and
  /// decompresses every block, which is the only way to learn the end of the
  /// file is there.
  Future<String> readBack(File archive) async {
    final listed = await _start(ArchiveFailureKind.unreadable, tools.pgRestore, [
      '--list',
      archive.path,
    ]);
    final contents = '${listed.stdout}';
    if (listed.exitCode != 0 || !contents.contains('TABLE DATA')) {
      throw ArchiveFailure(ArchiveFailureKind.unreadable, _tail(listed.stderr));
    }

    final read = await _start(ArchiveFailureKind.unreadable, tools.pgRestore, [
      '--file',
      Platform.isWindows ? 'NUL' : '/dev/null',
      archive.path,
    ]);
    if (read.exitCode != 0) {
      throw ArchiveFailure(ArchiveFailureKind.unreadable, _tail(read.stderr));
    }
    return contents;
  }

  /// Replace everything in [into] with what is in [from].
  ///
  /// **Read in full before anything is touched, then all or nothing.** A
  /// damaged file is refused while the database is still intact, and the
  /// restore itself is `--single-transaction`, so one that fails part-way
  /// through `--clean` rolls back to the database that was there — never to an
  /// emptied one, which is the worst state a restore can leave.
  ///
  /// `--no-owner` because the account restoring — the database's owner, which
  /// is not a superuser — is the one that should own what it creates, whoever
  /// owned the tables where the copy was taken. It could not hand them to
  /// anybody else in any case. Grants are restored as dumped, so the till's
  /// account keeps exactly what it had.
  Future<void> restore({
    required File from,
    required BackupConnection into,
  }) async {
    await readBack(from);

    final restored = await _trusting(
      ArchiveFailureKind.restoreFailed,
      into,
      (environment) => _start(
        ArchiveFailureKind.restoreFailed,
        tools.pgRestore,
        [
          '--clean',
          '--if-exists',
          '--no-owner',
          '--single-transaction',
          ...into.arguments,
          '--dbname',
          into.database,
          from.path,
        ],
        environment: environment,
      ),
    );
    if (restored.exitCode != 0) {
      throw ArchiveFailure(
        ArchiveFailureKind.restoreFailed,
        _tail(restored.stderr),
      );
    }
  }

  /// Delete all but the newest [keep] archives named `<prefix>…​.dump`.
  ///
  /// Only ours: nothing else in the folder is ours to delete — it may be a USB
  /// stick somebody also keeps the menu photos on. Newest by NAME, because the
  /// name carries the time it was taken and a copy's modified time changes the
  /// moment somebody copies it back.
  ///
  /// Returns what it deleted.
  static List<File> prune(
    Directory folder, {
    required String prefix,
    required int keep,
    // `.db` for a till whose copies are its SQLite file.
    String extension = '.dump',
  }) {
    if (!folder.existsSync()) return const [];
    final ours =
        folder.listSync().whereType<File>().where((file) {
          final name = file.uri.pathSegments.last;
          return name.startsWith(prefix) && name.endsWith(extension);
        }).toList()..sort(
          (a, b) => b.uri.pathSegments.last.compareTo(a.uri.pathSegments.last),
        );

    final gone = ours.skip(keep).toList();
    for (final old in gone) {
      old.deleteSync();
    }
    return gone;
  }

  /// Runs [body] with [connection]'s environment, and — on a paired till —
  /// its pinned certificate in a file libpq can be pointed at.
  ///
  /// **A fresh folder per run, gone when the run is.** `createTemp` makes it
  /// owner-only on macOS (mkdtemp, 0700) and under the signed-in user's own
  /// profile on Windows. The certificate is public; what the folder protects
  /// is the *file*, because whoever can replace a trust anchor between our
  /// write and libpq's read chooses which server the backup is sent to. A
  /// fixed path beside `config.json` would be one more thing to keep
  /// writable by the till and nobody else, for ever.
  Future<ProcessResult> _trusting(
    ArchiveFailureKind kind,
    BackupConnection connection,
    Future<ProcessResult> Function(Map<String, String> environment) body,
  ) async {
    final pem = connection.pinnedCertificatePem?.trim() ?? '';
    if (!connection.verifyTls) return body(connection.environment);
    if (pem.isEmpty) {
      // Unpinned, and encrypted — a LAN or remote host whose certificate a
      // real authority issued; loopback never gets here, it is `disable`.
      // The till itself verifies that chain against the operating system's
      // roots (`PosTls`: no SecurityContext, so dart:io's default). libpq
      // does NOT: under verify-full with no PGSSLROOTCERT it reads
      // `~/.postgresql/root.crt`, which no till has, and refuses — the
      // backup fails while the till connects fine, the same split the pin
      // file above was written to close.
      //
      // `system` is libpq 16's word for "the OS store". Older libpq reads
      // it as a FILE named `system`, fails the same way it does today, and
      // says so less clearly — so it is only set where the located pg_dump
      // is 16 or newer. Below that, or when the version did not parse, this
      // stays as it was: still verify-full, never `require`, which would
      // "fix" it by trusting any certificate on the switch. (The libpq that
      // runs is the one shipped with the located pg_dump — EDB's bin folder
      // on Windows, Homebrew's or Postgres.app's keg on macOS — so the
      // tool's major version stands in for libpq's.)
      final systemRoots = (tools.majorVersion ?? 0) >= 16;
      return body(
        systemRoots
            ? connection.environmentWith(rootCertificate: 'system')
            : connection.environment,
      );
    }
    final Directory folder;
    try {
      folder = await Directory.systemTemp.createTemp('xorder-pos-tls-');
    } on FileSystemException catch (error) {
      throw ArchiveFailure(
        kind,
        'the paired certificate could not be written: ${error.message}',
      );
    }
    final anchor = File('${folder.path}${Platform.pathSeparator}root.crt');
    try {
      try {
        await anchor.writeAsString('$pem\n', flush: true);
      } on FileSystemException catch (error) {
        throw ArchiveFailure(
          kind,
          'the paired certificate could not be written: ${error.message}',
        );
      }
      return await body(
        connection.environmentWith(rootCertificate: anchor.path),
      );
    } finally {
      try {
        await folder.delete(recursive: true);
      } on FileSystemException {
        // A public certificate left in the user's temp folder is untidy, not
        // a leak; failing a backup that succeeded over it would be worse.
      }
    }
  }

  Future<ProcessResult> _start(
    ArchiveFailureKind kind,
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
  }) async {
    try {
      return await _run(executable, arguments, environment: environment);
    } on ProcessException catch (error) {
      throw ArchiveFailure(kind, '$executable could not be started: $error');
    }
  }

  /// The last few lines of PostgreSQL's diagnostics — where the reason is.
  static String _tail(Object? text, {int lines = 4}) {
    final kept = '$text'.trim().split('\n');
    return (kept.length <= lines ? kept : kept.sublist(kept.length - lines))
        .join('\n')
        .trim();
  }
}
