import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/destructive_confirm_dialog.dart';
import '../../../core/ui/widgets/mono_amount.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../data/backup/backup_service.dart'
    show BackupPaths, BackupService;
import '../../../data/backup/pg_tools.dart';
import '../../../domain/models/backup.dart';
import '../../../domain/models/permissions.dart';
import '../../../domain/models/pos_settings.dart';
import '../../../domain/models/reason_code.dart';
import '../../../domain/models/shift.dart';
import '../../../domain/services/authorization.dart';
import 'admin_messages.dart';
import 'admin_pane_bits.dart';

/// Copies of this database, and the one button that destroys everything.
///
/// **The pane says out loud what a local backup is not.** A copy on the same
/// disk as the database survives a bad edit and a dropped table, and does not
/// survive the disk failing, the machine being stolen, a fire, or a ransomware
/// run — which is most of what actually ends a restaurant's records. Off-machine
/// copying is not built; the warning strip is there because a screen that
/// implies otherwise is worse than no screen.
///
/// **And it says out loud when it cannot work at all.** `pg_dump` is a binary
/// that has to be on the machine. A backup button that silently did nothing
/// would leave a restaurant believing it had copies, so the tools are located,
/// the answer is printed, and when it is "nowhere" the pane lists the places it
/// looked in and what to install.
class ManagementBackupPane extends ConsumerStatefulWidget {
  const ManagementBackupPane({required this.admin, super.key});

  final PosStaff admin;

  @override
  ConsumerState<ManagementBackupPane> createState() =>
      _ManagementBackupPaneState();
}

class _ManagementBackupPaneState extends ConsumerState<ManagementBackupPane> {
  final _directory = TextEditingController();
  final _readerPassword = TextEditingController();
  bool _busy = false;
  String? _note;
  bool _noteIsGood = false;

  /// Whether the field has been filled from the saved setting yet.
  ///
  /// A one-shot, not a rebuild-time assignment: the settings provider re-emits
  /// after every save, and re-seeding the controller from it would yank the
  /// cursor out from under somebody typing a path.
  bool _seeded = false;

