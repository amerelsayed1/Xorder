import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../setup/application/setup_controller.dart';
import '../../../app/labels.dart';
import '../../../core/l10n/app_strings.dart';
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

  /// Only used while no platform is configured — the field that ASKS for the
  /// address instead of defaulting to one nobody chose.
  final _platformController = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _keyController.dispose();
    _platformController.dispose();
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
    // And every tablet selling through this main device, which reads it from
    // the shared database rather than holding one of its own.
    if (result.installed) {
      unawaited(ref.read(siteLicencePublisherProvider).publish());
    }

    setState(() {
      _busy = false;
      _error = result.notice?.text(ref.read(stringsProvider));
      _notice = result.succeeded
          ? ref.read(stringsProvider).licenceUpdated
          : null;
    });
  }

  Future<void> _activateByKey() => _run(
    () => ref
        .read(licenceServiceProvider)
        .activate(
          deployment: ref.read(deploymentProvider),
          key: _keyController.text,
        ),
  );

  Future<void> _activateFromFile() async {
    final contents = await showDialog<String>(
      context: context,
      barrierColor: context.pos.scrim,
      builder: (_) => const _PasteLicenceDialog(),
    );
    if (contents == null || !mounted) return;

    await _run(
      () => ref
          .read(licenceServiceProvider)
          .activate(
            deployment: ref.read(deploymentProvider),
            fileContents: contents,
          ),
    );
  }

  /// Ask the platform whether a renewal has been issued.
  ///
  /// Offered in **every** mode. An offline terminal keeps its sales in the
  /// building but still renews against the hosted platform — that check-in is
  /// the whole mechanism behind the licence's offline window. What decides
  /// whether the button appears is therefore the build's licence transport, not
  /// the deployment mode.
  Future<void> _checkForRenewal() async {
    final deployment = ref.read(deploymentProvider);

    if (!ref.read(licenceServiceProvider).canActivateOnline) {
      setState(() => _notice = context.strings.cannotCheckForRenewal);
      return;
    }

    await _run(
      () => ref
          .read(licenceServiceProvider)
          .activate(deployment: deployment, key: _keyController.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entitlement = ref.watch(licenceEntitlementProvider);
    final strings = context.strings;

    return Scaffold(
      backgroundColor: context.pos.page,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: PosSize.topBar,
            padding: const EdgeInsets.symmetric(horizontal: PosSpace.s14),
            decoration: BoxDecoration(
              color: context.pos.shell,
              border: Border(bottom: context.pos.accentBorder),
            ),
            child: Row(
              children: [
                PosButton(
                  label: strings.backArrow,
                  height: 38,
                  foreground: context.pos.shellText,
                  border: Border.fromBorderSide(context.pos.shellBorder),
                  onPressed: widget.onClose,
                ),
                const SizedBox(width: PosSpace.lg),
                Text(
                  strings.licence,
                  style: PosText.ui(
                    size: 15,
                    weight: FontWeight.w800,
                    color: context.pos.shellText,
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
                        loading: () => Padding(
                          padding: EdgeInsets.all(PosSpace.xl),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: context.pos.accent,
                            ),
                          ),
                        ),
                        error: (error, _) => Text('$error'),
                        data: _StatusPanel.new,
                      ),
                      const SizedBox(height: PosSpace.s24),
                      _renewalCard(
                        ref.watch(licenceServiceProvider).canActivateOnline,
                      pos: context.pos),
                      if (_error != null) ...[
                        const SizedBox(height: PosSpace.lg),
                        _banner(
                          _error!,
                          context.pos.danger,
                          context.pos.dangerSoft,
                        pos: context.pos),
                      ],
                      if (_notice != null) ...[
                        const SizedBox(height: PosSpace.lg),
                        _banner(_notice!, context.pos.ok, context.pos.okSoft, pos: context.pos),
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

  Widget _renewalCard(bool online, {required PosPalette pos}) => Container(
    padding: const EdgeInsets.all(PosSpace.xl),
    decoration: BoxDecoration(
      color: pos.surface,
      border: Border.fromBorderSide(pos.resting),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MicroLabel(context.strings.renewThisTerminal),
        const SizedBox(height: PosSpace.md),
        // The key goes to a server, and the operator deserves to see which
        // one — a wrong address once wore a "key not recognised" costume
        // here. A terminal with no platform configured is ASKED for one,
        // never silently defaulted.
        Builder(
          builder: (context) {
            final configured = ref.watch(deploymentProvider).baseUrl;
            if (configured != null && configured.isNotEmpty) {
              return Padding(
                padding: const EdgeInsets.only(bottom: PosSpace.lg),
                child: Row(
                  children: [
                    MicroLabel(context.strings.platformCaps),
                    const SizedBox(width: PosSpace.md),
                    Expanded(
                      child: Text(
                        configured,
                        style: PosText.mono(size: 12.5, color: pos.body),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: PosSpace.lg),
              child: TextField(
                controller: _platformController,
                style: PosText.mono(color: pos.inkWarm, size: 13),
                decoration: InputDecoration(
                  labelText: context.strings.platformAddress,
                  hintText: 'https://xorder.io',
                  hintStyle: PosText.ui(size: 13, color: pos.muted),
                ),
                onChanged: (value) => ref
                    .read(deploymentProvider.notifier)
                    .apply(
                      ref
                          .read(deploymentProvider)
                          .copyWith(
                            baseUrl: SetupController.baseUrlFrom(value),
                          ),
                    ),
              ),
            );
          },
        ),
        TextField(
          controller: _keyController,
          style: PosText.mono(color: pos.inkWarm, size: 14),
          decoration: InputDecoration(
            hintText: context.strings.licenceKeyHint,
            hintStyle: PosText.ui(size: 14, color: pos.muted),
          ),
        ),
        const SizedBox(height: PosSpace.lg),
        Wrap(
          spacing: PosSpace.md,
          runSpacing: PosSpace.md,
          children: [
            PosButton(
              label: context.strings.activateKey,
              background: pos.accent,
              foreground: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: PosSpace.xl),
              onPressed: _busy ? null : _activateByKey,
            ),
            PosButton(
              label: context.strings.importLicenceFile,
              border: Border.fromBorderSide(
                BorderSide(color: pos.inkWarm),
              ),
              padding: const EdgeInsets.symmetric(horizontal: PosSpace.xl),
              onPressed: _busy ? null : _activateFromFile,
            ),
            PosButton(
              label: context.strings.checkForRenewal,
              border: Border.fromBorderSide(pos.resting),
              padding: const EdgeInsets.symmetric(horizontal: PosSpace.xl),
              onPressed: _busy ? null : _checkForRenewal,
            ),
          ],
        ),
        const SizedBox(height: PosSpace.lg),
        Text(
          online
              ? context.strings.renewalOnlineHelp
              : context.strings.renewalOfflineHelp,
          style: PosText.ui(size: 12.5, color: pos.muted, height: 1.5),
        ),
      ],
    ),
  );

  Widget _banner(String message, Color accent, Color background, {required PosPalette pos}) => Container(
    padding: const EdgeInsets.all(PosSpace.lg),
    decoration: BoxDecoration(
      color: background,
      border: Border.all(color: accent, width: 2),
    ),
    child: Text(
      message,
      style: PosText.ui(size: 13.5, color: pos.ink, height: 1.5),
    ),
  );
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel(this.entitlement);

  final LicenseEntitlement entitlement;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    // Only the paint switches here. The headline itself comes from the shared
    // `LicenseStateHeadline` extension, so the licence panel and the start
    // screen cannot drift into two different verdicts for one state.
    final (background, accent) = switch (entitlement.state) {
      LicenseState.valid => (context.pos.okSoft, context.pos.ok),
      LicenseState.expiringSoon => (context.pos.warnSoft, context.pos.warn),
      LicenseState.inGrace => (context.pos.warnSoft, context.pos.warn),
      LicenseState.expired => (context.pos.dangerSoft, context.pos.danger),
      LicenseState.missing => (context.pos.dangerSoft, context.pos.danger),
      _ => (context.pos.dangerSoft, context.pos.danger),
    };
    final headline = entitlement.state.headline(strings);

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
                  ? strings.daysRemaining(entitlement.daysRemaining!)
                  : strings.daysPastExpiry(-entitlement.daysRemaining!),
              style: PosText.mono(
                size: 20,
                weight: FontWeight.w600,
                color: context.pos.ink,
              ),
            ),
          ],
          if (entitlement.notice != null) ...[
            const SizedBox(height: PosSpace.sm),
            Text(
              entitlement.notice!.text(strings),
              style: PosText.ui(size: 13.5, color: context.pos.ink, height: 1.5),
            ),
          ],
          const SizedBox(height: PosSpace.lg),
          // Spell out what still works. An operator seeing a red panel needs to
          // know immediately whether they can cash up tonight.
          _capability(strings.capabilityOpenShift, entitlement.canOpenShift, pos: context.pos),
          _capability(strings.capabilitySell, entitlement.canSell, pos: context.pos),
          _capability(strings.capabilityCashUp, entitlement.canCashUp, pos: context.pos),
          _capability(strings.capabilityReprint, entitlement.canReprint, pos: context.pos),
          _capability(strings.capabilityExport, entitlement.canExportData, pos: context.pos),
          _capability(
            strings.capabilityConfigure,
            entitlement.canChangeConfiguration,
          pos: context.pos),
        ],
      ),
    );
  }

  Widget _capability(String label, bool allowed, {required PosPalette pos}) => Padding(
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
              color: allowed ? pos.ok : pos.danger,
            ),
          ),
        ),
        Text(
          label,
          style: PosText.ui(
            size: 13,
            color: allowed ? pos.ink : pos.body,
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
    backgroundColor: context.pos.surface,
    shape: RoundedRectangleBorder(
      side: context.pos.emphasis,
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
            Text(
              context.strings.importLicenceFile,
              style: PosText.panelTitle(color: context.pos.ink),
            ),
            const SizedBox(height: PosSpace.md),
            TextField(
              controller: _controller,
              maxLines: 6,
              style: PosText.mono(color: context.pos.inkWarm, size: 12),
              decoration: InputDecoration(
                hintText: context.strings.licenceFileHint,
              ),
            ),
            const SizedBox(height: PosSpace.lg),
            Row(
              children: [
                const Spacer(),
                PosButton(
                  label: context.strings.cancel,
                  padding: const EdgeInsets.symmetric(horizontal: PosSpace.xl),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: PosSpace.sm),
                PosButton(
                  label: context.strings.importLabel,
                  background: context.pos.accent,
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
