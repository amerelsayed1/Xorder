import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/config/deployment.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/repositories/repositories.dart';
import '../../licensing/domain/license.dart';
import '../application/setup_controller.dart';
import '../domain/setup_state.dart';

/// The body of the current wizard step.
class SetupPane extends ConsumerWidget {
  const SetupPane({super.key, required this.draft});

  final SetupDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) => switch (draft.step) {
        SetupStep.language => _LanguagePane(draft: draft),
        SetupStep.deployment => _DeploymentPane(draft: draft),
        SetupStep.licence => _LicencePane(draft: draft),
        SetupStep.account => _AccountPane(draft: draft),
        SetupStep.branch => _BranchPane(draft: draft),
        SetupStep.terminal => _TerminalPane(draft: draft),
        SetupStep.hardware => _HardwarePane(draft: draft),
        SetupStep.money => _MoneyPane(draft: draft),
        SetupStep.catalogue => _CataloguePane(draft: draft),
        SetupStep.summary => _SummaryPane(draft: draft),
      };
}

/// A selectable card. Emphasis is a 2px ink border, never a shadow.
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.title,
    required this.blurb,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  final String title;
  final String blurb;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? PosColors.accentSoft : PosColors.surface,
        child: InkWell(
          onTap: onTap,
          hoverColor: PosColors.accentSoft,
          child: Container(
            padding: const EdgeInsets.all(PosSpace.lg),
            decoration: BoxDecoration(
              border: selected
                  ? Border.all(color: PosColors.ink, width: 2)
                  : const Border.fromBorderSide(PosBorders.resting),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: PosText.ui(size: 15, weight: FontWeight.w600, color: PosColors.ink),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        blurb,
                        style: PosText.ui(size: 12.5, color: PosColors.muted, height: 1.4),
                      ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      );
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
    this.help,
    this.mono = false,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final String? hint;
  final String? help;
  final bool mono;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MicroLabel(label),
          const SizedBox(height: PosSpace.sm),
          TextFormField(
            initialValue: value,
            onChanged: onChanged,
            style: mono ? PosText.mono(size: 14) : PosText.ui(size: 14),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: PosText.ui(size: 14, color: PosColors.muted),
            ),
          ),
          if (help != null) ...[
            const SizedBox(height: PosSpace.sm),
            Text(help!, style: PosText.ui(size: 12, color: PosColors.muted, height: 1.5)),
          ],
        ],
      );
}

class _LanguagePane extends ConsumerWidget {
  const _LanguagePane({required this.draft});

  final SetupDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(setupProvider.notifier);

    return Column(
      children: [
        _ChoiceTile(
          title: 'English',
          blurb: 'Left-to-right layout.',
          selected: draft.locale == 'en',
          onTap: () => controller.setLocale('en'),
        ),
        const SizedBox(height: PosSpace.md),
        _ChoiceTile(
          title: 'العربية',
          blurb: 'Right-to-left layout, Arabic-Indic digits on receipts.',
          selected: draft.locale == 'ar',
          onTap: () => controller.setLocale('ar'),
        ),
        const SizedBox(height: PosSpace.lg),
        Text(
          'This sets the till interface only. The menu is shown to diners in '
          'whichever languages the restaurant publishes.',
          style: PosText.ui(size: 12.5, color: PosColors.muted, height: 1.5),
        ),
      ],
    );
  }
}

class _DeploymentPane extends ConsumerWidget {
  const _DeploymentPane({required this.draft});