  @override
  void initState() {
    super.initState();
    // Ask again on open, so "install PostgreSQL and come back" is a thing that
    // works without restarting the till.
    //
    // After the frame, not in `initState`: `ref` reaches for an inherited
    // widget and Riverpod asserts on that here. Deferring is not a workaround —
    // the answer is wanted for the *next* frame, and the first one has nothing
    // to show until the lookup finishes anyway.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(pgToolsProvider);
    });
  }

  @override
  void dispose() {
    _directory.dispose();
    _readerPassword.dispose();
    super.dispose();
  }

  bool get _mayManage =>
      Authorization.check(widget.admin, PosCapability.backupManage).isAllowed;

  Future<void> _saveSetting(String key, String value) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(settingsRepositoryProvider)
          .save(
            key: key,
            value: value,
            // Restaurant-wide: there is one database per branch and two tills
            // disagreeing about where its copies go is two half-filled folders.
            scope: SettingScope.restaurant,
            by: widget.admin,
          );
      ref.invalidate(settingsProvider);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _note = '$error';
          _noteIsGood = false;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _backUpNow() async {
    final strings = context.strings;
    setState(() {
      _busy = true;
      _note = null;
    });

    final service = await ref.read(backupServiceProvider.future);
    if (!mounted) return;
    if (service == null) {
      setState(() => _busy = false);
      return;
    }

    final result = await service.take(
      by: widget.admin,
      trigger: BackupTrigger.manual,
    );
    if (!mounted) return;

    ref.invalidate(backupsProvider);
    setState(() {
      _busy = false;
      if (!result.succeeded) {
        _note = AdminText.refusal(strings, result.refusal!);
        _noteIsGood = false;
        return;
      }
      final record = result.value!;
      _noteIsGood = record.isRestorable;
      _note = record.isRestorable
          ? null
          : AdminText.backupFailure(strings, record.failure!);
    });
  }

  Future<void> _restore(BackupRecord record) async {
    final strings = context.strings;
    setState(() {
      _busy = true;
      _note = null;
    });

    final service = await ref.read(backupServiceProvider.future);
    if (!mounted || service == null) {
      if (mounted) setState(() => _busy = false);
      return;
    }

    final check = await service.checkRestore(record);
    if (!mounted) return;
    setState(() => _busy = false);

    // Refused while the till is still trading. Restoring mid-service is
    // unrecoverable and the person doing it does not find out until the drawer
    // fails to reconcile, hours later, with no way to reconstruct the evening.
    if (!check.isPermitted) {
      await _RestoreBlockedDialog.show(context, check);
      return;
    }

    final confirmed = await DestructiveConfirmDialog.show(
      context,
      title: strings.backupRestoreTitle(_stamp(record.takenAt)),
      confirmLabel: strings.backupRestoreConfirm,
      keepLabel: strings.backupRestoreKeep,
      // Counted, not described. "All data since 14:32" is a line somebody reads
      // past; the number of orders and what they came to is one they stop at.
      consequences: [
        strings.backupRestoreOrdersLost(
          check.ordersSince,
          check.valueSince.format(),
        ),
        strings.backupRestoreEverythingElseLost,
        strings.backupRestoreNoWayBack,
      ],
      // No reason list: there is nowhere left to record one. The audit row for
      // this lands in the database that is about to replace this one.
      requirement: ReasonRequirement.disabled,
    );
    if (confirmed == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final result = await service.restore(record, by: widget.admin);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _noteIsGood = result.succeeded;
        _note = result.succeeded
            ? strings.backupRestoreDone
            : AdminText.refusal(strings, result.refusal!);
      });
      ref.invalidate(backupsProvider);
    } on RestoreRefused catch (refused) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _noteIsGood = false;
        _note = [
          strings.backupRestoreBlocked,
          for (final blocker in refused.blockers)
            AdminText.restoreBlocker(strings, blocker),
        ].join(' · ');
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _noteIsGood = false;
        _note = strings.backupRestoreFailed('$error');
      });
    }
  }

  /// Keep the backup account's password on this machine.
  ///
  /// Not tried first, unlike the back-office password at the door: the only
  /// thing that proves it is a backup, and the next one — pressed here, or at
  /// day close — records exactly why if it is wrong.
  Future<void> _saveReaderPassword() async {
    final value = _readerPassword.text;
    if (value.isEmpty || _busy) return;
    final strings = context.strings;
    setState(() {
      _busy = true;
      _note = null;
    });
    try {
      await ref.read(backupPasswordStoreProvider).write(value);
      ref.invalidate(backupPasswordProvider);
      _readerPassword.clear();
      if (mounted) {
        setState(() {
          _note = strings.backupAccountSaved;
          _noteIsGood = true;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _note = '$error';
          _noteIsGood = false;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Put a verified copy on a USB drive — the one copy that leaves the
  /// building, and so the one checked rather than assumed.
  Future<void> _copy(BackupRecord record) async {
    final strings = context.strings;
    final destination = await FilePicker.getDirectoryPath(
      dialogTitle: strings.backupCopyAction,
    );
    if (destination == null || !mounted) return;

    setState(() {
      _busy = true;
      _note = null;
    });
    final service = await ref.read(backupServiceProvider.future);
    if (!mounted) return;
    try {
      if (service == null) throw StateError('No database on this terminal.');
      final copied = await service.copyTo(record, destination);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _noteIsGood = true;
        _note = strings.backupCopyDone(copied.path);
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _noteIsGood = false;
        _note = strings.backupCopyFailed(
          error is StateError ? error.message : '$error',
        );
      });
    }
  }

  /// A copy brought back on a drive — the case where the database that
  /// recorded it is the one that is gone. From here it is the same restore,
  /// with the same guards and the same confirmation.
  Future<void> _restoreFromFile() async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: context.strings.backupRestoreFromFile,
      type: FileType.custom,
      allowedExtensions: const ['dump'],
    );
    final path = picked.isEmpty ? null : picked.single.path;
    if (path == null || !mounted) return;

    final service = await ref.read(backupServiceProvider.future);
    if (service == null || !mounted) return;
    final described = await service.describeFile(File(path), by: widget.admin);
    if (!mounted) return;
    await _restore(described);
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;
    final policy = ref.watch(backupPolicyProvider);
    final fileExists = ref.watch(backupFileExistsProvider);
    final readerStored = ref.watch(backupPasswordProvider).valueOrNull != null;
    final tools = ref.watch(pgToolsProvider);
    final history = ref.watch(backupsProvider);

    if (!_seeded && ref.watch(settingsProvider).hasValue) {
      _seeded = true;
      // The RESOLVED folder, not the configured one. An empty box would read
      // as "backups go nowhere" when in fact there is a perfectly good default,
      // and would have somebody typing a path they did not need to.
      _directory.text = BackupPaths.resolve(policy);
    }

    return ListView(
      padding: const EdgeInsets.all(PosSpace.xl),
      children: [
        PaneSection(title: strings.paneBackup, hint: strings.paneBackupBlurb),

        // The sentence this pane exists to make impossible to miss.
        PlatformOwnedNotice(text: strings.backupSameDiskWarning),
        const SizedBox(height: PosSpace.lg),

        tools.when(
          loading: () => const SizedBox(height: 20),
          error: (error, _) => _Failure(text: '$error'),
          data: (found) => found == null
              ? const _ToolsMissing()
              : Align(
                  alignment: AlignmentDirectional.centerStart,
                  // A path and a version number, so mono and left to right in
                  // both languages — they are codes, not words.
                  child: MonoCode(
                    'pg_dump ${found.version} · ${found.pgDump}',
                    size: 12,
                  ),
                ),
        ),
        const SizedBox(height: PosSpace.lg),

        MicroLabel(strings.backupAccount),
        const SizedBox(height: PosSpace.xs),
        Text(
          strings.backupAccountHint,
          style: PosText.ui(size: 12.5, color: palette.muted, height: 1.5),
        ),
        const SizedBox(height: PosSpace.xs),
        Text(
          readerStored ? strings.backupAccountStored : strings.backupAccountMissing,
          key: const Key('backup-account-status'),
          style: PosText.ui(
            size: 12.5,
            weight: FontWeight.w600,
            color: readerStored ? palette.ok : palette.warn,
          ),
        ),
        const SizedBox(height: PosSpace.sm),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('backup-account-password'),
                controller: _readerPassword,
                obscureText: true,
                enabled: _mayManage && !_busy,
                textDirection: TextDirection.ltr,
                onSubmitted: (_) => _saveReaderPassword(),
                style: PosText.mono(size: 13, color: palette.ink),
                decoration: _boxed(palette, label: BackupService.readerRole),
              ),
            ),
            const SizedBox(width: PosSpace.sm),
            PosButton(
              key: const Key('backup-account-save'),
              label: strings.save,
              border: Border.fromBorderSide(palette.resting),
              onPressed: _mayManage && !_busy ? _saveReaderPassword : null,
            ),
          ],
        ),
        const SizedBox(height: PosSpace.lg),

        MicroLabel(strings.backupDestination),
        const SizedBox(height: PosSpace.xs),
        Text(
          strings.backupDestinationHint,
          style: PosText.ui(size: 12.5, color: palette.muted),
        ),
        const SizedBox(height: PosSpace.sm),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('backup-directory'),
                controller: _directory,
                enabled: _mayManage && !_busy,
                textDirection: TextDirection.ltr,
                style: PosText.mono(size: 13, color: palette.ink),
                decoration: InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: palette.resting,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: palette.resting,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: palette.accentBorder,
                  ),
                ),
              ),
            ),
            const SizedBox(width: PosSpace.sm),
            PosButton(
              key: const Key('backup-directory-save'),
              label: strings.save,
              border: Border.fromBorderSide(palette.resting),
              onPressed: _mayManage && !_busy
                  ? () => _saveSetting(
                      SettingKey.backupDirectory,
                      _directory.text.trim(),
                    )
                  : null,
            ),
          ],
        ),
        const SizedBox(height: PosSpace.md),

        SwitchListTile(
          key: const Key('backup-on-day-close'),
          value: policy.onDayClose,
          onChanged: _mayManage && !_busy
              ? (on) =>
                    _saveSetting(SettingKey.backupOnDayClose, on ? 'true' : 'false')
              : null,
          contentPadding: EdgeInsets.zero,
          title: Text(
            strings.backupAutomatic,
            style: PosText.ui(size: 13.5, color: palette.body),
          ),
          subtitle: Text(
            strings.backupAutomaticHint,
            style: PosText.ui(size: 11.5, color: palette.muted),
          ),
        ),
        const SizedBox(height: PosSpace.md),

        Wrap(
          spacing: PosSpace.sm,
          runSpacing: PosSpace.sm,
          children: [
            PosButton(
              key: const Key('backup-now'),
              label: _busy ? strings.backupTaking : strings.backupTakeNow,
              background: palette.accent,
              foreground: Colors.white,
              fontWeight: FontWeight.w700,
              onPressed: _mayManage && !_busy && tools.valueOrNull != null
                  ? _backUpNow
                  : null,
            ),
            PosButton(
              key: const Key('backup-restore-file'),
              label: strings.backupRestoreFromFile,
              border: Border.fromBorderSide(BorderSide(color: palette.danger)),
              foreground: palette.danger,
              onPressed: _mayManage && !_busy && tools.valueOrNull != null
                  ? _restoreFromFile
                  : null,
            ),
          ],
        ),

        if (_note != null) ...[
          const SizedBox(height: PosSpace.md),
          Text(
            _note!,
            style: PosText.ui(
              size: 12.5,
              color: _noteIsGood ? palette.ok : palette.danger,
              height: 1.5,
            ),
          ),
        ],

        const SizedBox(height: PosSpace.xl),
        MicroLabel(strings.backupHistory),
        const SizedBox(height: PosSpace.sm),
        ...history.when(
          loading: () => const [SizedBox(height: 40)],
          error: (error, _) => [_Failure(text: '$error')],
          data: (all) => [
            _Freshness(records: all),
            const SizedBox(height: PosSpace.sm),
            for (final record in all)
              if (record.isRestorable && !fileExists(record.filePath))
                _BackupRow(record: record, fileGone: true)
              else
                _BackupRow(
                  record: record,
                  onRestore: _mayManage && !_busy && record.isRestorable
                      ? () => _restore(record)
                      : null,
                  onCopy: _mayManage && !_busy && record.isRestorable
                      ? () => _copy(record)
                      : null,
                ),
          ],
        ),
      ],
    );
  }
}

