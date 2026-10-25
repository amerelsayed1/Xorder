import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/config/admin_mode_settings.dart';
import '../../../core/config/deployment.dart';
import '../../../core/config/lan_tls.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/certificate_fingerprint.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/permissions.dart';
import '../../../domain/models/shift.dart';
import '../../../domain/repositories/admin_repositories.dart'
    show AuditAction;
import '../../../domain/services/authorization.dart';
import '../application/admin_session.dart';
import 'admin_pane_bits.dart';
import 'admin_shortcut.dart';

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
        const SizedBox(height: PosSpace.xl),
        MicroLabel(strings.adminSignInTitle),
        const SizedBox(height: PosSpace.xs),
        Text(
          strings.adminModeSettingsHint,
          style: PosText.ui(size: 12.5, color: palette.muted, height: 1.5),
        ),
        const SizedBox(height: PosSpace.md),
        _AdminModeSettings(enabled: _mayManage),
        const SizedBox(height: PosSpace.xl),
        _LanEncryption(admin: widget.admin, enabled: _mayManage),
      ],
    );
  }
}

/// This till's LAN encryption: the certificate it trusts, or the one it
/// presents, and the technician's override.
///
/// **Both ends of a pairing read this pane.** On the main device it shows the
/// fingerprint of the certificate its PostgreSQL presents to the LAN — what
/// the person setting up a child compares against. On a till that reaches its
/// database over the network it shows what that till trusts.
///
/// **Turning encryption off lives here and nowhere else**, behind
/// `terminal.manage` like the reset beside it, because it is the same kind of
/// act: a decision about this machine that a cashier must not be able to
/// make. The audit row is written first, over the connection as it is, and a
/// change the ledger refused is not made — an override with no record is the
/// thing ADR-006 rules out. Turning it back on is a pairing: the server's
/// fingerprint is shown and confirmed, exactly as in the wizard.
class _LanEncryption extends ConsumerStatefulWidget {
  const _LanEncryption({required this.admin, required this.enabled});

  final PosStaff admin;
  final bool enabled;

  @override
  ConsumerState<_LanEncryption> createState() => _LanEncryptionState();
}

class _LanEncryptionState extends ConsumerState<_LanEncryption> {
  bool _busy = false;
  String? _refusal;

  /// What the ledger keeps: where, how, and which certificate. Never a
  /// password and never key material — there is none on a till to keep.
  static Map<String, Object?> _transportOf(DeploymentConfig config) => {
    'host': config.databaseHost,
    'transport': config.lanTls.transport.name,
    'pinned_sha256': config.lanTls.pin?.sha256,
  };

  Future<bool> _record(DeploymentConfig before, DeploymentConfig after) async {
    try {
      await ref
          .read(auditRepositoryProvider)
          .record(
            by: widget.admin,
            action: AuditAction.lanEncryptionChanged,
            entityType: AuditAction.entityTerminal,
            entityId: ref.read(posWriteContextProvider)?.terminalId,
            before: _transportOf(before),
            after: _transportOf(after),
          );
      return true;
    } on Object {
      return false;
    }
  }

  /// In force now, and in `config.json` for the next launch — the same
  /// read-modify-write the Admin Mode settings above use.
  Future<void> _apply(DeploymentConfig next) async {
    ref.read(deploymentProvider.notifier).apply(next);
    try {
      final store = ref.read(terminalConfigStoreProvider);
      final saved = await store.read();
      if (saved != null) await store.write(saved.copyWith(deployment: next));
    } on Object {
      // In force for this run; the next change tries the file again.
    }
  }