  final SetupDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(setupProvider.notifier);
    final config = draft.deployment;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final mode in DeploymentMode.values) ...[
          _ChoiceTile(
            title: mode.label,
            blurb: mode.blurb,
            selected: config.mode == mode,
            onTap: () => controller.setMode(mode),
          ),
          const SizedBox(height: PosSpace.md),
        ],
        if (config.mode.needsBaseUrl) ...[
          const SizedBox(height: PosSpace.sm),
          _Field(
            label: 'Server address',
            value: config.baseUrl ?? '',
            mono: true,
            hint: config.mode == DeploymentMode.cloud
                ? 'https://xorder.io'
                : 'https://192.168.1.20:8100',
            onChanged: controller.setBaseUrl,
            help: config.mode == DeploymentMode.branchServer
                ? 'The box in this branch running XOrder. Every till on this '
                    'network sends its sales here.'
                : null,
          ),
          if (config.mode == DeploymentMode.branchServer) ...[
            const SizedBox(height: PosSpace.xl),
            _Field(
              label: 'Upstream',
              value: config.upstreamUrl ?? '',
              mono: true,
              hint: 'https://xorder.io',
              onChanged: controller.setUpstreamUrl,
              help: 'Where the branch server forwards to when the internet is up. '
                  'Required: a branch that forwards nowhere is a restaurant the '
                  'platform cannot see, and every till has to be visible to '
                  'Super Admin.',
            ),
            if (config.isPrivateHost) ...[
              const SizedBox(height: PosSpace.lg),
              _ChoiceTile(
                title: 'Trust this server without a certificate',
                blurb: 'Only for a box on this local network. Never for a public address.',
                selected: !config.verifyTls,
                onTap: () => controller.setVerifyTls(!config.verifyTls),
              ),
            ],
            const SizedBox(height: PosSpace.s28),
            const MicroLabel('Branch database'),
            const SizedBox(height: PosSpace.md),
            Text(
              'This till writes its sales straight into the branch server’s '
              'PostgreSQL, so it needs an account there.',
              style: PosText.ui(size: 12.5, color: PosColors.muted, height: 1.5),
            ),
            const SizedBox(height: PosSpace.lg),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: _Field(
                    label: 'Database',
                    value: config.databaseName,
                    mono: true,
                    hint: 'xorder_pos',
                    onChanged: controller.setDatabaseName,
                  ),
                ),
                const SizedBox(width: PosSpace.lg),
                Expanded(
                  child: _Field(
                    label: 'Port',
                    value: config.databasePort.toString(),
                    mono: true,
                    hint: '5432',
                    onChanged: controller.setDatabasePort,
                  ),
                ),
              ],
            ),
            const SizedBox(height: PosSpace.xl),
            _Field(
              label: 'Database user',
              value: config.databaseUser,
              mono: true,
              hint: 'pos_till',
              onChanged: controller.setDatabaseUser,
              help: 'Use the restricted till account, not a superuser. It needs '
                  'only to read the menu and write sales.',
            ),
            const SizedBox(height: PosSpace.xl),
            _PasswordField(
              label: 'Database password',
              value: draft.databasePassword,
              onChanged: controller.setDatabasePassword,
              help: 'Kept on this machine only, and never written into the '
                  'terminal’s configuration file. You will be asked for it again '
                  'if this till is reinstalled.',
            ),
          ],
          const SizedBox(height: PosSpace.xl),
          Align(
            alignment: Alignment.centerLeft,
            child: PosButton(
              label: 'Test connection',
              border: const Border.fromBorderSide(BorderSide(color: PosColors.inkWarm)),
              padding: const EdgeInsets.symmetric(horizontal: PosSpace.xl),
              onPressed: draft.busy ? null : controller.testConnection,
            ),
          ),
        ] else
          Text(
            'No server to configure — this till keeps everything on this machine. '
            'It still checks in with the platform from time to time, and its '
            'licence sets how long it may go without doing so. Back it up: '
            'there is no second copy.',
            style: PosText.ui(size: 13, color: PosColors.warn, height: 1.5),
          ),
        const SizedBox(height: PosSpace.s28),
        const MicroLabel('Sending sales'),
        const SizedBox(height: PosSpace.md),
        for (final policy in SyncPolicy.values) ...[
          _ChoiceTile(
            title: policy.label,
            blurb: policy.blurb,
            selected: config.syncPolicy == policy,
            onTap: () => controller.setSyncPolicy(policy),
          ),
          const SizedBox(height: PosSpace.md),
        ],
        Text(
          'Every till sells offline either way — this only decides when the '
          'queue drains. The terminal reports in to the dashboard on its own '
          'schedule regardless.',
          style: PosText.ui(size: 12.5, color: PosColors.muted, height: 1.5),
        ),
      ],
    );
  }
}

