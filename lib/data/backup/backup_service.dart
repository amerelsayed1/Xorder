import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../core/config/deployment.dart';
import '../../core/money/money.dart';
import '../../domain/models/backup.dart';
import '../../domain/models/permissions.dart';
import '../../domain/models/shift.dart';
import '../../domain/repositories/admin_repositories.dart';
import '../../domain/services/authorization.dart';
import '../postgres/pos_database.dart';
import 'pg_tools.dart';

/// Taking a copy of the branch database, proving it, and putting one back.
///
/// **`pg_dump -Fc`, not a hand-written export.** The alternative was considered
/// and rejected twice over: a Dart exporter silently misses the table somebody
/// added last month — this schema has grown by thirty-five migrations and every
/// one of them would have needed a matching line here — and getting foreign-key
/// ordering right on the way back in is a problem PostgreSQL has already
/// solved. The custom format also gives `pg_restore --list`, which is the only
/// reason verification is cheap enough to do on every single backup.
///
/// **Where the copies go is on the same disk as the database, and that protects
/// against almost nothing.** A backup beside the thing it backs up survives a
/// dropped table, a bad migration and somebody deleting the wrong week. It does
/// not survive the disk failing, the machine being stolen, a fire, or the
/// ransomware run that encrypts every file the account can write — which is
/// the list of things that actually happen to a restaurant. Copying the folder
/// off the machine is out of scope for this change; saying so, on the screen
/// and here, is not.
class BackupService {
  BackupService({
    required PosDatabase database,
    required this.config,
    required this.restaurantId,
    required this.branchId,
    required this.directory,
    required this.backups,
    required this.audit,
    this.toolset,
    this.password,
    this.quiesce,
    this.currency = 'EGP',
    this.exponent = 2,
  }) : _db = database;

  final PosDatabase _db;

  /// Where the attempt is written down, whichever way it went.
  final BackupRepository backups;

  final AuditRepository audit;


  /// The connection the guard queries and the audit row run on. The **till's**,
  /// deliberately: a backup is taken at day close by a machine on which nobody
  /// has opened the back office, and the counts it needs — open shifts, open
  /// days, orders since — are all reads the till credential already holds.
  final DeploymentConfig config;

  final int restaurantId;
  final int branchId;

  /// Absolute, and already resolved. [BackupPaths] decides the default; this
  /// class is only ever told.
  final String directory;

  /// Null when PostgreSQL's client tools are not installed. Everything here
  /// then refuses in a way the screen can print — see [BackupFailure.toolsMissing].
  final PgToolset? toolset;

  /// The administrator role's database password, when somebody has supplied it
  /// this session.
  ///
  /// **Null is the ordinary case at day close, and the automatic backup still
  /// tries.** The password is held in memory for a Management session and never
  /// written to disk — that decision predates this file and is the reason a
  /// stolen till credential cannot reprice the menu. Storing it so that
  /// backups could always run would hand back exactly what the split was
  /// protecting, so instead `pg_dump` is invoked with no `PGPASSWORD` and
  /// succeeds wherever local authentication is `trust`, `peer`, or a `.pgpass`
  /// the installer wrote. Where it is none of those the attempt is recorded as
  /// a failure and the pane says so, which is the honest outcome: the
  /// restaurant learns it has no nightly copy on the day it starts not having
  /// one, rather than on the day it needs one.
  final String? password;

  /// Closes every pool before a restore drops the objects underneath them.
  final Future<void> Function()? quiesce;

  final String currency;
  final int exponent;

  /// The tables whose absence means the archive is not worth keeping.
  ///
  /// A curated list, not every table: the question verification asks is "could
  /// a restaurant trade and answer a tax audit from this file", and these are
  /// the rows that answer it — what was sold, what was paid, who was on, and
  /// the ledger nobody may edit. [BackupRecord.tablesFound] carries the total
  /// so a shrinking archive is still visible in the list.
  static const essentialTables = <String>[
    'pos_orders',
    'pos_order_lines',
    'pos_order_payments',
    'pos_shifts',
    'pos_business_days',
    'pos_audit_events',
    'pos_products',
    'pos_staff',
  ];

