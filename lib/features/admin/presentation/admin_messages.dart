import '../../../core/l10n/app_strings.dart';
import '../../../core/money/quantity.dart';
import '../../../core/security/pin_hash.dart';
import '../../../domain/models/backup.dart';
import '../../../domain/models/business_logo.dart';
import '../../../domain/models/catalog.dart';
import '../../../domain/models/combo_draft.dart';
import '../../../domain/models/financial_account.dart';
import '../../../domain/models/held_sync.dart';
import '../../../domain/models/option_group.dart';
import '../../../domain/models/purchase_order.dart';
import '../../../domain/models/supplier_invoice.dart';
import '../../../domain/models/permissions.dart';
import '../../../domain/repositories/admin_repositories.dart';
import '../../../domain/services/authorization.dart';
import '../../../domain/services/stock_costing.dart' show OpeningCostProblem;
import '../application/users_overview.dart';

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
        PosCapability.purchaseManage => s.capPurchaseManage,
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
        PosCapability.reportExport => s.capReportExport,
        PosCapability.backupManage => s.capBackupManage,
        PosCapability.adminEnter => s.capAdminEnter,
        PosCapability.paymentRemove => s.capPaymentRemove,
        PosCapability.customersCreate => s.capCustomersCreate,
        PosCapability.orderTypesManage => s.capOrderTypesManage,
        PosCapability.brandingManage => s.capBrandingManage,
        PosCapability.financeAccounts => s.capFinanceAccounts,
        // A capability from a newer build. Shown rather than hidden: a manager
        // seeing a permission they do not recognise is better informed than one
        // looking at a list that quietly omits it. Untranslated of course —
        // this build has never heard of it.
        _ => capability,
      };

  /// What an audit row *did*, in a sentence.
  ///
  /// **The Activity pane rendered `entry.action` raw** — every row read
  /// `supplier_invoice.saved`, in both languages, on the screen a restaurant
  /// looks at when it wants to know who changed something. Same shape of gap as
  /// the unlabelled capability, one screen over, and worse: there was no switch
  /// with a missing case, there was no switch.
  ///
  /// The fall-through is deliberate and matches [capability]: a row written by a
  /// newer build is shown as it was stored rather than hidden, because an audit
  /// log that omits what it cannot name is an audit log nobody can rely on.
  /// `capability_labels_test.dart` is what keeps *this* build out of that path.
  static String auditAction(AppStrings s, String action) => switch (action) {
    AuditAction.staffCreated => s.actStaffCreated,
    AuditAction.staffUpdated => s.actStaffUpdated,
    AuditAction.staffDisabled => s.actStaffDisabled,
    AuditAction.staffReactivated => s.actStaffReactivated,
    AuditAction.staffPinReset => s.actStaffPinReset,
    AuditAction.staffPasswordSet => s.actStaffPasswordSet,
    AuditAction.staffPasswordCleared => s.actStaffPasswordCleared,
    AuditAction.staffRoleChanged => s.actStaffRoleChanged,
    AuditAction.staffGrantsChanged => s.actStaffGrantsChanged,
    AuditAction.roleCreated => s.actRoleCreated,
    AuditAction.roleUpdated => s.actRoleUpdated,
    AuditAction.roleDeleted => s.actRoleDeleted,
    AuditAction.permissionOverridden => s.actPermissionOverridden,
    AuditAction.shiftOpened => s.actShiftOpened,
    AuditAction.shiftClosed => s.actShiftClosed,
    AuditAction.receiptReprinted => s.actReceiptReprinted,
    AuditAction.categoryCreated => s.actCategoryCreated,
    AuditAction.categoryUpdated => s.actCategoryUpdated,
    AuditAction.categoryArchived => s.actCategoryArchived,
    AuditAction.categoryRestored => s.actCategoryRestored,
    AuditAction.categoryDeleted => s.actCategoryDeleted,
    AuditAction.productCreated => s.actProductCreated,
    AuditAction.productUpdated => s.actProductUpdated,
    AuditAction.productArchived => s.actProductArchived,
    AuditAction.productRestored => s.actProductRestored,
    AuditAction.productRepriced => s.actProductRepriced,
    AuditAction.unitSaved => s.actUnitSaved,
    AuditAction.stockItemSaved => s.actStockItemSaved,
    AuditAction.moneyConfigChanged => s.actMoneyConfigChanged,
    AuditAction.receiptProfileChanged => s.actReceiptProfileChanged,
    AuditAction.tableCreated => s.actTableCreated,
    AuditAction.tableUpdated => s.actTableUpdated,
    AuditAction.tableArchived => s.actTableArchived,
    AuditAction.tableRestored => s.actTableRestored,
    AuditAction.purchaseOrderStatusChanged => s.actPurchaseOrderStatusChanged,
    AuditAction.stockReceived => s.actStockReceived,
    AuditAction.supplierSaved => s.actSupplierSaved,
    AuditAction.supplierInvoiceSaved => s.actSupplierInvoiceSaved,
    AuditAction.supplierInvoiceVoided => s.actSupplierInvoiceVoided,
    AuditAction.supplierPaid => s.actSupplierPaid,
    AuditAction.supplierPaymentVoided => s.actSupplierPaymentVoided,
    AuditAction.serviceChargeSaved => s.actServiceChargeSaved,
    AuditAction.tenderTypeSaved => s.actTenderTypeSaved,
    AuditAction.financialAccountSaved => s.actFinancialAccountSaved,
    AuditAction.tenderAccountDefaultSaved => s.actTenderAccountDefaultSaved,
    AuditAction.orderTypeSaved => s.actOrderTypeSaved,
    AuditAction.contentLanguagesSaved => s.actContentLanguagesSaved,
    AuditAction.businessLogoSaved => s.actBusinessLogoSaved,
    AuditAction.businessLogoRemoved => s.actBusinessLogoRemoved,
    AuditAction.taxGroupSaved => s.actTaxGroupSaved,
    AuditAction.comboSaved => s.actComboSaved,
    AuditAction.stockCostSet => s.actStockCostSet,
    AuditAction.productOptionsChanged => s.actProductOptionsChanged,
    AuditAction.optionGroupSaved => s.actOptionGroupSaved,
    AuditAction.optionGroupRepriced => s.actOptionGroupRepriced,
    AuditAction.optionGroupDeleted => s.actOptionGroupDeleted,
    AuditAction.backupTaken => s.actBackupTaken,
    AuditAction.backupRestored => s.actBackupRestored,
    AuditAction.adminEntered => s.actAdminEntered,
    AuditAction.adminExited => s.actAdminExited,
    AuditAction.adminTimedOut => s.actAdminTimedOut,
    AuditAction.adminRefused => s.actAdminRefused,
    AuditAction.adminLockedOut => s.actAdminLockedOut,
    AuditAction.syncRecordReleased => s.actSyncRecordReleased,
    AuditAction.lanEncryptionChanged => s.actLanEncryptionChanged,
    _ => action,
  };

  /// Why a new Admin Mode password was refused. Enum-keyed, so a rule added
  /// to `PasswordPolicy` cannot reach the door without both languages. The
  /// numbers are the policy's own constants, so the sentence and the rule
  /// cannot disagree about how long "long enough" is.
  static String passwordProblem(AppStrings s, PasswordProblem problem) =>
      switch (problem) {
        PasswordProblem.sameAsPin => s.passwordSameAsPin,
        PasswordProblem.tooShort => s.passwordTooShort(
          PasswordPolicy.minLength,
        ),
        PasswordProblem.tooLong => s.passwordTooLong(PasswordPolicy.maxLength),
        PasswordProblem.sameAsUsername => s.passwordSameAsUsername,
      };

  /// What kind of record is held. Enum-keyed, so a lifecycle event added to the
  /// outbox without a word here fails to compile.
  static String heldSyncKind(AppStrings s, HeldSyncKind kind) =>
      switch (kind) {
        HeldSyncKind.sale => s.heldKindSale,
        HeldSyncKind.shiftOpen => s.heldKindShiftOpen,
        HeldSyncKind.shiftClose => s.heldKindShiftClose,
        HeldSyncKind.cashMovement => s.heldKindCashMovement,
        HeldSyncKind.refund => s.heldKindRefund,
        HeldSyncKind.customer => s.heldKindCustomer,
        HeldSyncKind.other => s.heldKindOther,
      };

  /// Why it is held, in a sentence. The raw code is shown beside it in mono,
  /// because it is what support asks for; this is what the manager reads.
  static String quarantineCode(AppStrings s, QuarantineCode code) =>
      switch (code) {
        QuarantineCode.validationFailed => s.quarantineValidationFailed,
        QuarantineCode.idempotencyPayloadMismatch =>
          s.quarantineIdempotencyPayloadMismatch,
        QuarantineCode.menuItemNotFound => s.quarantineMenuItemNotFound,
        QuarantineCode.branchNotInTenant => s.quarantineBranchNotInTenant,
        QuarantineCode.customerNotFound => s.quarantineCustomerNotFound,
        QuarantineCode.refundExceedsSold => s.quarantineRefundExceedsSold,
        QuarantineCode.saleNeverQueued => s.quarantineSaleNeverQueued,
        QuarantineCode.refundHasNoLines => s.quarantineRefundHasNoLines,
        QuarantineCode.tenderNotFromPlatform =>
          s.quarantineTenderNotFromPlatform,
        QuarantineCode.localSourceMissing => s.quarantineLocalSourceMissing,
        QuarantineCode.unknown => s.quarantineUnknown,
      };

  /// How much of a backup a row actually is.
  ///
  /// Enum-keyed, so a fourth outcome fails to compile rather than rendering
  /// `unverified` on a badge. And the middle case is not a hedge: a copy that
  /// could not be read back is shown as **not a backup**, because a restaurant
  /// that believes it has one is in a worse position than one that knows it
  /// does not.
  static String backupOutcome(AppStrings s, BackupOutcome outcome) =>
      switch (outcome) {
        BackupOutcome.verified => s.backupOutcomeVerified,
        BackupOutcome.unverified => s.backupOutcomeUnverified,
        BackupOutcome.failed => s.backupOutcomeFailed,
      };

  static String backupTrigger(AppStrings s, BackupTrigger trigger) =>
      switch (trigger) {
        BackupTrigger.manual => s.backupTriggerManual,
        BackupTrigger.dayClose => s.backupTriggerDayClose,
      };

  /// Why a copy is not a copy. The raw output of `pg_dump` travels beside this
  /// in [BackupRecord.detail] and is shown untranslated — see that field.
  static String backupFailure(AppStrings s, BackupFailure failure) =>
      switch (failure) {
        BackupFailure.toolsMissing => s.backupFailureToolsMissing,
        BackupFailure.destinationUnwritable =>
          s.backupFailureDestinationUnwritable,
        BackupFailure.dumpRefused => s.backupFailureDumpRefused,
        BackupFailure.archiveUnreadable => s.backupFailureArchiveUnreadable,
        BackupFailure.archiveIncomplete => s.backupFailureArchiveIncomplete,
      };

  /// What is standing between somebody and a restore.
  static String restoreBlocker(AppStrings s, RestoreBlocker blocker) =>
      switch (blocker.kind) {
        RestoreBlockerKind.openShift => s.restoreBlockerOpenShifts(
          blocker.count,
        ),
        RestoreBlockerKind.openBusinessDay => s.restoreBlockerOpenDay(
          blocker.count,
        ),
        RestoreBlockerKind.pendingSync => s.restoreBlockerPendingSync(
          blocker.count,
        ),
      };

  /// A file size, as somebody reading a folder listing would say it.
  ///
  /// **Integer arithmetic, like every other number in this codebase.** The
  /// obvious `bytes / 1024 / 1024` routes a count through a `double`, which is
  /// the habit the money code exists to break — and a size is a count. One
  /// decimal place, computed from the remainder, because "4.2 MB" is what a
  /// person needs and "4.19 MB" is precision nobody asked for.
  ///
  /// Powers of 1024 with the short units, which is what every file manager a
  /// restaurant has ever used shows.
  static String bytes(int size) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];

    var unit = 0;
    var divisor = 1;
    while (size >= divisor * 1024 && unit < units.length - 1) {
      divisor *= 1024;
      unit++;
    }
    if (unit == 0) return '$size ${units[0]}';

    // Multiply before dividing, so the tenth survives the integer division
    // instead of being the thing it throws away.
    final tenths = (size * 10) ~/ divisor;
    return '${tenths ~/ 10}.${tenths % 10} ${units[unit]}';
  }

  /// Where a purchase order has got to.
  ///
  /// **Keyed by the enum, not by its wire value.** A `String` switch cannot be
  /// exhaustive, so a sixth `PurchaseStatus` would have fallen through and
  /// rendered `partially_received` on a chip. This one fails to compile instead.
  static String purchaseStatus(AppStrings s, PurchaseStatus status) =>
      switch (status) {
        PurchaseStatus.draft => s.statusDraft,
        PurchaseStatus.sent => s.statusSent,
        PurchaseStatus.partiallyReceived => s.statusPartReceived,
        PurchaseStatus.received => s.statusReceived,
        PurchaseStatus.cancelled => s.statusCancelled,
      };

  /// How the restaurant paid somebody. Enum-keyed for the same reason.
  static String paymentMethod(AppStrings s, SupplierPaymentMethod method) =>
      switch (method) {
        SupplierPaymentMethod.cash => s.methodCash,
        SupplierPaymentMethod.bankTransfer => s.methodTransfer,
        SupplierPaymentMethod.cheque => s.methodCheque,
        SupplierPaymentMethod.card => s.methodCard,
        SupplierPaymentMethod.other => s.methodOther,
      };

  /// Basis points as a percentage, for anywhere a rate is shown.
  ///
  /// 1400 is 14%; 1250 is 12.5% and not 12.50%, because a trailing zero on a
  /// rate reads as precision nobody claimed.
  ///
  /// **Integer arithmetic.** The service-charge row did this with
  /// `(rateBp / 100).toStringAsFixed(...)`, which routes a rate through a
  /// `double` — harmless for 1250, and exactly the habit the rest of the money
  /// code exists to avoid.
  static String rateBp(int basisPoints) {
    final whole = basisPoints ~/ 100;
    final fraction = basisPoints % 100;
    if (fraction == 0) return '$whole%';
    final digits = fraction.toString().padLeft(2, '0').replaceAll(
      RegExp(r'0+$'),
      '',
    );
    return '$whole.$digits%';
  }

  /// What a unit is called on screen.
  ///
  /// `QuantityUnit.wire` is a storage token, and `ea` is not a unit anybody
  /// writes on a delivery note — least of all in Arabic, where it means nothing
  /// at all. The symbols that *are* conventional (kg, ml) stay Latin in both
  /// languages, because that is what is printed on the box.
  static String unit(AppStrings s, QuantityUnit unit) => switch (unit.wire) {
    'ea' => s.unitEach,
    'kg' => s.unitKilogram,
    'g' => s.unitGram,
    'l' => s.unitLitre,
    'ml' => s.unitMillilitre,
    'box' => s.unitBox,
    'pack' => s.unitPack,
    // One the restaurant added. Its code is what it wrote on the delivery
    // note; the screens that list units show the names it gave it.
    final code => code,
  };

  static String group(AppStrings s, CapabilityGroup group) => switch (group) {
    CapabilityGroup.selling => s.capGroupSelling,
    CapabilityGroup.money => s.capGroupMoney,
    CapabilityGroup.drawer => s.capGroupDrawer,
    CapabilityGroup.backOffice => s.capGroupBackOffice,
  };

  /// The Users table's status filter. Enum-keyed, as [purchaseStatus] is.
  static String staffStatus(AppStrings s, StaffStatusFilter status) =>
      switch (status) {
        StaffStatusFilter.all => s.staffStatusAll,
        StaffStatusFilter.active => s.staffStatusActive,
        StaffStatusFilter.disabled => s.staffStatusDisabled,
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
        LogoRejected(:final reason) => switch (reason) {
          LogoRefusal.empty => s.logoRefusedEmpty,
          LogoRefusal.tooLarge => s.logoRefusedTooLarge,
          LogoRefusal.unsupported => s.logoRefusedUnsupported,
          LogoRefusal.unreadable => s.logoRefusedUnreadable,
          LogoRefusal.tooSmall => s.logoRefusedTooSmall,
          LogoRefusal.tooBig => s.logoRefusedTooBig,
        },
        RoleNotAllowed(:final reason) => _roleReason(s, reason),
        UserSeatsExhausted(:final maxUsers) => s.refusalUserSeatsExhausted(
          maxUsers,
        ),
        UsernameTaken(:final username) => s.refusalUsernameTaken(username),
        WouldLockEveryoneOut() => s.refusalWouldLockEveryoneOut,
        OwnerAlreadyExists(:final ownerName) => s.refusalOwnerAlreadyExists(
          ownerName,
        ),
        OwnerIsFixed() => s.refusalOwnerIsFixed,
        OwnerIsNotAnExtraRole() => s.refusalOwnerIsNotAnExtraRole,
        OwnerPinIsTheirs() => s.refusalOwnerPinIsTheirs,
        OwnerPasswordIsTheirs() => s.refusalOwnerPasswordIsTheirs,
        PasswordRejected(:final problem) => passwordProblem(s, problem),
        EditedElsewhere() => s.refusalEditedElsewhere,
        // The reason comes from the catalogue importer, which speaks for
        // itself; there is nothing here to translate it into.
        CatalogInvalid(:final reason) => reason,
        CatalogRefused(:final problem) => catalogProblem(s, problem),
        AccountRefused(:final problem) => accountProblem(s, problem),
        ComboRefused(:final problem) => comboProblem(s, problem),
        OpeningCostRefused(:final problem) => switch (problem) {
          OpeningCostProblem.notPositive => s.refusalOpeningCostNotPositive,
          OpeningCostProblem.alreadyCosted =>
            s.refusalOpeningCostAlreadyCosted,
          OpeningCostProblem.itemUnknown => s.refusalOpeningCostItemUnknown,
        },
        OptionGroupRefused(:final problem, :final names) => optionGroupProblem(
          s,
          problem,
          names,
        ),
        AdministratorCredentialRequired() =>
          s.refusalAdministratorCredentialRequired,
        NoDatabaseConfigured() => s.refusalNoDatabaseConfigured,
        ManagedByPlatform(:final what) => s.refusalManagedByPlatform(what),
        PurchaseRefused(:final reason) => _purchaseReason(s, reason),
        StockHeldInAnotherUnit(:final item, :final held, :final asked) =>
          s.refusalStockHeldInAnotherUnit(
            item,
            held.format(),
            unit(s, held.unit),
            unit(s, asked),
          ),
      };

  /// Why an item or a category could not be saved. Keyed by the enum, like
  /// [optionGroupProblem], so a new reason cannot reach the screen unworded.
  static String catalogProblem(AppStrings s, CatalogProblem problem) =>
      switch (problem) {
        CatalogProblem.itemNameMissing => s.refusalItemNameMissing,
        CatalogProblem.offerAbovePrice => s.refusalOfferAbovePrice,
        CatalogProblem.categoryNameMissing => s.refusalCategoryNameMissing,
        CatalogProblem.skuTaken => s.refusalSkuTaken,
        CatalogProblem.categoryUnavailable => s.refusalCategoryUnavailable,
        CatalogProblem.categoryHasItems => s.refusalCategoryHasItems,
      };

  /// Why an account, or the account a payment method pays into, could not be
  /// saved. Keyed by the enum, so a reason added to [AccountProblem] is a
  /// compile error here rather than a blank on an Arabic back office.
  static String accountProblem(AppStrings s, AccountProblem problem) =>
      switch (problem) {
        AccountProblem.nameMissing => s.refusalAccountNameMissing,
        AccountProblem.nameTaken => s.refusalAccountNameTaken,
        AccountProblem.referenceLooksLikeNumber => s.refusalAccountReference,
        AccountProblem.nameLooksLikeNumber => s.refusalAccountNameNumber,
        AccountProblem.branchUnknown => s.refusalAccountBranchUnknown,
        AccountProblem.methodUnknown => s.refusalAccountMethodUnknown,
        AccountProblem.accountUnavailable => s.refusalAccountUnavailable,
        AccountProblem.accountOfAnotherBranch => s.refusalAccountOtherBranch,
        AccountProblem.accountKindMismatch => s.refusalAccountKindMismatch,
        AccountProblem.accountIsDefault => s.refusalAccountIsDefault,
      };

  /// Why a size or extra could not be saved.
  ///
  /// A combo's reason, keyed by the enum so one learned later is a compile
  /// error here rather than a blank on an Arabic back office.
  static String comboProblem(AppStrings s, ComboProblem problem) =>
      switch (problem) {
        ComboProblem.nameMissing => s.refusalComboNameMissing,
        ComboProblem.categoryMissing => s.refusalComboCategoryMissing,
        ComboProblem.priceNegative => s.refusalComboPriceNegative,
        ComboProblem.noGroups => s.refusalComboNoGroups,
        ComboProblem.groupNameMissing => s.refusalComboGroupNameMissing,
        ComboProblem.groupEmpty => s.refusalComboGroupEmpty,
        ComboProblem.selectionRange => s.refusalComboSelectionRange,
        ComboProblem.minAboveOptions => s.refusalComboMinAboveOptions,
        ComboProblem.duplicateOption => s.refusalComboDuplicateOption,
        ComboProblem.deltaNegative => s.refusalComboDeltaNegative,
        ComboProblem.categoryUnknown => s.refusalComboCategoryUnknown,
        ComboProblem.taxGroupUnknown => s.refusalComboTaxGroupUnknown,
        ComboProblem.productUnknown => s.refusalComboProductUnknown,
        ComboProblem.skuTaken => s.refusalComboSkuTaken,
      };

  /// Keyed by the enum, so a reason the repository learns is a compile error
  /// here rather than an English sentence on an Arabic back office — which is
  /// exactly what these were while they travelled inside `CatalogInvalid`.
  /// [names] is empty for every reason that names nothing; the ones that do
  /// always receive at least one, and read an empty name rather than throwing
  /// if a newer writer ever sends none.
  static String optionGroupProblem(
    AppStrings s,
    OptionGroupProblem problem,
    List<String> names,
  ) {
    final name = names.isEmpty ? '' : names.first;
    return switch (problem) {
      OptionGroupProblem.nameMissing => s.refusalGroupNameMissing,
      OptionGroupProblem.scopeNeedsLibrary => s.refusalGroupScopeNeedsLibrary,
      OptionGroupProblem.categoriesMissing => s.refusalGroupCategoriesMissing,
      OptionGroupProblem.choicesOutOfRange => s.refusalGroupChoicesOutOfRange(
        OptionGroupRules.maxChoices,
      ),
      OptionGroupProblem.negativeCounts => s.refusalGroupNegativeCounts,
      OptionGroupProblem.needsMoreThanAllows =>
        s.refusalGroupNeedsMoreThanAllows,
      OptionGroupProblem.tooManyOptions => s.refusalGroupTooManyOptions(
        OptionGroupRules.maxOptions,
      ),
      OptionGroupProblem.requiredButEmpty => s.refusalGroupRequiredButEmpty,
      OptionGroupProblem.optionNameMissing => s.refusalOptionNameMissing,
      OptionGroupProblem.optionTwice => s.refusalOptionTwice,
      OptionGroupProblem.negativePrice => s.refusalOptionNegativePrice,
      OptionGroupProblem.saleNotBelowPrice => s.refusalOptionSaleNotBelowPrice,
      OptionGroupProblem.groupTwice => s.refusalGroupTwice,
      OptionGroupProblem.typedOnAnotherItem => s.refusalGroupTypedOnAnotherItem,
      OptionGroupProblem.notInLibrary => s.refusalGroupNotInLibrary(name),
      OptionGroupProblem.alreadyReaches => s.refusalGroupAlreadyReaches(name),
      OptionGroupProblem.secondSizes => s.refusalGroupSecondSizes(
        names.length,
        _list(s, names),
      ),
      OptionGroupProblem.wouldGiveSecondSizes =>
        s.refusalGroupWouldGiveSecondSizes(name),
      OptionGroupProblem.belongsToOneItem => s.refusalGroupBelongsToOneItem,
      OptionGroupProblem.belongsToLibrary => s.refusalGroupBelongsToLibrary,
      OptionGroupProblem.foreignOption => s.refusalGroupForeignOption,
      OptionGroupProblem.foreignCategory => s.refusalGroupForeignCategory,
    };
  }

  /// Keyed by the refusal and then by the status it names — both sealed or
  /// enums — so a sixth status is a compile error here rather than a blank
  /// line on the Purchasing pane.
  static String _purchaseReason(AppStrings s, PurchaseRefusal reason) =>
      switch (reason) {
        OrderNotEditable(:final status) => switch (status) {
          PurchaseStatus.sent => s.refusalPurchaseAlreadySent,
          PurchaseStatus.partiallyReceived ||
          PurchaseStatus.received => s.refusalPurchaseGoodsArrived,
          PurchaseStatus.cancelled => s.refusalPurchaseCancelled,
          // A draft is editable by definition; only a stale screen gets here.
          PurchaseStatus.draft => s.refusalEditedElsewhere,
        },
        OrderHasNoLines() => s.refusalPurchaseHasNoLines,
        LineQuantityNotPositive() => s.refusalPurchaseQuantityNotPositive,
        OrderAlreadyClosed(:final status) => switch (status) {
          PurchaseStatus.partiallyReceived =>
            s.refusalPurchaseCannotCancelArrived,
          PurchaseStatus.received => s.refusalPurchaseAllArrived,
          PurchaseStatus.cancelled => s.refusalPurchaseCancelled,
          PurchaseStatus.draft ||
          PurchaseStatus.sent => s.refusalEditedElsewhere,
        },
        StatusFollowsTheGoods() => s.refusalPurchaseFollowsTheGoods,
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