class _LicencePane extends ConsumerWidget {
  const _LicencePane({required this.draft});

  final SetupDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(setupProvider.notifier);
    final online = ref.watch(licenceServiceProvider).canActivateOnline;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (online) _Field(
          label: 'Licence key',
          value: draft.licenceKey,
          mono: true,
          hint: 'XORD-0000-0000-0000',
          onChanged: controller.setLicenceKey,
        ),
        const SizedBox(height: PosSpace.lg),
        Row(
          children: [
            // Only offered when something can answer. There is no licence
            // server yet, so showing this button would be showing a button that
            // always fails — and an installer taps it three times before
            // reading the error.
            if (online) ...[
              PosButton(
                label: 'Activate online',
                background: PosColors.ink,
                foreground: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: PosSpace.xl),
                onPressed: draft.busy ? null : () => controller.activateLicence(),
              ),
              const SizedBox(width: PosSpace.md),
            ],
            PosButton(
              label: 'Activate from file',
              // Promoted to the primary action when it is the only action.
              background: online ? PosColors.surface : PosColors.ink,
              foreground: online ? PosColors.ink : Colors.white,
              border: online
                  ? const Border.fromBorderSide(BorderSide(color: PosColors.inkWarm))
                  : null,
              padding: const EdgeInsets.symmetric(horizontal: PosSpace.xl),
              // Offline activation is a first-class path, not a fallback: an
              // on-premises till may never see the internet.
              onPressed: draft.busy ? null : () => _pickFile(context, controller),
            ),
          ],
        ),
        const SizedBox(height: PosSpace.lg),
        Text(
          online
              ? 'No internet at this site? Ask your supplier for the .xlic file '
                  'and activate from it. The licence is verified on this machine '
                  '— it does not need to phone home.'
              : 'Licences are issued as a .xlic file. The signature is checked on '
                  'this machine against a key built into the app, so the till '
                  'never has to phone home — and a file that was not signed by '
                  'your supplier will not activate.',
          style: PosText.ui(size: 12.5, color: PosColors.muted, height: 1.5),
        ),
        if (draft.entitlement != null) ...[
          const SizedBox(height: PosSpace.xl),
          _LicenceStatusCard(entitlement: draft.entitlement!),
        ],
      ],
    );
  }

  Future<void> _pickFile(BuildContext context, SetupController controller) async {
    // A real file picker lands with the desktop packaging work; until then the
    // path is exercised with a paste dialog so the offline route is testable.
    final contents = await showDialog<String>(
      context: context,
      barrierColor: PosColors.scrim,
      builder: (_) => const _PasteLicenceDialog(),
    );
    if (contents == null) return;

    await controller.activateLicence(fileContents: contents);
  }
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
                Text('Paste licence file', style: PosText.panelTitle()),
                const SizedBox(height: PosSpace.md),
                TextField(
                  controller: _controller,
                  maxLines: 6,
                  style: PosText.mono(size: 12),
                  decoration: const InputDecoration(hintText: '{"payload": "...", "signature": "..."}'),
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
                      label: 'Activate',
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

class _LicenceStatusCard extends StatelessWidget {
  const _LicenceStatusCard({required this.entitlement});

  final LicenseEntitlement entitlement;

  @override
  Widget build(BuildContext context) {
    final (background, accent, headline) = switch (entitlement.state) {
      LicenseState.valid => (PosColors.okSoft, PosColors.ok, 'Licensed'),
      LicenseState.expiringSoon => (PosColors.warnSoft, PosColors.warn, 'Renewal due'),
      LicenseState.inGrace => (PosColors.warnSoft, PosColors.warn, 'Expired — in grace'),
      LicenseState.expired => (PosColors.dangerSoft, PosColors.danger, 'Expired'),
      _ => (PosColors.dangerSoft, PosColors.danger, 'Not licensed'),
    };

    return Container(
      padding: const EdgeInsets.all(PosSpace.lg),
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
              size: 11,
              weight: FontWeight.w600,
              color: accent,
              letterSpacing: 1.2,
            ),
          ),
          if (entitlement.message != null) ...[
            const SizedBox(height: PosSpace.sm),
            Text(
              entitlement.message!,
              style: PosText.ui(size: 13.5, color: PosColors.ink, height: 1.5),
            ),
          ],
          if (entitlement.state == LicenseState.expired) ...[
            const SizedBox(height: PosSpace.sm),
            Text(
              'Cash-up, reprint and data export stay available whatever the '
              'licence says.',
              style: PosText.ui(size: 12, color: PosColors.body, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }
}

class _AccountPane extends ConsumerWidget {
  const _AccountPane({required this.draft});

  final SetupDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(setupProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Field(
          label: 'Restaurant',
          value: draft.deployment.tenantSlug ?? '',
          mono: true,
          hint: 'mahsoub',
          onChanged: controller.setTenantSlug,
          // Usernames are unique per tenant on the server, so the tenant has
          // to be known before a cashier can even be looked up.
          help: 'The restaurant’s short name, as in mahsoub.xorder.io. '
              'Staff usernames are unique within a restaurant, so this has to '
              'be set before anyone can sign in.',
        ),
        const SizedBox(height: PosSpace.s28),
        for (final method in SetupMethod.values) ...[
          _ChoiceTile(
            title: method.label,
            blurb: method.blurb,
            selected: draft.method == method,
            onTap: () => controller.setMethod(method),
          ),
          const SizedBox(height: PosSpace.md),
        ],
        const SizedBox(height: PosSpace.sm),
        if (draft.method == SetupMethod.pairingCode)
          _PairingCodeFields(draft: draft)
        else
          _ManualCredentialFields(draft: draft),
      ],
    );
  }
}

/// The provisioned path: the dashboard already made this terminal, and the code
/// fetches what it decided.
class _PairingCodeFields extends ConsumerWidget {
  const _PairingCodeFields({required this.draft});

  final SetupDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(setupProvider.notifier);

    if (draft.claimed) {
      return Container(
        padding: const EdgeInsets.all(PosSpace.lg),
        decoration: const BoxDecoration(
          color: PosColors.okSoft,
          border: Border.fromBorderSide(PosBorders.resting),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Claimed as ${draft.terminalName} · ${draft.branchLabel}',
              style: PosText.ui(size: 14, weight: FontWeight.w600, color: PosColors.ink),
            ),
            const SizedBox(height: PosSpace.sm),
            Text(
              'The branch, the till name and the terminal id all came from the '
              'dashboard. The next two steps just confirm them.',
              style: PosText.ui(size: 12.5, color: PosColors.muted, height: 1.5),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Field(
          label: 'Setup code',
          value: draft.pairingCode,
          mono: true,
          hint: 'MAADI-7Q42',
          onChanged: controller.setPairingCode,
          help: 'From the dashboard, under Settings → Terminals. Codes are '
              'single-use and expire, so ask for a fresh one rather than '
              'reusing an old note.',
        ),
        const SizedBox(height: PosSpace.xl),
        Align(
          alignment: Alignment.centerLeft,
          child: PosButton(
            label: 'Claim this terminal',
            border: const Border.fromBorderSide(BorderSide(color: PosColors.inkWarm)),
            padding: const EdgeInsets.symmetric(horizontal: PosSpace.xl),
            onPressed: draft.busy || draft.pairingCode.isEmpty ? null : controller.claimTerminal,
          ),
        ),
      ],
    );
  }
}

/// The fallback path, for an installer with no dashboard access.
class _ManualCredentialFields extends ConsumerWidget {
  const _ManualCredentialFields({required this.draft});

  final SetupDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(setupProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Field(
          label: 'Username',
          value: draft.operatorUsername,
          mono: true,
          hint: 'manager',
          onChanged: controller.setOperatorUsername,
        ),
        const SizedBox(height: PosSpace.xl),
        _PasswordField(
          value: draft.operatorPassword,
          onChanged: controller.setOperatorPassword,
        ),
        const SizedBox(height: PosSpace.lg),
        Text(
          'Use the smallest account that may add a terminal, not the owner’s. '
          'This till sits in a public room, and a password typed here is a '
          'password that also opens the dashboard.',
          style: PosText.ui(size: 12.5, color: PosColors.warn, height: 1.5),
        ),
      ],
    );
  }
}

