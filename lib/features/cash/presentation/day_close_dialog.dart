import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/business_day.dart';
import '../../../domain/models/permissions.dart';
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
      return Center(child: CircularProgressIndicator(color: palette.accent));
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
        DayBlockerKind.parkedTicket => strings.dayBlockerParkedTables(
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
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
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
      Navigator.of(context).pop(closed);
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
