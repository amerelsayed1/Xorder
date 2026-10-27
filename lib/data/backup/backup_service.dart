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
import 'pg_archive.dart';
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
    this.reader,
    this.restorer,
    this.quiesce,
    this.currency = 'EGP',
    this.exponent = 2,
    this.keep = 14,
    ProcessRunner? run,
  }) : _db = database,
       _runner = run;

  final PosDatabase _db;

  /// Where the attempt is written down, whichever way it went.
  final BackupRepository backups;

  final AuditRepository audit;


  /// The connection the guard queries, the record and the audit row run on.
  /// The **till's**, deliberately: a backup is taken at day close by a machine on which nobody
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

  /// Who `pg_dump` connects as: [readerRole], on the till's own host and
  /// database, with the password kept for it on this machine.
  ///
  /// **A dedicated account, because neither of the other two can do this
  /// job.** The till's credential holds SELECT on the tables it sells from and
  /// not on all of them, and a dump that silently omitted a table is the exact
  /// failure this feature exists to prevent. The administrator's password is
  /// kept in the operating system's secret store (`adminDbSecretStoreProvider`
  /// — saved at install, or the first time it is typed at the back-office
  /// door), but it is loaded into a connection only for the length of an
  /// Admin Mode session — and the nightly copy is taken at day close, when
  /// nobody has opened the back office. Nor is a credential that can rewrite
  /// every table the one to leave running unattended. So the backup runs as a member of `pg_read_all_data` and nothing
  /// else: it can read every row and change none, which makes it the one
  /// credential it is safe to keep beside the till's.
  ///
  /// Null only when this terminal has no database to copy.
  final BackupConnection? reader;

  /// Who a restore connects as: the database's owner, with the password
  /// supplied this session. Null until somebody has — and a restore is only
  /// ever started from the back office, which asks for it at the door.
  final BackupConnection? restorer;

  /// How many verified copies the folder keeps before the oldest goes. Two
  /// weeks of day closes: long enough to notice a mistake made last week, short
  /// enough that the folder cannot quietly fill the disk it is protecting.
  final int keep;

  final ProcessRunner? _runner;

  /// The read-only account the installer creates for backups.
  static const readerRole = 'pos_backup';

  /// What a safety copy taken by [restore] is called before the usual name.
  static const preRestorePrefix = 'pre-restore-';

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
    'pos_users',
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
    bool preRestore = false,
    BackupConnection? using,
  }) async {
    final at = DateTime.now();
    final path = _fileFor(at, preRestore: preRestore);

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

    final from = using ?? reader;
    if (from == null) {
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
          detail: 'This terminal has no database connection to copy from.',
        ),
      );
    }

    final String contents;
    try {
      contents = await PgArchive(tools, run: _runner).dump(
        from: from,
        to: File(path),
      );
    } on ArchiveFailure catch (failure) {
      // Nothing is left on disk either way: `PgArchive` writes to `.part` and
      // throws the part away. A file with a plausible name and a plausible size
      // that cannot be read is precisely what somebody restores from in a panic.
      final unreadable = failure.kind == ArchiveFailureKind.unreadable;
      return _record(
        by: by,
        entry: BackupRecord(
          takenAt: at,
          takenByName: by.name,
          takenById: by.id,
          trigger: trigger,
          outcome: unreadable ? BackupOutcome.unverified : BackupOutcome.failed,
          filePath: path,
          sizeBytes: failure.sizeBytes ?? 0,
          failure: unreadable
              ? BackupFailure.archiveUnreadable
              : BackupFailure.dumpRefused,
          detail: unreadable
              ? failure.detail
              : explainRefusal(failure.detail, user: from.user),
        ),
      );
    }

    final file = File(path);
    final size = file.lengthSync();
    final checksum = await _checksum(file);

    final tables = tablesIn(contents);
    final missing = [
      for (final wanted in essentialTables)
        if (!tables.contains(wanted)) wanted,
    ];

    final stored = await _record(
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

    // Only after a copy that counts. Pruning after a failure would delete a
    // good old copy to make room for a bad new one.
    //
    // And never for the copy a restore takes first: the oldest file in the
    // folder may be the very one about to be restored from, and housekeeping
    // that deleted it would turn a safety step into the reason the restore
    // fails. Its own name is outside the prefix, so later prunes pass it by too.
    if (stored.isRestorable && !preRestore) {
      try {
        PgArchive.prune(
          Directory(directory),
          prefix: '${config.databaseName}-',
          keep: keep,
        );
      } on FileSystemException {
        // A copy that could not be tidied away is still a copy. The folder
        // growing is visible; a failed backup caused by housekeeping is not.
      }
    }
    return stored;
  }

  /// PostgreSQL's refusal, with the one next step it cannot know.
  ///
  /// The commonest refusal on a new install is the backup account itself — not
  /// created yet, or no password entered on this machine — and PostgreSQL's
  /// wording for that names the role but not where to fix it.
  static String explainRefusal(String? detail, {required String user}) {
    final said = detail ?? '';
    final aboutTheAccount =
        said.contains('password authentication failed') ||
        said.contains('no password supplied') ||
        said.contains('role "$user" does not exist');
    if (!aboutTheAccount) return said;
    return '$said\n'
        'Backups sign in as "$user": enter its password under Backup account, '
        'or ask whoever installed PostgreSQL to create it — see the offline '
        'install runbook, "The backup account".';
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
  /// **The guards are read here rather than enforced by a trigger, and that is
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
            AND o.received_at > @since),
        -- Owed to the platform, across BOTH queues: a refund or a shift close
        -- that never went up is as lost as a sale. The predicate is the one
        -- `pos_sync_outbox_pending_idx` is built on, so "pending" here means
        -- what the drain means by it.
        (SELECT count(*) FROM pos_outbox q
          WHERE q.restaurant_id = @restaurant AND q.branch_id = @branch
            AND q.delivered_at IS NULL AND q.quarantined_at IS NULL)
        + (SELECT count(*) FROM pos_sync_outbox q
          WHERE q.restaurant_id = @restaurant AND q.branch_id = @branch
            AND q.delivered_at IS NULL AND q.quarantined_at IS NULL),
        -- Refused by the platform and waiting on a person. Never delivered, so
        -- just as lost to a restore — counted apart because it is a warning,
        -- not a blocker; see `RestoreBlockerKind.pendingSync`.
        (SELECT count(*) FROM pos_outbox q
          WHERE q.restaurant_id = @restaurant AND q.branch_id = @branch
            AND q.delivered_at IS NULL AND q.quarantined_at IS NOT NULL)
        + (SELECT count(*) FROM pos_sync_outbox q
          WHERE q.restaurant_id = @restaurant AND q.branch_id = @branch
            AND q.delivered_at IS NULL AND q.quarantined_at IS NOT NULL)
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
    final pendingSync = counts[5] as int? ?? 0;
    final heldSync = counts[6] as int? ?? 0;

    // Decided by the mode and not by the count alone. An offline terminal never
    // drains its outbox, so anything in it is a leftover from a past life as a
    // cloud till — refusing on it would be a lock-out with no way to clear it,
    // where on a cloud till the way to clear it is to let it finish sending.
    final owesThePlatform =
        config.mode == DeploymentMode.cloud && pendingSync > 0;

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
        if (owesThePlatform)
          RestoreBlocker(
            kind: RestoreBlockerKind.pendingSync,
            count: pendingSync,
          ),
      ],
      ordersSince: counts[2] as int? ?? 0,
      valueSince: Money(
        counts[3] as int? ?? 0,
        currency: currency,
        exponent: exponent,
      ),
      lastOrderAt: (counts[4] as DateTime?)?.toLocal(),
      pendingSync: pendingSync,
      heldSync: heldSync,
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
  ///
  /// **And a copy of this database is taken first, every time** — see
  /// [preRestorePrefix] for its name. If it cannot be taken the restore does
  /// not happen ([RestoreSnapshotFailed]). Thrown rather than returned as a
  /// refusal, like [RestoreRefused] and every other precondition here: an
  /// `AdminRefusal` says the person may not, and nothing about the person is
  /// wrong — the disk, the folder or `pg_dump` is. Its path goes in the
  /// audit row, because that row is written into the restored database and so
  /// is the one record of it that survives.
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

    // Checked before the safety copy as well as after it, so a restore that
    // was never going to be allowed does not cost a full dump to find out.
    final early = await checkRestore(from);
    if (!early.isPermitted) throw RestoreRefused(early.blockers);

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

    final into = restorer;
    if (into == null) {
      throw StateError(
        'Restoring needs the back-office database password, and none has been '
        'entered this session.',
      );
    }

    // A copy of what is about to be replaced, taken through the same path as
    // every other backup, verified and recorded the same way. **No safety
    // copy, no restore.** The alternative was to warn and carry on, which is
    // the shape of the incident this exists for (D3): an older file put back
    // over an evening nobody had uploaded, and nothing left anywhere that held
    // it. A restore that waits for the disk or the folder to be fixed
    // costs minutes; one that went ahead without the copy costs the evening,
    // and is the one an owner rings about. Unverified counts as failed here,
    // for the reason it does in the list: a file `pg_restore` cannot read is
    // not a way back.
    //
    // **Dumped as the restorer, not as [reader].** The owner's password is
    // already in hand — the restore cannot run without it — and it can read
    // every object it is about to drop. The backup account's password is kept
    // per machine, and the restore that matters most is the one on a
    // replacement till brought up from a USB copy, where nobody has entered it
    // yet; demanding it there would turn the safety step into a lock-out.
    final safety = await _take(
      by: by,
      trigger: BackupTrigger.manual,
      preRestore: true,
      using: into,
    );
    if (!safety.isRestorable) throw RestoreSnapshotFailed(safety);

    // Again, now: the copy took seconds, and a shift opened at the next till
    // during them is exactly the race the first check cannot see.
    final check = await checkRestore(from);
    if (!check.isPermitted) throw RestoreRefused(check.blockers);

    // Let go of every pooled connection first. An idle session holds no locks,
    // so this is belt and braces rather than a fix — but `--clean` drops every
    // object in the database and the failure mode if it does block is a till
    // frozen mid-restore, which is the one state worse than not having started.
    await quiesce?.call();

    try {
      // Read in full first, then all or nothing — see `PgArchive.restore`.
      await PgArchive(tools, run: _runner).restore(from: file, into: into);
    } on ArchiveFailure catch (failure) {
      throw StateError(
        'The restore did not complete and the database was not changed: '
        '${failure.detail ?? failure.kind.name}',
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
        'sync_pending_discarded': check.pendingSync,
        'sync_held_discarded': check.heldSync,
      },
      after: {
        'restored_from': from.filePath,
        'backup_taken_at': from.takenAt.toIso8601String(),
        'checksum': from.checksum,
        // The only durable pointer to it: the `pos_backups` row the safety
        // copy wrote went with the database it described.
        'pre_restore_snapshot': safety.filePath,
        'pre_restore_checksum': safety.checksum,
      },
    );

    return AdminResult.done(from);
  }

  /// Copy a verified backup somewhere else — a USB drive — and prove the copy.
  ///
  /// **The copy is what leaves the building, so it is checked, not assumed.**
  /// A stick pulled out a second early, or a full one, leaves a file with the
  /// right name that is not the backup; so the copy is written to `.part`, its
  /// checksum compared with the one recorded when the original was verified,
  /// and only then given the name. Same checksum, same bytes — the copy is as
  /// good as the verified original, without running `pg_restore` over a slow
  /// drive.
  ///
  /// Not recorded in `pos_backups`: that table is a record of copies taken of
  /// this database, and this is the same copy in a second place.
  Future<File> copyTo(BackupRecord record, String destination) async {
    if (!record.isRestorable) {
      throw StateError(
        'That copy failed verification when it was taken, so it is not a '
        'backup and there is nothing worth copying.',
      );
    }
    final source = File(record.filePath);
    if (!source.existsSync()) {
      throw StateError('The backup file is no longer at ${record.filePath}.');
    }

    final name = source.uri.pathSegments.last;
    final target = File('$destination${Platform.pathSeparator}$name');
    final part = File('${target.path}.part');
    try {
      await source.copy(part.path);
      final copied = await _checksum(part);
      if (record.checksum != null && copied != record.checksum) {
        throw StateError(
          'The copy at ${target.path} does not match the backup — the drive '
          'may be full, failing or removed too early. Nothing was kept there.',
        );
      }
      if (target.existsSync()) await target.delete();
      await part.rename(target.path);
    } finally {
      if (part.existsSync()) await part.delete();
    }
    return target;
  }

  /// A backup file brought from somewhere else — a USB drive, another till —
  /// described the way a restore needs it.
  ///
  /// **Nothing here is taken on trust.** The file has no row in this database
  /// (the database it was recorded in may be the one that died), so it is
  /// described as the file claims to be, and [restore] then does what it always
  /// does: reads it in full before touching anything, and refuses one that does
  /// not read. When it was taken comes from its name where the name is one of
  /// ours — that is what the orders-since count is measured from — and from
  /// the file's own date otherwise. A name knows only the second, and is read
  /// as the start of it: an order earlier in that same second is counted as
  /// lost when it is not, which is the direction that warning can afford to be
  /// wrong in.
  Future<BackupRecord> describeFile(File file, {required PosStaff by}) async {
    final name = file.uri.pathSegments.last;
    final stamp = RegExp(
      r'(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})(\d{2})\.dump$',
    ).firstMatch(name);
    final takenAt = stamp == null
        ? file.lastModifiedSync()
        : DateTime(
            int.parse(stamp.group(1)!),
            int.parse(stamp.group(2)!),
            int.parse(stamp.group(3)!),
            int.parse(stamp.group(4)!),
            int.parse(stamp.group(5)!),
            int.parse(stamp.group(6)!),
          );

    return BackupRecord(
      takenAt: takenAt,
      takenByName: by.name,
      takenById: by.id,
      trigger: BackupTrigger.manual,
      // Verified in the only sense a restore relies on: the checksum below is
      // this file's, so the file restored is the file described. Whether it
      // READS is decided by the restore itself, before anything is dropped.
      outcome: BackupOutcome.verified,
      filePath: file.path,
      sizeBytes: file.lengthSync(),
      checksum: await _checksum(file),
    );
  }

  /// `xorder_pos-20260909-231407.dump`
  ///
  /// Sortable, second-resolution, and it names the database — a folder holding
  /// two branches' copies must not need a technician to open them to tell which
  /// is which. Local time, because the person reading the folder is standing in
  /// the restaurant.
  ///
  /// The copy a restore takes first is `pre-restore-xorder_pos-….dump`. **The
  /// name is the label, because nothing else could carry it.** `trigger_kind`
  /// is CHECKed to `manual`/`day_close`, and widening that is a migration for a
  /// row that does not survive anyway — it is written into the database the
  /// restore then replaces. The file is what survives, so the file says what it
  /// is. A prefix rather than a suffix for two reasons: [describeFile] reads
  /// the time off the end of the name, so "Restore from a file…" undoes a
  /// restore like any other copy; and [PgArchive.prune] matches on the
  /// database's own prefix, so these are never counted against [keep] — a
  /// suffix would have counted them among the nightly copies, and a few
  /// attempts at a restore would have pushed real ones out of the folder.
  String _fileFor(DateTime at, {bool preRestore = false}) {
    String two(int value) => value.toString().padLeft(2, '0');
    final stamp =
        '${at.year}${two(at.month)}${two(at.day)}-'
        '${two(at.hour)}${two(at.minute)}${two(at.second)}';
    return '$directory${Platform.pathSeparator}'
        '${preRestore ? preRestorePrefix : ''}'
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

  /// Streamed, not read into memory. A year of a busy restaurant is a file
  /// nobody should be loading into a till's RAM to hash.
  static Future<String> _checksum(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();
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
