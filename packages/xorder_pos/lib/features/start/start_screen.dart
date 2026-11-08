import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/labels.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/tokens.dart';
import '../../core/ui/widgets/pos_widgets.dart';
import '../admin/presentation/management_eta_pane.dart' show etaProblemText;
import '../admin/presentation/management_screen.dart' show ManagementPane;
import '../../domain/repositories/repositories.dart';
import '../licensing/domain/license.dart';
import '../shift/presentation/shift_dialogs.dart';
import 'database_unavailable.dart';

/// Start screen — terminal identity and opening the shift.
///
/// Full-screen shell ground, one centred column at most 520 wide. Tap or Enter
/// signs in (name and PIN). **Signing in does not open a shift**: that is a
/// button on Home, for whoever may (pos-signin-first-home), so a manager can
/// close the day without ever opening a drawer.
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

  /// Sign in, then go to Home (or straight to selling, for a branch that sells
  /// one way with a shift already open — the router decides).
  ///
  /// **Not gated by the licence.** An expired licence blocks opening the *next
  /// shift*, which is Home's button; a manager must still be able to get in to
  /// cash up, reprint and close the day.
  Future<void> _signIn() async {
    final signedIn = await SignInDialog.show(context);
    if (signedIn && mounted) widget.onStart();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    // Watched though no longer shown, so the menu is loading while the shift
    // is opened rather than after the till is already on screen.
    ref.watch(catalogProvider);
    // The same for the order types: whether this shift goes to the home screen
    // or straight to selling depends on them (pos-home-screen).
    ref.watch(orderTypeConfigProvider);
    ref.watch(branchesProvider);
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
                  _signIn();
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
                        child: _body(context, data, licence, terminal),
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
  ) {
    final strings = context.strings;

    // No licence loaded yet is treated as permitted: a slow read must not look
    // like a lapsed licence.
    final blocked = licence != null && !licence.canOpenShift;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // XOrder's mark, with the business's own logo under it when it has
        // one (XORD-021), above the business's name.
        const Center(child: StartLogo()),
        const SizedBox(height: PosSpace.s28),
        // The name stays under the logo: it is what the receipt and every other
        // screen call the business, and a logo may be a bare symbol.
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
          key: const Key('start-sign-in'),
          label: strings.signIn,
          height: 72,
          alignLeft: true,
          background: context.pos.accent,
          foreground: Colors.white,
          fontSize: 17,
          fontWeight: FontWeight.w800,
          padding: const EdgeInsets.symmetric(horizontal: PosSpace.xl),
          trailing: KeyChip(strings.enterKeyCap, onShell: true),
          onPressed: _signIn,
        ),
        const SizedBox(height: PosSpace.md),
        Text(
          strings.signInOnlyHelp,
          textAlign: TextAlign.center,
          style: PosText.ui(size: 12, color: context.pos.shellMuted),
        ),
      ],
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
  /// Not the business — it is the heading directly above, and a cell saying
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

/// The pictures at the top of the start screen: the XOrder mark, always, and
/// under it the business's own logo when it has one (XORD-021).
///
/// **The business's logo never replaces the XOrder mark** (owner, 26 Oct
/// 2026). It first did, which made every till look like a different product.
/// The mark is the product's and stays; the logo is the business's, smaller,
/// beneath it.
///
/// **It cannot fail the screen.** The logo is read from the till's own database
/// (`businessLogoProvider`, which never throws) and drawn from memory, so there
/// is no network and nothing to wait for; if the stored bytes will not decode
/// the logo is simply left out and the mark is still there, and if the mark is
/// missing too the space is empty. The shift button below does not depend on
/// any of it.
class StartLogo extends ConsumerWidget {
  const StartLogo({super.key});

  Widget _mark() => Image.asset(
    'assets/icons/xorder_logo_official.png',
    key: const Key('start-xorder-logo'),
    width: 180,
    fit: BoxFit.contain,
    // The business's name is right below; a missing asset is better absent
    // than a broken-image glyph.
    errorBuilder: (context, error, stack) => const SizedBox.shrink(),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logo = ref.watch(businessLogoProvider).valueOrNull;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _mark(),
        if (logo != null) ...[
          const SizedBox(height: PosSpace.md),
          // Drawn as it is, with no plate behind it (owner, 26 Oct 2026): the
          // white box around a logo that has its own background looked like
          // a frame on the screen. A transparent PNG with a dark mark is
          // faint on the dark theme; the Settings card still previews on a
          // plate for that reason.
          Container(
            key: const Key('start-business-logo'),
            constraints: const BoxConstraints(maxWidth: 160, maxHeight: 72),
            child: Image.memory(
              logo.bytes,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              // Decode at about twice the size it is drawn, not at the pixel
              // size of a 4000-pixel upload.
              cacheWidth: 320,
              // Undecodable bytes: no logo, and the mark above is still there.
              errorBuilder: (context, error, stack) => const SizedBox.shrink(),
            ),
          ),
        ],
      ],
    );
  }
}
