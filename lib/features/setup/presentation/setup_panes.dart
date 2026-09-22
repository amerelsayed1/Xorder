import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/config/deployment.dart';
import '../../../core/config/platform_endpoint.dart';
import '../../../core/config/printer_config.dart';
import '../../../app/labels.dart';
import '../../../core/l10n/app_strings.dart';
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
    SetupStep.setupType => _SetupTypePane(draft: draft),
    SetupStep.language => _LanguagePane(draft: draft),
    SetupStep.deployment => _DeploymentPane(draft: draft),
    SetupStep.licence => _LicencePane(draft: draft),
    SetupStep.account => _AccountPane(draft: draft),
    SetupStep.branch => _BranchPane(draft: draft),
    SetupStep.terminal => _TerminalPane(draft: draft),
    SetupStep.connecting => _ConnectingPane(draft: draft),
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
    this.enabled = true,
    this.trailing,
  });

  final String title;
  final String blurb;
  final bool selected;
  final VoidCallback onTap;

  /// A choice that exists but is not this customer's. Rendered flat and inert
  /// rather than removed — see the note where the deployment tiles are built.
  final bool enabled;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Material(
    color: !enabled
        ? context.pos.page
        : (selected ? context.pos.accentSoft : context.pos.surface),
    child: InkWell(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.all(PosSpace.lg),
        decoration: BoxDecoration(
          border: selected
              ? Border.all(color: context.pos.ink, width: 2)
              : Border.fromBorderSide(context.pos.resting),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: PosText.ui(
                      size: 15,
                      weight: FontWeight.w600,
                      color: enabled ? context.pos.ink : context.pos.muted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    blurb,
                    style: PosText.ui(
                      size: 12.5,
                      color: context.pos.muted,
                      height: 1.4,
                    ),
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

class _Field extends StatefulWidget {
  const _Field({
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
    this.help,
    this.mono = false,
    this.readOnly = false,
    this.error,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final String? hint;
  final String? help;

  /// Why this value cannot be used, shown in place of [help].
  ///
  /// Inline rather than in the error bar at the foot of the screen, because
  /// this kind of refusal belongs to ONE field and usually disables Continue —
  /// and a Continue that dims with no visible reason is indistinguishable from
  /// a broken button.
  final String? error;
  final bool mono;

  /// A value that arrived from somewhere authoritative — a licence, or a
  /// redeemed pairing code — and is shown for confirmation rather than input.
  /// Editing it could only ever contradict its source.
  final bool readOnly;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  late final TextEditingController _controller;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  /// Push a value in from outside — but NEVER while the operator is typing.
  ///
  /// This used to rewrite the controller whenever the parent's value differed,
  /// which silently ate a keystroke. The setters transform what they are given
  /// (a PIN keeps only digits, a slug is lowercased) and they also churn other
  /// state, so a rebuild can land carrying the value from *before* the last
  /// character — and this then wrote that stale value back over the field. The
  /// operator saw four dots for five digits, and only found out their PIN was
  /// not what they typed when it would not let them in.
  ///
  /// While the field has focus the person at the keyboard is the source of
  /// truth. Values from elsewhere — a prefill, an adopted terminal, a slug the
  /// licence supplied — only ever arrive when it does not.
  @override
  void didUpdateWidget(covariant _Field oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_focus.hasFocus) return;
    if (_controller.text != widget.value) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      MicroLabel(widget.label),
      const SizedBox(height: PosSpace.sm),
      TextFormField(
        // The field identity must not contain its value. Doing that
        // destroys and recreates the TextFormField after every keystroke,
        // which drops keyboard focus and makes an operator type only one
        // character at a time. The label is stable within each pane.
        key: ValueKey('${widget.label}:${widget.readOnly}'),
        controller: _controller,
        focusNode: _focus,
        onChanged: widget.onChanged,
        readOnly: widget.readOnly,
        style: widget.mono
            ? PosText.mono(
                size: 14,
                color: widget.readOnly ? context.pos.muted : context.pos.ink,
              )
            : PosText.ui(
                size: 14,
                color: widget.readOnly ? context.pos.muted : context.pos.ink,
              ),
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: PosText.ui(size: 14, color: context.pos.muted),
        ),
      ),
      if (widget.error != null) ...[
        const SizedBox(height: PosSpace.sm),
        Text(
          widget.error!,
          style: PosText.ui(size: 12, color: context.pos.danger, height: 1.5),
        ),
      ] else if (widget.help != null) ...[
        const SizedBox(height: PosSpace.sm),
        Text(
          widget.help!,
          style: PosText.ui(size: 12, color: context.pos.muted, height: 1.5),
        ),
      ],
    ],
  );
}

class _LanguagePane extends ConsumerWidget {
  const _LanguagePane({required this.draft});

  final SetupDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.strings;
    final controller = ref.read(setupProvider.notifier);

    return Column(
      children: [
        // Each language names ITSELF, in itself — the whole point of this
        // step is that somebody who cannot read the current one can still
        // find their own.
        _ChoiceTile(
          title: const EnStrings().languageName,
          blurb: s.englishBlurb,
          selected: draft.locale == 'en',
          onTap: () => controller.setLocale('en'),
        ),
        const SizedBox(height: PosSpace.md),
        _ChoiceTile(
          title: const ArStrings().languageName,
          blurb: s.arabicBlurb,
          selected: draft.locale == 'ar',
          onTap: () => controller.setLocale('ar'),
        ),
        const SizedBox(height: PosSpace.lg),
        Text(
          s.languagePaneHelp,
          style: PosText.ui(size: 12.5, color: context.pos.muted, height: 1.5),
        ),
      ],
    );
  }
}

/// The first question: which product is this terminal (owner's phase-1 notes).
///
/// Both modes are selectable, each dimmed only when the LICENCE does not cover
/// it. Dimmed rather than hidden for the same reason the deployment pane greys
/// unlicensed modes — a missing tile reads as a broken build, a dimmed one
/// reads as something the customer did not buy.
class _SetupTypePane extends ConsumerWidget {
  const _SetupTypePane({required this.draft});

  final SetupDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.strings;
    final controller = ref.read(setupProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final mode in DeploymentMode.values) ...[
          _ChoiceTile(
            title: mode.label(s),
            blurb: mode.blurb(s),
            selected: draft.deployment.mode == mode,
            // The licence decides. A tile the customer did not buy stays
            // visible so the operator can see what exists and ask for it.
            enabled: draft.licensedModes.contains(mode),
            onTap: () => controller.setMode(mode),
            trailing: draft.licensedModes.contains(mode)
                ? null
                : MicroLabel(s.notLicensedBadge),
          ),
          const SizedBox(height: PosSpace.md),
        ],
        const SizedBox(height: PosSpace.sm),
        Text(
          draft.deployment.mode == DeploymentMode.offline
              ? s.setupTypeOfflineHelp
              : s.setupTypeCloudHelp,
          style: PosText.ui(size: 12.5, color: context.pos.muted, height: 1.5),
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
    final s = context.strings;
    final controller = ref.read(setupProvider.notifier);
    final config = draft.deployment;

    // A tablet builds nothing and chooses nothing here: it finds its main
    // device. See [TerminalRole].
    if (config.isChild) return _MainDevicePane(draft: draft);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The mode was chosen on the first step; restating it here as a fact
        // rather than a second question keeps the wizard linear.
        Row(
          children: [
            MicroLabel(s.stepSetupType.toUpperCase()),
            const SizedBox(width: PosSpace.md),
            Text(
              config.mode.label(s).toUpperCase(),
              style: PosText.mono(
                size: 12,
                weight: FontWeight.w700,
                color: context.pos.ink,
              ),
            ),
          ],
        ),
        if (config.mode.needsBaseUrl) ...[
          const SizedBox(height: PosSpace.xl),
          _Field(
            label: s.platformAddress,
            value: config.baseUrl ?? '',
            mono: true,
            hint: 'https://xorder.io',
            onChanged: controller.setBaseUrl,
            help: s.platformAddressHelp,
          ),
        ],
        const SizedBox(height: PosSpace.s28),
        MicroLabel(s.theDatabase),
        const SizedBox(height: PosSpace.md),
        Text(
          // The plan decides the shape, so the wizard states which one this
          // licence bought rather than asking a question the operator cannot
          // answer correctly on their own.
          draft.allowsSharedDatabase
              ? s.sharedDatabaseHelp(draft.maxTerminals)
              : s.singleMachineHelp,
          style: PosText.ui(
            size: 12.5,
            color: draft.allowsSharedDatabase
                ? context.pos.muted
                : context.pos.warn,
            height: 1.5,
          ),
        ),
        const SizedBox(height: PosSpace.lg),
        if (draft.allowsSharedDatabase) ...[
          _Field(
            label: s.databaseHost,
            value: config.databaseHost,
            mono: true,
            hint: '192.168.1.20',
            onChanged: controller.setDatabaseHost,
            help: s.databaseHostHelp,
          ),
          if (config.isPrivateHost && !config.isSingleMachine) ...[
            const SizedBox(height: PosSpace.lg),
            _ChoiceTile(
              title: s.trustWithoutCertificate,
              blurb: s.trustWithoutCertificateBlurb,
              selected: !config.verifyTls,
              onTap: () => controller.setVerifyTls(!config.verifyTls),
            ),
          ],
          const SizedBox(height: PosSpace.xl),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: _Field(
                label: s.databaseName,
                value: config.databaseName,
                mono: true,
                hint: 'xorder_pos',
                // Said HERE and now, not five steps later out of the DDL. This
                // rule also disables Continue, and a button that dims with no
                // visible reason reads as a broken button.
                error:
                    config.databaseName.isEmpty || config.hasValidDatabaseName
                    ? null
                    : s.databaseNameInvalid(config.databaseName),
                onChanged: controller.setDatabaseName,
              ),
            ),
            const SizedBox(width: PosSpace.lg),
            Expanded(
              child: _Field(
                label: s.databasePort,
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
          label: s.databaseUser,
          value: config.databaseUser,
          mono: true,
          hint: 'pos_till',
          onChanged: controller.setDatabaseUser,
          help: s.databaseUserHelp,
        ),
        const SizedBox(height: PosSpace.xl),
        // Shown only when the keystore itself refused at boot — not when it was
        // simply empty. Typing a password here will be accepted either way, so
        // the operator has to learn *now* that this one will not survive a
        // restart, rather than tomorrow morning when the wizard reappears.
        if (ref.watch(terminalSeedProvider).credentialStoreUnavailable) ...[
          Container(
            padding: const EdgeInsets.all(PosSpace.lg),
            decoration: BoxDecoration(
              color: context.pos.warnSoft,
              border: Border.all(color: context.pos.warn, width: 2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MicroLabel(s.keystoreUnavailable, color: context.pos.warn),
                const SizedBox(height: PosSpace.sm),
                Text(
                  s.keystoreUnavailableHelp,
                  style: PosText.ui(
                    size: 13,
                    color: context.pos.ink,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: PosSpace.xl),
        ],
        _PasswordField(
          field: 'database',
          label: s.databasePassword,
          value: draft.databasePassword,
          onChanged: controller.setDatabasePassword,
          help: s.databasePasswordHelp,
        ),
        const SizedBox(height: PosSpace.xl),
        Align(
          alignment: Alignment.centerLeft,
          child: PosButton(
            label: s.testConnection,
            border: Border.fromBorderSide(
              BorderSide(color: context.pos.inkWarm),
            ),
            padding: const EdgeInsets.symmetric(horizontal: PosSpace.xl),
            onPressed: draft.busy ? null : controller.testConnection,
          ),
        ),
        // The first install itself — building the database and creating the
        // person who will run it — is the NEXT step. This screen answers only
        // "where does the database live"; who may open the till is a different
        // question and was being asked under a heading about sales.
        // Only cloud has a queue to drain. Offering the choice to an offline
        // terminal asked it to decide when to send sales it never sends.
        if (config.mode.syncsSalesToPlatform) ...[
          const SizedBox(height: PosSpace.s28),
          MicroLabel(s.sendingSales),
          const SizedBox(height: PosSpace.md),
          for (final policy in SyncPolicy.values) ...[
            _ChoiceTile(
              title: policy.label(s),
              blurb: policy.blurb(s),
              selected: config.syncPolicy == policy,
              onTap: () => controller.setSyncPolicy(policy),
            ),
            const SizedBox(height: PosSpace.md),
          ],
          Text(
            s.sendingSalesHelp,
            style: PosText.ui(size: 12.5, color: context.pos.muted, height: 1.5),
          ),
        ],
      ],
    );
  }
}

/// A child tablet's connection step: where the main device is, and the till
/// password it was set up with. Connecting reads the licence it shares.
class _MainDevicePane extends ConsumerWidget {
  const _MainDevicePane({required this.draft});

  final SetupDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.strings;
    final controller = ref.read(setupProvider.notifier);
    final config = draft.deployment;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          s.mainDeviceHelp,
          style: PosText.ui(size: 12.5, color: context.pos.muted, height: 1.5),
        ),
        const SizedBox(height: PosSpace.xl),
        _Field(
          label: s.mainDeviceAddress,
          value: config.databaseHost,
          mono: true,
          hint: '192.168.1.20',
          onChanged: controller.setDatabaseHost,
          help: s.mainDeviceAddressHelp,
        ),
        if (config.isPrivateHost && !config.isSingleMachine) ...[
          const SizedBox(height: PosSpace.lg),
          _ChoiceTile(
            title: s.trustWithoutCertificate,
            blurb: s.trustWithoutCertificateBlurb,
            selected: !config.verifyTls,
            onTap: () => controller.setVerifyTls(!config.verifyTls),
          ),
        ],
        const SizedBox(height: PosSpace.xl),
        // Defaults every install the wizard made shares; shown because one set
        // up by hand may not.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: _Field(
                label: s.databaseName,
                value: config.databaseName,
                mono: true,
                hint: 'xorder_pos',
                onChanged: controller.setDatabaseName,
              ),
            ),
            const SizedBox(width: PosSpace.lg),
            Expanded(
              child: _Field(
                label: s.databasePort,
                value: config.databasePort.toString(),
                mono: true,
                hint: '5432',
                onChanged: controller.setDatabasePort,
              ),
            ),
          ],
        ),
        const SizedBox(height: PosSpace.xl),
        _PasswordField(
          field: 'database',
          label: s.databasePassword,
          value: draft.databasePassword,
          onChanged: controller.setDatabasePassword,
          help: s.databasePasswordHelp,
        ),
        const SizedBox(height: PosSpace.xl),
        Align(
          alignment: Alignment.centerLeft,
          child: PosButton(
            label: s.connectToMainDevice,
            background: context.pos.ink,
            foreground: context.pos.onInk,
            padding: const EdgeInsets.symmetric(horizontal: PosSpace.xl),
            onPressed:
                draft.busy ||
                    config.databaseHost.trim().isEmpty ||
                    draft.databasePassword.isEmpty
                ? null
                : controller.connectToMainDevice,
          ),
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
    final s = context.strings;
    final controller = ref.read(setupProvider.notifier);
    final online = ref.watch(licenceServiceProvider).canActivateOnline;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (online) ...[
          _Field(
            label: s.licenceKey,
            value: draft.licenceKey,
            mono: true,
            hint: s.licenceKeyHint,
            onChanged: controller.setLicenceKey,
          ),
          const SizedBox(height: PosSpace.lg),
          // The platform this key will be sent to, SHOWN rather than assumed.
          //
          // Its absence is what made the commonest activation failure
          // unreadable: a key issued by one platform, typed into a till built
          // to ask another, is refused perfectly correctly — and the message
          // said only "not recognised", so the installer went hunting for a
          // typo in a key that was fine. The address is the answer, and it
          // belongs on the screen where the question is asked.
          //
          // Editable, and that costs nothing: every licence is Ed25519-signed
          // and checked against a key compiled into this binary, so a hostile
          // address cannot mint one that passes. The most it can hand over is
          // bytes, and bytes that fail verification are refused.
          _Field(
            label: s.licenceServer,
            value: draft.deployment.licenceServerUrl ?? PlatformEndpoint.base,
            mono: true,
            hint: PlatformEndpoint.base,
            help: s.licenceServerHelp,
            onChanged: controller.setLicenceServer,
          ),
        ],
        const SizedBox(height: PosSpace.lg),
        // Only offered when something can answer. A build with no licence
        // transport would be showing a button that always fails — and an
        // installer taps it three times before reading the error.
        if (online)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: PosButton(
              label: s.activateOnline,
              background: context.pos.ink,
              foreground: context.pos.onInk,
              padding: const EdgeInsets.symmetric(horizontal: PosSpace.xl),
              onPressed: draft.busy ? null : () => controller.activateLicence(),
            ),
          ),
        const SizedBox(height: PosSpace.lg),
        Text(
          online ? s.licenceOnlineHelp : s.licenceOfflineHelp,
          style: PosText.ui(size: 12.5, color: context.pos.muted, height: 1.5),
        ),
        if (draft.entitlement != null) ...[
          const SizedBox(height: PosSpace.xl),
          _LicenceStatusCard(entitlement: draft.entitlement!),
        ],
        // What the licence bought, stated here rather than discovered two steps
        // later. `max_terminals` is what decides whether the connection step
        // will let the database live on another machine.
        if (draft.claims case final claims?) ...[
          const SizedBox(height: PosSpace.lg),
          Text(
            s.licenceCoverage(
              claims.tenantName.isEmpty ? claims.tenantSlug : claims.tenantName,
              claims.plan,
              claims.maxTerminals,
            ),
            style: PosText.ui(size: 12.5, color: context.pos.body, height: 1.5),
          ),
        ],
      ],
    );
  }
}