  void _refuse(String message) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _refusal = message;
    });
  }

  Future<void> _turnOff() async {
    final strings = context.strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _LanEncryptionDialog(
        strings: strings,
        title: strings.lanEncryptionTurnOffTitle,
        body: strings.lanEncryptionTurnOffBody,
        confirm: strings.lanEncryptionTurnOff,
        danger: true,
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _refusal = null;
    });

    final before = ref.read(deploymentProvider);
    // The pin goes with it: an override and a pin together would be a
    // config whose meaning depends on which rule reads it first.
    final after = before.copyWith(
      allowInsecureLan: true,
      clearPinnedCertificate: true,
    );
    if (!await _record(before, after)) {
      _refuse(strings.lanEncryptionNotRecorded);
      return;
    }
    await _apply(after);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _turnOn() async {
    final strings = context.strings;
    setState(() {
      _busy = true;
      _refusal = null;
    });

    final before = ref.read(deploymentProvider);
    final fetch = await ref
        .read(serverCertificateProbeProvider)
        .fetch(before.databaseHost.trim(), before.databasePort);
    if (!mounted) return;
    if (fetch is! CertificateFetched) {
      _refuse(strings.lanEncryptionNoCertificate);
      return;
    }
    final presented = fetch.certificate;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _LanEncryptionDialog(
        strings: strings,
        title: strings.serverCertificateTitle,
        body: strings.lanEncryptionTurnOnBody,
        confirm: strings.serverCertificateConfirm,
        certificate: presented,
      ),
    );
    if (!mounted) return;
    if (confirmed != true) {
      setState(() => _busy = false);
      return;
    }

    final after = before.copyWith(
      allowInsecureLan: false,
      pinnedCertificateSha256: presented.sha256,
      pinnedCertificatePem: presented.pem,
    );
    if (!await _record(before, after)) {
      _refuse(strings.lanEncryptionNotRecorded);
      return;
    }
    await _apply(after);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;
    final config = ref.watch(deploymentProvider);
    final tls = config.lanTls;
    final hint = PosText.ui(size: 12.5, color: palette.muted, height: 1.5);
    final overLan =
        !config.isLoopback && config.databaseHost.trim().isNotEmpty;

    final published = config.isChild
        ? null
        : ref.watch(publishedServerCertificateProvider).valueOrNull;

    return Column(
      key: const Key('terminal-lan-encryption'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MicroLabel(strings.lanEncryptionTitle),
        const SizedBox(height: PosSpace.xs),
        // The main device: what its PostgreSQL presents to the LAN.
        if (!config.isChild) ...[
          Text(
            published == null
                ? strings.serverCertificateNone
                : strings.serverCertificateThisMachine,
            style: hint,
          ),
          if (published != null) ...[
            const SizedBox(height: PosSpace.md),
            CertificateFingerprint(
              key: const Key('terminal-published-certificate'),
              sha256: published.sha256,
              notAfter: published.notAfter,
            ),
          ],
        ],
        // A till that reaches its database over the network: what it trusts.
        if (overLan) ...[
          const SizedBox(height: PosSpace.md),
          ...switch (tls.transport) {
            LanTransport.pinned => [
              Text(strings.lanEncryptedPinned, style: hint),
              if (tls.pin case final pin?) ...[
                const SizedBox(height: PosSpace.md),
                CertificateFingerprint(
                  key: const Key('terminal-pinned-certificate'),
                  sha256: pin.sha256,
                  notAfter: LanTls.notAfterOfPem(pin.pem),
                ),
              ],
            ],
            LanTransport.verifiedChain => [
              Text(strings.lanEncryptedVerified, style: hint),
            ],
            LanTransport.insecureLan => [
              Container(
                key: const Key('terminal-insecure-lan'),
                padding: const EdgeInsets.all(PosSpace.md),
                decoration: BoxDecoration(
                  color: palette.warnSoft,
                  border: Border.all(color: palette.warn, width: 2),
                ),
                child: Text(
                  strings.insecureLanWarning,
                  style: PosText.ui(
                    size: 13,
                    color: palette.ink,
                    height: 1.5,
                  ),
                ),
              ),
            ],
            LanTransport.loopback => const <Widget>[],
          },
          const SizedBox(height: PosSpace.md),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: config.isInsecureLan
                ? PosButton(
                    key: const Key('terminal-lan-encryption-on'),
                    label: strings.lanEncryptionTurnOn,
                    background: palette.ink,
                    foreground: palette.onInk,
                    onPressed: widget.enabled && !_busy ? _turnOn : null,
                  )
                // Offered only where the override would take effect: on a
                // public host it is ignored, and a button that did nothing
                // would be worse than none.
                : config.isPrivateHost
                ? PosButton(
                    key: const Key('terminal-lan-encryption-off'),
                    label: strings.lanEncryptionTurnOff,
                    border: Border.fromBorderSide(
                      BorderSide(color: palette.danger),
                    ),
                    foreground: palette.danger,
                    onPressed: widget.enabled && !_busy ? _turnOff : null,
                  )
                : const SizedBox.shrink(),
          ),
        ],
        if (_refusal != null) ...[
          const SizedBox(height: PosSpace.md),
          Text(
            _refusal!,
            key: const Key('terminal-lan-encryption-refused'),
            style: PosText.ui(size: 12.5, color: palette.danger, height: 1.5),
          ),
        ],
      ],
    );
  }
}