/// Obscured, and deliberately not a [_Field]: nothing else in the wizard hides
/// what it is showing.
class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.value,
    required this.onChanged,
    this.label = 'Password',
    this.help,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String label;
  final String? help;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MicroLabel(label),
          const SizedBox(height: PosSpace.sm),
          TextFormField(
            initialValue: value,
            onChanged: onChanged,
            obscureText: true,
            style: PosText.ui(size: 14),
          ),
          if (help != null) ...[
            const SizedBox(height: PosSpace.sm),
            Text(help!, style: PosText.ui(size: 12, color: PosColors.muted, height: 1.5)),
          ],
        ],
      );
}

class _BranchPane extends ConsumerWidget {
  const _BranchPane({required this.draft});

  final SetupDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branches = ref.watch(branchesProvider);
    final controller = ref.read(setupProvider.notifier);

    return branches.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(PosSpace.s28),
          child: CircularProgressIndicator(color: PosColors.accent),
        ),
      ),
      error: (error, _) => Text('$error', style: PosText.ui(color: PosColors.danger)),
      data: (list) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final branch in list) ...[
            _ChoiceTile(
              title: branch.name,
              blurb: branch.supportedOrderTypes.isEmpty
                  ? 'No order types configured'
                  : branch.supportedOrderTypes.join(' · ').replaceAll('_', '-'),
              selected: draft.branchId == branch.id,
              onTap: () => controller.setBranch(branch.id, branch.name),
              trailing: branch.code == null
                  ? null
                  : Text(branch.code!, style: PosText.mono(size: 12, color: PosColors.muted)),
            ),
            const SizedBox(height: PosSpace.md),
          ],
          const SizedBox(height: PosSpace.sm),
          Text(
            'The branch decides which order types this till offers and supplies '
            'the invoice-number prefix.',
            style: PosText.ui(size: 12.5, color: PosColors.muted, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _TerminalPane extends ConsumerWidget {
  const _TerminalPane({required this.draft});

  final SetupDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Field(
            label: 'Terminal name',
            value: draft.terminalName,
            hint: 'Counter 1',
            onChanged: ref.read(setupProvider.notifier).setTerminalName,
            help: draft.method == SetupMethod.pairingCode
                ? 'Set in the dashboard when this till was added. Change it '
                    'there rather than here, so reports keep matching.'
                : 'Shown on receipts and in shift reports, so name it the way '
                    'staff refer to it out loud.',
          ),
          if (draft.method == SetupMethod.manual) ...[
            const SizedBox(height: PosSpace.xl),
            Align(
              alignment: Alignment.centerLeft,
              child: PosButton(
                label: draft.claimed ? 'Registered' : 'Register this terminal',
                border: const Border.fromBorderSide(BorderSide(color: PosColors.inkWarm)),
                padding: const EdgeInsets.symmetric(horizontal: PosSpace.xl),
                onPressed: draft.busy || draft.claimed || draft.branchId == null
                    ? null
                    : ref.read(setupProvider.notifier).registerTerminal,
              ),
            ),
            const SizedBox(height: PosSpace.sm),
            Text(
              'Registering is what puts this till on the dashboard. If it fails '
              'you can still finish setup — the terminal registers at first '
              'sync instead.',
              style: PosText.ui(size: 12, color: PosColors.muted, height: 1.5),
            ),
          ],
          if (draft.terminalId != null) ...[
            const SizedBox(height: PosSpace.xl),
            const MicroLabel('Terminal id'),
            const SizedBox(height: PosSpace.sm),
            SelectableText(
              draft.terminalId!,
              style: PosText.mono(size: 12.5, color: PosColors.body),
            ),
            const SizedBox(height: PosSpace.sm),
            Text(
              'Generated once on this machine and never reissued — shifts and '
              'orders are tied to it. Reinstalling keeps it; a new machine gets '
              'a new one.',
              style: PosText.ui(size: 12, color: PosColors.muted, height: 1.5),
            ),
          ],
        ],
      );
}

