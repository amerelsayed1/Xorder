import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/permissions.dart';
import '../../../domain/models/shift.dart';
import '../../../domain/services/authorization.dart';
import 'admin_pane_bits.dart';

/// This till's own setup, and running it again.
///
/// **Here, not on the start screen.** A reset drops the database address and
/// password and sends the till back through the wizard. The start screen is
/// where a cashier opens the shift, and a cashier must not be one tap from
/// wiping the till they are about to sell on. Behind `terminal.manage` —
/// critical, and the Owner's by default — it is reached by whoever is actually
/// moving the till.
///
/// Nothing is lost by the move: the start screen only offered it once the
/// session had loaded, so a till that cannot reach its database was never
/// helped by it either.
class ManagementTerminalPane extends ConsumerStatefulWidget {
  const ManagementTerminalPane({
    required this.admin,
    required this.onReconfigure,
    super.key,
  });

  final PosStaff admin;

  /// Off to the setup wizard, once the configuration is cleared. The router
  /// only redirects when something navigates, so the pane that cleared it has
  /// to say where to go.
  final VoidCallback onReconfigure;

  @override
  ConsumerState<ManagementTerminalPane> createState() =>
      _ManagementTerminalPaneState();
}

class _ManagementTerminalPaneState
    extends ConsumerState<ManagementTerminalPane> {
  bool _busy = false;
  String? _refusal;

  bool get _mayManage =>
      Authorization.check(widget.admin, PosCapability.terminalManage).isAllowed;

  /// Clear this terminal's configuration and run setup again.
  ///
  /// Refused outright while a shift is open. The drawer has not been counted,
  /// and a till that dropped its database address mid-shift would leave that
  /// count with nowhere to go.
  Future<void> _reset() async {
    final strings = context.strings;
    setState(() {
      _busy = true;
      _refusal = null;
    });

    PosShift? openShift;
    try {
      openShift = await ref.read(shiftRepositoryProvider).current();
    } on Exception {
      if (mounted) {
        setState(() {
          _busy = false;
          _refusal = strings.resetTerminalShiftUnknown;
        });
      }
      return;
    }
    if (!mounted) return;

    if (openShift != null) {
      setState(() {
        _busy = false;
        _refusal = strings.resetTerminalShiftOpen;
      });
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _ResetTerminalDialog(strings: strings),
    );
    if (!mounted) return;
    if (confirmed != true) {
      setState(() => _busy = false);
      return;
    }

    await ref.read(terminalResetProvider).run();
    if (mounted) widget.onReconfigure();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;

    return ListView(
      padding: const EdgeInsets.all(PosSpace.xl),
      children: [
        PaneSection(title: strings.paneTerminal, hint: strings.paneTerminalBlurb),
        MicroLabel(strings.resetTerminal),
        const SizedBox(height: PosSpace.xs),
        Text(
          strings.resetTerminalHint,
          style: PosText.ui(size: 12.5, color: palette.muted, height: 1.5),
        ),
        const SizedBox(height: PosSpace.md),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: PosButton(
            key: const Key('terminal-reset'),
            label: strings.resetTerminal,
            border: Border.fromBorderSide(BorderSide(color: palette.danger)),
            foreground: palette.danger,
            onPressed: _mayManage && !_busy ? _reset : null,
          ),
        ),
        if (_refusal != null) ...[
          const SizedBox(height: PosSpace.md),
          Text(
            _refusal!,
            key: const Key('terminal-reset-refused'),
            style: PosText.ui(size: 12.5, color: palette.danger, height: 1.5),
          ),
        ],
      ],
    );
  }
}

/// Confirms a terminal reset, and says plainly what it does and does not touch.
///
/// The fear this answers is "will I lose today's sales". The answer is no, and
/// an operator standing at a till at nine in the morning should not have to
/// take that on faith from a one-line dialog.
class _ResetTerminalDialog extends StatelessWidget {
  const _ResetTerminalDialog({required this.strings});

  final AppStrings strings;

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: context.pos.page,
    insetPadding: const EdgeInsets.all(PosSpace.s24),
    shape: RoundedRectangleBorder(
      side: context.pos.emphasis,
      borderRadius: PosBorders.radius,
    ),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Padding(
        padding: const EdgeInsets.all(PosSpace.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(strings.resetTerminalTitle, style: PosText.panelTitle(color: context.pos.ink)),
            const SizedBox(height: PosSpace.sm),
            Text(
              strings.resetTerminalBody,
              style: PosText.ui(size: 13, color: context.pos.muted, height: 1.5),
            ),
            const SizedBox(height: PosSpace.lg),
            Row(
              children: [
                Expanded(
                  child: PosButton(
                    label: strings.cancel,
                    border: Border.all(color: context.pos.line),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ),
                const SizedBox(width: PosSpace.md),
                Expanded(
                  child: PosButton(
                    label: strings.resetTerminalConfirm,
                    background: context.pos.danger,
                    foreground: Colors.white,
                    fontWeight: FontWeight.w700,
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