/// Confirms a change to this till's LAN encryption. With [certificate], the
/// fingerprint to compare is the body of the question.
class _LanEncryptionDialog extends StatelessWidget {
  const _LanEncryptionDialog({
    required this.strings,
    required this.title,
    required this.body,
    required this.confirm,
    this.certificate,
    this.danger = false,
  });

  final AppStrings strings;
  final String title;
  final String body;
  final String confirm;
  final PresentedCertificate? certificate;
  final bool danger;

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: context.pos.page,
    insetPadding: const EdgeInsets.all(PosSpace.s24),
    shape: RoundedRectangleBorder(
      side: context.pos.emphasis,
      borderRadius: PosBorders.radius,
    ),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Padding(
        padding: const EdgeInsets.all(PosSpace.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: PosText.panelTitle(color: context.pos.ink)),
            const SizedBox(height: PosSpace.sm),
            Text(
              body,
              style: PosText.ui(size: 13, color: context.pos.muted, height: 1.5),
            ),
            if (certificate case final shown?) ...[
              const SizedBox(height: PosSpace.lg),
              CertificateFingerprint(
                sha256: shown.sha256,
                notAfter: shown.notAfter,
              ),
            ],
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
                    key: const Key('terminal-lan-encryption-confirm'),
                    label: confirm,
                    background: danger ? context.pos.danger : context.pos.ink,
                    foreground: danger ? Colors.white : context.pos.onInk,
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

/// Which chord opens Admin Mode on this till, and how long it stays open with
/// nobody touching it.
///
/// Here, beside the reset, because both are facts about this machine rather
/// than the restaurant — and behind the same `terminal.manage`, so the person
/// who may wipe the till is the person who may change how its back office is
/// reached.
class _AdminModeSettings extends ConsumerWidget {
  const _AdminModeSettings({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.strings;
    final palette = context.pos;
    final settings = ref.watch(adminModeSettingsProvider);
    final controller = ref.read(adminModeSettingsProvider.notifier);
    final label = PosText.ui(size: 13, color: palette.muted);
    final choice = PosText.ui(color: palette.inkWarm, size: 13);

    return Wrap(
      spacing: PosSpace.xl,
      runSpacing: PosSpace.md,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(strings.adminLockAfter, style: label),
            const SizedBox(width: PosSpace.sm),
            DropdownButton<int>(
              key: const Key('admin-timeout'),
              value: settings.timeoutMinutes,
              underline: const SizedBox.shrink(),
              style: choice,
              items: [
                for (final minutes in AdminModeSettings.timeoutChoices)
                  DropdownMenuItem(
                    value: minutes,
                    child: Text(strings.adminMinutes(minutes)),
                  ),
              ],
              onChanged: enabled
                  ? (minutes) {
                      if (minutes == null) return;
                      controller.save(
                        settings.copyWith(timeoutMinutes: minutes),
                      );
                    }
                  : null,
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(strings.adminShortcut, style: label),
            const SizedBox(width: PosSpace.sm),
            DropdownButton<AdminShortcut>(
              key: const Key('admin-shortcut'),
              value: settings.shortcut,
              underline: const SizedBox.shrink(),
              style: choice,
              items: [
                for (final shortcut in AdminShortcut.values)
                  DropdownMenuItem(
                    value: shortcut,
                    // Key names, not words: the same on every keyboard, in
                    // either language, and always left to right.
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(adminShortcutLabel(shortcut)),
                    ),
                  ),
              ],
              onChanged: enabled
                  ? (shortcut) {
                      if (shortcut == null) return;
                      controller.save(settings.copyWith(shortcut: shortcut));
                    }
                  : null,
            ),
          ],
        ),
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