/// How long it has been since this restaurant last had a real copy.
///
/// The one number on this screen that matters at a glance. A verified copy is
/// the only kind that counts here: a list full of unverified rows is a list of
/// nights the restaurant did not have a backup, and summarising it as "last
/// backup: yesterday" would be the reassuring lie.
class _Freshness extends StatelessWidget {
  const _Freshness({required this.records});

  final List<BackupRecord> records;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;

    if (records.isEmpty) {
      return _Strip(text: strings.backupNoneYet, tone: palette.warn);
    }

    final verified = records.where((r) => r.isRestorable).toList();
    if (verified.isEmpty) {
      return _Strip(text: strings.backupNoVerifiedCopy, tone: palette.danger);
    }

    final newest = verified.first;
    final days = newest.ageAt(DateTime.now()).inDays;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.backupLastVerified(_stamp(newest.takenAt)),
          style: PosText.ui(size: 12.5, color: palette.muted),
        ),
        // Two days, not one: a restaurant that closes Sunday should not be
        // shouted at on Monday morning for a Saturday backup.
        if (days >= 2) ...[
          const SizedBox(height: PosSpace.xs),
          _Strip(text: strings.backupStale(days), tone: palette.warn),
        ],
      ],
    );
  }
}

class _BackupRow extends StatelessWidget {
  const _BackupRow({
    required this.record,
    this.onRestore,
    this.onCopy,
    this.fileGone = false,
  });

