import '../../../core/config/deployment.dart';
import '../../../domain/repositories/repositories.dart'
    show PosBranch, PosTerminalSummary;
import '../../licensing/domain/license.dart';
import '../../../core/security/pin_hash.dart';

/// How this terminal is being set up (POS-BE-023).
///
/// Both paths land on the same `pos_terminals` row. The pairing code is the
/// default because the alternative types a staff password into a machine that
/// lives in a public room and may be stolen — a code that expires in a day is a
/// much smaller thing to lose.
enum SetupMethod { pairingCode, manual }

/// The steps of first-run setup, in order.
///
/// Deliberately one linear path with no branching screens: the person working
/// through this is often the restaurant owner rather than a technician, and a
/// wizard that forks is a wizard that strands people.
///
/// [SetupMethod] does **not** fork it. A pairing code pre-fills the branch and
/// terminal steps, so those screens become confirmations rather than questions
/// — the same path, with the answers already written in.
enum SetupStep {
  // The licence is step ONE (owner decision, 2026-09-06). It is the gate: a
  // terminal with no licence has nothing to set up, and asking anything else
  // first collects answers that may turn out to be worthless.
  //
  // The order is load-bearing in three further directions. The licence carries
  // `tenant_slug`, so it *supplies* the tenant the account step signs into
  // rather than being checked against one the terminal guessed. It carries
  // `max_terminals`, which decides whether the database may live on another
  // machine. And it carries `modes` — which is why it precedes [setupType].
  //
  // Activation therefore cannot depend on `base_url`, which does not exist yet.
  // It goes to the hosted platform directly (`PlatformEndpoint.licence`), or the
  // operator imports a signed file — see `licence_service.dart`.
  licence,
  // Language used to come first, so that the licence refusals — the screens
  // most worth reading closely — would already be in the installer's language.
  // That property is NOT lost by moving it: the Settings bar above the wizard
  // carries a language switch on every screen, including this one, so an
  // installer facing a refusal they cannot read is one menu away from fixing
  // it. What the old order cost was making everybody answer a question before
  // the one that decides whether the rest of the wizard happens at all.
  language,
  // Which product this terminal is — asked **after** the licence, because the
  // licence is what answers it. A tenant is sold cloud, offline, or both when
  // the Super Admin creates it, and the modes claim carries that to the till.
  // Asking first, as this wizard used to, meant accepting a choice and then
  // refusing it two screens later; asking second means the unbought mode is
  // simply not offered, and a single-mode licence leaves nothing to ask at all.
  setupType,
  deployment,
  account,
  branch,
  terminal,
  hardware,
  money,
  catalogue,
  summary,
}

/// Everything the wizard has gathered so far.
class SetupDraft {
  /// A PIN is typed on a keypad at the counter, so it is digits and nothing
  /// else, and it is exactly [PinRules.length] of them — the till's keypads
  /// submit on the last digit rather than on a confirm key, so a longer PIN
  /// created here could never be typed by the person it belongs to.
  static const pinLength = PinRules.length;

  const SetupDraft({
    // The wizard opens on the licence — see [SetupStep].
    this.step = SetupStep.licence,
    this.locale = 'en',
    this.deployment = DeploymentConfig.unconfigured,
    this.entitlement,
    this.claims,
    this.licenceKey = '',
    // Credentials are the phase-1 default: the owner's notes define cloud
    // setup as slug + admin credentials pulling the tenant's configuration.
    // The pairing code stays available as the provisioned path.
    this.method = SetupMethod.manual,
    this.pairingCode = '',
    this.operatorUsername = '',
    this.operatorPassword = '',
    this.connected = false,
    this.tenantName,
    this.pulledBranches,
    this.databasePassword = '',
    this.adminDatabasePassword = '',
    this.ownerName = '',
    this.ownerUsername = '',
    this.ownerPin = '',
    this.bootstrapped = false,
    this.bootstrapReport,
    this.claimed = false,
    this.pulledTerminals,
    this.adoptTerminalId,
    this.branchId,
    this.branchLabel,
    this.restaurantId,
    this.branchCode,
    this.terminalName = '',
    this.terminalId,
    this.installationId,
    this.printerName,
    this.drawerAttached = false,
    this.scannerAttached = false,
    this.catalogueItems,
    this.busy = false,
    this.error,
    this.notice,
  });