class _LicenceStatusCard extends StatelessWidget {
  const _LicenceStatusCard({required this.entitlement});

  final LicenseEntitlement entitlement;

  @override
  Widget build(BuildContext context) {
    final headline = entitlement.state.headline(context.strings);
    final (background, accent) = switch (entitlement.state) {
      LicenseState.valid => (context.pos.okSoft, context.pos.ok),
      LicenseState.expiringSoon => (context.pos.warnSoft, context.pos.warn),
      LicenseState.inGrace => (context.pos.warnSoft, context.pos.warn),
      LicenseState.expired => (context.pos.dangerSoft, context.pos.danger),
      _ => (context.pos.dangerSoft, context.pos.danger),
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
          if (entitlement.notice != null) ...[
            const SizedBox(height: PosSpace.sm),
            Text(
              entitlement.notice!.text(context.strings),
              style: PosText.ui(size: 13.5, color: context.pos.ink, height: 1.5),
            ),
          ],
          if (entitlement.state == LicenseState.expired) ...[
            const SizedBox(height: PosSpace.sm),
            Text(
              context.strings.cashUpNeverGated,
              style: PosText.ui(size: 12, color: context.pos.body, height: 1.5),
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

    // A child signs in as a manager its main device already has. The
    // restaurant came with the shared licence, so it is shown and not asked.
    if (draft.deployment.isChild) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Field(
            label: context.strings.restaurant,
            value: draft.tenantName ??
                draft.claims?.tenantName ??
                draft.deployment.tenantSlug ??
                '',
            readOnly: true,
            onChanged: (_) {},
          ),
          const SizedBox(height: PosSpace.s28),
          _ManualCredentialFields(draft: draft),
        ],
      );
    }

    // An offline till has no platform to sign in to and no account to sign in
    // WITH — the first administrator does not exist anywhere yet. Asking for a
    // dashboard username here offered credentials that cannot exist and a
    // "connect & pull" that has nothing to pull, and `canAdvance` then required
    // a connection an offline terminal can never make: the path was blocked at
    // this step. So on this path the question is the honest one — who is the
    // first person who may open this till — and answering it is what builds
    // the database.
    if (draft.deployment.mode == DeploymentMode.offline) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [_FirstInstallFields(draft: draft)],
      );
    }

    final s = context.strings;
    final pairing = draft.method == SetupMethod.pairingCode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The restaurant, STATED. The licence names exactly one tenant and it
        // was installed a screen ago; letting an operator retype it here could
        // only ever produce a slug that contradicts their own licence, which
        // the verifier would then reject as a tenant mismatch on a licence that
        // was perfectly good.
        _Field(
          label: s.restaurant,
          value: draft.deployment.tenantSlug ?? '',
          mono: true,
          hint: 'mahsoub',
          readOnly: draft.claims != null,
          onChanged: controller.setTenantSlug,
          // Usernames are unique per tenant on the server, so the tenant has
          // to be known before a cashier can even be looked up.
          help: draft.claims != null
              ? s.restaurantFromLicenceHelp
              : s.restaurantHelp,
        ),
        const SizedBox(height: PosSpace.s28),
        // One road, not a junction. The two tiles that used to be here asked
        // the installer to choose between a code and a staff password before
        // either had been typed — a question with an obvious answer nine times
        // out of ten, in front of somebody who had not been told which one they
        // were holding. The code is the road; the other is a link off it.
        if (pairing)
          _PairingCodeFields(draft: draft)
        else
          _ManualCredentialFields(draft: draft),
        const SizedBox(height: PosSpace.lg),
        if (!draft.claimed && !draft.connected)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: PosButton(
              label: pairing ? s.signInInstead : s.useASetupCodeInstead,
              background: Colors.transparent,
              foreground: context.pos.accent,
              padding: const EdgeInsets.symmetric(horizontal: PosSpace.sm),
              onPressed: draft.busy
                  ? null
                  : () => controller.setMethod(
                      pairing ? SetupMethod.manual : SetupMethod.pairingCode,
                    ),
            ),
          ),
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
        decoration: BoxDecoration(
          color: context.pos.okSoft,
          border: Border.fromBorderSide(context.pos.resting),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.strings.claimedAs(
                draft.terminalName,
                draft.branchLabel ?? '',
              ),
              style: PosText.ui(
                size: 14,
                weight: FontWeight.w600,
                color: context.pos.ink,
              ),
            ),
            const SizedBox(height: PosSpace.sm),
            Text(
              context.strings.claimedFromDashboardHelp,
              style: PosText.ui(
                size: 12.5,
                color: context.pos.muted,
                height: 1.5,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Field(
          label: context.strings.setupCode,
          value: draft.pairingCode,
          mono: true,
          hint: 'MAADI-7Q42',
          onChanged: controller.setPairingCode,
          help: context.strings.setupCodeHelp,
        ),
        const SizedBox(height: PosSpace.xl),
        Align(
          alignment: Alignment.centerLeft,
          child: PosButton(
            label: context.strings.claimThisTerminal,
            border: Border.fromBorderSide(
              BorderSide(color: context.pos.inkWarm),
            ),
            padding: const EdgeInsets.symmetric(horizontal: PosSpace.xl),
            onPressed: draft.busy || draft.pairingCode.isEmpty
                ? null
                : controller.claimTerminal,
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
    final s = context.strings;
    final controller = ref.read(setupProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Field(
          label: s.username,
          value: draft.operatorUsername,
          mono: true,
          hint: 'manager',
          onChanged: controller.setOperatorUsername,
        ),
        const SizedBox(height: PosSpace.xl),
        _PasswordField(
          field: 'operator',
          label: s.managerPassword,
          value: draft.operatorPassword,
          onChanged: controller.setOperatorPassword,
        ),
        const SizedBox(height: PosSpace.lg),
        Text(
          s.manualCredentialsWarning,
          style: PosText.ui(size: 12.5, color: context.pos.warn, height: 1.5),
        ),
        const SizedBox(height: PosSpace.xl),
        if (draft.connected)
          Container(
            padding: const EdgeInsets.all(PosSpace.lg),
            decoration: BoxDecoration(
              color: context.pos.okSoft,
              border: Border.fromBorderSide(context.pos.resting),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.connectedTo(
                    draft.tenantName ?? draft.deployment.tenantSlug ?? '',
                  ),
                  style: PosText.ui(
                    size: 14,
                    weight: FontWeight.w600,
                    color: context.pos.ink,
                  ),
                ),
                const SizedBox(height: PosSpace.sm),
                Text(
                  s.branchesRetrieved(draft.pulledBranches?.length ?? 0),
                  style: PosText.ui(
                    size: 12.5,
                    color: context.pos.muted,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          )
        else
          Align(
            alignment: Alignment.centerLeft,
            child: PosButton(
              label: s.connectAndPullConfiguration,
              border: Border.fromBorderSide(
                BorderSide(color: context.pos.inkWarm),
              ),
              padding: const EdgeInsets.symmetric(horizontal: PosSpace.xl),
              onPressed:
                  draft.busy ||
                      draft.operatorUsername.trim().isEmpty ||
                      draft.operatorPassword.isEmpty ||
                      (draft.deployment.tenantSlug?.isEmpty ?? true)
                  ? null
                  : controller.connectTenant,
            ),
          ),
      ],
    );
  }
}

/// Obscured, and deliberately not a [_Field]: nothing else in the wizard hides
/// what it is showing.
class _PasswordField extends StatefulWidget {
  const _PasswordField({
    required this.value,
    required this.onChanged,
    required this.field,
    this.label,
    this.help,
  });

  final String value;
  final ValueChanged<String> onChanged;

  /// Which password this is, for the form key. Stable across languages, unlike
  /// [label] — keying on the caption would remount the field when the wizard's
  /// language changes and take whatever was half-typed with it.
  final String field;

  /// Defaults to the generic "Password" when the caller has nothing more
  /// specific to say.
  final String? label;
  final String? help;

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  late final TextEditingController _controller;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  /// Same rule as [_FieldState], and it matters more here: the swallowed
  /// character is in a PIN or a database password, so nothing looks wrong until
  /// a credential that was typed correctly is refused.
  @override
  void didUpdateWidget(covariant _PasswordField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_focus.hasFocus) return;
    if (_controller.text != widget.value) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      MicroLabel(widget.label ?? context.strings.password),
      const SizedBox(height: PosSpace.sm),
      TextFormField(
        key: ValueKey('${widget.field}:password'),
        controller: _controller,
        focusNode: _focus,
        onChanged: widget.onChanged,
        obscureText: true,
        style: PosText.ui(color: context.pos.inkWarm, size: 14),
      ),
      if (widget.help != null) ...[
        const SizedBox(height: PosSpace.sm),
        Text(
          widget.help!,
          style: PosText.ui(size: 12, color: context.pos.muted, height: 1.5),
        ),
      ],
    ],
  );
}

class _BranchPane extends ConsumerWidget {
  const _BranchPane({required this.draft});

  final SetupDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(setupProvider.notifier);

    // The credentials pull already brought the branch list from the platform;
    // on a fresh cloud terminal the local database is empty until the
    // bootstrap seeds it, so the pull is the only truthful source.
    final pulled = draft.pulledBranches;
    if (pulled != null) {
      return _branchList(context, controller, pulled);
    }

    final branches = ref.watch(branchesProvider);
    return branches.when(
      loading: () => Center(
        child: Padding(
          padding: EdgeInsets.all(PosSpace.s28),
          child: CircularProgressIndicator(color: context.pos.accent),
        ),
      ),
      error: (error, _) =>
          Text('$error', style: PosText.ui(color: context.pos.danger)),
      data: (list) => _branchList(context, controller, list),
    );
  }

  Widget _branchList(
    BuildContext context,
    SetupController controller,
    List<PosBranch> list,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final branch in list) ...[
        _ChoiceTile(
          title: branch.name,
          blurb: branch.supportedOrderTypes.isEmpty
              ? context.strings.noOrderTypesConfigured
              : branch.supportedOrderTypes.join(' · ').replaceAll('_', '-'),
          selected: draft.branchId == branch.id,
          onTap: () => controller.setBranch(branch.id, branch.name),
          trailing: branch.code == null
              ? null
              : Text(
                  branch.code!,
                  style: PosText.mono(size: 12, color: context.pos.muted),
                ),
        ),
        const SizedBox(height: PosSpace.md),
      ],
      const SizedBox(height: PosSpace.sm),
      Text(
        context.strings.branchPaneHelp,
        style: PosText.ui(size: 12.5, color: context.pos.muted, height: 1.5),
      ),
    ],
  );
}