  final BackupRecord record;
  final VoidCallback? onRestore;
  final VoidCallback? onCopy;

  /// A verified copy whose file has since been pruned. Still shown — the
  /// record of it having existed is the point of the list — but with nothing
  /// to press, because there is nothing left to restore or copy.
  final bool fileGone;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;
    // Elevation is a border here, so an unusable row is a red edge rather than
    // a grey card.
    final tone = switch (record.outcome) {
      BackupOutcome.verified => palette.ok,
      BackupOutcome.unverified => palette.danger,
      BackupOutcome.failed => palette.warn,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: PosSpace.xs),
      padding: const EdgeInsets.symmetric(
        vertical: PosSpace.sm,
        horizontal: PosSpace.sm,
      ),
      decoration: BoxDecoration(
        border: BorderDirectional(
          bottom: palette.hairline,
          start: BorderSide(color: tone, width: 2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: MonoCode(_stamp(record.takenAt), size: 12),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AdminText.backupOutcome(strings, record.outcome),
                  style: PosText.ui(
                    size: 13,
                    weight: FontWeight.w700,
                    color: tone,
                  ),
                ),
                const SizedBox(height: PosSpace.xs),
                Text(
                  '${record.takenByName} · '
                  '${AdminText.backupTrigger(strings, record.trigger)}',
                  style: PosText.ui(size: 12, color: palette.muted),
                ),
                if (record.failure != null) ...[
                  const SizedBox(height: PosSpace.xs),
                  Text(
                    AdminText.backupFailure(strings, record.failure!),
                    style: PosText.ui(
                      size: 12,
                      color: palette.body,
                      height: 1.4,
                    ),
                  ),
                ],
                if (record.detail != null) ...[
                  const SizedBox(height: PosSpace.xs),
                  // PostgreSQL's own words, untranslated and in mono. This is
                  // the line a technician pastes into a search box.
                  MonoCode(record.detail!, size: 11),
                ],
                const SizedBox(height: PosSpace.xs),
                MonoCode(record.filePath, size: 11),
              ],
            ),
          ),
          SizedBox(
            width: 110,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                MonoCode(AdminText.bytes(record.sizeBytes), size: 12),
                if (record.tablesFound > 0) ...[
                  const SizedBox(height: PosSpace.xs),
                  Text(
                    strings.backupTablesFound(record.tablesFound),
                    style: PosText.ui(size: 11.5, color: palette.muted),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: PosSpace.sm),
          SizedBox(
            width: 110,
            // Absent, not disabled, on a row that is not a backup: a Restore
            // button beside a file nobody could restore from is an invitation
            // to try it at the worst possible moment.
            child: !record.isRestorable
                ? null
                : fileGone
                ? Text(
                    strings.backupFileGone,
                    style: PosText.ui(
                      size: 11,
                      color: palette.muted,
                      height: 1.4,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PosButton(
                        label: strings.backupRestoreAction,
                        border: Border.fromBorderSide(
                          BorderSide(color: palette.danger),
                        ),
                        foreground: palette.danger,
                        onPressed: onRestore,
                      ),
                      const SizedBox(height: PosSpace.xs),
                      PosButton(
                        key: Key('backup-copy-${record.id}'),
                        label: strings.backupCopyAction,
                        border: Border.fromBorderSide(palette.resting),
                        onPressed: onCopy,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// What the pane says when `pg_dump` is nowhere on the machine.
class _ToolsMissing extends ConsumerWidget {
  const _ToolsMissing();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.strings;
    final palette = context.pos;

    return Container(
      padding: const EdgeInsets.all(PosSpace.md),
      color: palette.dangerSoft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.backupToolsMissing,
            style: PosText.ui(size: 13, color: palette.danger, height: 1.5),
          ),
          const SizedBox(height: PosSpace.xs),
          Text(
            strings.backupToolsMissingHelp,
            style: PosText.ui(size: 12.5, color: palette.body, height: 1.5),
          ),
          const SizedBox(height: PosSpace.sm),
          MicroLabel(strings.backupSearchedIn),
          const SizedBox(height: PosSpace.xs),
          // The places, not just the verdict. "pg_dump was not found" sends
          // somebody to a search engine; the list sends them to the folder.
          MonoCode(
            PgTools.searchPath().take(8).join('\n'),
            size: 11,
          ),
        ],
      ),
    );
  }
}

/// Why a restore cannot happen yet, named and counted.
class _RestoreBlockedDialog extends StatelessWidget {
  const _RestoreBlockedDialog({required this.check});

  final RestoreCheck check;

  static Future<void> show(BuildContext context, RestoreCheck check) =>
      showDialog<void>(
        context: context,
        builder: (_) => _RestoreBlockedDialog(check: check),
      );

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;

    return Dialog(
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: PosSize.dialogCount),
        child: Padding(
          padding: const EdgeInsets.all(PosSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings.backupRestoreBlocked,
                style: PosText.ui(
                  size: 17,
                  weight: FontWeight.w800,
                  color: palette.ink,
                ),
              ),
              const SizedBox(height: PosSpace.md),
              for (final blocker in check.blockers)
                Container(
                  margin: const EdgeInsets.only(bottom: PosSpace.xs),
                  padding: const EdgeInsets.all(PosSpace.sm),
                  decoration: BoxDecoration(
                    color: palette.warnSoft,
                    border: BorderDirectional(
                      start: BorderSide(color: palette.warn, width: 2),
                    ),
                  ),
                  child: Text(
                    AdminText.restoreBlocker(strings, blocker),
                    style: PosText.ui(size: 13, color: palette.body),
                  ),
                ),
              const SizedBox(height: PosSpace.lg),
              PosButton(
                label: strings.close,
                border: Border.fromBorderSide(palette.resting),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Strip extends StatelessWidget {
  const _Strip({required this.text, required this.tone});

  final String text;
  final Color tone;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(PosSpace.sm),
    decoration: BoxDecoration(
      border: BorderDirectional(start: BorderSide(color: tone, width: 2)),
    ),
    child: Text(text, style: PosText.ui(size: 12.5, color: tone, height: 1.5)),
  );
}

class _Failure extends StatelessWidget {
  const _Failure({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: PosText.ui(size: 12.5, color: context.pos.danger));
}

/// Western digits in both languages, as everywhere else in the till.
String _stamp(DateTime at) {
  final local = at.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

/// The pane's boxed field: square, hairline at rest, accent when focused.
InputDecoration _boxed(PosPalette palette, {String? label}) => InputDecoration(
  isDense: true,
  labelText: label,
  labelStyle: PosText.mono(size: 12, color: palette.muted),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.zero,
    borderSide: palette.resting,
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.zero,
    borderSide: palette.resting,
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.zero,
    borderSide: palette.accentBorder,
  ),
);