  final SetupStep step;
  final String locale;
  final DeploymentConfig deployment;

  /// Null until the licence step has run.
  final LicenseEntitlement? entitlement;

  /// The claims of the licence just installed. Null until the licence step has
  /// run, which is why that step now comes first — see [SetupStep].
  final LicenseClaims? claims;
  final String licenceKey;

  /// The deployments this licence covers.
  ///
  /// An empty `modes[]` is treated as *everything*, not as *nothing*. The
  /// difference matters: parsing an absent claim into an empty set and then
  /// refusing every mode reads to the operator as a till that will not set up,
  /// with no way to tell why.
  Set<DeploymentMode> get licensedModes {
    final modes = claims?.modes ?? const <DeploymentMode>{};
    return modes.isEmpty ? DeploymentMode.values.toSet() : modes;
  }

  /// Whether the first person's PIN is one the till could actually accept.
  bool get hasUsablePin => PinRules.isWellFormed(ownerPin);

  /// How many terminals the plan covers. One until a licence says otherwise.
  int get maxTerminals => claims?.maxTerminals ?? 1;

  /// Whether the database may live on another machine.
  ///
  /// This — not the deployment mode — is what decides whether the wizard asks
  /// for a database address. A one-terminal plan has nobody to share with, so
  /// the only honest answer is this machine.
  bool get allowsSharedDatabase => maxTerminals > 1;

  final SetupMethod method;
  final String pairingCode;
  final String operatorUsername;

  /// True once the slug + credentials have been verified against the platform
  /// and the tenant's configuration pulled. Everything the following steps
  /// display — the branch list above all — came from that pull.
  final bool connected;

  /// The tenant's display name, from the pull. Shown so the operator can see
  /// they signed into the right restaurant before anything is written.
  final String? tenantName;

  /// Branches retrieved by the pull. Null until connected; the branch step
  /// prefers these over the local database, which on a fresh cloud terminal
  /// is empty until the bootstrap seeds it.
  final List<PosBranch>? pulledBranches;

  /// Terminals the dashboard already created for this tenant, pulled with the
  /// branch list. Null until sign-in; empty means the tenant genuinely has
  /// none and this till will be its first.
  final List<PosTerminalSummary>? pulledTerminals;

  /// The existing terminal this till is adopting, if the operator picked one.
  /// Null means "create a new one", which is the only option when nothing
  /// adoptable came back.
  final int? adoptTerminalId;

  /// The wizard's steps for the path being walked.
  ///
  /// Every step is walked, including the licence. This used to hide the licence
  /// step in cloud mode — a cloud terminal receives one inside the bootstrap
  /// bundle at registration (POS-BE-015 §5), so there was nothing to type — but
  /// that rule became circular the moment the licence started deciding the
  /// mode: it hid the step on the strength of a mode the licence had not yet
  /// been read to determine. The bundle still delivers a cloud licence; what it
  /// no longer does is excuse this terminal from holding one before it picks
  /// how to run. The Super Admin issues the key with the tenant, so an
  /// installer on either path arrives with one in hand.
  List<SetupStep> get visibleSteps => SetupStep.values;

  bool get isFirstStep => visibleSteps.first == step;
  bool get isLastStep => visibleSteps.last == step;

  /// 1-based position of the current step among the visible ones, for the
  /// "Step N of M" header.
  int get stepNumber => visibleSteps.indexOf(step) + 1;
  int get stepCount => visibleSteps.length;

  /// Held only for the length of the wizard and never persisted with the rest
  /// of the draft — it exists to authenticate one registration call.
  final String operatorPassword;

  /// The branch database password. Held for the length of the wizard and handed
  /// to the credential store at the end — never written into the draft's
  /// persisted form, and never into device config.
  final String databasePassword;

  // ── First install on this machine ──────────────────────────────────────────
  // An offline restaurant has no dashboard and, before this, no way to get a
  // schema either — the app's migrator only ever ran on the cloud claim path,
  // so every install began at a command line. These four fields are what the
  // wizard needs to build a database itself.

  /// The administrator role's password. Used to CREATE DATABASE, migrate and
  /// grant, then **discarded** — only the till's password is ever stored.
  final String adminDatabasePassword;