class _TerminalPane extends ConsumerWidget {
  const _TerminalPane({required this.draft});

  final SetupDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.strings;
    final controller = ref.read(setupProvider.notifier);
    // Terminals the dashboard already made and nobody has paired yet. `active`
    // ones are deliberately absent: adopting a till already in service would
    // take the seat out from under a machine that is trading on it.
    final adoptable = (draft.pulledTerminals ?? const <PosTerminalSummary>[])
        .where((t) => t.isAdoptable)
        .toList();
    final creatingNew = draft.adoptTerminalId == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Since a tenant is created with its terminals provisioned in advance,
        // the first question is WHICH till this is — not what to call a new one.
        // Registering another beside them is how a two-seat restaurant ends up
        // with four rows and a seat limit nobody can explain.
        if (draft.method == SetupMethod.manual && adoptable.isNotEmpty) ...[
          MicroLabel(s.whichTillIsThis),
          const SizedBox(height: PosSpace.md),
          for (final terminal in adoptable) ...[
            _ChoiceTile(
              title: terminal.name,
              blurb: s.tillAwaitingDevice,
              selected: draft.adoptTerminalId == terminal.id,
              enabled: !draft.claimed,
              onTap: () => controller.setAdoptedTerminal(terminal.id),
            ),
            const SizedBox(height: PosSpace.md),
          ],
          _ChoiceTile(
            title: s.aNewTill,
            blurb: s.aNewTillBlurb,
            selected: creatingNew,
            enabled: !draft.claimed,
            onTap: () => controller.setAdoptedTerminal(null),
          ),
          const SizedBox(height: PosSpace.xl),
        ],
        // The name is the SERVER's when adopting — showing an editable field
        // would invite an operator to change something this screen cannot save.
        if (creatingNew || draft.method == SetupMethod.pairingCode)
          _Field(
            label: s.terminalName,
            value: draft.terminalName,
            hint: s.terminalNameHint,
            onChanged: controller.setTerminalName,
            help: draft.method == SetupMethod.pairingCode
                ? s.terminalNameProvisionedHelp
                : s.terminalNameManualHelp,
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MicroLabel(s.terminalName.toUpperCase()),
              const SizedBox(height: PosSpace.sm),
              Text(
                draft.terminalName,
                style: PosText.ui(
                  size: 15,
                  weight: FontWeight.w600,
                  color: context.pos.ink,
                ),
              ),
              const SizedBox(height: PosSpace.sm),
              Text(
                s.terminalNameProvisionedHelp,
                style: PosText.ui(
                  size: 12.5,
                  color: context.pos.muted,
                  height: 1.5,
                ),
              ),
            ],
          ),
        if (draft.method == SetupMethod.manual) ...[
          const SizedBox(height: PosSpace.xl),
          Align(
            alignment: Alignment.centerLeft,
            child: PosButton(
              label: draft.claimed
                  ? (creatingNew ? s.registered : s.alreadySetUp)
                  : (creatingNew ? s.registerThisTerminal : s.useThisTill),
              border: Border.fromBorderSide(
                BorderSide(color: context.pos.inkWarm),
              ),
              padding: const EdgeInsets.symmetric(horizontal: PosSpace.xl),
              // Adopting needs no branch chosen here: the terminal already has
              // one, and the server's answer overwrites whatever was picked.
              onPressed:
                  draft.busy ||
                      draft.claimed ||
                      (creatingNew && draft.branchId == null)
                  ? null
                  : controller.registerTerminal,
            ),
          ),
          const SizedBox(height: PosSpace.sm),
          Text(
            !creatingNew
                ? s.adoptTerminalHelp
                : draft.deployment.mode == DeploymentMode.cloud
                ? s.registerCloudHelp
                : s.registerHelp,
            style: PosText.ui(size: 12, color: context.pos.muted, height: 1.5),
          ),
        ],
        if (draft.terminalId != null) ...[
          const SizedBox(height: PosSpace.xl),
          MicroLabel(s.terminalId),
          const SizedBox(height: PosSpace.sm),
          SelectableText(
            draft.terminalId!,
            style: PosText.mono(size: 12.5, color: context.pos.body),
          ),
          const SizedBox(height: PosSpace.sm),
          Text(
            s.terminalIdHelp,
            style: PosText.ui(size: 12, color: context.pos.muted, height: 1.5),
          ),
        ],
      ],
    );
  }
}

