import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/backup.dart';
import '../../../domain/models/business_day.dart';
import '../../../domain/models/permissions.dart';
import '../../../domain/models/shift.dart';
import '../../../domain/services/authorization.dart';
import '../../admin/presentation/supervisor_override.dart';

/// Ending the trading day (§28).
///
/// **The blocker list is the screen.** A close that refused without saying what
/// was in the way would send a manager hunting through four screens at
/// midnight; one that closed silently over open tables would lose the evening's
/// last hour. So it names each thing, counts it, and offers exactly two ways
/// forward: settle them, or say why you are not going to.
class DayCloseDialog extends ConsumerStatefulWidget {
  const DayCloseDialog({super.key});

  /// Returns the closed day, or null if nothing was closed.
  static Future<BusinessDay?> show(BuildContext context) =>
      showDialog<BusinessDay>(
        context: context,
        builder: (_) => const DayCloseDialog(),
      );

  @override
  ConsumerState<DayCloseDialog> createState() => _DayCloseDialogState();
}

class _DayCloseDialogState extends ConsumerState<DayCloseDialog> {
  final _reason = TextEditingController();
  DayCloseCheck? _check;
  bool _busy = true;
  String? _error;

  /// Set once the day is actually closed.
  ///
  /// The dialog can outlive the close by a few seconds — it stays open to
  /// report a backup that did not work — and the caller must still be handed
  /// the closed day when it finally goes. Without this the manager would press
  /// the only remaining button and the screen behind would carry on believing
  /// the day was open.
  BusinessDay? _closed;

