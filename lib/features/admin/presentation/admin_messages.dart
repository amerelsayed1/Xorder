import '../../../core/l10n/app_strings.dart';
import '../../../domain/models/permissions.dart';
import '../../../domain/repositories/admin_repositories.dart';
import '../../../domain/services/authorization.dart';

/// Where the Management section's domain values become words.
///
/// The words themselves live in [AppStrings], the same sealed pair as the rest
/// of the app, so a capability or a refusal that has no Arabic is a compile
/// error rather than an English sentence on an Arabic till. What stays here is
/// the *mapping*: a switch over a domain type, exhaustive, so a capability
/// added to [PosCapability] or a case added to [AdminRefusal] cannot reach a
/// screen without somebody writing both languages for it.
abstract final class AdminText {
  /// What a permission means, in the words a manager ticking the box needs.
  ///
  /// The capability *name* is not shown on its own anywhere: `price.override`
  /// tells a restaurant owner nothing, and a permission screen nobody
  /// understands is a permission screen everybody ticks.
  static String capability(AppStrings s, String capability) =>
      switch (capability) {
        PosCapability.operate => s.capOperate,
        PosCapability.catalogView => s.capCatalogView,
        PosCapability.catalogManage => s.capCatalogManage,
        PosCapability.staffManage => s.capStaffManage,
        PosCapability.terminalManage => s.capTerminalManage,
        PosCapability.settingsManage => s.capSettingsManage,
        PosCapability.discountApply => s.capDiscountApply,
        PosCapability.priceOverride => s.capPriceOverride,
        PosCapability.orderVoid => s.capOrderVoid,
        PosCapability.orderItemCancel => s.capOrderItemCancel,
        PosCapability.orderItemVoid => s.capOrderItemVoid,
        PosCapability.orderViewAll => s.capOrderViewAll,
        PosCapability.cashOpenWithoutSale => s.capCashOpenWithoutSale,
        PosCapability.shiftViewExpectedCash => s.capShiftViewExpectedCash,
        PosCapability.cashVarianceView => s.capCashVarianceView,
        PosCapability.dayClose => s.capDayClose,
        PosCapability.dayForceClose => s.capDayForceClose,
        PosCapability.orderRefund => s.capOrderRefund,
        PosCapability.receiptReprint => s.capReceiptReprint,
        PosCapability.shiftOpen => s.capShiftOpen,
        PosCapability.shiftClose => s.capShiftClose,
        PosCapability.cashMovement => s.capCashMovement,
        PosCapability.reportsView => s.capReportsView,
        PosCapability.backupManage => s.capBackupManage,
        // A capability from a newer build. Shown rather than hidden: a manager
        // seeing a permission they do not recognise is better informed than one
        // looking at a list that quietly omits it. Untranslated of course —
        // this build has never heard of it.
        _ => capability,
      };

  static String group(AppStrings s, CapabilityGroup group) => switch (group) {
    CapabilityGroup.selling => s.capGroupSelling,
    CapabilityGroup.money => s.capGroupMoney,
    CapabilityGroup.drawer => s.capGroupDrawer,
    CapabilityGroup.backOffice => s.capGroupBackOffice,
  };

  /// Why a write did not happen, in a sentence that says what to do next.
  ///
  /// A refusal that only says "not allowed" makes the manager try the same
  /// thing again; one that names the obstacle makes them go and move it.
  static String refusal(AppStrings s, AdminRefusal refusal) =>
      switch (refusal) {
        NotPermitted(:final capability) => s.refusalNotPermitted(
          _lower(AdminText.capability(s, capability)),
        ),
        RoleStillHeld(:final staffNames) => s.refusalRoleStillHeld(
          _list(s, staffNames),
        ),
        RoleIsSystemDefined() => s.refusalRoleIsSystemDefined,
        RoleNotAllowed(:final reason) => _roleReason(s, reason),
        UserSeatsExhausted(:final maxUsers) => s.refusalUserSeatsExhausted(
          maxUsers,
        ),
        UsernameTaken(:final username) => s.refusalUsernameTaken(username),
        WouldLockEveryoneOut() => s.refusalWouldLockEveryoneOut,
        EditedElsewhere() => s.refusalEditedElsewhere,
        // The reason comes from the catalogue importer, which speaks for
        // itself; there is nothing here to translate it into.
        CatalogInvalid(:final reason) => reason,
        AdministratorCredentialRequired() =>
          s.refusalAdministratorCredentialRequired,
        NoDatabaseConfigured() => s.refusalNoDatabaseConfigured,
        ManagedByPlatform(:final what) => s.refusalManagedByPlatform(what),
      };

  /// What a risk level is called on a badge.
  static String risk(AppStrings s, PermissionRisk level) => switch (level) {
    PermissionRisk.low => s.riskLow,
    PermissionRisk.medium => s.riskMedium,
    PermissionRisk.high => s.riskHigh,
    PermissionRisk.critical => s.riskCritical,
  };

  static String _roleReason(AppStrings s, RoleRefusal reason) =>
      switch (reason) {
        OwnerMustKeepEverything() => s.refusalOwnerMustKeepEverything,
        CashiersAreNotAdministrators(:final capabilities) =>
          s.refusalCashiersAreNotAdministrators(
            _list(s, [
              for (final c in capabilities) _lower(AdminText.capability(s, c)),
            ]),
          ),
        CannotGrantWhatYouLack(:final capabilities) =>
          s.refusalCannotGrantWhatYouLack(
            _list(s, [
              for (final c in capabilities) _lower(AdminText.capability(s, c)),
            ]),
          ),
      };

  /// Lower-casing the first letter is an English sentence-joining trick and
  /// nothing else — Arabic has no letter case, so `substring` would only be a
  /// way to corrupt the first character of a word.
  static String _lower(String label) =>
      label.isEmpty || !_startsWithLatin(label)
      ? label
      : label[0].toLowerCase() + label.substring(1);

  static bool _startsWithLatin(String value) {
    final first = value.codeUnitAt(0);
    return (first >= 0x41 && first <= 0x5A) || (first >= 0x61 && first <= 0x7A);
  }

  /// "Rana", "Rana and Nour", "Rana, Nour and Sara" — and the same shape in
  /// Arabic, where both joiners are different characters.
  static String _list(AppStrings s, Iterable<String> items) {
    final all = items.toList();
    if (all.isEmpty) return '';
    if (all.length == 1) return all.single;
    return all.take(all.length - 1).join(s.listSeparator) +
        s.listAnd +
        all.last;
  }
}