/// The cloud path's one automatic screen (owner decision, 2026-09-15).
///
/// Nothing on it is a question. It reads the database off the installation,
/// builds and migrates it, pulls the restaurant's own configuration from the
/// platform and looks for a printer — the four screens this replaced, minus the
/// asking. What it shows is what it did, line by line, because a progress
/// screen with nothing on it but a spinner is indistinguishable from one that
/// has hung, and the person watching is standing in a restaurant.
class _ConnectingPane extends ConsumerStatefulWidget {
  const _ConnectingPane({required this.draft});

  final SetupDraft draft;

  @override
  ConsumerState<_ConnectingPane> createState() => _ConnectingPaneState();
}

class _ConnectingPaneState extends ConsumerState<_ConnectingPane> {
  @override
  void initState() {
    super.initState();
    // After the first frame, so the screen paints before the work starts. A
    // provisioning run kicked off in `initState` would hold the frame and the
    // operator would see the previous screen for as long as it took.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final draft = ref.read(setupProvider);
      // Already done, already running, or waiting on the fallback fields —
      // going Back and forward again must not run any of it twice.
      if (draft.provisioned || draft.busy || draft.needsDatabase) return;
      ref.read(setupProvider.notifier).provisionTerminal();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    final draft = widget.draft;

    // `provisioned` and not `needsDatabase` alone: the fields answered their
    // question the moment the build succeeded, and leaving them up meant the
    // one screen that says "this till is ready" was never shown to the operator
    // who had just made it ready.
    if (draft.needsDatabase && !draft.provisioned) {
      return _InstalledDatabaseMissing(draft: draft);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(PosSpace.lg),
          decoration: BoxDecoration(
            color: draft.provisioned ? context.pos.okSoft : context.pos.surface,
            border: Border.all(
              color: draft.provisioned ? context.pos.ok : context.pos.line,
              width: draft.provisioned ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                draft.provisioned ? s.tillIsReady : s.settingUpThisTill,
                style: PosText.ui(
                  size: 13.5,
                  weight: FontWeight.w700,
                  color: context.pos.ink,
                ),
              ),
              if (draft.bootstrapReport case final report?
                  when report.isNotEmpty) ...[
                const SizedBox(height: PosSpace.sm),
                Text(
                  report,
                  style: PosText.ui(
                    size: 12.5,
                    color: context.pos.body,
                    height: 1.6,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: PosSpace.lg),
        Text(
          s.connectingPaneHelp,
          style: PosText.ui(size: 12.5, color: context.pos.muted, height: 1.5),
        ),
        // A refusal above the fold has already been shown in the error bar; the
        // one thing missing there is a way to try the whole thing again, which
        // is what the commonest cause — a platform that was briefly down —
        // actually needs.
        if (draft.error != null && !draft.busy) ...[
          const SizedBox(height: PosSpace.lg),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: PosButton(
              label: s.tryAgain,
              border: Border.fromBorderSide(
                BorderSide(color: context.pos.inkWarm),
              ),
              padding: const EdgeInsets.symmetric(horizontal: PosSpace.xl),
              onPressed: ref.read(setupProvider.notifier).provisionTerminal,
            ),
          ),
        ],
      ],
    );
  }
}

/// The fallback, for a machine `installer/provision.ps1` never ran on.
///
/// A developer's Mac, above all — there is no macOS installer, so there is no
/// `install-credentials.json` and no way to know a password nobody typed. These
/// are the fields the connection step used to carry, prefilled with the
/// defaults every wizard-built install shares, and they are the only thing on
/// the cloud path anybody is still asked about the database.
///
/// **The administrator half is not optional.** This screen used to ask for the
/// till's account alone, which is everything needed to *use* a database and
/// nothing like enough to *build* one — and on this path nothing else builds
/// it. The button then ran the seeder against a database that did not exist and
/// the operator read `3D000` off the driver. Two more fields, the same two the
/// offline pane has, and the button does what its label says.
///
/// Not shown on Windows, ever: if it appears there, the credentials file is
/// missing or unreadable and the answer is to restore it, not to type around it.
class _InstalledDatabaseMissing extends ConsumerWidget {
  const _InstalledDatabaseMissing({required this.draft});

