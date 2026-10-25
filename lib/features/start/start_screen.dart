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
import '../../domain/models/branch_sales.dart' show businessDayWire;
import '../../domain/repositories/repositories.dart';
import '../../domain/services/business_day_service.dart';
import '../licensing/domain/license.dart';
import '../cash/presentation/day_close_dialog.dart';
import '../shift/presentation/shift_dialogs.dart';
import 'database_unavailable.dart';

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
    required this.onManage,
  });

  final VoidCallback onStart;
  final VoidCallback onManageLicence;

  /// A back-office pane, for the warnings that point at one — E-receipts from
  /// a filing problem. The way into the back office itself is the window's
  /// bar and F8, not this screen; backups are said inside it.
  final void Function(ManagementPane pane) onManage;

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
    // On a main device, share the licence with its tablets. Here because this
    // is where every main device arrives — after setup, after a renewal, and
    // on the first boot of one installed before tablets could be children.
    // A no-op on a child and on a one-terminal licence; never throws.
    Future.microtask(() => ref.read(siteLicencePublisherProvider).publish());
    // The staff list this screen's sign-in reads is the platform's: a
    // cashier added there should be able to start a shift here without a
    // restart — see the lock screen.
    Future.microtask(() => ref.read(cloudSyncProvider)?.nudge());
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
    // Watched though no longer shown, so the menu is loading while the shift
    // is opened rather than after the till is already on screen.
    ref.watch(catalogProvider);
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
        error: (error, _) => DatabaseUnavailable(
          error: error,
          onRetry: () => ref.invalidate(sessionProvider),
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
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: _body(
                          context,
                          data,
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

  Widget _body(
    BuildContext context,
    PosSession session,
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
        // XOrder's mark above the restaurant's name. Orange on transparent, so
        // the one asset carries both themes, as it does on the welcome screen.
        // Centred because the column stretches, and a stretched image ignores
        // its width.
        Center(
          child: Image.asset(
            'assets/icons/xorder_logo_official.png',
            key: const Key('start-xorder-logo'),
            width: 180,
            fit: BoxFit.contain,
            // The restaurant's name is right below; a missing asset is better
            // absent than a broken-image glyph.
            errorBuilder: (context, error, stack) => const SizedBox.shrink(),
          ),
        ),
        const SizedBox(height: PosSpace.s28),
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
        _identityGrid(strings, session, terminal, pos: context.pos),
        // For as long as a technician's "encryption off" is in force, on the
        // screen every shift starts from: an override nobody can see is an
        // override nobody remembers to undo.
        if (ref.watch(deploymentProvider).isInsecureLan) ...[
          const SizedBox(height: PosSpace.lg),
          Container(
            key: const Key('start-insecure-lan'),
            padding: const EdgeInsets.all(PosSpace.md),
            decoration: BoxDecoration(
              color: context.pos.offlinePillBg,
              border: Border.all(color: context.pos.warn),
            ),
            child: Text(
              strings.insecureLanWarning,
              textAlign: TextAlign.center,
              style: PosText.ui(
                size: 12.5,
                color: context.pos.offlinePillText,
                height: 1.5,
              ),
            ),
          ),
        ],
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
        if (ref.watch(dayNoticeProvider).valueOrNull case final notice?) ...[
          const SizedBox(height: PosSpace.lg),
          _dayNoticeBanner(notice, pos: context.pos),
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
        // Ending the night. Here rather than on the sale screen because it is
        // the last thing anybody does, and because a trading day is a property
        // of the branch rather than of the till somebody happens to be standing
        // at. Only shown while one is open.
        //
        // Resetting the terminal is not beside it: that is the back office's
        // (System › Terminal, behind `terminal.manage`), because a cashier
        // opens the till from here and must not be one tap from wiping it.
        if (ref.watch(businessDayProvider).valueOrNull != null)
          Align(
            child: PosButton(
              label: context.strings.dayCloseTitle,
              height: PosSize.minTouchTarget,
              foreground: context.pos.shellMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              onPressed: _closeDay,
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

  /// A day left open from an earlier date, or sales after the date was closed.
  /// A warning, not a refusal: nothing here stops the till selling.
  Widget _dayNoticeBanner(DayNotice notice, {required PosPalette pos}) {
    final strings = context.strings;
    final date = businessDayWire(notice.date);
    return Container(
      key: const Key('start-day-notice'),
      padding: const EdgeInsets.all(PosSpace.md),
      decoration: BoxDecoration(
        color: pos.offlinePillBg,
        border: Border.all(color: pos.warn),
      ),
      child: Text(
        switch (notice.kind) {
          DayNoticeKind.staleOpenDay => strings.dayStillOpenFrom(date),
          DayNoticeKind.todayAlreadyClosed => strings.dayClosedTodayNotice(
            date,
          ),
        },
        textAlign: TextAlign.center,
        style: PosText.ui(size: 12.5, color: pos.offlinePillText, height: 1.5),
      ),
    );
  }

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

  /// Branch and till: one row of cells on 1px shellLine gaps.
  ///
  /// Not the restaurant — it is the heading directly above, and a cell saying
  /// it again under the heading was the same name twice. Not the menu either:
  /// how many items are cached is nothing whoever opens the shift acts on.
  Widget _identityGrid(
    AppStrings strings,
    PosSession session,
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
