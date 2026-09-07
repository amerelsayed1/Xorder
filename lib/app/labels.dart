import '../core/config/deployment.dart';
import '../core/l10n/app_strings.dart';
import '../domain/models/dining_table.dart';
import '../domain/models/tender_method.dart';
import '../domain/models/ticket.dart';
import '../features/licensing/domain/license.dart';
import '../features/setup/domain/setup_state.dart';

/// Where domain values become words.
///
/// The enums below carry no display text of their own — an `OrderType` is a
/// fact about an order, and "Dine-in" is a fact about the language the till was
/// set up in. Keeping the two apart is what makes `lib/domain/` testable
/// without a locale and translatable without touching it.
///
/// This file lives in `app/` because it is the only layer permitted to see both
/// halves: `core/l10n` must not depend on features, and features must not
/// depend on each other.

extension OrderTypeLabel on OrderType {
  String label(AppStrings s) => switch (this) {
    OrderType.dineIn => s.orderTypeDineIn,
    OrderType.takeaway => s.orderTypeTakeaway,
    OrderType.delivery => s.orderTypeDelivery,
    OrderType.driveThru => s.orderTypeDriveThru,
  };
}

extension DeploymentModeLabel on DeploymentMode {
  String label(AppStrings s) => switch (this) {
    DeploymentMode.cloud => s.modeCloud,
    DeploymentMode.offline => s.modeOffline,
  };

  String blurb(AppStrings s) => switch (this) {
    DeploymentMode.cloud => s.modeCloudBlurb,
    DeploymentMode.offline => s.modeOfflineBlurb,
  };
}

extension SyncPolicyLabel on SyncPolicy {
  String label(AppStrings s) => switch (this) {
    SyncPolicy.automatic => s.syncAutomatic,
    SyncPolicy.manual => s.syncManual,
  };

  String blurb(AppStrings s) => switch (this) {
    SyncPolicy.automatic => s.syncAutomaticBlurb,
    SyncPolicy.manual => s.syncManualBlurb,
  };
}

extension SetupMethodLabel on SetupMethod {
  String label(AppStrings s) => switch (this) {
    SetupMethod.pairingCode => s.methodPairingCode,
    SetupMethod.manual => s.methodManual,
  };

  String blurb(AppStrings s) => switch (this) {
    SetupMethod.pairingCode => s.methodPairingCodeBlurb,
    SetupMethod.manual => s.methodManualBlurb,
  };
}

extension SetupStepLabel on SetupStep {
  /// [mode] retitles the one step whose MEANING changes with it.
  ///
  /// On the cloud path the account step signs in to the platform and pulls the
  /// tenant's configuration. Offline there is no platform to sign in to and no
  /// account to sign in with — the first administrator does not exist yet, and
  /// this is the screen that creates them. Same position in the wizard, a
  /// different question, so it must not wear the same title.
  String title(AppStrings s, {DeploymentMode? mode}) => switch (this) {
    SetupStep.account when mode == DeploymentMode.offline =>
      s.stepFirstAdministrator,
    SetupStep.setupType => s.stepSetupType,
    SetupStep.language => s.stepLanguage,
    SetupStep.deployment => s.stepConnection,
    SetupStep.account => s.stepAccount,
    SetupStep.licence => s.stepLicence,
    SetupStep.branch => s.stepBranch,
    SetupStep.terminal => s.stepTerminal,
    SetupStep.hardware => s.stepHardware,
    SetupStep.money => s.stepMoney,
    SetupStep.catalogue => s.stepCatalogue,
    SetupStep.summary => s.stepReady,
  };

  String blurb(AppStrings s, {DeploymentMode? mode}) => switch (this) {
    SetupStep.account when mode == DeploymentMode.offline =>
      s.stepFirstAdministratorBlurb,
    SetupStep.setupType => s.stepSetupTypeBlurb,
    SetupStep.language => s.stepLanguageBlurb,
    SetupStep.deployment => s.stepConnectionBlurb,
    SetupStep.account => s.stepAccountBlurb,
    SetupStep.licence => s.stepLicenceBlurb,
    SetupStep.branch => s.stepBranchBlurb,
    SetupStep.terminal => s.stepTerminalBlurb,
    SetupStep.hardware => s.stepHardwareBlurb,
    SetupStep.money => s.stepMoneyBlurb,
    SetupStep.catalogue => s.stepCatalogueBlurb,
    SetupStep.summary => s.stepReadyBlurb,
  };
}

extension LicenseStateHeadline on LicenseState {
  /// The one-word verdict at the top of the licence panel.
  ///
  /// Anything not enumerated is a licence the till cannot make sense of —
  /// damaged, unsigned, for another tenant. They share a headline because the
  /// operator's next move is the same in every case: get a new file.
  String headline(AppStrings s) => switch (this) {
    LicenseState.valid => s.licensedHeadline,
    LicenseState.expiringSoon => s.renewalDueHeadline,
    LicenseState.inGrace => s.expiredInGraceHeadline,
    LicenseState.expired => s.expiredHeadline,
    LicenseState.missing => s.notLicensedHeadline,
    _ => s.licenceProblemHeadline,
  };
}