  final SetupDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.strings;
    final controller = ref.read(setupProvider.notifier);
    final config = draft.deployment;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(PosSpace.lg),
          decoration: BoxDecoration(
            color: context.pos.warnSoft,
            border: Border.all(color: context.pos.warn, width: 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MicroLabel(s.noInstalledDatabase, color: context.pos.warn),
              const SizedBox(height: PosSpace.sm),
              Text(
                s.noInstalledDatabaseHelp,
                style: PosText.ui(
                  size: 13,
                  color: context.pos.ink,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: PosSpace.xl),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: _Field(
                label: s.databaseName,
                value: config.databaseName,
                mono: true,
                hint: 'xorder_pos',
                error:
                    config.databaseName.isEmpty || config.hasValidDatabaseName
                    ? null
                    : s.databaseNameInvalid(config.databaseName),
                onChanged: controller.setDatabaseName,
              ),
            ),
            const SizedBox(width: PosSpace.lg),
            Expanded(
              child: _Field(
                label: s.databasePort,
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
          label: s.databaseUser,
          value: config.databaseUser,
          mono: true,
          hint: 'pos_till',
          onChanged: controller.setDatabaseUser,
          help: s.databaseUserHelp,
        ),
        const SizedBox(height: PosSpace.xl),
        _PasswordField(
          field: 'database',
          label: s.databasePassword,
          value: draft.databasePassword,
          onChanged: controller.setDatabasePassword,
          help: s.databasePasswordHelp,
        ),
        const SizedBox(height: PosSpace.xl),
        _Field(
          label: s.adminDatabaseUser,
          value: config.adminDatabaseUser,
          mono: true,
          hint: 'pos_admin',
          onChanged: controller.setAdminDatabaseUser,
          help: s.adminDatabaseUserHelp,
        ),
        const SizedBox(height: PosSpace.xl),
        _PasswordField(
          field: 'admin',
          label: s.adminPasswordFor(config.adminDatabaseUser),
          value: draft.adminDatabasePassword,
          onChanged: controller.setAdminDatabasePassword,
          // Not `adminPasswordHelp`, which promises the password is never
          // written to this machine. True where it is written — the offline
          // build screen — and false here: `complete()` puts it in the secret
          // store so the back office is a username and a PIN.
          help: s.adminPasswordKeptHelp,
        ),
        const SizedBox(height: PosSpace.xl),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: PosButton(
            label: s.useThisDatabase,
            background: context.pos.ink,
            foreground: context.pos.onInk,
            padding: const EdgeInsets.symmetric(horizontal: PosSpace.xl),
            // Both credentials, because this button does both jobs: the
            // administrator's builds the database, the till's is what the
            // grants are for and what every sale after tonight connects with.
            onPressed:
                draft.busy ||
                    draft.databasePassword.isEmpty ||
                    draft.adminDatabasePassword.isEmpty ||
                    config.adminDatabaseUser.isEmpty ||
                    !config.hasValidDatabaseName
                ? null
                : controller.provisionTerminal,
          ),
        ),
      ],
    );
  }
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
    final s = context.strings;
    final controller = ref.read(setupProvider.notifier);
    final draft = widget.draft;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            PosButton(
              label: _scanning ? s.lookingForPrinters : s.findPrinters,
              border: Border.fromBorderSide(
                BorderSide(color: context.pos.inkWarm),
              ),
              padding: const EdgeInsets.symmetric(horizontal: PosSpace.xl),
              onPressed: _scanning ? null : _scan,
            ),
            if (draft.printerName != null) ...[
              const SizedBox(width: PosSpace.md),
              PosButton(
                label: s.testPrint,
                border: Border.fromBorderSide(context.pos.resting),
                padding: const EdgeInsets.symmetric(horizontal: PosSpace.xl),
                onPressed: () async {
                  final ok = await ref
                      .read(hardwarePortsProvider)
                      .testPrint(draft.printerName!);
                  if (!context.mounted) return;
                  posToast(context, ok ? s.testReceiptSent : s.nothingPrinted);
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
        // Asked here because it is a fact about the roll in the machine, and
        // the person holding the roll is standing at the till right now. A
        // receipt built for 576 dots on a 58mm printer is not scaled down — the
        // printer keeps the columns it has a head for and drops the rest, so
        // the totals go over the edge and the till looks broken.
        const SizedBox(height: PosSpace.sm),
        MicroLabel(s.printerPaperWidth),
        const SizedBox(height: PosSpace.sm),
        _ChoiceTile(
          title: s.printerPaper80,
          blurb: s.printerPaperWidthHelp,
          selected: draft.paperWidthDots == PrinterConfig.width80mm,
          onTap: () => controller.setPaperWidth(PrinterConfig.width80mm),
        ),
        const SizedBox(height: PosSpace.md),
        _ChoiceTile(
          title: s.printerPaper58,
          blurb: s.printerPaperWidthHelp,
          selected: draft.paperWidthDots == PrinterConfig.width58mm,
          onTap: () => controller.setPaperWidth(PrinterConfig.width58mm),
        ),
        const SizedBox(height: PosSpace.lg),
        _ChoiceTile(
          title: s.cashDrawerAttached,
          blurb: s.cashDrawerAttachedBlurb,
          selected: draft.drawerAttached,
          onTap: () => controller.setDrawer(!draft.drawerAttached),
        ),
        const SizedBox(height: PosSpace.md),
        _ChoiceTile(
          title: s.scannerAttached,
          blurb: s.scannerAttachedBlurb,
          selected: draft.scannerAttached,
          onTap: () => controller.setScanner(!draft.scannerAttached),
        ),
        const SizedBox(height: PosSpace.lg),
        Text(
          s.hardwareHelp,
          style: PosText.ui(size: 12.5, color: context.pos.muted, height: 1.5),
        ),
      ],
    );
  }
}