  /// The first person. Without one, an offline till has nobody to sign in as:
  /// the account step authenticates against `pos_staff`, which starts empty.
  final String ownerName;
  final String ownerUsername;
  final String ownerPin;

  /// Whether this wizard built the database. Not persisted — a re-run of the
  /// bootstrap is harmless (every statement is an upsert) but pointless.
  final bool bootstrapped;

  /// What it did, in the operator's words. Null before it has run.
  final String? bootstrapReport;

  /// True once the server has confirmed this terminal. On the pairing path the
  /// branch, name and id below were filled in by that response.
  final bool claimed;

  final int? branchId;
  final String? branchLabel;

  /// Supplied by provisioning, never typed. Both are needed before the till can
  /// write a row: one stamps the tenant, the other is the invoice prefix.
  final int? restaurantId;
  final String? branchCode;

  final String terminalName;
  final String? terminalId;
  final String? installationId;
  final String? printerName;
  final bool drawerAttached;
  final bool scannerAttached;

  /// Items pulled in the first catalogue sync; null until it runs.
  final int? catalogueItems;

  final bool busy;
  final String? error;

  /// A fact worth stating that is NOT a failure — "the catalog arrives on
  /// first sync", "this till exceeds the plan's seat count". Its own channel
  /// because a notice wearing the error bar's red teaches operators to
  /// ignore red, which is the one colour they must never learn to ignore.
  final String? notice;

  /// Whether the current step has enough to move on.
  ///
  /// Note what is deliberately *not* required: hardware. A till with no printer
  /// must still finish setup — the receipt queues and the sale completes.
  /// Printing is never on the critical path of taking money.
  bool get canAdvance => switch (step) {
    // Either mode may go on, provided the licence covers it. `setMode` refuses
    // anything unlicensed, so a draft can only be sitting on a covered mode —
    // this re-states the rule rather than trusting that.
    SetupStep.setupType => licensedModes.contains(deployment.mode),
    SetupStep.language => true,
    // `canSell` rather than `state == valid`: a licence in its grace window
    // still permits trade, and refusing to finish setup on one would be its
    // own outage.
    SetupStep.licence => entitlement?.canSell ?? false,
    // Every mode writes straight to PostgreSQL, so no terminal gets past
    // this step without a credential to do it with — that is no longer a
    // branch-server special case.
    // The name is checked HERE, where it is typed. Letting a hyphen through
    // meant the operator filled in four more fields on the next screen before
    // `CREATE DATABASE "x"` threw at them.
    SetupStep.deployment =>
      deployment.isConfigured &&
          deployment.hasValidDatabaseName &&
          databasePassword.isNotEmpty,
    // A pairing code must actually be redeemed before moving on, because
    // everything after this step is the answer it returned. Manual setup
    // only needs credentials — it registers at the terminal step, where the
    // branch and till name it has to send are finally known.
    // Both paths must have actually spoken to the platform before moving on,
    // because everything after this step displays what came back. A pairing
    // code is redeemed; credentials are connected — the owner's phase-1 flow:
    // slug + admin credentials pull the tenant's configuration.
    // Offline: the database has to exist and hold its first administrator.
    // This used to demand `connected` in every mode, which an offline till can
    // never satisfy — there is no platform to connect to — so the offline path
    // could not get past this step at all.
    SetupStep.account when deployment.mode == DeploymentMode.offline =>
      bootstrapped,
    SetupStep.account =>
      (deployment.tenantSlug?.isNotEmpty ?? false) &&
          switch (method) {
            SetupMethod.pairingCode => claimed,
            SetupMethod.manual => connected,
          },
    SetupStep.branch => branchId != null,
    // Registration is load-bearing in BOTH modes, and pretending otherwise was
    // a live contradiction: this rule used to let an offline terminal walk
    // past unregistered, and then `complete()` refused it for having no
    // restaurant id and no branch code — which only registration supplies. The
    // operator reached the last screen before being told the sixth was wrong.
    //
    // Cloud registration issues the device token every later platform pull
    // rides on. Offline registration writes the `pos_terminals` row that gives
    // this machine its identity and its invoice prefix. Neither is optional.
    SetupStep.terminal => terminalName.trim().isNotEmpty && claimed,
    SetupStep.hardware => true,
    SetupStep.money => true,
    SetupStep.catalogue => catalogueItems != null,
    SetupStep.summary => true,
  };

