import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/labels.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/money/money.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/tokens.dart';
import '../../core/ui/widgets/pos_widgets.dart';
import '../admin/presentation/management_eta_pane.dart' show etaProblemText;
import '../admin/presentation/management_screen.dart' show ManagementPane;
import '../../domain/repositories/repositories.dart';
import '../licensing/domain/license.dart';
import '../cash/presentation/day_close_dialog.dart';
import '../shift/presentation/shift_dialogs.dart';

/// Start screen — terminal identity and opening the shift.
///
/// Full-screen shell ground, one centred column at most 520 wide. Tap or Enter
/// starts the shift; the real implementation opens a `Shift` record with the
/// counted float (POS-BE-009, still PROPOSED).
class StartScreen extends ConsumerStatefulWidget {
  const StartScreen({
    super.key,
    required this.onStart,
    required this.onManageLicence,
    required this.onReconfigure,
    required this.onManage,
  });

  final VoidCallback onStart;
  final VoidCallback onManageLicence;

  /// A back-office pane, for the warnings that point at one — the Backup pane
  /// from "no verified copy", E-receipts from a filing problem. The way into
  /// the back office itself is the window's bar and F8, not this screen.
  final void Function(ManagementPane pane) onManage;

  /// Back to the setup wizard, after the terminal's configuration has been
  /// cleared. The router will not redirect there on its own once setup is
  /// complete, so the screen that clears it has to say where to go.
  final VoidCallback onReconfigure;