  /// Take one, verify it, and record what happened either way.
  ///
  /// **The permission is checked for a manual copy and not for an automatic
  /// one, and that is deliberate rather than an oversight.** `backup.manage` is
  /// held by the Owner alone; `day.close` is held by every manager. If the
  /// automatic copy demanded the first, the only nights with a backup would be
  /// the nights the owner happened to be the one closing the day — which is the
  /// same as having no nightly backup, arrived at by a route nobody would
  /// notice. Pressing the button is a decision somebody makes about the
  /// database; closing the day is not, and the copy that follows it is the
  /// system doing its job.
  ///
  /// Never throws for an ordinary failure. A backup that failed is a *row*
  /// saying it failed — the pane's whole job is to make that row visible, and
  /// an exception that only reached a log would leave the list looking like
  /// nothing had been attempted.
  Future<AdminResult<BackupRecord>> take({
    required PosStaff by,
    required BackupTrigger trigger,
  }) async {
    // `Authorization.check`, never `by.capabilities` — that field is the direct
    // grants alone and an owner holds almost everything through their role.
    if (trigger == BackupTrigger.manual &&
        !Authorization.check(by, PosCapability.backupManage).isAllowed) {
      return const AdminResult.refused(
        NotPermitted(PosCapability.backupManage),
      );
    }
    return AdminResult.done(await _take(by: by, trigger: trigger));
  }

  Future<BackupRecord> _take({
    required PosStaff by,
    required BackupTrigger trigger,
  }) async {
    final at = DateTime.now();
    final path = _fileFor(at);

    final tools = toolset;
    if (tools == null) {
      return _record(
        by: by,
        entry: BackupRecord(
          takenAt: at,
          takenByName: by.name,
          takenById: by.id,
          trigger: trigger,
          outcome: BackupOutcome.failed,
          filePath: path,
          failure: BackupFailure.toolsMissing,
        ),
      );
    }

    try {
      Directory(directory).createSync(recursive: true);
    } on FileSystemException catch (error) {
      return _record(
        by: by,
        entry: BackupRecord(
          takenAt: at,
          takenByName: by.name,
          takenById: by.id,
          trigger: trigger,
          outcome: BackupOutcome.failed,
          filePath: path,
          failure: BackupFailure.destinationUnwritable,
          detail: error.osError?.message ?? error.message,
        ),
      );
    }

    final dump = await _run(tools.pgDump, [
      '--format=custom',
      // Compressed by default in custom format, which matters on a till whose
      // disk is the reason we are here.
      '--file=$path',
      '--host=${config.databaseHost}',
      '--port=${config.databasePort}',
      '--username=${config.databaseUser}',
      // Never prompt. A subprocess waiting on a password nobody can see is a
      // till that appears to hang at midnight, forever.
      '--no-password',
      config.databaseName,
    ]);

    if (dump == null || dump.exitCode != 0) {
      // Leave nothing that looks like a backup. A half-written file with a
      // plausible size is precisely what somebody restores from in a panic.
      _deleteQuietly(path);
      return _record(
        by: by,
        entry: BackupRecord(
          takenAt: at,
          takenByName: by.name,
          takenById: by.id,
          trigger: trigger,
          outcome: BackupOutcome.failed,
          filePath: path,
          failure: BackupFailure.dumpRefused,
          detail: dump == null
              ? 'pg_dump could not be started'
              : _tail('${dump.stderr}'),
        ),
      );
    }

    final file = File(path);
    final size = file.existsSync() ? file.lengthSync() : 0;
    final checksum = size == 0 ? null : await _checksum(file);

    // The verification, and the reason this is a feature rather than a button.
    final listed = await _run(tools.pgRestore, ['--list', path]);
    if (listed == null || listed.exitCode != 0) {
      return _record(
        by: by,
        entry: BackupRecord(
          takenAt: at,
          takenByName: by.name,
          takenById: by.id,
          trigger: trigger,
          outcome: BackupOutcome.unverified,
          filePath: path,
          sizeBytes: size,
          checksum: checksum,
          failure: BackupFailure.archiveUnreadable,
          detail: listed == null
              ? 'pg_restore could not be started'
              : _tail('${listed.stderr}'),
        ),
      );
    }

    final tables = tablesIn('${listed.stdout}');
    final missing = [
      for (final wanted in essentialTables)
        if (!tables.contains(wanted)) wanted,
    ];

    return _record(
      by: by,
      entry: BackupRecord(
        takenAt: at,
        takenByName: by.name,
        takenById: by.id,
        trigger: trigger,
        outcome: missing.isEmpty
            ? BackupOutcome.verified
            : BackupOutcome.unverified,
        filePath: path,
        sizeBytes: size,
        checksum: checksum,
        tablesFound: tables.length,
        failure: missing.isEmpty ? null : BackupFailure.archiveIncomplete,
        // The names, not a count: "pos_orders is not in this file" is the
        // sentence that gets somebody to look at the right thing.
        detail: missing.isEmpty ? null : missing.join(', '),
      ),
    );
  }

