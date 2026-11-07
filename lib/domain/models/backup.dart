/// Copies of the branch database, and what is actually known about each one.
///
/// **A dump nobody has read back is not a backup.** The whole reason this file
/// carries an outcome rather than a boolean is that the interesting state is
/// the middle one: a file exists, it has a size, and `pg_restore` could not
/// list it. That row must read as *not a backup* on the screen, because the
/// business's belief that it has one is the thing that costs them the year.
library;

import '../../core/money/money.dart';
import 'pos_settings.dart';

/// What caused a copy to be taken.
///
/// Recorded because "we take one every night" and "somebody took one in March"
/// are different claims about the same table, and only the row can tell them
/// apart.
enum BackupTrigger {
  /// Somebody pressed the button in Management.
  manual('manual'),

  /// The trading day was closed. See `DayCloseDialog` for why that is the hook.
  dayClose('day_close');

  const BackupTrigger(this.wire);

  final String wire;

  static BackupTrigger fromWire(String value) {
    for (final trigger in BackupTrigger.values) {
      if (trigger.wire == value) return trigger;
    }
    // A trigger from a newer build. Manual is the honest fallback: it says a
    // person is not promised this will happen again.
    return BackupTrigger.manual;
  }
}

/// How much of a backup this row actually is.
///
/// Three states, not two, and the middle one is the point. See the library
/// comment.
enum BackupOutcome {
  /// Written, checksummed, and `pg_restore --list` read it back and found the
  /// tables a business would need. The only state [BackupRecord.isRestorable]
  /// is true in.
  verified('verified'),

  /// A file was produced and the verification did not confirm it — truncated,
  /// written to a full disk, or missing tables. **Not a backup**, and the list
  /// says so in those words.
  unverified('unverified'),

  /// `pg_dump` never produced a usable file: not installed, refused by the
  /// server, or nowhere to write. [BackupRecord.note] carries what to do.
  failed('failed');

  const BackupOutcome(this.wire);

  final String wire;

  static BackupOutcome fromWire(String value) {
    for (final outcome in BackupOutcome.values) {
      if (outcome.wire == value) return outcome;
    }
    // An outcome this build does not know is treated as unproven rather than
    // as proven. A backup wrongly believed good is the failure this whole
    // feature exists to prevent.
    return BackupOutcome.unverified;
  }
}

/// Why a copy is not a copy.
///
/// **An enum, and the sentence lives in `AppStrings`.** The first draft stored
/// the message — which would have put an English sentence in the database and
/// printed it to a business working in Arabic, and would have frozen the
/// wording of a row written in 2026 into every screen that ever reads it. The
/// raw output of `pg_dump` still travels beside this, in
/// [BackupRecord.detail], because PostgreSQL's own diagnostics are what a
/// technician needs and translating them would be inventing meaning.
enum BackupFailure {
  /// `pg_dump` and `pg_restore` are not on this machine.
  toolsMissing('tools_missing'),

  /// Nowhere to write: the folder does not exist, or is not writable by the
  /// account the till runs as.
  destinationUnwritable('destination_unwritable'),

  /// `pg_dump` ran and refused — a credential, a permission, a full disk.
  dumpRefused('dump_refused'),

  /// A file exists and `pg_restore --list` cannot read it. The commonest cause
  /// is a dump that ran out of disk halfway, which leaves a plausible-looking
  /// file of plausible-looking size.
  archiveUnreadable('archive_unreadable'),

  /// Readable, and missing tables a business could not trade without.
  archiveIncomplete('archive_incomplete');

  const BackupFailure(this.wire);

  final String wire;

  static BackupFailure? fromWire(String? value) {
    if (value == null) return null;
    for (final failure in BackupFailure.values) {
      if (failure.wire == value) return failure;
    }
    return null;
  }
}

/// One attempt at copying the database, as it is recorded and read back.
///
/// Names as well as ids, for the same reason `AuditEntry` denormalises them: a
/// row has to still make sense once the person who took it has left.
class BackupRecord {
  const BackupRecord({
    required this.takenAt,
    required this.takenByName,
    required this.trigger,
    required this.outcome,
    required this.filePath,
    this.id,
    this.takenById,
    this.sizeBytes = 0,
    this.checksum,
    this.tablesFound = 0,
    this.failure,
    this.detail,
  });

  final int? id;

  final DateTime takenAt;
  final int? takenById;
  final String takenByName;

  final BackupTrigger trigger;
  final BackupOutcome outcome;

  /// Absolute, and kept even for a [BackupOutcome.failed] row: "we tried to
  /// write here and could not" is the sentence that gets the disk fixed.
  final String filePath;

  /// Bytes on disk. Zero when nothing was written.
  ///
  /// An `int`, like everything else countable here — see `Money` and
  /// `Quantity`. A `double` would start losing whole bytes at 9 petabytes,
  /// which is not the reason; the reason is that this codebase does not put
  /// counted things in floating point.
  final int sizeBytes;

  /// SHA-256 of the file, lower-case hex. Null when there is no file.
  ///
  /// Its job is *this* comparison and no other: the row says what was on disk
  /// when it was written, so a file that has since been replaced or truncated
  /// can be told apart from the one this row is about.
  final String? checksum;

  /// How many tables `pg_restore --list` found in the archive.
  final int tablesFound;

  /// What went wrong. Null when nothing did.
  final BackupFailure? failure;

  /// PostgreSQL's own words, kept verbatim and shown in mono.
  ///
  /// Untranslated on purpose — the same decision as `CatalogInvalid`. This is
  /// the line a technician pastes into a search, and a paraphrase of it in
  /// Arabic would help nobody and mislead somebody.
  final String? detail;