  SetupDraft copyWith({
    SetupStep? step,
    String? locale,
    DeploymentConfig? deployment,
    LicenseEntitlement? entitlement,
    LicenseClaims? claims,
    String? licenceKey,
    SetupMethod? method,
    String? pairingCode,
    String? operatorUsername,
    String? operatorPassword,
    bool? connected,
    String? tenantName,
    List<PosBranch>? pulledBranches,
    String? databasePassword,
    String? adminDatabasePassword,
    String? ownerName,
    String? ownerUsername,
    String? ownerPin,
    bool? bootstrapped,
    String? bootstrapReport,
    bool? claimed,
    List<PosTerminalSummary>? pulledTerminals,
    int? adoptTerminalId,
    bool clearAdoption = false,
    int? branchId,
    String? branchLabel,
    int? restaurantId,
    String? branchCode,
    String? terminalName,
    String? terminalId,
    String? installationId,
    String? printerName,
    bool? drawerAttached,
    bool? scannerAttached,
    int? catalogueItems,
    bool? busy,
    String? error,
    String? notice,
    bool clearError = false,
    bool clearNotice = false,
    bool clearClaim = false,
    // Changing the slug or the credentials makes an earlier pull stale: the
    // branch list on screen would belong to a tenant the operator just
    // stopped typing. `?? this.x` cannot express "forget", so a flag does.
    bool clearConnection = false,
  }) => SetupDraft(
    step: step ?? this.step,
    locale: locale ?? this.locale,
    deployment: deployment ?? this.deployment,
    entitlement: entitlement ?? this.entitlement,
    claims: claims ?? this.claims,
    licenceKey: licenceKey ?? this.licenceKey,
    method: method ?? this.method,
    pairingCode: pairingCode ?? this.pairingCode,
    operatorUsername: operatorUsername ?? this.operatorUsername,
    operatorPassword: operatorPassword ?? this.operatorPassword,
    connected: clearConnection ? false : (connected ?? this.connected),
    tenantName: clearConnection ? null : (tenantName ?? this.tenantName),
    pulledBranches: clearConnection
        ? null
        : (pulledBranches ?? this.pulledBranches),
    databasePassword: databasePassword ?? this.databasePassword,
    adminDatabasePassword: adminDatabasePassword ?? this.adminDatabasePassword,
    ownerName: ownerName ?? this.ownerName,
    ownerUsername: ownerUsername ?? this.ownerUsername,
    ownerPin: ownerPin ?? this.ownerPin,
    bootstrapped: bootstrapped ?? this.bootstrapped,
    bootstrapReport: bootstrapReport ?? this.bootstrapReport,
    // `clearClaim` exists because the `?? this.x` idiom cannot express
    // "forget this": switching setup path has to erase the branch and till
    // name a previous claim filled in, not merely leave them unset.
    claimed: clearClaim ? false : (claimed ?? this.claimed),
    pulledTerminals: pulledTerminals ?? this.pulledTerminals,
    adoptTerminalId: clearClaim || clearAdoption
        ? null
        : (adoptTerminalId ?? this.adoptTerminalId),
    branchId: clearClaim ? null : (branchId ?? this.branchId),
    branchLabel: clearClaim ? null : (branchLabel ?? this.branchLabel),
    restaurantId: clearClaim ? null : (restaurantId ?? this.restaurantId),
    branchCode: clearClaim ? null : (branchCode ?? this.branchCode),
    terminalName: clearClaim ? '' : (terminalName ?? this.terminalName),
    terminalId: clearClaim ? null : (terminalId ?? this.terminalId),
    installationId: installationId ?? this.installationId,
    printerName: printerName ?? this.printerName,
    drawerAttached: drawerAttached ?? this.drawerAttached,
    scannerAttached: scannerAttached ?? this.scannerAttached,
    catalogueItems: catalogueItems ?? this.catalogueItems,
    busy: busy ?? this.busy,
    error: clearError ? null : (error ?? this.error),
    notice: clearNotice ? null : (notice ?? this.notice),
  );
}
