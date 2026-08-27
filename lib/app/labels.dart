import '../core/config/deployment.dart';
import '../core/l10n/app_strings.dart';
import '../domain/models/dining_table.dart';
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
        DeploymentMode.branchServer => s.modeBranchServer,
        DeploymentMode.standalone => s.modeStandalone,
      };

  String blurb(AppStrings s) => switch (this) {
        DeploymentMode.cloud => s.modeCloudBlurb,
        DeploymentMode.branchServer => s.modeBranchServerBlurb,
        DeploymentMode.standalone => s.modeStandaloneBlurb,
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
  String title(AppStrings s) => switch (this) {
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

  String blurb(AppStrings s) => switch (this) {
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
        LicenceModeNotCovered(:final mode) =>
          s.licenceModeNotCovered(mode.label(s)),
        LicenceOtherTerminal() => s.licenceOtherTerminal,
        LicenceNotYetValid(:final startsOn) =>
          s.licenceNotYetValid(_shortDate(startsOn)),
        LicenceFileDamaged() => s.licenceFileDamaged,
        LicenceUnverifiable() => s.licenceUnverifiable,
        LicenceMissing() => s.noLicenceInstalled,
        NoLicenceServer() => s.noLicenceServer,
        NotALicenceFile() => s.notALicenceFile,
        LicenceKeyNotRecognised() => s.licenceKeyNotRecognised,
      };
}

/// Day-first, which both languages read the same way. Deliberately not
/// `intl`'s locale date format: this string is nearly always shown next to
/// "check the terminal's clock", and a date the operator has to re-read in an
/// unfamiliar order is the wrong thing to put there.
String _shortDate(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/'
    '${value.month.toString().padLeft(2, '0')}/${value.year}';