  bool get isRestorable => outcome == BackupOutcome.verified;

  /// How old this copy is, as of [now].
  Duration ageAt(DateTime now) => now.difference(takenAt);
}

/// Where copies go, and whether one is taken at the end of the day.
///
/// The same shape as `DayPolicy` and `CashPolicy`: a value object per decision,
/// with the default baked in, so nothing outside `PosSettings` asks for a key
/// by name.
class BackupPolicy {
  const BackupPolicy({this.directory, this.onDayClose = true});

  /// Automatic backups **on** by default.
  ///
  /// The opposite of the drawer settings, where the safe default is the one
  /// that surprises nobody. Here the surprising outcome is the silent one: a
  /// business that never opened this pane and never took a copy has no idea
  /// it has no copy, and finds out from a dead disk.
  static const defaults = BackupPolicy();

  factory BackupPolicy.from(PosSettings settings) => BackupPolicy(
    directory: settings.text(SettingKey.backupDirectory),
    onDayClose: settings.boolean(SettingKey.backupOnDayClose, orElse: true),
  );

  /// Null means "wherever this operating system's default is" — resolved in
  /// the data layer, because the domain has no business knowing about
  /// `Platform`.
  final String? directory;

  final bool onDayClose;
}

/// Why a restore cannot happen yet.
///
/// Data rather than a sentence, the same shape as `DayBlocker`, so the screen
/// can name each obstacle and count it.
class RestoreBlocker {
  const RestoreBlocker({required this.kind, required this.count});

  final RestoreBlockerKind kind;
  final int count;
}

enum RestoreBlockerKind {
  /// A till has a drawer open. Restoring now replaces the shift row underneath
  /// the cash in the drawer, and nobody finds out until the count does not
  /// reconcile — by which time the evening is unreconstructable.
  openShift,

  /// The trading day has not been closed. Same problem one level up: the day's
  /// takings would be replaced by a day that had not happened yet.
  openBusinessDay,

  /// Sales or cash events this database still owes the platform — on a cloud
  /// terminal only. The copy being restored predates them, so the rows that
  /// would have carried them up are among the rows the restore drops, and the
  /// platform never hears about money that changed hands (scenario D3).
  ///
  /// **A blocker in cloud mode and a warning offline, deliberately not the
  /// same everywhere.** Offline the outbox is never drained, so a count there
  /// is a leftover from a terminal that used to be cloud — refusing on it would
  /// lock somebody out of their own backups with nothing they could do to clear
  /// it. Rows the platform *rejected* (quarantined) are not a blocker in either
  /// mode: they wait on a person rather than on the network, so refusing on
  /// them would be the same lock-out — see [RestoreCheck.heldSync].
  pendingSync,
}

/// What restoring [from] would cost, in the concrete terms a person can weigh.
///
/// **Counted, not described.** "All data since 14:32" is a sentence somebody
/// reads past; "217 orders worth 41,880.00 will be discarded" is a number they
/// stop at. The count comes from reading the rows, so it is the business's
/// own evening rather than an estimate.
class RestoreCheck {
  const RestoreCheck({
    required this.from,
    required this.blockers,
    required this.ordersSince,
    required this.valueSince,
    this.lastOrderAt,
    this.pendingSync = 0,
    this.heldSync = 0,
  });

  final BackupRecord from;
  final List<RestoreBlocker> blockers;

  /// Orders settled after [BackupRecord.takenAt] — the ones the restore throws
  /// away.
  final int ordersSince;

  /// What those orders came to. Minor units, like every other amount here.
  final Money valueSince;

  final DateTime? lastOrderAt;

  /// Rows in `pos_outbox` and `pos_sync_outbox` not yet delivered and not held
  /// — what this terminal still means to send. On a cloud terminal a non-zero
  /// count is also a [RestoreBlockerKind.pendingSync] blocker; offline it is
  /// only said, because nothing there would ever send it.
  final int pendingSync;

  /// Rows the platform refused and that wait for a person (quarantined, never
  /// delivered). A warning in every mode: the restore drops them with the rest,
  /// and the only record of what they were is then the safety copy taken just
  /// before.
  final int heldSync;

  /// Whether the restore may proceed at all. Not "whether it is wise".
  bool get isPermitted => blockers.isEmpty;
}

/// The copy of *this* database that a restore takes first could not be made.
///
/// Thrown, like [RestoreRefused], because a caller must be unable to read past
/// it — and not an `AdminRefusal`, because nothing about the person or the
/// request is wrong: the disk, the folder or `pg_dump` is. [attempt] is
/// the row that records it, so the screen can name the same [BackupFailure]
/// the backup list does and show PostgreSQL's own words beside it.
class RestoreSnapshotFailed implements Exception {
  const RestoreSnapshotFailed(this.attempt);

  final BackupRecord attempt;

  @override
  String toString() =>
      'RestoreSnapshotFailed(${attempt.failure?.wire ?? attempt.outcome.wire}'
      '${attempt.detail == null ? '' : ': ${attempt.detail}'})';
}

/// The refusal a restore comes back with when it must not run.
///
/// A thrown type rather than a bool, because every caller must be unable to
/// ignore it: a restore that silently did nothing would leave a manager
/// believing the database had been replaced.
class RestoreRefused implements Exception {
  const RestoreRefused(this.blockers);

  final List<RestoreBlocker> blockers;

  @override
  String toString() =>
      'RestoreRefused(${[for (final b in blockers) '${b.kind.name}:${b.count}'].join(', ')})';
}