class _MoneyPane extends StatelessWidget {
  const _MoneyPane({required this.draft});

  final SetupDraft draft;

  @override
  Widget build(BuildContext context) {
    final s = context.strings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: context.pos.surface,
            border: Border.fromBorderSide(context.pos.resting),
          ),
          child: Column(
            children: [
              _row(s.currency, s.currencyValue('EGP', 2), pos: context.pos),
              _row(s.serviceCharge, s.serviceChargeValue, pos: context.pos),
              _row(s.vat, s.vatValue, pos: context.pos),
              _row(s.rounding, s.roundingValue, pos: context.pos),
            ],
          ),
        ),
        const SizedBox(height: PosSpace.lg),
        Container(
          padding: const EdgeInsets.all(PosSpace.lg),
          decoration: BoxDecoration(
            color: context.pos.warnSoft,
            border: Border.all(color: context.pos.warn, width: 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MicroLabel(s.fromDeviceConfiguration, color: context.pos.warn),
              const SizedBox(height: PosSpace.sm),
              Text(
                s.deviceTaxHelp,
                style: PosText.ui(size: 13, color: context.pos.ink, height: 1.5),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(String label, String value, {required PosPalette pos}) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: PosSpace.lg,
      vertical: PosSpace.md,
    ),
    decoration: BoxDecoration(
      border: Border(bottom: pos.hairline),
    ),
    child: Row(
      children: [
        Text(label, style: PosText.ui(color: pos.inkWarm, size: 13.5)),
        const Spacer(),
        Text(value, style: PosText.mono(size: 13, color: pos.body)),
      ],
    ),
  );
}

class _CataloguePane extends ConsumerWidget {
  const _CataloguePane({required this.draft});

  final SetupDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.strings;
    final items = draft.catalogueItems;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: PosButton(
            // Offline this button downloads nothing — `syncCatalogue` early
            // -returns out of the platform pull and reads local Postgres. A
            // button that says "Download menu" on a machine with no platform
            // teaches the operator to distrust the whole screen.
            label: draft.deployment.mode == DeploymentMode.cloud
                ? (items == null ? s.downloadMenu : s.downloadAgain)
                : (items == null ? s.readMenu : s.readMenuAgain),
            background: context.pos.ink,
            foreground: context.pos.onInk,
            padding: const EdgeInsets.symmetric(horizontal: PosSpace.xl),
            onPressed: draft.busy
                ? null
                : ref.read(setupProvider.notifier).syncCatalogue,
          ),
        ),
        // A download that returned nothing is not a success, and painting it
        // green is how a till reaches a restaurant with an empty menu and a
        // tick beside it. The step still advances — an installer may genuinely
        // be setting up before the menu is authored, and blocking would strand
        // them — but the consequence is stated rather than implied.
        if (items != null) ...[
          const SizedBox(height: PosSpace.lg),
          Container(
            padding: const EdgeInsets.all(PosSpace.lg),
            decoration: BoxDecoration(
              color: items > 0 ? context.pos.okSoft : context.pos.warnSoft,
              border: Border.all(
                color: items > 0 ? context.pos.ok : context.pos.warn,
                width: 2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  items > 0 ? s.itemsCached(items) : s.menuEmpty,
                  style: PosText.ui(
                    size: 13.5,
                    weight: FontWeight.w600,
                    color: context.pos.ink,
                  ),
                ),
                if (items == 0) ...[
                  const SizedBox(height: PosSpace.sm),
                  Text(
                    draft.deployment.mode == DeploymentMode.cloud
                        ? s.menuEmptyHelp
                        : s.menuEmptyHelpOffline,
                    style: PosText.ui(
                      size: 13,
                      color: context.pos.ink,
                      height: 1.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: PosSpace.lg),
        Text(
          draft.deployment.mode == DeploymentMode.cloud
              ? s.cataloguePaneHelp
              : s.cataloguePaneHelpOffline,
          style: PosText.ui(size: 12.5, color: context.pos.muted, height: 1.5),
        ),
      ],
    );
  }
}

class _SummaryPane extends ConsumerWidget {
  const _SummaryPane({required this.draft});

  final SetupDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.strings;

    // The chosen language names itself, not the language you are reading —
    // this row is the record of a decision, and `العربية` is what was picked.
    final language = draft.locale == 'ar'
        ? const ArStrings().languageName
        : const EnStrings().languageName;

    // A cloud main device answered four questions to get here, so the last
    // screen restates four things. The long list below is a review of a dozen
    // decisions an installer made; a review of decisions nobody made is a
    // screen people learn to press past, and the one row that would have been
    // worth reading goes past with it.
    final short =
        draft.deployment.mode == DeploymentMode.cloud &&
        !draft.deployment.isChild;

    final rows = short
        ? <(String, String)>[
            (
              s.summaryRestaurant,
              draft.tenantName ??
                  draft.claims?.tenantName ??
                  draft.deployment.tenantSlug ??
                  s.notSet,
            ),
            (s.summaryBranch, draft.branchLabel ?? s.notSet),
            (s.summaryTerminal, draft.terminalName),
            (s.summaryPrinter, draft.printerName ?? s.summaryNoPrinter),
          ]
        : <(String, String)>[
            (s.summaryLanguage, language),
            (s.summaryConnection, draft.deployment.mode.label(s)),
            if (draft.deployment.baseUrl?.isNotEmpty ?? false)
              (s.summaryUpstream, draft.deployment.baseUrl!),
            (
              s.theDatabase,
              draft.deployment.isSingleMachine
                  ? s.summaryThisMachine
                  : draft.deployment.databaseHost,
            ),
            (s.summaryRestaurant, draft.deployment.tenantSlug ?? s.notSet),
            (s.summaryBranch, draft.branchLabel ?? s.notSet),
            (s.summaryTerminal, draft.terminalName),
            (s.summaryPrinter, draft.printerName ?? s.summaryNoPrinter),
            (
              s.summaryCashDrawer,
              draft.drawerAttached ? s.summaryAttached : s.none,
            ),
            (
              s.summaryScanner,
              draft.scannerAttached ? s.summaryAttached : s.none,
            ),
            (s.summaryMenu, s.itemsCached(draft.catalogueItems ?? 0)),
            (
              s.summaryLicence,
              // The verdict in words, not the enum's Dart name.
              draft.entitlement?.state.headline(s) ?? s.notLicensedHeadline,
            ),
          ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: context.pos.surface,
            border: Border.fromBorderSide(context.pos.resting),
          ),
          child: Column(
            children: [
              for (final (label, value) in rows)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: PosSpace.lg,
                    vertical: PosSpace.md,
                  ),
                  decoration: BoxDecoration(
                    border: Border(bottom: context.pos.hairline),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 160,
                        child: Text(
                          label,
                          style: PosText.ui(size: 13, color: context.pos.muted),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          value,
                          overflow: TextOverflow.ellipsis,
                          style: PosText.ui(color: context.pos.inkWarm, 
                            size: 13.5,
                            weight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        // The last screen before "Open the till" must not show an all-clear
        // over a terminal that has nothing to sell.
        if ((draft.catalogueItems ?? 0) == 0) ...[
          const SizedBox(height: PosSpace.lg),
          Container(
            padding: const EdgeInsets.all(PosSpace.lg),
            decoration: BoxDecoration(
              color: context.pos.warnSoft,
              border: Border.all(color: context.pos.warn, width: 2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.strings.menuEmpty,
                  style: PosText.ui(
                    size: 13.5,
                    weight: FontWeight.w600,
                    color: context.pos.ink,
                  ),
                ),
                const SizedBox(height: PosSpace.sm),
                Text(
                  draft.deployment.mode == DeploymentMode.cloud
                      ? context.strings.menuEmptyHelp
                      : context.strings.menuEmptyHelpOffline,
                  style: PosText.ui(
                    size: 13,
                    color: context.pos.ink,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
        // The hardware screen is where this used to live, and a cloud till no
        // longer sees that screen when exactly one printer was found. Somebody
        // has to be able to put paper through the thing before the restaurant
        // opens, and this is now the last place they can.
        if (draft.printerName case final printer?) ...[
          const SizedBox(height: PosSpace.lg),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: PosButton(
              label: s.testPrint,
              border: Border.fromBorderSide(context.pos.resting),
              padding: const EdgeInsets.symmetric(horizontal: PosSpace.xl),
              onPressed: () async {
                final ok = await ref
                    .read(hardwarePortsProvider)
                    .testPrint(printer);
                if (!context.mounted) return;
                posToast(context, ok ? s.testReceiptSent : s.nothingPrinted);
              },
            ),
          ),
        ],
        const SizedBox(height: PosSpace.lg),
        Text(
          s.summaryHelp,
          style: PosText.ui(size: 12.5, color: context.pos.muted),
        ),
      ],
    );
  }
}

/// Build this machine's database from the wizard.
///
/// The offline path used to begin at a command line — `PosMigrator` ran only on
/// the cloud claim path, so an offline restaurant needed somebody at a terminal
/// with `bin/pos_migrate.dart` before the wizard could do anything at all. This
/// is that command, on the screen the operator is already looking at.
///
/// Shown open, because this IS the step now.
///
/// It used to sit collapsed behind a "this machine has no database yet" button,
/// at the foot of the connection screen, so that a till being re-installed
/// against an existing database was not invited to re-run it. That reasoning
/// belonged to the old position. As the whole content of the first-administrator
/// step, a lone button — whose label reads as a status line rather than an
/// action — is the step appearing to have nothing on it.
class _FirstInstallFields extends ConsumerStatefulWidget {
  const _FirstInstallFields({required this.draft});

  final SetupDraft draft;

  @override
  ConsumerState<_FirstInstallFields> createState() =>
      _FirstInstallFieldsState();
}

class _FirstInstallFieldsState extends ConsumerState<_FirstInstallFields> {
  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    final draft = widget.draft;
    final controller = ref.read(setupProvider.notifier);

    if (draft.bootstrapped) {
      return Container(
        padding: const EdgeInsets.all(PosSpace.md),
        decoration: BoxDecoration(
          color: context.pos.accentSoft,
          border: Border.all(color: context.pos.ok),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.machineNowHasDatabase,
              style: PosText.ui(
                size: 13,
                weight: FontWeight.w700,
                color: context.pos.ink,
              ),
            ),
            const SizedBox(height: PosSpace.sm),
            Text(
              draft.bootstrapReport ?? '',
              style: PosText.ui(size: 12.5, color: context.pos.body, height: 1.6),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MicroLabel(s.firstInstallHeading),
        const SizedBox(height: PosSpace.sm),
        Text(
          s.firstInstallHelp,
          style: PosText.ui(size: 12.5, color: context.pos.muted, height: 1.5),
        ),
        const SizedBox(height: PosSpace.lg),
        _PasswordField(
          field: 'admin',
          label: s.adminPasswordFor(draft.deployment.adminDatabaseUser),
          value: draft.adminDatabasePassword,
          onChanged: controller.setAdminDatabasePassword,
          help: s.adminPasswordHelp,
        ),
        const SizedBox(height: PosSpace.lg),
        _Field(
          label: s.firstPerson,
          value: draft.ownerName,
          onChanged: controller.setOwnerName,
          help: s.firstPersonHelp,
        ),
        const SizedBox(height: PosSpace.md),
        _Field(
          label: s.theirUsername,
          value: draft.ownerUsername,
          mono: true,
          hint: 'owner',
          onChanged: controller.setOwnerUsername,
        ),
        const SizedBox(height: PosSpace.md),
        _PasswordField(
          field: 'owner-pin',
          label: s.theirPin,
          value: draft.ownerPin,
          onChanged: controller.setOwnerPin,
          help: s.theirPinHelp,
        ),
        const SizedBox(height: PosSpace.xl),
        Align(
          alignment: Alignment.centerLeft,
          child: PosButton(
            label: draft.busy ? s.buildingDatabase : s.buildTheDatabase,
            background: context.pos.ink,
            foreground: context.pos.onInk,
            padding: const EdgeInsets.symmetric(horizontal: PosSpace.xl),
            onPressed: draft.busy ? null : controller.bootstrapDatabase,
          ),
        ),
      ],
    );
  }
}
