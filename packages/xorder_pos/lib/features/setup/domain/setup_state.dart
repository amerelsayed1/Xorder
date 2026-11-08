import '../../../core/config/deployment.dart';
import '../../../core/config/lan_tls.dart' show PresentedCertificate;
import '../../../core/config/printer_config.dart';
import '../../../domain/repositories/repositories.dart'
    show PosBranch, PosTerminalSummary;
import '../../licensing/domain/license.dart';
import '../../licensing/domain/license_verifier.dart' show LicenseFile;
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
/// through this is often the business owner rather than a technician, and a
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
  // Everything a cloud main device used to be asked, done instead of asked
  // (owner decision, 2026-09-15: "cloud setup should get everything from
  // cloud, no need for asking anything"). One screen with no inputs on it: the
  // installer's database credentials, the schema, the bundle, the menu and the
  // printer. It sits after [terminal] because the sign-in path behind "sign in
  // instead" still registers a till by hand on those two screens first, and
  // this list is walked in enum order.
  connecting,
  hardware,
  money,
  catalogue,
  summary,
}

/// The two screens inside the offline first-install step (pos-setup-owner-step).
///
/// One step, two pages: the wizard's step list, its numbering and the saved
/// progress do not change. Not persisted — a restart comes back on the first.
enum OwnerPage {
  /// The password of the PostgreSQL account that creates the database.
  databaseAccess,

  /// The owner's name, username and PIN, and the button that builds it all.
  ownerAccount,
}

/// What the wizard's one primary button does on this screen.
enum FooterAction {
  /// Move to the next step. Enabled by [SetupDraft.canAdvance], as ever.
  next,

  /// The last step: publish the setup and open the till.
  finish,

  /// Offline first install, page one: on to the owner's page.
  toOwnerPage,