  @override
  ConsumerState<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends ConsumerState<StartScreen> {
  @override
  void initState() {
    super.initState();
    // Re-read the licence every time this screen is reached, rather than
    // trusting a value cached for the life of the process. This screen is the
    // gate for opening a shift, so a renewal applied five minutes ago has to be
    // visible here without restarting the till.
    Future.microtask(() => ref.invalidate(licenceEntitlementProvider));
  }

  /// Clear this terminal's configuration and run setup again.
  ///
  /// Refused outright while a shift is open. The drawer has not been counted,
  /// and a till that dropped its database address mid-shift would leave that
  /// count with nowhere to go.
  Future<void> _reconfigure() async {
    final strings = context.strings;

    PosShift? openShift;
    try {
      openShift = await ref.read(shiftRepositoryProvider).current();
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.resetTerminalShiftUnknown)),
      );
      return;
    }
    if (!mounted) return;

    if (openShift != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.resetTerminalShiftOpen)));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _ResetTerminalDialog(strings: strings),
    );
    if (confirmed != true || !mounted) return;

    await ref.read(terminalResetProvider).run();
    if (mounted) widget.onReconfigure();
  }

  /// Open a shift, then go selling.
  ///
  /// A shift already open is resumed rather than replaced: a till restarted
  /// mid-service must come back to the same drawer, because the drawer never
  /// closed. Only a genuinely new shift asks who is on the till and what is in
  /// it.
  Future<void> _start() async {
    final licence = ref.read(licenceEntitlementProvider).valueOrNull;
    if (licence != null && !licence.canOpenShift) return;

    if (ref.read(shiftProvider).valueOrNull != null) {
      widget.onStart();
      return;
    }

    final opened = await OpenShiftDialog.show(context);
    if (opened && mounted) widget.onStart();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final catalog = ref.watch(catalogProvider);
    // The one place the licence actually gates anything: opening a shift.
    // Never mid-service, and never cash-up — see LicenseEntitlement.
    final licence = ref.watch(licenceEntitlementProvider).valueOrNull;
    final terminal = ref.watch(terminalProfileProvider);

    return Scaffold(
      backgroundColor: context.pos.shell,
      body: session.when(
        loading: () => Center(
          child: CircularProgressIndicator(color: context.pos.accent),
        ),
        error: (error, _) => Center(
          child: Text('$error', style: PosText.ui(color: context.pos.shellText)),
        ),
        data: (data) => Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          },
          child: Actions(
            actions: {
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  _start();
                  return null;
                },
              ),
            },
            child: Focus(
              autofocus: true,
              child: Column(
                children: [
                  _topBar(),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: _body(
                          context,
                          data,
                          catalog.valueOrNull?.products.length,
                          licence,
                          terminal,
                          ref.watch(shiftProvider).valueOrNull,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Who is signed in, when somebody is.
  ///
  /// The back office is not here: the window's own bar carries it, beside
  /// Settings, and F8 opens it from anywhere. A second button for it on this
  /// screen was the same door twice.
  ///
  /// Nothing at all before a PIN has been entered — this screen is where the
  /// shift is opened, and opening it is what asks for one. See
  /// `operatorNameProvider`.
  Widget _topBar() {
    final operator = ref.watch(operatorNameProvider);
    if (operator.isEmpty) return const SizedBox.shrink();

    return Container(
      height: PosSize.topBar,
      decoration: BoxDecoration(
        color: context.pos.shell,
        border: Border(bottom: context.pos.accentBorder),
      ),
      padding: const EdgeInsets.symmetric(horizontal: PosSpace.s14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            color: context.pos.accent,
            child: Text(
              ref.watch(operatorInitialsProvider),
              style: PosText.ui(
                size: 16,
                weight: FontWeight.w800,
                color: context.pos.onAccent,
              ),
            ),
          ),
          const SizedBox(width: PosSpace.sm),
          Text(
            operator,
            style: PosText.ui(
              size: 13.5,
              weight: FontWeight.w600,
              color: context.pos.shellText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(
    BuildContext context,
    PosSession session,
    int? itemCount,
    LicenseEntitlement? licence,
    TerminalProfile terminal,
    PosShift? openShift,
  ) {
    final strings = context.strings;

    // No licence loaded yet is treated as permitted: a slow read must not look
    // like a lapsed licence.
    final blocked = licence != null && !licence.canOpenShift;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The handoff specifies a 280px logo image. Until the tenant logo is
        // fetched from config it is rendered as the wordmark rather than a
        // placeholder box, which would read as a broken asset.
        Text(
          session.tenantName.toUpperCase(),
          textAlign: TextAlign.center,
          style: PosText.ui(
            size: 34,
            weight: FontWeight.w800,
            color: context.pos.shellText,
          ),
        ),
        const SizedBox(height: PosSpace.md),
        Text(
          strings.pointOfSale,
          textAlign: TextAlign.center,
          style: PosText.mono(
            size: 10.5,
            weight: FontWeight.w600,
            color: context.pos.shellMuted,
            letterSpacing: 2.5,
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(vertical: PosSpace.s28),
          child: ColoredBox(
            color: context.pos.accent,
            child: SizedBox(height: 2),
          ),
        ),
        _identityGrid(strings, session, itemCount, terminal, pos: context.pos),
        if (ref.watch(terminalRejectedProvider)) ...[
          const SizedBox(height: PosSpace.lg),
          _terminalRejectedBanner(pos: context.pos),
        ],
        if (licence?.needsAttention ?? false) ...[
          const SizedBox(height: PosSpace.lg),
          _licenceBanner(licence!, pos: context.pos),
          const SizedBox(height: PosSpace.md),
          PosButton(
            label: blocked ? strings.renewLicence : strings.manageLicence,
            background: blocked ? context.pos.accent : context.pos.shellCard,
            foreground: blocked ? Colors.white : context.pos.shellText,
            onPressed: widget.onManageLicence,
          ),
        ],
        if (etaProblemText(strings, ref.watch(etaFilingProblemProvider))
            case final problem?) ...[
          const SizedBox(height: PosSpace.lg),
          Container(
            key: const Key('start-eta-problem'),
            padding: const EdgeInsets.all(PosSpace.md),
            decoration: BoxDecoration(
              color: context.pos.shellDangerBg,
              border: Border.all(color: context.pos.danger),
            ),
            child: Text(
              problem,
              textAlign: TextAlign.center,
              style: PosText.ui(
                size: 12.5,
                color: context.pos.shellDangerText,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: PosSpace.md),
          PosButton(
            key: const Key('start-eta-open'),
            label: strings.etaOpenPane,
            background: context.pos.shellCard,
            foreground: context.pos.shellText,
            onPressed: () => widget.onManage(ManagementPane.eta),
          ),
        ],
        if (_backupWarning(strings) case final warning?) ...[
          const SizedBox(height: PosSpace.lg),
          _backupBanner(warning, pos: context.pos),
          const SizedBox(height: PosSpace.md),
          PosButton(
            key: const Key('start-backup-open'),
            label: strings.backupOpenPane,
            background: context.pos.shellCard,
            foreground: context.pos.shellText,
            onPressed: () => widget.onManage(ManagementPane.backup),
          ),
        ],
        const SizedBox(height: PosSpace.s28),
        PosButton(
          label: blocked
              ? strings.licenceRequired
              : (openShift == null
                    ? strings.startShift
                    : strings.resumeShift(openShift.reference)),
          height: 72,
          alignLeft: true,
          background: blocked ? context.pos.shellCard : context.pos.accent,
          foreground: blocked ? context.pos.shellMuted : Colors.white,
          fontSize: 17,
          fontWeight: FontWeight.w800,
          padding: const EdgeInsets.symmetric(horizontal: PosSpace.xl),
          trailing: blocked
              ? null
              : KeyChip(strings.enterKeyCap, onShell: true),
          onPressed: blocked ? null : _start,
        ),
        const SizedBox(height: PosSpace.md),
        Text(
          blocked
              ? strings.cashUpStillAvailable
              : (openShift == null
                    ? strings.startShiftHelp
                    : strings.resumeShiftHelp(openShift.openedByName)),
          textAlign: TextAlign.center,
          style: PosText.ui(size: 12, color: context.pos.shellMuted),
        ),
        const SizedBox(height: PosSpace.s28),
        // Deliberately quiet, and deliberately present: an installer moving the
        // till to another branch server needs it, and a cashier must never
        // reach for it by accident.
        Align(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Ending the night. Here rather than on the sale screen because
              // it is the last thing anybody does, and because a trading day
              // is a property of the branch rather than of the till somebody
              // happens to be standing at. Only shown while one is open.
              if (ref.watch(businessDayProvider).valueOrNull != null)
                PosButton(
                  label: context.strings.dayCloseTitle,
                  height: PosSize.minTouchTarget,
                  foreground: context.pos.shellMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  onPressed: _closeDay,
                ),
              PosButton(
                label: context.strings.resetTerminal,
                height: PosSize.minTouchTarget,
                foreground: context.pos.shellMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                onPressed: _reconfigure,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _closeDay() async {
    final closed = await DayCloseDialog.show(context);
    if (closed == null || !mounted) return;
    posToast(
      context,
      context.strings.dayClosed(
        (closed.gross ?? Money.zero).format(withCurrency: true),
      ),
    );
  }

  /// The platform has stopped recognising this till.
  ///
  /// Ranked above the licence banner on purpose: a licence warning is about
  /// permission to sell, this is about the till being orphaned from the
  /// platform entirely, and the operator can act on it (re-pair) without
  /// anyone's approval. The pending count is named explicitly — the whole
  /// failure mode this fixes is a queue growing where nobody looks.
  Widget _terminalRejectedBanner({required PosPalette pos}) {
    final strings = context.strings;
    final queued = ref.watch(pendingSyncCountProvider).valueOrNull ?? 0;

    return Container(
      padding: const EdgeInsets.all(PosSpace.md),
      decoration: BoxDecoration(
        color: pos.shellDangerBg,
        border: Border.all(color: pos.danger),
      ),
      child: Column(
        children: [
          Text(
            strings.terminalRejectedTitle,
            textAlign: TextAlign.center,
            style: PosText.ui(
              size: 13,
              weight: FontWeight.w700,
              color: pos.shellDangerText,
            ),
          ),
          const SizedBox(height: PosSpace.sm),
          Text(
            strings.terminalRejectedBody,
            textAlign: TextAlign.center,
            style: PosText.ui(
              size: 12.5,
              color: pos.shellDangerText,
              height: 1.5,
            ),
          ),
          if (queued > 0) ...[
            const SizedBox(height: PosSpace.sm),
            Text(
              strings.terminalRejectedQueued.replaceFirst('{count}', '$queued'),
              textAlign: TextAlign.center,
              style: PosText.mono(
                size: 12,
                weight: FontWeight.w600,
                color: pos.shellDangerText,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// What the screen somebody opens the restaurant from should say about
  /// backups, or null for nothing.
  ///
  /// Here and not only in the Backup pane, because the pane is two menus deep
  /// behind the owner's PIN and the person who needs to know the nightly copy
  /// has been failing is whoever opens up tomorrow. Only a VERIFIED copy
  /// counts, and two days rather than one before an old one is called old — a
  /// restaurant closed on Sunday should not be told off on Monday morning.
  String? _backupWarning(AppStrings strings) {
    if (!ref.watch(backupsApplyProvider)) return null;
    final records = ref.watch(backupsProvider).valueOrNull;
    if (records == null) return null;

    final verified = records.where((r) => r.isRestorable);
    if (verified.isEmpty) {
      return records.isEmpty ? strings.backupNoneYet : strings.backupNoVerifiedCopy;
    }
    final days = verified.first.ageAt(DateTime.now()).inDays;
    return days >= 2 ? strings.backupStale(days) : null;
  }

  Widget _backupBanner(String text, {required PosPalette pos}) => Container(
    key: const Key('start-backup-warning'),
    padding: const EdgeInsets.all(PosSpace.md),
    decoration: BoxDecoration(
      color: pos.offlinePillBg,
      border: Border.all(color: pos.warn),
    ),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: PosText.ui(size: 12.5, color: pos.offlinePillText, height: 1.5),
    ),
  );

  Widget _licenceBanner(LicenseEntitlement licence, {required PosPalette pos}) {
    final severe = !licence.canOpenShift;

    return Container(
      padding: const EdgeInsets.all(PosSpace.md),
      decoration: BoxDecoration(
        color: severe ? pos.shellDangerBg : pos.offlinePillBg,
        border: Border.all(color: severe ? pos.danger : pos.warn),
      ),
      child: Text(
        licence.notice?.text(context.strings) ?? '',
        textAlign: TextAlign.center,
        style: PosText.ui(
          size: 12.5,
          color: severe ? pos.shellDangerText : pos.offlinePillText,
          height: 1.5,
        ),
      ),
    );
  }

  /// Branch, till and menu: one row of cells on 1px shellLine gaps.
  ///
  /// Not the restaurant — it is the heading directly above, and a cell saying
  /// it again under the heading was the same name twice.
  Widget _identityGrid(
    AppStrings strings,
    PosSession session,
    int? itemCount,
    TerminalProfile terminal, {
    required PosPalette pos,
  }) => Container(
    color: pos.shellLine,
    child: IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _cell(
              strings.branchCell,
              terminal.branchName ?? session.branchName,
              pos: pos,
            ),
          ),
          const SizedBox(width: 1),
          Expanded(
            child: _cell(
              strings.terminalCell,
              terminal.terminalName ?? session.terminalCode,
              pos: pos,
            ),
          ),
          const SizedBox(width: 1),
          Expanded(
            child: _cell(
              strings.catalogCell,
              itemCount == null
                  ? strings.catalogSyncing
                  : strings.catalogCachedItems(itemCount),
              valueColor: itemCount == null
                  ? pos.shellMuted
                  : pos.onlinePillText,
              pos: pos,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _cell(
    String label,
    String value, {required PosPalette pos, 
    Color? valueColor,
  }) => Container(
    color: pos.shellRow,
    padding: const EdgeInsets.symmetric(
      horizontal: PosSpace.lg,
      vertical: PosSpace.s14,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        MicroLabel(label, color: pos.shellMuted),
        const SizedBox(height: PosSpace.xs),
        Text(
          value,
          overflow: TextOverflow.ellipsis,
          style: PosText.ui(
            size: 15,
            weight: FontWeight.w600,
            color: valueColor ?? pos.shellText,
          ),
        ),
      ],
    ),
  );
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