  /// The table names in a `pg_restore --list` table of contents.
  ///
  /// Static and public so the parsing is testable without a database — the
  /// output format is PostgreSQL's, not ours, and it is the one thing here that
  /// could change under us on a client upgrade.
  static Set<String> tablesIn(String toc) => {
    for (final match in RegExp(
      r'^\d+;.*\bTABLE(?: DATA)? \S+ (\w+)',
      multiLine: true,
    ).allMatches(toc))
      match.group(1)!,
  };

  /// What restoring [from] would cost, and what stands in the way.
  ///
  /// **Both guards are read here rather than enforced by a trigger, and that is
  /// a limitation worth naming.** Every other cross-row rule in this codebase
  /// lives in the database because a rule in Dart holds only until somebody
  /// writes the second writer. A restore is not a row write — it is a process
  /// replacing the whole database — so there is no INSERT to hang a trigger on,
  /// and the second writer here is a technician with `pg_restore` and a shell,
  /// whom nothing in the schema could ever stop. What the database *can* do it
  /// does: the counts below are the database's own answer, taken in one round
  /// trip so a shift opening mid-read cannot be missed by one query and seen by
  /// the next.
  Future<RestoreCheck> checkRestore(BackupRecord from) async {
    final rows = await _db.query(
      config,
      '''
      SELECT
        (SELECT count(*) FROM pos_shifts s
          WHERE s.restaurant_id = @restaurant AND s.branch_id = @branch
            AND s.closed_at IS NULL),
        (SELECT count(*) FROM pos_business_days d
          WHERE d.restaurant_id = @restaurant AND d.branch_id = @branch
            AND d.closed_at IS NULL),
        (SELECT count(*) FROM pos_orders o
          WHERE o.restaurant_id = @restaurant AND o.branch_id = @branch
            AND o.received_at > @since),
        (SELECT coalesce(sum(o.total_minor), 0)::bigint FROM pos_orders o
          WHERE o.restaurant_id = @restaurant AND o.branch_id = @branch
            AND o.received_at > @since),
        (SELECT max(o.received_at) FROM pos_orders o
          WHERE o.restaurant_id = @restaurant AND o.branch_id = @branch
            AND o.received_at > @since)
      ''',
      parameters: {
        'restaurant': restaurantId,
        'branch': branchId,
        // `received_at`, not `occurred_at`: the question is what is in this
        // database and would stop being in it, and a ticket rung up before the
        // dump but settled after it is a row the dump does not contain.
        'since': from.takenAt.toUtc(),
      },
    );

    final counts = rows.first.toList();
    final openShifts = counts[0] as int? ?? 0;
    final openDays = counts[1] as int? ?? 0;

    return RestoreCheck(
      from: from,
      blockers: [
        if (openShifts > 0)
          RestoreBlocker(
            kind: RestoreBlockerKind.openShift,
            count: openShifts,
          ),
        if (openDays > 0)
          RestoreBlocker(
            kind: RestoreBlockerKind.openBusinessDay,
            count: openDays,
          ),
      ],
      ordersSince: counts[2] as int? ?? 0,
      valueSince: Money(
        counts[3] as int? ?? 0,
        currency: currency,
        exponent: exponent,
      ),
      lastOrderAt: (counts[4] as DateTime?)?.toLocal(),
    );
  }

