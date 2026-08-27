import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../data/licence_service.dart';
import '../domain/license.dart';

/// Settings → Licence. Where a licence is renewed after the terminal is set up.
///
/// This exists because renewal is the *common* case and first activation is the
/// rare one: a till is set up once and renewed every year. Burying activation
/// inside the setup wizard would mean a lapsed licence could only be fixed by
/// wiping the terminal.
class LicenceScreen extends ConsumerStatefulWidget {
  const LicenceScreen({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  ConsumerState<LicenceScreen> createState() => _LicenceScreenState();
}

class _LicenceScreenState extends ConsumerState<LicenceScreen> {
  final _keyController = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<LicenceActivationResult> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });

    final result = await action();
    if (!mounted) return;

    // Re-read the installed licence so every screen sees the new one at once.
    ref.invalidate(licenceEntitlementProvider);

    setState(() {
      _busy = false;
      _error = result.error;
      _notice = result.succeeded ? 'Licence updated.' : null;
    });
  }

  Future<void> _activateByKey() => _run(() => ref.read(licenceServiceProvider).activate(
        deployment: ref.read(deploymentProvider),
        key: _keyController.text,
      ));

  Future<void> _activateFromFile() async {
    final contents = await showDialog<String>(
      context: context,
      barrierColor: PosColors.scrim,
      builder: (_) => const _PasteLicenceDialog(),
    );
    if (contents == null || !mounted) return;

    await _run(() => ref.read(licenceServiceProvider).activate(
          deployment: ref.read(deploymentProvider),
          fileContents: contents,
        ));
  }

  /// Ask the platform whether a renewal has been issued.
  ///
  /// Only meaningful where the platform is reachable — a branch server or a
  /// standalone till has nobody to ask, and saying so is more useful than
  /// spinning forever.
  Future<void> _checkForRenewal() async {
    final deployment = ref.read(deploymentProvider);

    if (!deployment.mode.canReachPlatform) {
      setState(() => _notice =
          'This terminal is not connected to the XOrder platform, so it cannot '
          'check for a renewal. Enter a key or import the licence file instead.');
      return;
    }

    await _run(() => ref.read(licenceServiceProvider).activate(
          deployment: deployment,
          key: _keyController.text,
        ));
  }

  @override
  Widget build(BuildContext context) {
    final entitlement = ref.watch(licenceEntitlementProvider);
    final deployment = ref.watch(deploymentProvider);

    return Scaffold(
      backgroundColor: PosColors.page,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: PosSize.topBar,
            padding: const EdgeInsets.symmetric(horizontal: PosSpace.s14),
            decoration: const BoxDecoration(
              color: PosColors.shell,
              border: Border(bottom: PosBorders.accent),
            ),
            child: Row(
              children: [
                PosButton(
                  label: '← Back',
                  height: 38,
                  foreground: PosColors.shellText,
                  border: const Border.fromBorderSide(PosBorders.shell),
                  onPressed: widget.onClose,
                ),
                const SizedBox(width: PosSpace.lg),
                Text(
                  'Licence',
                  style: PosText.ui(
                    size: 15,
                    weight: FontWeight.w800,
                    color: PosColors.shellText,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(PosSpace.s28),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      entitlement.when(
                        loading: () => const Padding(
                          padding: EdgeInsets.all(PosSpace.xl),
                          child: Center(
                            child: CircularProgressIndicator(color: PosColors.accent),
                          ),
                        ),
                        error: (error, _) => Text('$error'),
                        data: _StatusPanel.new,
                      ),
                      const SizedBox(height: PosSpace.s24),
                      _renewalCard(deployment.mode.canReachPlatform),
                      if (_error != null) ...[
                        const SizedBox(height: PosSpace.lg),
                        _banner(_error!, PosColors.danger, PosColors.dangerSoft),
                      ],
                      if (_notice != null) ...[
                        const SizedBox(height: PosSpace.lg),
                        _banner(_notice!, PosColors.ok, PosColors.okSoft),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _renewalCard(bool online) => Container(
        padding: const EdgeInsets.all(PosSpace.xl),
        decoration: const BoxDecoration(
          color: PosColors.surface,
          border: Border.fromBorderSide(PosBorders.resting),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const MicroLabel('Renew this terminal'),
            const SizedBox(height: PosSpace.md),
            TextField(
              controller: _keyController,
              style: PosText.mono(size: 14),
              decoration: InputDecoration(
                hintText: 'XORD-0000-0000-0000',
                hintStyle: PosText.ui(size: 14, color: PosColors.muted),
              ),
            ),
            const SizedBox(height: PosSpace.lg),
            Wrap(
              spacing: PosSpace.md,
              runSpacing: PosSpace.md,
              children: [
                PosButton(
                  label: 'Activate key',
                  background: PosColors.accent,
                  foreground: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: PosSpace.xl),
                  onPressed: _busy ? null : _activateByKey,
                ),
                PosButton(
                  label: 'Import licence file',
                  border: const Border.fromBorderSide(BorderSide(color: PosColors.inkWarm)),
                  padding: const EdgeInsets.symmetric(horizontal: PosSpace.xl),
                  onPressed: _busy ? null : _activateFromFile,
                ),
                PosButton(
                  label: 'Check for renewal',
                  border: const Border.fromBorderSide(PosBorders.resting),
                  padding: const EdgeInsets.symmetric(horizontal: PosSpace.xl),
                  onPressed: _busy ? null : _checkForRenewal,
                ),
              ],
            ),
            const SizedBox(height: PosSpace.lg),
            Text(
              online
                  ? 'Renewals bought on the platform arrive automatically — this '
                      'terminal re-checks at start-up and before each shift opens. '
                      'The buttons above are for forcing it sooner.'
                  : 'This terminal has no route to the platform, so renewals '
                      'arrive as a file. Ask your supplier for the .xlic and '
                      'import it — no internet is needed to verify it.',
              style: PosText.ui(size: 12.5, color: PosColors.muted, height: 1.5),
            ),
          ],
        ),
      );

  Widget _banner(String message, Color accent, Color background) => Container(
        padding: const EdgeInsets.all(PosSpace.lg),
        decoration: BoxDecoration(
          color: background,
          border: Border.all(color: accent, width: 2),
        ),
        child: Text(
          message,
          style: PosText.ui(size: 13.5, color: PosColors.ink, height: 1.5),
        ),
      );
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel(this.entitlement);

  final LicenseEntitlement entitlement;

  @override
  Widget build(BuildContext context) {
    final (background, accent, headline) = switch (entitlement.state) {
      LicenseState.valid => (PosColors.okSoft, PosColors.ok, 'Licensed'),
      LicenseState.expiringSoon => (PosColors.warnSoft, PosColors.warn, 'Renewal due'),
      LicenseState.inGrace => (PosColors.warnSoft, PosColors.warn, 'Expired — in grace'),
      LicenseState.expired => (PosColors.dangerSoft, PosColors.danger, 'Expired'),
      LicenseState.missing => (PosColors.dangerSoft, PosColors.danger, 'Not licensed'),
      _ => (PosColors.dangerSoft, PosColors.danger, 'Licence problem'),
    };

    return Container(
      padding: const EdgeInsets.all(PosSpace.xl),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: accent, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            headline.toUpperCase(),
            style: PosText.mono(
              size: 12,
              weight: FontWeight.w600,
              color: accent,
              letterSpacing: 1.2,
            ),
          ),
          if (entitlement.daysRemaining != null) ...[
            const SizedBox(height: PosSpace.sm),
            Text(
              entitlement.daysRemaining! >= 0
                  ? '${entitlement.daysRemaining} days remaining'
                  : '${-entitlement.daysRemaining!} days past expiry',
              style: PosText.mono(size: 20, weight: FontWeight.w600, color: PosColors.ink),
            ),
          ],
          if (entitlement.message != null) ...[
            const SizedBox(height: PosSpace.sm),
            Text(
              entitlement.message!,
              style: PosText.ui(size: 13.5, color: PosColors.ink, height: 1.5),
            ),
          ],
          const SizedBox(height: PosSpace.lg),
          // Spell out what still works. An operator seeing a red panel needs to
          // know immediately whether they can cash up tonight.
          _capability('Open a new shift', entitlement.canOpenShift),
          _capability('Sell on an open shift', entitlement.canSell),
          _capability('Cash up, X/Z report', entitlement.canCashUp),
          _capability('Reprint a receipt', entitlement.canReprint),
          _capability('Export data', entitlement.canExportData),
          _capability('Change configuration', entitlement.canChangeConfiguration),
        ],
      ),
    );
  }

  Widget _capability(String label, bool allowed) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              child: Text(
                allowed ? '✓' : '×',
                style: PosText.mono(
                  size: 13,
                  weight: FontWeight.w600,
                  color: allowed ? PosColors.ok : PosColors.danger,
                ),
              ),
            ),
            Text(
              label,
              style: PosText.ui(
                size: 13,
                color: allowed ? PosColors.ink : PosColors.body,
              ),
            ),
          ],
        ),
      );
}

class _PasteLicenceDialog extends StatefulWidget {
  const _PasteLicenceDialog();

  @override
  State<_PasteLicenceDialog> createState() => _PasteLicenceDialogState();
}

class _PasteLicenceDialogState extends State<_PasteLicenceDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
        backgroundColor: PosColors.surface,
        shape: const RoundedRectangleBorder(
          side: PosBorders.emphasis,
          borderRadius: PosBorders.radius,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(PosSpace.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Import licence file', style: PosText.panelTitle()),
                const SizedBox(height: PosSpace.md),
                TextField(
                  controller: _controller,
                  maxLines: 6,
                  style: PosText.mono(size: 12),
                  decoration: const InputDecoration(
                    hintText: '{"payload": "...", "signature": "..."}',
                  ),
                ),
                const SizedBox(height: PosSpace.lg),
                Row(
                  children: [
                    const Spacer(),
                    PosButton(
                      label: 'Cancel',
                      padding: const EdgeInsets.symmetric(horizontal: PosSpace.xl),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: PosSpace.sm),
                    PosButton(
                      label: 'Import',
                      background: PosColors.accent,
                      foreground: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: PosSpace.xl),
                      onPressed: () => Navigator.of(context).pop(_controller.text),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
}