  /// Offline first install, page two: create the database and the owner.
  createDatabase,
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
    this.locale = 'ar',
    this.deployment = DeploymentConfig.unconfigured,
    this.entitlement,
    this.claims,
    this.licenceFile,
    this.licenceKey = '',
    // The main road on cloud (owner decision, 2026-09-15). The dashboard mints
    // a code per terminal, and redeeming one is what lets the wizard stop
    // asking: the branch, the till's name, its id and its sync policy all come
    // back in the answer. Signing in with a staff password is still reachable —
    // "sign in instead", on that screen — for a till registered by hand.
    SetupMethod method = SetupMethod.pairingCode,
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
    this.ownerPinConfirm = '',
    this.ownerPage = OwnerPage.databaseAccess,
    this.bootstrapped = false,
    this.bootstrapReport,
    this.provisioned = false,
    this.resumed = false,
    this.needsDatabase = false,
    this.detectedPrinters,
    this.claimed = false,
    this.pulledTerminals,
    this.adoptTerminalId,
    this.branchId,
    this.branchLabel,
    this.businessId,
    this.branchCode,
    this.terminalName = '',
    this.terminalId,
    this.installationId,
    this.printerName,
    this.paperWidthDots = PrinterConfig.width80mm,
    this.drawerAttached = false,
    this.scannerAttached = false,
    this.catalogueItems,
    this.mainDeviceLinked = false,
    this.presentedCertificate,
    this.busy = false,
    this.error,
    this.notice,
  }) : _chosenMethod = method;

  final SetupStep step;
  final String locale;
  final DeploymentConfig deployment;

  /// Null until the licence step has run.
  final LicenseEntitlement? entitlement;

  /// The claims of the licence just activated. Null until the licence step has
  /// run, which is why that step now comes first — see [SetupStep].
  final LicenseClaims? claims;

  /// The licence itself, held here until the terminal is finished.
  ///
  /// Activating no longer writes it: the licence step is the FIRST of ten, and
  /// a file written there outlives every abandoned wizard — an owner trying a
  /// key to see what it covers, an installer stopped at the database password.
  /// The machine was left holding a licence for a business it had never been
  /// set up for. `complete()` is what puts this on disk.
  ///
  /// Null also when the licence was RESTORED rather than activated: that one is
  /// already on disk, and rewriting a working licence file buys nothing and
  /// risks a disk error.
  final LicenseFile? licenceFile;
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

  /// Whether the PIN was typed the same twice.
  bool get pinsMatch => ownerPin == ownerPinConfirm;

  /// The step where an offline terminal builds its database and first owner —
  /// the one with two pages. A child tablet signs in to its main device and a
  /// cloud terminal pairs, so neither is this.
  bool get isFirstInstall =>
      step == SetupStep.account &&
      !deployment.isChild &&
      deployment.mode == DeploymentMode.offline;

  /// What the footer's one button does. Everywhere but the first install it is
  /// what it always was; on the first install, before the database exists, it
  /// walks the two pages and then builds.
  FooterAction get footerAction {
    if (isFirstInstall && !bootstrapped) {
      return ownerPage == OwnerPage.databaseAccess
          ? FooterAction.toOwnerPage
          : FooterAction.createDatabase;
    }
    return isLastStep ? FooterAction.finish : FooterAction.next;
  }

  /// Whether that button may be pressed now. [canAdvance] is untouched: it still
  /// answers "may the wizard leave this step", which stays false on the first
  /// install until the database exists.
  bool get footerEnabled => switch (footerAction) {
    FooterAction.next || FooterAction.finish => canAdvance,
    // An empty administrator password is allowed, as it always was: a local
    // PostgreSQL that trusts this machine's account has none to give.
    FooterAction.toOwnerPage => true,
    // Filled in; what is wrong with it (a mismatch, a short PIN) is said when
    // it is pressed, in words, rather than by a button that will not say why.
    FooterAction.createDatabase =>
      ownerName.trim().isNotEmpty &&
          ownerUsername.trim().isNotEmpty &&
          ownerPin.isNotEmpty &&
          ownerPinConfirm.isNotEmpty,
  };

  /// How many terminals the plan covers. One until a licence says otherwise.
  int get maxTerminals => claims?.maxTerminals ?? 1;

  /// Whether the database may live on another machine.
  ///
  /// This — not the deployment mode — is what decides whether the wizard asks
  /// for a database address. A one-terminal plan has nobody to share with, so
  /// the only honest answer is this machine.
  bool get allowsSharedDatabase => maxTerminals > 1;

  final SetupMethod _chosenMethod;

  /// How this terminal is being set up.
  ///
  /// **Always [SetupMethod.manual] on anything but a cloud main device**,
  /// whatever was stored. A pairing code is minted by a dashboard, and an
  /// offline business has none; a child tablet has one available in principle
  /// — its main device may well be cloud — but codes are issued per terminal to
  /// the person installing the till, and a tablet signs in as a manager who
  /// already exists instead.
  ///
  /// Normalised here rather than guarded at each reader, because the readers are
  /// the wizard's path, its step titles, its panes and its gates. One of them
  /// forgetting is a terminal with no button to register itself with — which is
  /// exactly what happened to a child of a cloud main device the moment the
  /// pairing code became the default.
  SetupMethod get method =>
      deployment.mode == DeploymentMode.cloud && !deployment.isChild
      ? _chosenMethod
      : SetupMethod.manual;

  final String pairingCode;
  final String operatorUsername;

  /// True once the slug + credentials have been verified against the platform
  /// and the tenant's configuration pulled. Everything the following steps
  /// display — the branch list above all — came from that pull.
  final bool connected;

  /// The tenant's display name, from the pull. Shown so the operator can see
  /// they signed into the right business before anything is written.
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

  /// Whether the licence leaves a mode question worth asking.
  ///
  /// A tenant is sold cloud, offline, or both, and the `modes` claim carries
  /// that to the till. When it names ONE, the setup-type screen has a single
  /// choosable option — already chosen, because adopting the licence moves the
  /// draft onto a covered mode the moment it is read — sitting beside one
  /// greyed NOT LICENSED. That is not a question. It is a screen the installer
  /// presses Continue on to be told what the business was already sold, on a
  /// wizard that is ten screens long before it adds any.
  ///
  /// Null claims mean no licence has been read yet, which is the licence step
  /// itself: both modes are notionally open, so the step stays visible until
  /// the licence says otherwise.
  bool get asksSetupType => licensedModes.length > 1;

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
  ///
  /// [SetupStep.setupType] is the one step that can drop out, and only because
  /// the licence has answered it — see [asksSetupType].
  ///
  /// **A child tablet walks a different, shorter path** — see [childSteps].
  /// **A cloud main device walks a shorter one too** — see [cloudSteps].
  List<SetupStep> get visibleSteps {
    if (deployment.isChild) return childSteps;
    final path = deployment.mode == DeploymentMode.cloud
        ? cloudSteps
        : offlineSteps;
    if (path.contains(step)) return path;

    // A step being stood on is always listed, whatever the rule says: the rail
    // has to describe where the operator actually is, and `next()` and `back()`
    // count positions in this list. Rebuilt in enum order so an inserted step
    // lands where it belongs rather than at the end.
    return [
      for (final candidate in SetupStep.values)
        if (path.contains(candidate) || candidate == step) candidate,
    ];
  }

  /// What a cloud main device is asked (owner decision, 2026-09-15: "cloud
  /// setup should get everything from cloud, no need for asking anything").
  ///
  /// Everything struck off is something the platform already knows, so the
  /// terminal is TOLD it rather than asking: the language, currency and menu
  /// ride in the bootstrap bundle; the branch, the till's name, its id and its
  /// sync policy ride in the claim; the database is the one the Windows
  /// installer built, with the passwords it generated; the printer is whatever
  /// is plugged in. What survives are the two genuine questions — a licence key
  /// and a pairing code — because each is a secret nobody can guess on the
  /// operator's behalf, and the mode, on the one licence that covers both.
  ///
  /// Three steps come back when the answer stops being obvious, and only then:
  ///
  ///  * [SetupStep.hardware], when the scan found none or more than one printer
  ///    — which printer prints the receipt is a fact only the person standing
  ///    at the till holds.
  ///  * [SetupStep.branch] and [SetupStep.terminal], on the sign-in path behind
  ///    "sign in instead". A till registered by hand has no claim to read the
  ///    branch and the name off, so it has to be asked for both.
  ///
  /// This does not contradict the "no fork" rule on [SetupStep] any more than
  /// [childSteps] does: the mode is settled by the licence on screen one, before
  /// anything has been typed into a screen that could strand somebody.
  List<SetupStep> get cloudSteps => [
    SetupStep.licence,
    if (asksSetupType) SetupStep.setupType,
    SetupStep.account,
    if (method == SetupMethod.manual) ...[
      SetupStep.branch,
      SetupStep.terminal,
    ],
    SetupStep.connecting,
    if (detectedPrinters != 1) SetupStep.hardware,
    SetupStep.summary,
  ];

  /// The long path, unchanged. An offline business has no platform to be told
  /// anything by, so every one of these is a question somebody has to answer.
  List<SetupStep> get offlineSteps => [
    SetupStep.licence,
    SetupStep.language,
    if (asksSetupType) SetupStep.setupType,
    SetupStep.deployment,
    SetupStep.account,
    SetupStep.branch,
    SetupStep.terminal,
    SetupStep.hardware,
    SetupStep.money,
    SetupStep.catalogue,
    SetupStep.summary,
  ];

  /// What a child tablet is asked (owner decision, 2026-09-12).
  ///
  /// This does not contradict the "no fork" rule on [SetupStep]: the fork is
  /// decided by the device before the first screen, not by an answer halfway
  /// through, so nobody is stranded on the wrong branch of it. What is left out
  /// is everything the main device already owns — the licence and the mode (it
  /// shares its own), the database and the first administrator (it built them),
  /// and the money settings (the business's, not the tablet's).
  static const childSteps = [
    SetupStep.deployment,
    SetupStep.account,
    SetupStep.branch,
    SetupStep.terminal,
    SetupStep.hardware,
    SetupStep.catalogue,
    SetupStep.summary,
  ];

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
  // An offline business has no dashboard and, before this, no way to get a
  // schema either — the app's migrator only ever ran on the cloud claim path,
  // so every install began at a command line. These four fields are what the
  // wizard needs to build a database itself.

  /// The administrator role's password. Used to CREATE DATABASE, migrate and
  /// grant, then **discarded** — only the till's password is ever stored.
  final String adminDatabasePassword;

  /// The first person. Without one, an offline till has nobody to sign in as:
  /// the account step authenticates against `pos_users`, which starts empty.
  final String ownerName;
  final String ownerUsername;
  final String ownerPin;

  /// The PIN typed a second time. In memory only, like the PIN: a typo in a PIN
  /// that cannot be read back locks the owner out, so it is asked twice.
  final String ownerPinConfirm;

  /// Which of the first-install step's two screens is showing.
  final OwnerPage ownerPage;

  /// Whether this wizard built the database. Not persisted — a re-run of the
  /// bootstrap is harmless (every statement is an upsert) but pointless.
  final bool bootstrapped;

  /// What it did, in the operator's words. Null before it has run. Shared with
  /// the cloud path's [SetupStep.connecting], which reports the same kind of
  /// thing — a database created, migrations applied, grants given.
  final String? bootstrapReport;

  /// True once the cloud path's automatic provisioning has finished. Its own
  /// flag rather than a reading of [bootstrapped]: a cloud terminal on a
  /// machine the installer prepared builds no database at all — it was already
  /// built — and would otherwise never be able to leave the step.
  final bool provisioned;

  /// True when this draft was rebuilt from a claim an earlier run made, so
  /// the connecting screen can say why it is the one that opened. See
  /// `SetupController._restoreProgress`.
  final bool resumed;

  /// True when this machine has no `install-credentials.json`, so the database
  /// could not be read off the installation and has to be asked for.
  ///
  /// The fallback, and deliberately narrow: on Windows the installer wrote that
  /// file, so a real till never sees these fields. A developer's Mac has no
  /// installer and therefore no file, and guessing a password there would be a
  /// connection failure three screens later instead of a question now.
  final bool needsDatabase;

  /// How many printers the scan on [SetupStep.connecting] found. Null until it
  /// has run, which is why the hardware step is *shown* until then — the rail
  /// must not promise a screen the wizard has not yet decided to skip.
  final int? detectedPrinters;

  /// True once the server has confirmed this terminal. On the pairing path the
  /// branch, name and id below were filled in by that response.
  final bool claimed;

  final int? branchId;
  final String? branchLabel;

  /// Supplied by provisioning, never typed. Both are needed before the till can
  /// write a row: one stamps the tenant, the other is the invoice prefix.
  final int? businessId;
  final String? branchCode;

  final String terminalName;
  final String? terminalId;
  final String? installationId;
  final String? printerName;

  /// The printable width of the roll, in dots. Asked in the wizard rather than
  /// guessed, because a printer given the wrong one prints a receipt with its
  /// right-hand column missing and looks broken instead of mis-set.
  final int paperWidthDots;

  final bool drawerAttached;
  final bool scannerAttached;

  /// Items pulled in the first catalogue sync; null until it runs.
  final int? catalogueItems;

  /// A child tablet only: true once the main device's licence has been read
  /// from the database at the address on screen. Editing that address, or
  /// anything else about the connection, sets it back to false — the licence
  /// on the draft then belongs to a database the tablet is no longer pointing
  /// at.
  final bool mainDeviceLinked;

  /// The certificate the database server presented when the connection was
  /// refused for one, waiting for the technician to compare its fingerprint
  /// with the main device's and confirm. Null when there is nothing to
  /// confirm. **Never trusted by being here** — only
  /// `SetupController.trustPresentedCertificate` moves it into the
  /// deployment's pin, and only when a person presses the button.
  final PresentedCertificate? presentedCertificate;

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
    // A child tablet has reached its main device, and the licence found there
    // lets it trade. Loopback is refused on principle: a child's database is
    // by definition on another machine.
    SetupStep.deployment when deployment.isChild =>
      mainDeviceLinked &&
          !deployment.isLoopback &&
          databasePassword.isNotEmpty &&
          (entitlement?.canSell ?? false),
    // Signed in as a manager the main device already has. Never the offline
    // rule below — a child builds no database, so it is never `bootstrapped`.
    SetupStep.account when deployment.isChild => connected,
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
    // business id and no branch code — which only registration supplies. The
    // operator reached the last screen before being told the sixth was wrong.
    //
    // Cloud registration issues the device token every later platform pull
    // rides on. Offline registration writes the `pos_terminals` row that gives
    // this machine its identity and its invoice prefix. Neither is optional.
    SetupStep.terminal => terminalName.trim().isNotEmpty && claimed,
    // The one screen with no inputs on it, so the only thing that could gate it
    // is whether the work it does actually finished. A catalogue that could not
    // be downloaded does NOT gate it — the same rule the catalogue step has
    // always had, for the same reason: an installer on a site whose menu is not
    // authored yet must still be able to finish.
    SetupStep.connecting => provisioned,
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
    LicenseFile? licenceFile,
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
    String? ownerPinConfirm,
    OwnerPage? ownerPage,
    bool? bootstrapped,
    String? bootstrapReport,
    bool? provisioned,
    bool? resumed,
    bool? needsDatabase,
    int? detectedPrinters,
    bool? claimed,
    List<PosTerminalSummary>? pulledTerminals,
    int? adoptTerminalId,
    bool clearAdoption = false,
    int? branchId,
    String? branchLabel,
    int? businessId,
    String? branchCode,
    String? terminalName,
    String? terminalId,
    String? installationId,
    String? printerName,
    int? paperWidthDots,
    bool? drawerAttached,
    bool? scannerAttached,
    int? catalogueItems,
    bool? mainDeviceLinked,
    PresentedCertificate? presentedCertificate,
    bool clearPresentedCertificate = false,
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
    licenceFile: licenceFile ?? this.licenceFile,
    licenceKey: licenceKey ?? this.licenceKey,
    // `_method` rather than `method`: the getter normalises, and copying
    // through it would turn a cloud draft's pairing code into `manual` the
    // moment it passed through an offline mode on its way somewhere else.
    method: method ?? _chosenMethod,
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
    ownerPinConfirm: ownerPinConfirm ?? this.ownerPinConfirm,
    ownerPage: ownerPage ?? this.ownerPage,
    bootstrapped: bootstrapped ?? this.bootstrapped,
    bootstrapReport: bootstrapReport ?? this.bootstrapReport,
    provisioned: provisioned ?? this.provisioned,
    resumed: resumed ?? this.resumed,
    needsDatabase: needsDatabase ?? this.needsDatabase,
    detectedPrinters: detectedPrinters ?? this.detectedPrinters,
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
    businessId: clearClaim ? null : (businessId ?? this.businessId),
    branchCode: clearClaim ? null : (branchCode ?? this.branchCode),
    terminalName: clearClaim ? '' : (terminalName ?? this.terminalName),
    terminalId: clearClaim ? null : (terminalId ?? this.terminalId),
    installationId: installationId ?? this.installationId,
    printerName: printerName ?? this.printerName,
    paperWidthDots: paperWidthDots ?? this.paperWidthDots,
    drawerAttached: drawerAttached ?? this.drawerAttached,
    scannerAttached: scannerAttached ?? this.scannerAttached,
    catalogueItems: catalogueItems ?? this.catalogueItems,
    mainDeviceLinked: mainDeviceLinked ?? this.mainDeviceLinked,
    presentedCertificate: clearPresentedCertificate
        ? null
        : (presentedCertificate ?? this.presentedCertificate),
    busy: busy ?? this.busy,
    error: clearError ? null : (error ?? this.error),
    notice: clearNotice ? null : (notice ?? this.notice),
  );
}