class _HardwarePane extends ConsumerStatefulWidget {
  const _HardwarePane({required this.draft});

  final SetupDraft draft;

  @override
  ConsumerState<_HardwarePane> createState() => _HardwarePaneState();
}

class _HardwarePaneState extends ConsumerState<_HardwarePane> {
  List<DiscoveredPrinter>? _printers;
  bool _scanning = false;

  Future<void> _scan() async {
    setState(() => _scanning = true);
    final found = await ref.read(hardwarePortsProvider).discoverPrinters();
    if (!mounted) return;
    setState(() {
      _printers = found;
      _scanning = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(setupProvider.notifier);
    final draft = widget.draft;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            PosButton(
              label: _scanning ? 'Looking…' : 'Find printers',
              border: const Border.fromBorderSide(BorderSide(color: PosColors.inkWarm)),
              padding: const EdgeInsets.symmetric(horizontal: PosSpace.xl),
              onPressed: _scanning ? null : _scan,
            ),
            if (draft.printerName != null) ...[
              const SizedBox(width: PosSpace.md),
              PosButton(
                label: 'Test print',
                border: const Border.fromBorderSide(PosBorders.resting),
                padding: const EdgeInsets.symmetric(horizontal: PosSpace.xl),
                onPressed: () async {
                  final ok = await ref
                      .read(hardwarePortsProvider)
                      .testPrint(draft.printerName!);
                  if (!context.mounted) return;
                  posToast(
                    context,
                    ok ? 'Test receipt sent.' : 'Nothing printed — the sale would still complete.',
                  );
                },
              ),
            ],
          ],
        ),
        const SizedBox(height: PosSpace.lg),
        for (final printer in _printers ?? const <DiscoveredPrinter>[]) ...[
          _ChoiceTile(
            title: printer.name,
            blurb: printer.transport.toUpperCase(),
            selected: draft.printerName == printer.name,
            onTap: () => controller.setPrinter(printer.name),
          ),
          const SizedBox(height: PosSpace.md),
        ],
        const SizedBox(height: PosSpace.sm),
        _ChoiceTile(
          title: 'Cash drawer attached',
          blurb: 'Opened by the printer kick port.',
          selected: draft.drawerAttached,
          onTap: () => controller.setDrawer(!draft.drawerAttached),
        ),
        const SizedBox(height: PosSpace.md),
        _ChoiceTile(
          title: 'Barcode scanner attached',
          blurb: 'Keyboard-wedge scanners need no configuration.',
          selected: draft.scannerAttached,
          onTap: () => controller.setScanner(!draft.scannerAttached),
        ),
        const SizedBox(height: PosSpace.lg),
        Text(
          'All optional. A till with nothing attached still sells — the receipt '
          'queues and the screen says so. Printing is never on the critical '
          'path of taking money.',
          style: PosText.ui(size: 12.5, color: PosColors.muted, height: 1.5),
        ),
      ],
    );
  }
}

