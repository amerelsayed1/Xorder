import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/tokens.dart';
import '../../core/ui/widgets/pos_widgets.dart';
import '../../domain/repositories/repositories.dart';
import '../licensing/domain/license.dart';
import '../shift/presentation/shift_dialogs.dart';

/// Start screen — terminal identity and opening the shift.
///
/// Full-screen shell ground, one centred column at most 520 wide. Tap or Enter
/// starts the shift; the real implementation opens a `Shift` record with the
/// counted float (POS-BE-009, still PROPOSED).
class StartScreen extends ConsumerStatefulWidget {
  const StartScreen({super.key, required this.onStart, required this.onManageLicence});

  final VoidCallback onStart;
  final VoidCallback onManageLicence;

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
      backgroundColor: PosColors.shell,
      body: session.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: PosColors.accent),
        ),
        error: (error, _) => Center(
          child: Text('$error', style: PosText.ui(color: PosColors.shellText)),
        ),
        data: (data) => Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          },
          child: Actions(
            actions: {
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  // Enter runs exactly the action the CTA runs — licence gate,
                  // shift dialog and all. When they were two code paths the
                  // keyboard walked straight past the licence, because the
                  // button was disabled and Enter was not.
                  _start();
                  return null;
                },
              ),
            },
            child: Focus(
              autofocus: true,
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
          ),
        ),
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
          style: PosText.ui(size: 34, weight: FontWeight.w800, color: PosColors.shellText),
        ),
        const SizedBox(height: PosSpace.md),
        Text(
          'POINT OF SALE',
          textAlign: TextAlign.center,
          style: PosText.mono(
            size: 10.5,
            weight: FontWeight.w600,
            color: PosColors.shellMuted,
            letterSpacing: 2.5,
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: PosSpace.s28),
          child: ColoredBox(color: PosColors.accent, child: SizedBox(height: 2)),
        ),
        _identityGrid(session, itemCount, terminal),
        if (licence?.needsAttention ?? false) ...[
          const SizedBox(height: PosSpace.lg),
          _licenceBanner(licence!),
          const SizedBox(height: PosSpace.md),
          PosButton(
            label: blocked ? 'Renew licence' : 'Manage licence',
            background: blocked ? PosColors.accent : PosColors.shellCard,
            foreground: blocked ? Colors.white : PosColors.shellText,
            onPressed: widget.onManageLicence,
          ),
        ],
        const SizedBox(height: PosSpace.s28),
        PosButton(
          label: blocked
              ? 'Licence required'
              : (openShift == null
                  ? 'Start shift'
                  : 'Resume ${openShift.reference}'),
          height: 72,
          alignLeft: true,
          background: blocked ? PosColors.shellCard : PosColors.accent,
          foreground: blocked ? PosColors.shellMuted : Colors.white,
          fontSize: 17,
          fontWeight: FontWeight.w800,
          padding: const EdgeInsets.symmetric(horizontal: PosSpace.xl),
          trailing: blocked ? null : const KeyChip('ENTER', onShell: true),
          onPressed: blocked ? null : _start,
        ),
        const SizedBox(height: PosSpace.md),
        Text(
          blocked
              ? 'Cash-up and reprint for the last shift are still available.'
              : (openShift == null
                  ? 'You will be asked for your PIN and the cash already in the drawer.'
                  : 'Opened by ${openShift.openedByName}. The drawer was never '
                      'closed, so the shift is still yours.'),
          textAlign: TextAlign.center,
          style: PosText.ui(size: 12, color: PosColors.shellMuted),
        ),
      ],
    );
  }

  Widget _licenceBanner(LicenseEntitlement licence) {
    final severe = !licence.canOpenShift;

    return Container(
      padding: const EdgeInsets.all(PosSpace.md),
      decoration: BoxDecoration(
        color: severe ? const Color(0xFF3A1512) : PosColors.offlinePillBg,
        border: Border.all(color: severe ? PosColors.danger : PosColors.warn),
      ),
      child: Text(
        licence.message ?? '',
        textAlign: TextAlign.center,
        style: PosText.ui(
          size: 12.5,
          color: severe ? const Color(0xFFF2A79E) : PosColors.offlinePillText,
          height: 1.5,
        ),
      ),
    );
  }

  /// 2×2 grid of shellRow cells on 1px shellLine gaps.
  Widget _identityGrid(
    PosSession session,
    int? itemCount,
    TerminalProfile terminal,
  ) =>
      Container(
        color: PosColors.shellLine,
        child: Column(
          children: [
            Row(children: [
              Expanded(child: _cell('TENANT', session.tenantName)),
              const SizedBox(width: 1),
              Expanded(child: _cell('BRANCH', terminal.branchName ?? session.branchName)),
            ]),
            const SizedBox(height: 1),
            Row(children: [
              Expanded(
                child: _cell('TERMINAL', terminal.terminalName ?? session.terminalCode),
              ),
              const SizedBox(width: 1),
              Expanded(child: _cell(
                'CATALOG',
                itemCount == null ? 'syncing…' : 'cached · $itemCount items',
                valueColor: itemCount == null ? PosColors.shellMuted : PosColors.onlinePillText,
              )),
            ]),
          ],
        ),
      );

  Widget _cell(String label, String value, {Color valueColor = PosColors.shellText}) =>
      Container(
        color: PosColors.shellRow,
        padding: const EdgeInsets.symmetric(
          horizontal: PosSpace.lg,
          vertical: PosSpace.s14,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            MicroLabel(label, color: PosColors.shellMuted),
            const SizedBox(height: PosSpace.xs),
            Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: PosText.ui(size: 15, weight: FontWeight.w600, color: valueColor),
            ),
          ],
        ),
      );
}