  /// Replace this database with [from]. The most dangerous act in the product.
  ///
  /// Re-checks the guards immediately before running, however carefully the
  /// caller checked: the dialog was on screen while somebody at the next till
  /// opened a shift, and a restore that raced that is a drawer nobody can
  /// reconcile and an evening nobody can reconstruct.
  ///
  /// **The audit row lands in the database being replaced — so it is written
  /// afterwards, into the restored one.** Written before, it would be inside
  /// the very rows `pg_restore --clean` drops, and the only trace of the most
  /// destructive act available in this product would be destroyed by the act
  /// itself. Written after, it survives, and it says which file was used and
  /// what was discarded. The cost is real and is stated rather than hidden: if
  /// the restore succeeds and the machine loses power before this row is
  /// written, the restore happened and nothing records it. The alternative —
  /// writing to a second database, or a file beside the dump — was rejected as
  /// a second store to install, grant, back up and keep in step, for a window
  /// of a few hundred milliseconds. `pos_backups` is the mitigation: the copy
  /// being restored *from* is itself a dated file on disk, so "what did this
  /// database used to be" is answerable even when the ledger row is missing.
  Future<AdminResult<BackupRecord>> restore(
    BackupRecord from, {
    required PosStaff by,
  }) async {
    if (!Authorization.check(by, PosCapability.backupManage).isAllowed) {
      return const AdminResult.refused(
        NotPermitted(PosCapability.backupManage),
      );
    }

    final tools = toolset;
    if (tools == null) {
      throw StateError(
        'PostgreSQL\'s client tools are not installed on this machine, so '
        'there is nothing here that can read a backup file.',
      );
    }

    final check = await checkRestore(from);
    if (!check.isPermitted) throw RestoreRefused(check.blockers);

    // Not a backup, so not a thing to replace a database with. The pane never
    // offers the button on such a row; this is the second line, because a
    // record can be handed here by any caller and "restore" from a file
    // `pg_restore` already said it could not read would leave the restaurant
    // with neither the old database nor a new one.
    if (!from.isRestorable) {
      throw StateError(
        'That copy failed verification when it was taken, so it is not a '
        'backup and cannot be restored from.',
      );
    }

    final file = File(from.filePath);
    if (!file.existsSync()) {
      throw StateError('The backup file is no longer at ${from.filePath}.');
    }

    // The checksum earns its column here and nowhere else: the row says what
    // was on disk when it was written, so a file that has since been replaced,
    // truncated or half-copied to a USB stick is a different file from the one
    // that was verified — and verification is the only reason to trust it.
    final onDisk = await _checksum(file);
    if (from.checksum != null && onDisk != from.checksum) {
      throw StateError(
        'The file at ${from.filePath} is not the one this record describes — '
        'it has been replaced or damaged since it was verified.',
      );
    }

    // Let go of every pooled connection first. An idle session holds no locks,
    // so this is belt and braces rather than a fix — but `--clean` drops every
    // object in the database and the failure mode if it does block is a till
    // frozen mid-restore, which is the one state worse than not having started.
    await quiesce?.call();

    final run = await _run(tools.pgRestore, [
      '--clean',
      '--if-exists',
      // All or nothing. Without this a restore that fails two thirds of the way
      // through leaves a database that is neither the old one nor the new one,
      // and no button anywhere puts that right.
      '--single-transaction',
      '--host=${config.databaseHost}',
      '--port=${config.databasePort}',
      '--username=${config.databaseUser}',
      '--no-password',
      '--dbname=${config.databaseName}',
      from.filePath,
    ]);

    if (run == null || run.exitCode != 0) {
      throw StateError(
        'The restore did not complete and the database was not changed: '
        '${run == null ? 'pg_restore could not be started' : _tail('${run.stderr}')}',
      );
    }

    await audit.record(
      by: by,
      action: AuditAction.backupRestored,
      entityType: AuditAction.entityBackup,
      entityId: from.id == null ? null : '${from.id}',
      // Both sides, in the shape the Activity pane already renders: what this
      // database was, and what it now is.
      before: {
        'orders_discarded': check.ordersSince,
        'value_discarded_minor': check.valueSince.minor,
      },
      after: {
        'restored_from': from.filePath,
        'backup_taken_at': from.takenAt.toIso8601String(),
        'checksum': from.checksum,
      },
    );

    return AdminResult.done(from);
  }