class _MoneyPane extends StatelessWidget {
  const _MoneyPane({required this.draft});

  final SetupDraft draft;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: const BoxDecoration(
              color: PosColors.surface,
              border: Border.fromBorderSide(PosBorders.resting),
            ),
            child: Column(
              children: [
                _row('Currency', 'EGP · 2 decimals'),
                _row('Service charge', '12% · dine-in only'),
                _row('VAT', '14% · on subtotal + service'),
                _row('Rounding', 'Half-up, once at the tax line'),
              ],
            ),
          ),
          const SizedBox(height: PosSpace.lg),
          Container(
            padding: const EdgeInsets.all(PosSpace.lg),
            decoration: BoxDecoration(
              color: PosColors.warnSoft,
              border: Border.all(color: PosColors.warn, width: 2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const MicroLabel('From device configuration', color: PosColors.warn),
                const SizedBox(height: PosSpace.sm),
                Text(
                  'These rates are held on this terminal, not issued by the '
                  'server. Every receipt printed from them says so on the slip. '
                  'Once the server owns tax, this screen becomes read-only.',
                  style: PosText.ui(size: 13, color: PosColors.ink, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _row(String label, String value) => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: PosSpace.lg,
          vertical: PosSpace.md,
        ),
        decoration: const BoxDecoration(border: Border(bottom: PosBorders.hairline)),
        child: Row(
          children: [
            Text(label, style: PosText.ui(size: 13.5)),
            const Spacer(),
            Text(value, style: PosText.mono(size: 13, color: PosColors.body)),
          ],
        ),
      );
}

class _CataloguePane extends ConsumerWidget {
  const _CataloguePane({required this.draft});

  final SetupDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: PosButton(
              label: draft.catalogueItems == null ? 'Download menu' : 'Download again',
              background: PosColors.ink,
              foreground: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: PosSpace.xl),
              onPressed: draft.busy ? null : ref.read(setupProvider.notifier).syncCatalogue,
            ),
          ),
          if (draft.catalogueItems != null) ...[
            const SizedBox(height: PosSpace.lg),
            Container(
              padding: const EdgeInsets.all(PosSpace.lg),
              decoration: BoxDecoration(
                color: PosColors.okSoft,
                border: Border.all(color: PosColors.ok, width: 2),
              ),
              child: Text(
                '${draft.catalogueItems} items cached on this terminal.',
                style: PosText.ui(size: 13.5, weight: FontWeight.w600, color: PosColors.ink),
              ),
            ),
          ],
          const SizedBox(height: PosSpace.lg),
          Text(
            'The menu is cached so the till can sell before it has ever been '
            'online again. It refreshes in the background while trading.',
            style: PosText.ui(size: 12.5, color: PosColors.muted, height: 1.5),
          ),
        ],
      );
}

