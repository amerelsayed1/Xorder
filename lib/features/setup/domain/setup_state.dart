import '../../../core/config/deployment.dart';
import '../../licensing/domain/license.dart';

/// How this terminal is being set up (POS-BE-023).
///
/// Both paths land on the same `pos_terminals` row. The pairing code is the
/// default because the alternative types a staff password into a machine that
/// lives in a public room and may be stolen — a code that expires in a day is a
/// much smaller thing to lose.
enum SetupMethod {
  pairingCode,
  manual,
}

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
  language,
  deployment,
  // Sign in comes **before** the licence, and the order is load-bearing. A
  // licence is issued to a tenant, and the verifier refuses one whose slug does
  // not match the terminal's. Asking for the licence first meant activating it
  // against whatever tenant the terminal happened to hold — which, until the
  // till read real data, was always the same fictional restaurant as the
  // licence, so the mismatch never showed.
  account,
  licence,
  branch,
  terminal,
  hardware,
  money,
  catalogue,
  summary;

  bool get isFirst => index == 0;
  bool get isLast => index == SetupStep.values.length - 1;
}

/// Everything the wizard has gathered so far.
class SetupDraft {
  const SetupDraft({
    this.step = SetupStep.language,
    this.locale = 'en',
    this.deployment = DeploymentConfig.unconfigured,
    this.entitlement,
    this.licenceKey = '',
    this.method = SetupMethod.pairingCode,
    this.pairingCode = '',
    this.operatorUsername = '',
    this.operatorPassword = '',
    this.databasePassword = '',
    this.claimed = false,
    this.branchId,
    this.branchLabel,
    this.restaurantId,
    this.branchCode,
    this.terminalName = '',
    this.terminalId,
    this.printerName,
    this.drawerAttached = false,
    this.scannerAttached = false,
    this.catalogueItems,
    this.busy = false,
    this.error,
  });

  final SetupStep step;
  final String locale;
  final DeploymentConfig deployment;

  /// Null until the licence step has run.
  final LicenseEntitlement? entitlement;
  final String licenceKey;

  final SetupMethod method;
  final String pairingCode;
  final String operatorUsername;

  /// Held only for the length of the wizard and never persisted with the rest
  /// of the draft — it exists to authenticate one registration call.
  final String operatorPassword;

  /// The branch database password. Held for the length of the wizard and handed
  /// to the credential store at the end — never written into the draft's
  /// persisted form, and never into device config.
  final String databasePassword;

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
  final String? printerName;
  final bool drawerAttached;
  final bool scannerAttached;

  /// Items pulled in the first catalogue sync; null until it runs.
  final int? catalogueItems;

  final bool busy;
  final String? error;

  /// Whether the current step has enough to move on.
  ///
  /// Note what is deliberately *not* required: hardware. A till with no printer
  /// must still finish setup — the receipt queues and the sale completes.
  /// Printing is never on the critical path of taking money.
  bool get canAdvance => switch (step) {
        SetupStep.language => true,
        // A branch-server till writes straight to PostgreSQL, so it cannot get
        // past this step without a credential to do it with.
        SetupStep.deployment => deployment.isConfigured &&
            (deployment.mode != DeploymentMode.branchServer || databasePassword.isNotEmpty),
        // `canSell` rather than `state == valid`: a licence in its grace window
        // still permits trade, and refusing to finish setup on one would be its
        // own outage.
        SetupStep.licence => entitlement?.canSell ?? false,
        // A pairing code must actually be redeemed before moving on, because
        // everything after this step is the answer it returned. Manual setup
        // only needs credentials — it registers at the terminal step, where the
        // branch and till name it has to send are finally known.
        SetupStep.account => (deployment.tenantSlug?.isNotEmpty ?? false) &&
            switch (method) {
              SetupMethod.pairingCode => claimed,
              SetupMethod.manual =>
                operatorUsername.trim().isNotEmpty && operatorPassword.isNotEmpty,
            },
        SetupStep.branch => branchId != null,
        SetupStep.terminal => terminalName.trim().isNotEmpty,
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
    String? licenceKey,
    SetupMethod? method,
    String? pairingCode,
    String? operatorUsername,
    String? operatorPassword,
    String? databasePassword,
    bool? claimed,
    int? branchId,
    String? branchLabel,
    int? restaurantId,
    String? branchCode,
    String? terminalName,
    String? terminalId,
    String? printerName,
    bool? drawerAttached,
    bool? scannerAttached,
    int? catalogueItems,
    bool? busy,
    String? error,
    bool clearError = false,
    bool clearClaim = false,
  }) =>
      SetupDraft(
        step: step ?? this.step,
        locale: locale ?? this.locale,
        deployment: deployment ?? this.deployment,
        entitlement: entitlement ?? this.entitlement,
        licenceKey: licenceKey ?? this.licenceKey,
        method: method ?? this.method,
        pairingCode: pairingCode ?? this.pairingCode,
        operatorUsername: operatorUsername ?? this.operatorUsername,
        operatorPassword: operatorPassword ?? this.operatorPassword,
        databasePassword: databasePassword ?? this.databasePassword,
        // `clearClaim` exists because the `?? this.x` idiom cannot express
        // "forget this": switching setup path has to erase the branch and till
        // name a previous claim filled in, not merely leave them unset.
        claimed: clearClaim ? false : (claimed ?? this.claimed),
        branchId: clearClaim ? null : (branchId ?? this.branchId),
        branchLabel: clearClaim ? null : (branchLabel ?? this.branchLabel),
        restaurantId: clearClaim ? null : (restaurantId ?? this.restaurantId),
        branchCode: clearClaim ? null : (branchCode ?? this.branchCode),
        terminalName: clearClaim ? '' : (terminalName ?? this.terminalName),
        terminalId: clearClaim ? null : (terminalId ?? this.terminalId),
        printerName: printerName ?? this.printerName,
        drawerAttached: drawerAttached ?? this.drawerAttached,
        scannerAttached: scannerAttached ?? this.scannerAttached,
        catalogueItems: catalogueItems ?? this.catalogueItems,
        busy: busy ?? this.busy,
        error: clearError ? null : (error ?? this.error),
      );
}