  /// `xorder_pos-20260909-231407.dump`
  ///
  /// Sortable, second-resolution, and it names the database — a folder holding
  /// two branches' copies must not need a technician to open them to tell which
  /// is which. Local time, because the person reading the folder is standing in
  /// the restaurant.
  String _fileFor(DateTime at) {
    String two(int value) => value.toString().padLeft(2, '0');
    final stamp =
        '${at.year}${two(at.month)}${two(at.day)}-'
        '${two(at.hour)}${two(at.minute)}${two(at.second)}';
    return '$directory${Platform.pathSeparator}'
        '${config.databaseName}-$stamp.dump';
  }

  Future<BackupRecord> _record({
    required PosStaff by,
    required BackupRecord entry,
  }) async {
    final stored = await backups.record(entry, by: by);
    await audit.record(
      by: by,
      action: AuditAction.backupTaken,
      entityType: AuditAction.entityBackup,
      entityId: stored.id == null ? null : '${stored.id}',
      after: {
        'outcome': stored.outcome.wire,
        'trigger': stored.trigger.wire,
        'file': stored.filePath,
        'size_bytes': stored.sizeBytes,
      },
    );
    return stored;
  }

  Future<ProcessResult?> _run(String executable, List<String> arguments) async {
    try {
      return await Process.run(
        executable,
        arguments,
        environment: {
          // Only when there is one. An empty PGPASSWORD is not the same as no
          // PGPASSWORD: it is a password, and it is wrong.
          if (password != null && password!.isNotEmpty) 'PGPASSWORD': password!,
        },
        // stdout is a table of contents we parse; stderr is diagnostics we
        // show. Neither is binary — the dump itself goes to `--file`.
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
    } on ProcessException {
      return null;
    }
  }

  /// Streamed, not read into memory. A year of a busy restaurant is a file
  /// nobody should be loading into a till's RAM to hash.
  static Future<String> _checksum(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  /// The last few lines of PostgreSQL's diagnostics.
  ///
  /// `pg_dump` can be verbose, and a column of a thousand characters in a list
  /// row is a row nobody reads. The last lines are where the reason is.
  static String _tail(String text, {int lines = 4}) {
    final kept = text.trim().split('\n');
    return (kept.length <= lines ? kept : kept.sublist(kept.length - lines))
        .join('\n')
        .trim();
  }

  static void _deleteQuietly(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } on FileSystemException {
      // Nothing to do and nothing to say: the record already carries the
      // failure, and a second error about tidying up would bury the first.
    }
  }
}

/// Where copies go when nobody has said.
///
/// Separate from [BackupService] because it is the one part of this that has to
/// answer before anything is configured — the pane shows the folder it *would*
/// use, so an operator can see it and change it before the first backup rather
/// than hunting for it afterwards.
abstract final class BackupPaths {
  /// The per-OS default, as an absolute path.
  ///
  /// Beside the application's own data rather than in Documents: a folder a
  /// person browses is a folder a person tidies, and "I deleted some big files
  /// I did not recognise" is a real way to lose a year. It is still on the same
  /// disk as the database, which protects against far less than it sounds like
  /// — see the note on [BackupService].
  static String defaultDirectory({Map<String, String>? environment}) {
    final env = environment ?? Platform.environment;
    final separator = Platform.pathSeparator;

    if (Platform.isWindows) {
      final base =
          env['LOCALAPPDATA'] ??
          env['APPDATA'] ??
          env['USERPROFILE'] ??
          r'C:\ProgramData';
      return '$base${separator}XOrder POS${separator}backups';
    }

    final home = env['HOME'] ?? '';
    if (Platform.isMacOS) {
      return '$home/Library/Application Support/XOrder POS/backups';
    }
    return '$home/.local/share/xorder-pos/backups';
  }

  /// What the service should use, given what the restaurant configured.
  static String resolve(BackupPolicy policy, {Map<String, String>? environment}) {
    final configured = policy.directory?.trim();
    return (configured == null || configured.isEmpty)
        ? defaultDirectory(environment: environment)
        : configured;
  }
}