  /// Take the automatic copy, if the restaurant asked for one.
  ///
  /// **Day close is the hook rather than a scheduler, and that is a decision.**
  /// A scheduler on a till is a background job on a machine somebody switches
  /// off at night, whose failures nobody sees and whose window lands in the
  /// middle of service if the restaurant trades late. Day close is the one
  /// moment that is *already* defined as "the day's data is complete and no
  /// shift is open", it happens exactly once per trading day, and a person is
  /// standing there to be told when it goes wrong. The cost is honest and worth
  /// naming: a restaurant that never closes its day never gets a copy — and
  /// that restaurant has a worse problem than backups, which the day-close
  /// blocker list already puts in front of them.
  ///
  /// Returns whether there is now a copy worth the name.
  Future<bool> _backUp(PosStaff by) async {
    if (!ref.read(backupPolicyProvider).onDayClose) return true;

    final service = await ref.read(backupServiceProvider.future);
    if (service == null) return true; // No database; nothing to copy.

    final result = await service.take(by: by, trigger: BackupTrigger.dayClose);
    ref.invalidate(backupsProvider);
    // A refusal cannot happen for an automatic copy — `take` only checks the
    // capability for a manual one, deliberately, so that the nightly backup
    // does not depend on who was closing. Handled anyway rather than asserted
    // away: a `!` here would be a crash at midnight.
    return result.succeeded && result.value!.isRestorable;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final check = await ref.read(businessDayRepositoryProvider).check();
      if (!mounted) return;
      setState(() {
        _check = check;
        _busy = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;
    final check = _check;

    return Dialog(
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: PosSize.dialogCount),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(PosSpace.lg),
              decoration: BoxDecoration(
                border: BorderDirectional(bottom: palette.resting),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.dayCloseTitle,
                    style: PosText.ui(
                      size: 20,
                      weight: FontWeight.w800,
                      color: palette.ink,
                    ),
                  ),
                  if (check != null) ...[
                    const SizedBox(height: PosSpace.xs),
                    Text(
                      strings.dayCloseFor(_dateText(check.day.date)),
                      style: PosText.ui(size: 12.5, color: palette.muted),
                    ),
                  ],
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(PosSpace.lg),
                child: _body(strings, palette, check),
              ),
            ),
            _footer(strings, palette, check),
          ],
        ),
      ),
    );
  }

  Widget _body(AppStrings strings, PosPalette palette, DayCloseCheck? check) {
    if (_busy) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: palette.accent),
          // Only once there is something to close. On the first load this is a
          // plain spinner, and naming a backup that has not been reached yet
          // would be describing work nobody has asked for.
          if (check != null) ...[
            const SizedBox(height: PosSpace.md),
            Text(
              strings.backupDayCloseWorking,
              textAlign: TextAlign.center,
              style: PosText.ui(size: 12.5, color: palette.muted),
            ),
          ],
        ],
      );
    }
    if (check == null) {
      return Text(
        _error ?? strings.dayCloseNothingOpen,
        style: PosText.ui(size: 13.5, color: palette.muted),
      );
    }
    if (check.isClear) {
      return Container(
        padding: const EdgeInsets.all(PosSpace.md),
        color: palette.okSoft,
        child: Text(
          strings.dayCloseClear,
          style: PosText.ui(size: 13.5, color: palette.ok),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MicroLabel(strings.dayCloseBlockersTitle),
        const SizedBox(height: PosSpace.sm),
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
              _blockerText(strings, blocker),
              style: PosText.ui(size: 13, color: palette.body),
            ),
          ),
        const SizedBox(height: PosSpace.lg),
        MicroLabel(strings.dayForceReasonLabel),
        const SizedBox(height: PosSpace.xs),
        TextField(
          controller: _reason,
          maxLines: 2,
          maxLength: 200,
          onChanged: (_) => setState(() {}),
          style: PosText.ui(size: 13.5, color: palette.ink),
          decoration: InputDecoration(
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
      ],
    );
  }

  static String _blockerText(AppStrings strings, DayBlocker blocker) =>
      switch (blocker.kind) {
        DayBlockerKind.openShift => strings.dayBlockerOpenShifts(blocker.count),
        DayBlockerKind.parkedTicket => strings.dayBlockerParkedTickets(
          blocker.count,
        ),
        DayBlockerKind.unpaidOrder => strings.dayBlockerUnpaidOrders(
          blocker.count,
        ),
      };

  Widget _footer(AppStrings strings, PosPalette palette, DayCloseCheck? check) {
    final forcing = check != null && check.needsForce;
    final ready =
        check != null &&
        !_busy &&
        (!forcing || _reason.text.trim().isNotEmpty);

    return Container(
      padding: const EdgeInsets.all(PosSpace.lg),
      decoration: BoxDecoration(
        border: BorderDirectional(top: palette.resting),
      ),
      child: Row(
        children: [
          Expanded(
            child: PosButton(
              label: strings.cancel,
              border: Border.fromBorderSide(palette.resting),
              // Carries the closed day out when the close succeeded and only
              // the backup did not — see [_closed].
              onPressed: _busy
                  ? null
                  : () => Navigator.of(context).pop(_closed),
            ),
          ),
          const SizedBox(width: PosSpace.sm),
          Expanded(
            flex: 2,
            child: PosButton(
              // Named for what it does. "Close the day" and "Close anyway" are
              // different acts and the button says which one is about to
              // happen.
              label: forcing
                  ? strings.dayForceCloseAction
                  : strings.dayCloseAction,
              background: ready
                  ? (forcing ? palette.danger : palette.accent)
                  : palette.ctaDisabled,
              foreground: Colors.white,
              fontWeight: FontWeight.w700,
              onPressed: ready ? () => _close(check, force: forcing) : null,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _close(DayCloseCheck check, {required bool force}) async {
    final strings = context.strings;

    // Forcing is a different permission from closing, because closing over
    // open tables is a different decision from closing after everything is
    // settled — and the person who may do the second is often not the person
    // who should be doing the first.
    final decision = await requestPermission(
      context,
      ref,
      force ? PosCapability.dayForceClose : PosCapability.dayClose,
      action: strings.dayCloseFor(_dateText(check.day.date)),
      auditAction: force ? 'day.force_closed' : 'day.closed',
      entityType: 'business_day',
      entityId: '${check.day.id}',
      approveLabel: force
          ? strings.dayForceCloseAction
          : strings.dayCloseAction,
    );
    if (!mounted || decision is! Allowed) return;

    final by = ref.read(signedInStaffProvider);
    if (by == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final closed = await ref
          .read(businessDayRepositoryProvider)
          .close(
            day: check.day,
            by: by,
            force: force,
            forceReason: force ? _reason.text.trim() : null,
          );
      if (!mounted) return;
      ref.invalidate(businessDayProvider);

      if (await _backUp(by)) {
        if (!mounted) return;
        Navigator.of(context).pop(closed);
        return;
      }
      // The day IS closed. The dialog stays open only to say that the copy is
      // not — popping straight through would make a silent failure of the one
      // thing this hook exists to make un-forgettable.
      if (!mounted) return;
      setState(() {
        _busy = false;
        _closed = closed;
        _error = strings.backupDayCloseFailed;
      });
    } on Object {
      if (!mounted) return;
      // Still open. A day reported closed that is not would leave tomorrow's
      // takings landing in yesterday.
      setState(() {
        _busy = false;
        _error = strings.dayCouldNotBeClosed;
      });
    }
  }

  static String _dateText(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