class _SummaryPane extends StatelessWidget {
  const _SummaryPane({required this.draft});

  final SetupDraft draft;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('Language', draft.locale == 'ar' ? 'العربية' : 'English'),
      ('Connection', draft.deployment.mode.label),
      if (draft.deployment.baseUrl != null) ('Server', draft.deployment.baseUrl!),
      if (draft.deployment.upstreamUrl?.isNotEmpty ?? false)
        ('Upstream', draft.deployment.upstreamUrl!),
      ('Restaurant', draft.deployment.tenantSlug ?? '—'),
      ('Branch', draft.branchLabel ?? '—'),
      ('Terminal', draft.terminalName),
      ('Printer', draft.printerName ?? 'None — receipts will queue'),
      ('Cash drawer', draft.drawerAttached ? 'Attached' : 'None'),
      ('Scanner', draft.scannerAttached ? 'Attached' : 'None'),
      ('Menu', '${draft.catalogueItems ?? 0} items cached'),
      ('Licence', draft.entitlement?.state.name ?? 'none'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: const BoxDecoration(
            color: PosColors.surface,
            border: Border.fromBorderSide(PosBorders.resting),
          ),
          child: Column(
            children: [
              for (final (label, value) in rows)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: PosSpace.lg,
                    vertical: PosSpace.md,
                  ),
                  decoration: const BoxDecoration(
                    border: Border(bottom: PosBorders.hairline),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 160,
                        child: Text(label, style: PosText.ui(size: 13, color: PosColors.muted)),
                      ),
                      Expanded(
                        child: Text(
                          value,
                          overflow: TextOverflow.ellipsis,
                          style: PosText.ui(size: 13.5, weight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: PosSpace.lg),
        Text(
          'You can change any of this later in Settings, except the terminal id.',
          style: PosText.ui(size: 12.5, color: PosColors.muted),
        ),
      ],
    );
  }
}