extension TableStateLabel on TableState {
  String badge(AppStrings s, {required int openLines}) => switch (this) {
    TableState.free => s.tableFree,
    TableState.open => s.tableLineCount(openLines),
    TableState.billAsked => s.tableBillAsked,
  };
}

extension LicenceNoticeText on LicenceNotice {
  /// The verifier's finding, in words.
  ///
  /// Exhaustive over a sealed hierarchy, so a new failure mode added to
  /// [LicenceNotice] cannot reach a screen without someone writing both
  /// languages for it.
  String text(AppStrings s) => switch (this) {
    LicenceExpiresIn(:final days) => s.licenceExpiresInDays(days),
    LicenceInGrace(:final daysLeft) => s.licenceGraceRemaining(daysLeft),
    LicenceExpired() => s.licenceExpiredNewShiftBlocked,
    LicenceTenantMismatch(:final licenceTenant, :final terminalTenant) =>
      s.licenceTenantMismatch(licenceTenant, terminalTenant),
    LicenceModeNotCovered(:final mode) => s.licenceModeNotCovered(
      mode.label(s),
    ),
    LicenceOtherTerminal() => s.licenceOtherTerminal,
    LicenceNotYetValid(:final startsOn) => s.licenceNotYetValid(
      _shortDate(startsOn),
    ),
    LicenceFileDamaged() => s.licenceFileDamaged,
    LicenceUnverifiable() => s.licenceUnverifiable,
    LicenceMissing() => s.noLicenceInstalled,
    NoLicenceServer() => s.noLicenceServer,
    NotALicenceFile() => s.notALicenceFile,
    LicenceRevoked() => s.licenceRevokedByPlatform,
    TooManyLicenceAttempts() => s.tooManyLicenceAttempts,
    LicenceServerUnreachable(:final address) => s.licenceServerUnreachable(
      address,
    ),
    LicenceServerRefused(:final address, :final status) =>
      s.licenceServerRefused(address, status),
    // Names the platform that refused it when there is one to name: the key
    // may be perfectly good and this simply the wrong platform to ask.
    LicenceKeyNotRecognised(:final address) =>
      address == null
          ? s.licenceKeyNotRecognised
          : s.licenceKeyNotRecognisedBy(address),
  };
}

/// Day-first, which both languages read the same way. Deliberately not
/// `intl`'s locale date format: this string is nearly always shown next to
/// "check the terminal's clock", and a date the operator has to re-read in an
/// unfamiliar order is the wrong thing to put there.
String _shortDate(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/'
    '${value.month.toString().padLeft(2, '0')}/${value.year}';

/// A provisioning refusal, in the operator's language.
///
/// The repositories return a machine-readable [code] beside their English
/// [fallback] — that is what POS-BE-019 specifies the codes FOR. Naming them
/// here rather than printing the message means the setup wizard says why it
/// stopped in the language the wizard is being run in, which is the one moment
/// an installer most needs it.
///
/// [fallback] is returned unchanged for a code this build has never heard of.
/// A newer server's untranslated sentence is worth more to somebody standing at
/// a half-configured till than a translated "something went wrong".
String provisioningRefusal(
  AppStrings s,
  String? code, {
  required String fallback,
  String? tenant,
  String? platform,
}) => switch (code) {
  'PAIRING_CODE_INVALID' => s.refusalPairingCodeInvalid,
  'PAIRING_CODE_SPENT' => s.refusalPairingCodeSpent,
  'CREDENTIALS_REJECTED' => s.refusalCredentialsRejected,
  'NO_BRANCHES' => s.refusalNoBranches,
  'BRANCH_UNKNOWN' => s.refusalBranchUnknown,
  // The variable half comes from the wizard's own state rather than from
  // the message, so the sentence can be rebuilt in either language.
  'TENANT_UNKNOWN' when tenant != null => s.refusalTenantUnknown(tenant),
  'WRONG_PLATFORM' when platform != null => s.refusalWrongPlatform(platform),
  'PLATFORM_UNREACHABLE' when platform != null => s.refusalPlatformUnreachable(
    platform,
  ),
  'CLAIM_UNREADABLE' => s.refusalClaimUnreadable,
  'NO_PLATFORM' => s.refusalNoPlatformConfigured,
  'NO_DATABASE' => s.refusalNoDatabaseReachable,
  'ADOPT_UNSUPPORTED' => s.refusalAdoptUnsupported,
  'VALIDATION_FAILED' => s.refusalValidationFailed,
  _ => fallback,
};

/// What a tender is called, in the reader's language.
///
/// Falls back to the stored text for anything the build does not recognise — a
/// tender type the restaurant configured itself has no translation here, and
/// showing what they named it is the honest answer.
///
/// Takes the id and the stored label rather than a `Tender`, because the same
/// question is asked about a settled order's payment, a refund's tender and a
/// live ticket's, and only one of those three is a `Tender`.
String tenderName(int? typeId, String stored, AppStrings s) => switch (typeId) {
  1 => s.tenderCash,
  2 => s.tenderCard,
  3 => s.tenderWallet,
  4 => s.tenderOnAccount,
  _ => stored,
};

extension TenderMethodLabel on TenderMethod {
  String label(AppStrings s) => tenderName(id, wireLabel, s);
}
