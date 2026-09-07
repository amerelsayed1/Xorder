import 'package:flutter/widgets.dart';

/// Every operator-facing string in the till, in both languages the product
/// supports.
///
/// **Hand-written rather than generated, and sealed rather than a map.** The
/// architecture note (`docs/pos/04-flutter-pos-architecture.md` §Localisation)
/// is explicit about why: with an abstract member per string and exactly two
/// implementations, a translation that was never written is a *compile error*.
/// An ARB file plus `gen-l10n` would instead fall back to English at runtime —
/// which on a till means the cashier who chose العربية discovers the gap
/// mid-service, in front of a customer, and nobody who could fix it is there.
///
/// Two rules keep this file honest:
///
/// * **No string is assembled from fragments at the call site.** Word order
///   differs between the two languages, so anything with a variable in it is a
///   method here, never `'${strings.x} $n ${strings.y}'` in a widget.
/// * **Numbers stay Western in both languages.** Money, quantities and
///   references are read aloud across a counter and typed back into a keypad;
///   Arabic-Indic digits are *accepted* on input (see
///   `core/utils/arabic_digits.dart`) but the till renders one digit shape, so
///   two people looking at the same screen see the same characters.
/// Wraps operator data — a restaurant name, a plan, a branch — in Unicode
/// isolates (FSI…PDI) so the bidi algorithm reorders *inside* it and never
/// around it.
///
/// Without this, an Arabic restaurant name in an English line drags the
/// separators and the count to the wrong side of the sentence: the licence
/// summary for «العاصمه» on a two-terminal plan renders as
/// "2 · العاصمه terminals" instead of "العاصمه · 2 terminals". The mirror
/// image happens to a Latin name inside an Arabic line. The isolate costs
/// nothing when both runs already point the same way.
String _bidi(String text) => '\u2068$text\u2069';

sealed class AppStrings {
  const AppStrings();

  /// The strings for [locale], falling back to English for anything the app
  /// does not translate. Used by the delegate and by tests.
  static AppStrings of(Locale locale) =>
      locale.languageCode == 'ar' ? const ArStrings() : const EnStrings();

  /// Language subtag, for the catalogue's `displayName(locale)` selection.
  String get languageCode;

  /// Which way this language runs. Drives [Directionality] through
  /// `MaterialApp.locale`, and is exposed here for the few places that need to
  /// pick a side without a `BuildContext`.
  TextDirection get direction;

  /// The language's own name, shown in the picker in that language.
  String get languageName;

  // ── Shared vocabulary ─────────────────────────────────────────────────────
  String get cancel;
  String get done;
  String get back;
  String get backArrow;
  String get continueLabel;
  String get importLabel;
  String get activate;
  String get none;

  /// Order types. Which of these are *offered* comes from the branch
  /// (POS-BE-005) — this only names the ones that are.
  String get orderTypeDineIn;
  String get orderTypeTakeaway;
  String get orderTypeDelivery;
  String get orderTypeDriveThru;

  // ── Selling screen ────────────────────────────────────────────────────────
  String outOfStock(String product);
  String get nothingToCharge;
  String get ticketVoided;
  String get ticketStillOpen;
  String get roundSentToKitchen;
  String get drawerOpenedToast;
  String get openTicketsNotBuilt;
  String get customAmountNotBuilt;
  String get searchHint;
  String get customAmount;
  String get shortcutStrip;
  String matchCount(int count);
  String catalogCached(int items);
  String get noItemsMatch;
  String get outOfStockBadge;

  // ── Top bar ───────────────────────────────────────────────────────────────
  String get openDrawer;

  /// Shown while a manual sync pass runs — the pill is the control on a
  /// cloud till, so the confirmation has to say what it started.
  String get syncingWithPlatform;

  /// The sync pill's four states. The leading dot is part of the caption
  /// rather than a prefix the widget glues on: the pill is one run of text,
  /// and an RTL line has to be able to put the dot on ITS start side.
  ///
  /// The counts are parameters because the words wrap around them differently
  /// — "3 queued" against "3 في الانتظار" — and because a till whose backlog
  /// is not yet known must say so rather than show a zero it has not proved.
  String get syncStatusUnavailable;
  String syncOfflineQueued(int? queued);
  String get syncChecking;
  String syncSyncedQueued(int queued);
  String get lock;
  String get closeShift;
  String get noShift;

  // ── Category rail ─────────────────────────────────────────────────────────
  String get categories;
  String get allItems;
  String get openTickets;
  String get tables;

  // ── Cart ──────────────────────────────────────────────────────────────────
  String get noTableYet;
  String seatedTable(String table, int? guests);
  String walkIn(String orderType);

  /// `OPEN · RANA A. · LIVE` — one string because the separators and the order
  /// are part of it.
  String cartStatusLine(String cashier, bool online);
  String get changeTable;
  String get cartEmptyHelp;
  String alreadySent(int lines);
  String get newRound;
  String get subtotal;
  String servicePercent(String percent);
  String vatPercent(String percent);
  String get totalCaps;
  String get closeTableCta;
  String get chargeCta;
  String get sendRoundKey;
  String get parkKey;
  String get voidTicket;

  // ── Modifier sheet ────────────────────────────────────────────────────────
  String modifierGroupFull(String group, int max);
  String pickGroupFirst(String group);
  String requiredPick(int count);
  String maxPick(int count);
  String get addToTicket;

  // ── Payment ───────────────────────────────────────────────────────────────
  String get tenderCash;
  String get tenderCard;
  String get tenderWallet;
  String get tenderOnAccount;
  String get payment;
  String get backToTicket;
  String lineCount(int lines);
  String get amountDue;
  String get remainingDue;
  String totalIs(String amount);
  String paidOfTotal(String paid, String total, int tenders);
  String get tendersHeading;
  String get noTenderYet;
  String get amount;
  String get exact;
  String get clear;
  String get takePayment;
  String get enterAmountAboveZero;

  // ── Receipt ───────────────────────────────────────────────────────────────
  String get taxRegistrationLine;
  String get provisionalInvoice;
  String get receiptSubtotal;
  String receiptService(String percent);
  String receiptVat(String percent);
  String get receiptTotal;
  String get receiptPaid;
  String get receiptChange;
  String get receiptQueuedOffline;
  String get receiptSynced;
  String get receiptThanks;
  String get receiptTaxFromDevice;
  String get newSale;
  String get printAndNew;
  String get receiptQueuedToast;

  // ── Floor ─────────────────────────────────────────────────────────────────
  String get pickATable;
  String get pickATableHelp;

  /// Shown on the floor when the branch has no tables at all. The cashier
  /// cannot add one — that is a manager's job in Management -> Floor — so the
  /// line says where they are made, and the screen still offers a way to sell.
  String get floorHasNoTables;

  /// Escape hatch off the floor: a walk-in does not occupy a table, and a
  /// branch that sells takeaway must not force one to be seated first.
  String get sellWithoutTable;
  String legendFree(int count);
  String legendOccupied(int count);
  String legendBillAsked(int count);
  String get tableFree;
  String tableLineCount(int lines);
  String get tableBillAsked;
  String tableSeats(int seats);
  String tableOpenWith(String total);
  String tableBillRequested(String total);

  // ── Lock ──────────────────────────────────────────────────────────────────
  String get terminalLocked;
  String get wrongPin;
  String enterPinFor(String name);

  // ── Start ─────────────────────────────────────────────────────────────────
  String get pointOfSale;
  String get renewLicence;
  String get manageLicence;
  String get licenceRequired;
  String get startShift;
  String resumeShift(String reference);
  String get cashUpStillAvailable;
  String get startShiftHelp;
  String resumeShiftHelp(String openedBy);
  String get enterKeyCap;
  String get tenantCell;
  String get branchCell;
  String get terminalCell;
  String get catalogCell;
  String get catalogSyncing;
  String catalogCachedItems(int items);

  // ── Opening and closing a shift ───────────────────────────────────────────
  String get signIn;
  String get openTheDrawer;
  String get signInHelp;
  String countTheDrawerHelp(String name);
  String get pinNotRecognised;

  /// Said by name rather than as a bare refusal: "Rana cannot open a shift"
  /// tells somebody what to do next, where "not permitted" sends them to
  /// retype a PIN that was already right.
  String notPermittedToOpenShift(String name);
  String get enterOpeningFloat;
  String get openShift;
  String get openingFloat;
  String get emptyDrawer;
  String get openingFloatHelp;
  String closeShiftTitle(String reference);
  String closeShiftHelp(String openedBy);

  /// What the supervisor is being asked to approve, in the cashier's words.
  /// Shown only — the audit row keeps its own stable English wording, so a
  /// record written on an Arabic till still reads the same to whoever
  /// reviews it later.
  String closeShiftApproval(String reference);
  String get countTheDrawer;
  String get signInBeforeClosing;
  String get countedInDrawer;
  String expectedInDrawerHelp(String expected, String float, String taken);
  String get varianceBalances;
  String get varianceOver;
  String get varianceShort;
  String shiftClosedTitle(String reference);
  String get drawerBalances;
  String closedWithVariance(String variance);
  String get zSales;
  String get zGrossTaken;
  String zTenderRow(String label, int count);
  String get zOpeningFloat;
  String get zExpectedInDrawer;
  String get zCounted;

  // ── Licence ───────────────────────────────────────────────────────────────
  String get licence;
  String get renewThisTerminal;
  String get licenceKeyHint;
  String get activateKey;
  String get importLicenceFile;
  String get checkForRenewal;

  /// Distinct from [noLicenceServer], which answers "this key cannot be
  /// checked". This one answers "a renewal cannot be looked for at all" —
  /// same cause, different question, and the operator's next move differs.
  String get cannotCheckForRenewal;
  String get renewalOnlineHelp;
  String get renewalOfflineHelp;
  String get licenceUpdated;
  String get noRouteToPlatform;
  String get licenceFileHint;
  String get capabilityOpenShift;
  String get capabilitySell;
  String get capabilityCashUp;
  String get capabilityReprint;
  String get capabilityExport;
  String get capabilityConfigure;
  String daysRemaining(int days);
  String daysPastExpiry(int days);
  String get licensedHeadline;
  String get renewalDueHeadline;
  String get expiredInGraceHeadline;
  String get expiredHeadline;
  String get notLicensedHeadline;
  String get licenceProblemHeadline;

  /// The verifier's findings. The domain decides *what* is wrong and hands back
  /// a `LicenceNotice`; only these methods put it into words, so the licence
  /// logic stays free of a locale — see `docs/pos/02-pos-requirements.md`
  /// POS-R078 for why that separation is worth keeping.
  String licenceExpiresInDays(int days);
  String licenceGraceRemaining(int days);
  String get licenceExpiredNewShiftBlocked;
  String licenceTenantMismatch(String licenceTenant, String terminalTenant);
  String licenceModeNotCovered(String mode);
  String get licenceOtherTerminal;
  String licenceNotYetValid(String date);
  String get licenceFileDamaged;
  String get noLicenceInstalled;
  String get licenceUnverifiable;
  String get noLicenceServer;
  String get notALicenceFile;
  String get licenceKeyNotRecognised;

  /// The same refusal, from a platform we can name.
  ///
  /// Which matters more than it sounds: a key is minted by one platform and
  /// checked against whichever one this build was compiled to ask. When those
  /// differ the key is fine and the address is wrong, and a message that says
  /// only "not recognised" sends an installer hunting for a typo.
  String licenceKeyNotRecognisedBy(String address);

  /// Could not reach the platform at all. Nothing was learned about the key.
  String licenceServerUnreachable(String address);

  /// Reached it, and it answered with something that was not a licence.
  String licenceServerRefused(String address, int status);

  /// Throttled after several attempts in a minute.
  String get tooManyLicenceAttempts;

  /// The platform knows this licence and has withdrawn it.
  String get licenceRevokedByPlatform;

  // ── Setup wizard chrome ───────────────────────────────────────────────────
  String get productWordmark;
  String get terminalSetup;
  String get terminalNotSetUp;
  String get switchToLight;
  String get switchToDark;
  String stepOf(int step, int total);
  String get openTheTill;

  String get stepSetupType;
  String get stepSetupTypeBlurb;
  String get setupTypeOfflineHelp;
  String get setupTypeCloudHelp;
  String get stepLanguage;
  String get stepLanguageBlurb;
  String get stepConnection;
  String get stepConnectionBlurb;
  String get stepAccount;
  String get stepAccountBlurb;

  /// The same step on an offline till, where it is a different question.
  /// There is no platform to sign in to and no account to sign in with — this
  /// is the screen that creates the first one.
  String get stepFirstAdministrator;
  String get stepFirstAdministratorBlurb;
  String get stepLicence;
  String get stepLicenceBlurb;
  String get stepBranch;
  String get stepBranchBlurb;
  String get stepTerminal;
  String get stepTerminalBlurb;
  String get stepHardware;
  String get stepHardwareBlurb;
  String get stepMoney;
  String get stepMoneyBlurb;
  String get stepCatalogue;
  String get stepCatalogueBlurb;
  String get stepReady;
  String get stepReadyBlurb;

  // ── Setup: language ───────────────────────────────────────────────────────
  String get englishBlurb;
  String get arabicBlurb;
  String get languagePaneHelp;

  // ── Setup: connection ─────────────────────────────────────────────────────
  String get modeCloud;
  String get modeCloudBlurb;
  String get modeOffline;
  String get modeOfflineBlurb;
  String get modeNotLicensed;

  /// The badge on a mode tile the licence does not cover. Short, because it
  /// sits inside the tile — the sentence is [modeNotLicensed].
  String get notLicensedBadge;
  String get syncAutomatic;
  String get syncAutomaticBlurb;
  String get syncManual;
  String get syncManualBlurb;
  String get platformAddress;
  String get platformCaps;
  String get platformAddressHelp;
  String get trustWithoutCertificate;
  String get trustWithoutCertificateBlurb;
  String get theDatabase;
  String get databaseHost;
  String get databaseHostHelp;
  String get databaseName;
  String get databasePort;
  String get databaseUser;
  String get databaseUserHelp;
  String get databasePassword;
  String get databasePasswordHelp;

  /// Shown when the OS keystore refused at boot, rather than simply holding
  /// nothing. The distinction matters: a password typed on a machine whose
  /// keystore is unreachable is accepted, appears to work, and is gone by
  /// tomorrow — so the operator has to be told while they are still here.
  String get keystoreUnavailable;
  String get keystoreUnavailableHelp;

  // First install: the wizard step that creates the database itself.
  String get machineNowHasDatabase;
  String get noDatabaseYet;
  String get firstInstallHeading;
  String get firstInstallHelp;
  String adminPasswordFor(String user);
  String get adminPasswordHelp;
  String get firstPerson;
  String get firstPersonHelp;
  String get theirUsername;
  String get theirPin;
  String get theirPinHelp;
  String get buildingDatabase;
  String get buildTheDatabase;

  // ── Setup: first install, step by step ────────────────────────────────────
  //
  // The bootstrap report is read by whoever is standing at a half-built till,
  // so each line says what happened rather than what was attempted.
  String get installLicenceFirst;
  String get firstPersonIncomplete;

  /// The PIN is present but the till could not accept it. Separate from
  /// [firstPersonIncomplete] because "fill everything in" is the wrong
  /// instruction for somebody who did.
  /// Both of these say the same rule in two places: one inside a form that
  /// has room for a sentence, one under a bare field that does not.
  String pinIsExactlyDigits(int length);
  String exactlyDigits(int length);

  /// The database name cannot be quoted into `CREATE DATABASE`. Named here
  /// rather than thrown, so the operator reads a sentence instead of an
  /// ArgumentError about bind parameters.
  String databaseNameInvalid(String name);

  /// Signed in, and refused the work. The remedy is a GRANT, not a password,
  /// so the words must not send anybody back to the password field.
  String permissionDenied(String user, String database);
  String createdDatabase(String database);
  String databaseAlreadyThere(String database);
  String get schemaAlreadyCurrent;
  String migrationsApplied(int count);
  String restaurantSeeded(String restaurant);
  String get rolesAlreadyThere;
  String rolesCreated(int count);
  String ownerCreated(String name);
  String ownerAlreadyHere(String username);
  String grantsApplied(String tillRole, String adminRole);
  String bootstrapAuthFailed(String user);
  String bootstrapUnreachable(String host, int port);
  String bootstrapRefused(Object raw);
  String setupIncomplete(String missing);
  String get missingTerminalName;
  String get missingRestaurantIdentity;
  String get missingBranch;
  String get missingBranchPrefix;
  String get missingTerminalId;
  String couldNotSaveSetup(Object error);
  String get platformAddressRequired;
  String couldNotReach(String address);
  String get noPlatformAddressInForce;
  String get terminalNotRegisteredYet;

  // ── Provisioning refusals ─────────────────────────────────────────────────
  //
  // Keyed off the machine-readable `code` the repositories return, not off
  // their English `message`. The code is the contract (POS-BE-019); the prose
  // is this layer's business, which is what lets an Arabic till say why setup
  // stopped instead of falling back to the server's English.
  String get refusalPairingCodeInvalid;
  String get refusalPairingCodeSpent;
  String get refusalCredentialsRejected;
  String get refusalNoBranches;
  String get refusalBranchUnknown;
  String refusalTenantUnknown(String tenant);
  String refusalWrongPlatform(String platform);
  String refusalPlatformUnreachable(String platform);
  String get refusalClaimUnreadable;
  String get refusalNoPlatformConfigured;
  String get refusalNoDatabaseReachable;
  String get refusalAdoptUnsupported;
  String get refusalValidationFailed;
  String menuDownloadRefused(String address, String answer);
  String get menuDownloadSilence;
  String menuDownloadHttp(int? status);
  String menuShapeNotUnderstood(String address);
  String get testConnection;

  /// Shown when the licence covers one terminal, so the database can only be
  /// this machine and there is no address to type.
  String get singleMachineHelp;

  /// Shown when the licence covers several terminals, so one of them holds the
  /// database the others share.
  String sharedDatabaseHelp(int terminals);
  String get sendingSales;
  String get sendingSalesHelp;

  /// Connection failures. Each names which of the four things went wrong,
  /// because an installer sent to fix the firewall when the password is wrong
  /// will not fix it.
  String unreachable(String address);
  String dnsFailure();
  String tcpFailure(int port);
  String authFailure(String user);
  String tlsFailure();
  String queryFailure(String database);

  /// The connection test WORKED. Said out loud, because its good outcome used
  /// to be the absence of red — indistinguishable from a button doing nothing.
  String connectionOk(String database);

  /// Reached Postgres, and there is no database by that name yet — the
  /// first-install case. Names the remedy, which is on the same screen: the
  /// old wording ("the database did not answer as expected") sent installers
  /// checking a name that was right all along.
  String missingDatabase(String database);

  // ── Setup: licence ────────────────────────────────────────────────────────
  String get licenceKey;

  /// The platform a typed key is sent to. Shown on the licence step because
  /// its absence made the commonest failure unreadable — a key issued by one
  /// platform and checked against another is refused correctly, and "not
  /// recognised" sends the installer hunting for a typo that is not there.
  String get licenceServer;
  String get licenceServerHelp;
  String get activateOnline;
  String get activateFromFile;
  String get licenceOnlineHelp;
  String get licenceOfflineHelp;
  String get pasteLicenceFile;

  /// What the licence bought, on one line under the activation panel.
  ///
  /// The tenant name is operator data in whichever script the restaurant
  /// registered under, so it is isolated inside the sentence — see [_bidi].
  String licenceCoverage(String tenant, String? plan, int terminals);
  String get cashUpNeverGated;

  // ── Setup: account ────────────────────────────────────────────────────────
  String get restaurant;
  String get restaurantHelp;
  String get restaurantFromLicenceHelp;
  String get methodPairingCode;
  String get methodPairingCodeBlurb;
  String get methodManual;
  String get methodManualBlurb;
  String claimedAs(String terminal, String branch);
  String get claimedHelp;
  String get claimedFromDashboardHelp;
  String get setupCode;
  String get setupCodeHelp;
  String get claimThisTerminal;
  String get username;
  String get password;
  String get manualCredentialsWarning;
  String connectedTo(String tenant);
  String branchesRetrieved(int branches);
  String get connectAndPullConfiguration;

  // ── Setup: branch, terminal, hardware ─────────────────────────────────────
  String get noOrderTypesConfigured;
  String get branchPaneHelp;
  String get terminalName;
  String get terminalNameProvisionedHelp;
  String get terminalNameManualHelp;
  String get registered;
  String get registerThisTerminal;
  String get registerHelp;
  String get whichTillIsThis;
  String get tillAwaitingDevice;
  String get aNewTill;
  String get aNewTillBlurb;
  String get terminalNameHint;
  String get alreadySetUp;
  String get useThisTill;
  String get adoptTerminalHelp;
  String get registerCloudHelp;
  String get terminalId;
  String get terminalIdHelp;
  String get findPrinters;
  String get lookingForPrinters;
  String get testPrint;
  String get testReceiptSent;
  String get nothingPrinted;
  String get cashDrawerAttached;
  String get cashDrawerAttachedBlurb;
  String get scannerAttached;
  String get scannerAttachedBlurb;
  String get hardwareHelp;

  // ── Setup: money, catalogue, summary ──────────────────────────────────────
  String get currency;
  String currencyValue(String code, int decimals);
  String get serviceCharge;
  String get serviceChargeValue;
  String get vat;
  String get vatValue;
  String get rounding;
  String get roundingValue;

  // ── Management: money rules, authored on an offline till ──────────────────
  String get moneyRules;
  String get moneyRulesHint;
  String get moneyComesFromPlatform;
  String get serviceDineInOnly;
  String get ratesFromThisTerminal;
  String get ratesNotSetYet;
  String get saveRates;
  String get ratesSaved;

  // ── Management: the floor ─────────────────────────────────────────────────
  String get floorPlan;
  String get floorPlanHint;
  String get floorComesFromPlatform;
  String get addTable;
  String get tableLabel;
  String get tableSeatsLabel;
  String get tableArea;
  String get takeOutOfService;
  String get putBackInService;
  String get noTablesYet;
  String tableSummary(int tables);
  String get fromDeviceConfiguration;
  String get deviceTaxHelp;
  String get downloadMenu;
  String get downloadAgain;
  String itemsCached(int items);

  /// Shown when the download succeeded but returned nothing. A menu is on the
  /// critical path of taking money in a way a printer is not, so an empty one
  /// is reported as a problem rather than as a successful download of zero.
  String get menuEmpty;
  String get menuEmptyHelp;
  String get cataloguePaneHelp;

  /// Offline: the same step reads the till's OWN database, so "download" and
  /// "refreshes in the background" are both untrue there.
  String get readMenu;
  String get readMenuAgain;
  String get cataloguePaneHelpOffline;

  /// The same empty menu, on a till that syncs nothing. Neither "the download
  /// worked" nor "it refreshes in the background" is true there — the menu
  /// arrives when somebody types it into Management, and never otherwise.
  String get menuEmptyHelpOffline;

  /// Said when adopting a licence moved the terminal off the mode the operator
  /// picked, onto one the licence actually covers.
  String licenceModeChanged(Object chosen, Object landed);
  String catalogueDownloadFailed(Object error);
  String get summaryLanguage;
  String get summaryConnection;
  String get summaryServer;
  String get summaryThisMachine;
  String get summaryUpstream;
  String get summaryRestaurant;
  String get summaryBranch;
  String get summaryTerminal;
  String get summaryPrinter;
  String get summaryNoPrinter;
  String get summaryCashDrawer;
  String get summaryScanner;
  String get summaryAttached;
  String get summaryMenu;
  String summaryItemsCached(int items);
  String get summaryLicence;
  String get summaryHelp;
  String get notSet;

  // ── Terminal reset ────────────────────────────────────────────────────────
  String get resetTerminal;
  String get resetTerminalTitle;
  String get resetTerminalBody;
  String get resetTerminalShiftOpen;
  String get resetTerminalShiftUnknown;
  String get resetTerminalConfirm;

  // ── Terminal no longer recognised ─────────────────────────────────────────
  String get terminalRejectedTitle;
  String get terminalRejectedBody;
  String get terminalRejectedQueued;

  // ── Forced re-setup (Cmd+Shift+S) ─────────────────────────────────────────
  String get forceResetTitle;
  String get forceResetBody;
  String get forceResetShiftOpen;
  String get forceResetQueued;
  String get forceResetConfirm;

  // ── Settings menu bar ─────────────────────────────────────────────────────
  String get settings;
  String get syncNow;
  String get management;

  /// The macOS Window menu. The app's own name above it is a brand and is
  /// never translated; this one is an ordinary word.
  String get windowMenu;

  // ── Management ────────────────────────────────────────────────────────────
  //
  // What a permission MEANS, in the words a manager ticking the box needs. The
  // capability name is never shown on its own: `price.override` tells a
  // restaurant owner nothing, and a permission screen nobody understands is a
  // permission screen everybody ticks.
  String get capOperate;
  String get capCatalogView;
  String get capCatalogManage;
  String get capStaffManage;
  String get capTerminalManage;
  String get capSettingsManage;
  String get capDiscountApply;
  String get capPriceOverride;
  String get capOrderVoid;
  String get capOrderItemCancel;
  String get capOrderItemVoid;
  String get capOrderViewAll;
  String get capOrderRefund;
  String get capReceiptReprint;
  String get capShiftOpen;
  String get capShiftClose;
  String get capCashMovement;
  String get capReportsView;
  String get capBackupManage;

  String get capGroupSelling;
  String get capGroupMoney;
  String get capGroupDrawer;
  String get capGroupBackOffice;

  /// Joins a list of names — "Rana and Nour", "رنا ونور". The separator is part
  /// of the language, not of the loop that builds the list.
  String get listAnd;
  String get listSeparator;

  // Why a write did not happen, in a sentence that says what to do next.
  String refusalNotPermitted(String capability);
  String refusalRoleStillHeld(String names);
  String get refusalRoleIsSystemDefined;

  /// Names the number, because "upgrade your licence" without one sends a
  /// manager to the phone with no idea what to ask for.
  String refusalUserSeatsExhausted(int maxUsers);
  String refusalUsernameTaken(String username);
  String get refusalWouldLockEveryoneOut;
  String get refusalEditedElsewhere;
  String get refusalAdministratorCredentialRequired;
  String get refusalNoDatabaseConfigured;
  String get refusalOwnerMustKeepEverything;
  String refusalCashiersAreNotAdministrators(String capabilities);

  // Management chrome.
  String get backToTill;
  String get paneStaff;
  String get paneStaffBlurb;
  String get paneMenu;
  String get paneMenuBlurb;
  String get paneRoles;
  String get paneRolesBlurb;
  String get paneActivity;
  String get paneActivityBlurb;
  String get pinCannotOpenManagement;
  String get managementPinHelp;
  String get managementPinRetryHelp;
  String cannotManageStaff(String name);
  String get backOfficePassword;
  String backOfficePasswordHelp(String name);
  String backOfficeAuthFailed(String user);
  String get backOfficeUnreachable;
  String get backOfficeRefused;
  String get checking;
  String get openManagement;

  // Staff pane.
  String get addSomebody;
  String staffCount(int active, int total);

  /// The same line on a till whose licence caps user accounts. States the cap
  /// where the count already is, so a manager sees the ceiling coming instead
  /// of meeting it as a refusal halfway through hiring somebody.
  String staffCountLicensed(int active, int total, int licensed);
  String get notSaved;
  String get close;
  String get you;
  String extraCapabilities(int count);
  String get resetPin;
  String newPinFor(String name);
  String get disable;
  String get enable;
  String get noRole;
  String get fieldName;
  String get fieldUsername;
  String get fieldPin;
  String get fieldRole;
  String get add;
  String get setPin;
  String get nameAndUsernameRequired;

  // Roles pane.
  String get noRolesYet;
  String permissionCount(int held, int total);
  String get createdByInstaller;
  String get discard;
  String get save;

  // Activity pane.
  String get nothingRecordedYet;

  /// Both names when a permission was lent. Which is which is the whole
  /// reason the approver is stored separately from the actor.
  String approvedByLine(String actor, String approver);

  // Supervisor override.
  String get supervisorApproval;
  String supervisorApprovalHelp(String action);
  String get pinCannotApprove;
  String get notPermittedTitle;
  String notPermittedBody(String capability);

  // ── Management: the menu pane ─────────────────────────────────────────────
  String get menuComesFromPlatform;
  String menuSummary(int categories, int items);
  String get noCategoriesYet;
  String get nothingInCategoryYet;
  String get addCategory;
  String get addItem;
  String get rename;
  String get takeOffTheRail;
  String get edit;
  String get offSale;
  String get backOnSale;
  String get newCategory;
  String get renameCategory;
  String get newItem;
  String get editItem;
  String get fieldNameArabic;
  String get fieldPrice;
  String get fieldSku;

  /// A field label with "optional" appended. One string rather than a label
  /// plus a suffix at the call site: the separator and the side the word falls
  /// on are both part of it, and neither survives being assembled in a widget.
  String optionalField(String label);
  String get fieldOfferPrice;
  String get rateIsNotANumber;
  String get priceIsNotANumber;
  String get offerPriceIsNotANumber;

  // ── Reasons ───────────────────────────────────────────────────────────────
  // The chrome around the reason picker. The reasons THEMSELVES are rows in
  // `pos_reason_codes` and are named by the restaurant in both languages —
  // translating them here would mean a restaurant's own wording could not
  // survive a language switch.
  String get reasonRequiredBadge;
  String get reasonOptionalBadge;
  String get reasonNote;
  String get reasonNoteHint;
  String get reasonRequiredHelp;
  String get reasonOptionalHelp;
  String get reasonNeedsNoteHelp;
  String get chooseAReason;

  // ── Irreversible acts ─────────────────────────────────────────────────────
  String get cannotBeUndone;
  String get amountMicroLabel;

  /// The keyboard contract, stated under the buttons. A person who has just
  /// been told an act cannot be undone should not have to discover by pressing
  /// something which key does what.
  String get destructiveKeyHint;

  // ── Manager approval ──────────────────────────────────────────────────────
  String get approvalRequired;
  String get approvalAction;
  String get approvalRequestedBy;
  String get approvalPin;
  String get approvalAboveLimit;
  String get approvalDone;

  /// How many tries are left before the keypad stops accepting. Pluralised,
  /// because "1 attempts left" is the kind of detail that makes a person
  /// distrust everything else on the screen.
  String wrongPinAttemptsLeft(int attempts);

  /// Names **both** people. An approval that records only the manager cannot
  /// answer "who asked for this", which is the question a month-end review
  /// actually asks.
  String approvalRecorded(String approver, String requester);

  // ── Discounts ─────────────────────────────────────────────────────────────
  String get discountTitle;
  String get discountWholeOrder;
  String get discountThisLine;
  String get discountPresets;
  String get discountCustom;
  String get discountPercent;
  String get discountAmount;
  String get discountNoneOffered;
  String get discountRemove;
  String get discountApplyAction;
  String get discountNewTotal;
  String get discountNotApplicable;
  String get discountNeedsCustomer;
  String get discountAlreadyOn;
  String get discountNothingToDiscount;

  /// The manager-approval sentence, with both figures. A supervisor told only
  /// "above the limit" has to ask two questions before deciding.
  String discountAboveLimitNote(String limit, String requested);

  /// What the supervisor is being asked to approve, in words.
  String discountApprovalAct(String amount);

  /// Short enough for a cart line: "approved by Hana M.".
  String approvedByShort(String approver);

  // ── Cancelling and voiding a line ─────────────────────────────────────────
  String get cancelLineAction;
  String get voidLineAction;
  String get keepLineAction;
  String get lineVoidedChip;
  String get cancelLineNothingMade;

  /// The question, naming the item. Two different questions on purpose: one is
  /// routine, the other is waste.
  String cancelLineTitle(String item);
  String voidLineTitle(String item);

  /// What voiding a cooked line actually does, in the order the handoff sets:
  /// what happens · what it does to work already done · what cannot be undone.
  String voidLineConsequenceRemoved(String amount);
  String get voidLineConsequenceKitchen;
  String get voidLineConsequenceIrreversible;

  // ── Voiding a whole order ─────────────────────────────────────────────────
  String get voidOrderAction;
  String get keepOrderAction;
  String get clearTicketTitle;
  String get clearTicketNothingSent;
  String voidOrderTitle(String reference);
  String voidOrderConsequenceBill(String amount);
  String get voidOrderConsequenceKitchen;
  String get voidOrderConsequenceRecorded;

  /// Shown after the void, naming what it was recorded as. A cashier who is
  /// told "done" and nothing else has no way to find it again.
  String voidOrderRecorded(String invoice);

  /// The write failed and the ticket is deliberately still on screen.
  String get voidCouldNotBeRecorded;

  // ── Order history ─────────────────────────────────────────────────────────
  String get orderHistoryTitle;

  /// Says what slice is on screen. A list that shows "today" without saying so
  /// looks like a list of everything, and somebody hunting last week's receipt
  /// concludes it is gone.
  String get orderHistoryToday;
  String get orderHistoryLast7Days;
  String get orderHistoryLast30Days;
  String get orderHistorySearchHint;
  String get orderHistoryAllStatuses;
  String get orderHistoryAllTypes;
  String get orderHistoryEveryone;
  String orderHistoryCount(int count);

  /// The cap was hit, so what is on screen is not all there is. Saying so is
  /// the difference between a short list and a wrong one.
  String orderHistoryTruncated(int limit);
  String get orderHistoryEmpty;
  String get orderHistoryEmptyFiltered;
  String get orderHistoryClearFilters;
  String get orderHistoryPickAnOrder;
  String get orderHistoryUnavailable;

  /// The person at the till may not browse the branch's orders.
  String get orderHistoryNotPermitted;

  // Column headings.
  String get orderColumnInvoice;
  String get orderColumnTime;
  String get orderColumnType;
  String get orderColumnWhere;
  String get orderColumnStaff;
  String get orderColumnTotal;
  String get orderColumnStatus;

  // Detail pane.
  String get orderDetailLines;
  String get orderDetailPayments;
  String get orderDetailDiscounts;
  String get orderDetailNoPayments;
  String get orderDetailSubtotal;
  String get orderDetailDiscount;
  String get orderDetailService;
  String get orderDetailVat;
  String get orderDetailTotal;
  String get orderDetailServedBy;

  /// Every order written before the till recorded a seller.
  String get orderDetailServedByUnknown;
  String orderDetailVoidedBy(String name);
  String get orderDetailVoidedLine;
  String orderDetailGuests(int count);
  String orderDetailApprovedBy(String name);

  /// Named as coming, not merely missing. A greyed-out button with no
  /// explanation reads as broken.
  String get orderActionsComingWithRefunds;

  // Status names, in the order they appear in `OrderStatus`.
  String get orderStatusDraft;
  String get orderStatusOpen;
  String get orderStatusSentToKitchen;
  String get orderStatusReady;
  String get orderStatusPaid;
  String get orderStatusClosed;
  String get orderStatusVoided;
  String get orderStatusCancelled;
  String get orderStatusRefunded;
  String get orderStatusPartiallyRefunded;

  // ── Refunds ───────────────────────────────────────────────────────────────
  String get refundAction;
  String refundTitle(String invoice);

  /// The number shown at every step. §18 is explicit that the remaining
  /// refundable value must be visible throughout — a cashier who cannot see it
  /// finds out they have over-refunded when the till refuses.
  String get refundRemaining;
  String get refundByItems;
  String get refundByAmount;
  String get refundAmountLabel;
  String get refundReturnTo;
  String get refundSubtotal;
  String get refundDiscount;
  String get refundService;
  String get refundVat;
  String get refundTotal;
  String refundConfirm(String amount);
  String get refundNothingSelected;
  String get refundAlreadyRefunded;
  String refundIssued(String amount);
  String get refundCouldNotBeIssued;
  String get refundNeedsApproval;
  String get refundItemsRemaining;

  /// Why the flow is not offered at all.
  String get refundDisabled;
  String refundOutsideWindow(String window);
  String get refundNothingLeft;
  String refundMoreThanRemains(int asked, int remaining);
  String refundAboveLimit(String limit);
  String refundAboveRemaining(String remaining);
  String get refundReasonNeeded;
  String get refundTenderNeeded;
  String get refundReceiptRequiredNote;

  /// The window names, for the sentence that says why a sale is too old.
  String get refundWindowSameShift;
  String get refundWindowSameDay;
  String get refundWindow7Days;
  String get refundWindow30Days;
  String get refundWindowUnlimited;

  /// Refunds already issued against an order, shown in its detail pane.
  String get refundsAlreadyGiven;
  String refundGivenBy(String name);

  // ── Price override ────────────────────────────────────────────────────────
  String get priceOverrideAction;

  /// The chip on a repriced cart line. Mono, short, and not a sentence.
  String get priceOverrideChip;
  String priceOverrideTitle(String item);
  String get priceOverrideMenuPrice;
  String get priceOverrideNewPrice;
  String get priceOverrideLineTotal;
  String get priceOverrideRestore;
  String get priceOverrideNothingSelected;
  String get priceOverrideUnchanged;
  String get priceOverrideBelowZero;

  /// Why a supervisor is being asked. A price override past the ceiling is the
  /// same act as a discount past it, and says so.
  String priceOverrideAboveLimit(String reduction, String limit);
  String get priceOverrideNotPermitted;
  String priceOverrideApplied(String price);
}

/// English. The reference wording — the Arabic below is a translation of this,
/// not of an earlier draft of it.
final class EnStrings extends AppStrings {
  const EnStrings();

  @override
  String get languageCode => 'en';
  @override
  TextDirection get direction => TextDirection.ltr;
  @override
  String get languageName => 'English';

  @override
  String get reasonRequiredBadge => 'REASON REQUIRED';
  @override
  String get reasonOptionalBadge => 'REASON OPTIONAL';
  @override
  String get reasonNote => 'NOTE';
  @override
  String get reasonNoteHint => 'Anything worth recording';
  @override
  String get reasonRequiredHelp =>
      'A reason is recorded with this and can be reported on later.';
  @override
  String get reasonOptionalHelp =>
      'A reason is optional here. Anything you write is kept with the record.';
  @override
  String get reasonNeedsNoteHelp => 'This reason needs a note.';
  @override
  String get chooseAReason => 'Choose a reason';
  @override
  String get cannotBeUndone => 'CANNOT BE UNDONE';
  @override
  String get amountMicroLabel => 'AMOUNT';
  @override
  String get destructiveKeyHint =>
      'Esc keeps it · the confirm button is never focused by default';
  @override
  String get approvalRequired => 'APPROVAL REQUIRED';
  @override
  String get approvalAction => 'ACTION';
  @override
  String get approvalRequestedBy => 'REQUESTED BY';
  @override
  String get approvalPin => 'MANAGER PIN';
  @override
  String get approvalAboveLimit => 'Above the limit';
  @override
  String get approvalDone => 'Done';
  @override
  String wrongPinAttemptsLeft(int attempts) => attempts == 1
      ? 'Wrong PIN. One attempt left.'
      : 'Wrong PIN. $attempts attempts left.';
  @override
  String approvalRecorded(String approver, String requester) =>
      '$approver approved this, requested by $requester. Both names are on the record.';
  @override
  String get discountTitle => 'Discount';
  @override
  String get discountWholeOrder => 'Whole order';
  @override
  String get discountThisLine => 'This line';
  @override
  String get discountPresets => 'OFFERED HERE';
  @override
  String get discountCustom => 'OR TYPE ONE';
  @override
  String get discountPercent => 'Percent';
  @override
  String get discountAmount => 'Amount';
  @override
  String get discountNoneOffered =>
      'No discounts are configured for this. You can still type one.';
  @override
  String get discountRemove => 'Remove discount';
  @override
  String get discountApplyAction => 'Apply discount';
  @override
  String get discountNewTotal => 'NEW TOTAL';
  @override
  String get discountNotApplicable =>
      'That discount is not offered on this order right now.';
  @override
  String get discountNeedsCustomer =>
      'That discount needs a customer on the order.';
  @override
  String get discountAlreadyOn =>
      'There is already a discount here. Remove it first.';
  @override
  String get discountNothingToDiscount => 'There is nothing to discount.';
  @override
  String discountAboveLimitNote(String limit, String requested) =>
      'The manual discount limit here is $limit. This discount is $requested.';
  @override
  String discountApprovalAct(String amount) => 'Discount $amount';
  @override
  String approvedByShort(String approver) => 'approved by $approver';
  @override
  String get cancelLineAction => 'Remove line';
  @override
  String get voidLineAction => 'Void line';
  @override
  String get keepLineAction => 'Keep it';
  @override
  String get lineVoidedChip => 'VOID';
  @override
  String get cancelLineNothingMade =>
      'Nothing has been made yet, so this just comes off the ticket.';
  @override
  String cancelLineTitle(String item) => 'Remove $item?';
  @override
  String voidLineTitle(String item) => 'Void $item?';
  @override
  String voidLineConsequenceRemoved(String amount) =>
      'The line comes off the bill and $amount is no longer charged.';
  @override
  String get voidLineConsequenceKitchen =>
      'The kitchen has already made this. It is waste, and it is reported as waste.';
  @override
  String get voidLineConsequenceIrreversible =>
      'This cannot be undone. The line stays on the ticket, marked, so the customer can be shown what happened.';
  @override
  String get voidOrderAction => 'Void order';
  @override
  String get keepOrderAction => 'Keep order';
  @override
  String get clearTicketTitle => 'Clear this ticket?';
  @override
  String get clearTicketNothingSent =>
      'Nothing has been sent to the kitchen, so this is not recorded anywhere.';
  @override
  String voidOrderTitle(String reference) => 'Void $reference?';
  @override
  String voidOrderConsequenceBill(String amount) =>
      'The whole bill of $amount is cancelled and nothing is charged.';
  @override
  String get voidOrderConsequenceKitchen =>
      'Everything already sent to the kitchen is waste, and is reported as waste.';
  @override
  String get voidOrderConsequenceRecorded =>
      'This cannot be undone. The order is recorded as voided, with your name and your reason on it.';
  @override
  String voidOrderRecorded(String invoice) => 'Voided and recorded as $invoice';
  @override
  String get voidCouldNotBeRecorded =>
      'That could not be recorded, so the ticket is still here. Try again.';

  @override
  String get orderHistoryTitle => 'Orders';
  @override
  String get orderHistoryToday => 'Today';
  @override
  String get orderHistoryLast7Days => 'Last 7 days';
  @override
  String get orderHistoryLast30Days => 'Last 30 days';
  @override
  String get orderHistorySearchHint => 'Invoice or table';
  @override
  String get orderHistoryAllStatuses => 'All statuses';
  @override
  String get orderHistoryAllTypes => 'All types';
  @override
  String get orderHistoryEveryone => 'Everyone';
  @override
  String orderHistoryCount(int count) =>
      count == 1 ? '1 order' : '$count orders';
  @override
  String orderHistoryTruncated(int limit) =>
      'Showing the newest $limit. Narrow the dates to see further back.';
  @override
  String get orderHistoryEmpty => 'No orders yet in this period.';
  @override
  String get orderHistoryEmptyFiltered => 'No orders match these filters.';
  @override
  String get orderHistoryClearFilters => 'Clear filters';
  @override
  String get orderHistoryPickAnOrder => 'Pick an order to see it.';
  @override
  String get orderHistoryUnavailable =>
      'History could not be read from the branch database.';
  @override
  String get orderHistoryNotPermitted =>
      'You do not have permission to see the branch\'s orders.';
  @override
  String get orderColumnInvoice => 'Invoice';
  @override
  String get orderColumnTime => 'Time';
  @override
  String get orderColumnType => 'Type';
  @override
  String get orderColumnWhere => 'Table';
  @override
  String get orderColumnStaff => 'Staff';
  @override
  String get orderColumnTotal => 'Total';
  @override
  String get orderColumnStatus => 'Status';
  @override
  String get orderDetailLines => 'Items';
  @override
  String get orderDetailPayments => 'Paid with';
  @override
  String get orderDetailDiscounts => 'Discounts';
  @override
  String get orderDetailNoPayments => 'No payment was taken.';
  @override
  String get orderDetailSubtotal => 'Subtotal';
  @override
  String get orderDetailDiscount => 'Discount';
  @override
  String get orderDetailService => 'Service';
  @override
  String get orderDetailVat => 'VAT';
  @override
  String get orderDetailTotal => 'Total';
  @override
  String get orderDetailServedBy => 'Served by';
  @override
  String get orderDetailServedByUnknown => 'Not recorded';
  @override
  String orderDetailVoidedBy(String name) => 'Voided by $name';
  @override
  String get orderDetailVoidedLine => 'Voided';
  @override
  String orderDetailGuests(int count) => count == 1 ? '1 guest' : '$count guests';
  @override
  String orderDetailApprovedBy(String name) => 'Approved by $name';
  @override
  String get orderActionsComingWithRefunds =>
      'Reprint and refund arrive with the refund flow.';
  @override
  String get orderStatusDraft => 'Draft';
  @override
  String get orderStatusOpen => 'Open';
  @override
  String get orderStatusSentToKitchen => 'In kitchen';
  @override
  String get orderStatusReady => 'Ready';
  @override
  String get orderStatusPaid => 'Paid';
  @override
  String get orderStatusClosed => 'Closed';
  @override
  String get orderStatusVoided => 'Voided';
  @override
  String get orderStatusCancelled => 'Cancelled';
  @override
  String get orderStatusRefunded => 'Refunded';
  @override
  String get orderStatusPartiallyRefunded => 'Part refunded';

  @override
  String get refundAction => 'Refund';
  @override
  String refundTitle(String invoice) => 'Refund $invoice';
  @override
  String get refundRemaining => 'Left to refund';
  @override
  String get refundByItems => 'By item';
  @override
  String get refundByAmount => 'By amount';
  @override
  String get refundAmountLabel => 'Amount to give back';
  @override
  String get refundReturnTo => 'Give back to';
  @override
  String get refundSubtotal => 'Subtotal';
  @override
  String get refundDiscount => 'Discount';
  @override
  String get refundService => 'Service';
  @override
  String get refundVat => 'VAT';
  @override
  String get refundTotal => 'Refund';
  @override
  String refundConfirm(String amount) => 'Refund $amount';
  @override
  String get refundNothingSelected => 'Choose what to give back first.';
  @override
  String get refundAlreadyRefunded => 'Already refunded';
  @override
  String refundIssued(String amount) => 'Refunded $amount';
  @override
  String get refundCouldNotBeIssued =>
      'That could not be recorded, so no money has gone back. Try again.';
  @override
  String get refundNeedsApproval => 'A supervisor has to approve this amount.';
  @override
  String get refundItemsRemaining => 'left';
  @override
  String get refundDisabled => 'Refunds are switched off for this restaurant.';
  @override
  String refundOutsideWindow(String window) =>
      'This sale is outside the refund window ($window).';
  @override
  String get refundNothingLeft => 'This order has nothing left to refund.';
  @override
  String refundMoreThanRemains(int asked, int remaining) =>
      'You asked for $asked, and $remaining is left.';
  @override
  String refundAboveLimit(String limit) =>
      'That is above the $limit refund limit. Nobody at the till can approve past it.';
  @override
  String refundAboveRemaining(String remaining) =>
      'Only $remaining is left on this order.';
  @override
  String get refundReasonNeeded => 'Give a reason for the refund.';
  @override
  String get refundTenderNeeded => 'Say how the money goes back.';
  @override
  String get refundReceiptRequiredNote =>
      'This restaurant asks for the original receipt.';
  @override
  String get refundWindowSameShift => 'same shift';
  @override
  String get refundWindowSameDay => 'same day';
  @override
  String get refundWindow7Days => '7 days';
  @override
  String get refundWindow30Days => '30 days';
  @override
  String get refundWindowUnlimited => 'no limit';
  @override
  String get refundsAlreadyGiven => 'Refunded';
  @override
  String refundGivenBy(String name) => 'by $name';

  @override
  String get priceOverrideAction => 'Change price';
  @override
  String get priceOverrideChip => 'PRICE';
  @override
  String priceOverrideTitle(String item) => 'Change the price of $item';
  @override
  String get priceOverrideMenuPrice => 'Menu price';
  @override
  String get priceOverrideNewPrice => 'New price, each';
  @override
  String get priceOverrideLineTotal => 'Line total';
  @override
  String get priceOverrideRestore => 'Back to menu price';
  @override
  String get priceOverrideNothingSelected =>
      'Pick a line on the ticket first.';
  @override
  String get priceOverrideUnchanged => 'That is the price it already has.';
  @override
  String get priceOverrideBelowZero => 'A price cannot be less than nothing.';
  @override
  String priceOverrideAboveLimit(String reduction, String limit) =>
      'That takes $reduction off, and you may take $limit. A supervisor can approve it.';
  @override
  String get priceOverrideNotPermitted =>
      'You do not have permission to change a price.';
  @override
  String priceOverrideApplied(String price) => 'Price changed to $price';

  @override
  String get cancel => 'Cancel';
  @override
  String get done => 'Done';
  @override
  String get back => 'Back';
  @override
  String get backArrow => '← Back';
  @override
  String get continueLabel => 'Continue';
  @override
  String get importLabel => 'Import';
  @override
  String get activate => 'Activate';
  @override
  String get none => 'None';

  @override
  String get orderTypeDineIn => 'Dine-in';
  @override
  String get orderTypeTakeaway => 'Takeaway';
  @override
  String get orderTypeDelivery => 'Delivery';
  @override
  String get orderTypeDriveThru => 'Drive-thru';

  @override
  String outOfStock(String product) =>
      "$product is out of stock — 86'd in the catalog.";
  @override
  String get nothingToCharge => 'Nothing to charge.';
  @override
  String get ticketVoided => 'Ticket voided.';
  @override
  String get ticketStillOpen =>
      'There is still a ticket on this till. Take payment or void it before '
      'closing the shift.';
  @override
  String get roundSentToKitchen => 'Round sent to the kitchen.';
  @override
  String get drawerOpenedToast => 'Cash drawer opened · F10';
  @override
  String get openTicketsNotBuilt => 'Open tickets — not built yet.';
  @override
  String get customAmountNotBuilt => 'Custom amount — not built yet.';
  @override
  String get searchHint => 'Scan barcode or search item / PLU';
  @override
  String get customAmount => 'Custom amount';
  @override
  String get shortcutStrip => 'F2 SEARCH   F4 PARK   F9 PAY   ESC CLOSE';
  @override
  String matchCount(int count) => '$count matches';
  @override
  String catalogCached(int items) => 'CATALOG CACHED · $items ITEMS';
  @override
  String get noItemsMatch => 'No items match.';
  @override
  String get outOfStockBadge => 'OUT';

  @override
  String get openDrawer => 'Open drawer';
  @override
  String get syncingWithPlatform => 'Syncing with the platform…';
  @override
  String get syncStatusUnavailable => '● Sync status unavailable';
  @override
  String syncOfflineQueued(int? queued) =>
      '● Offline · ${queued ?? '—'} queued';
  @override
  String get syncChecking => '● Checking sync…';
  @override
  String syncSyncedQueued(int queued) => '● Synced · $queued queued';
  @override
  String get lock => 'Lock';
  @override
  String get closeShift => 'Close shift';
  @override
  String get noShift => 'NO SHIFT';

  @override
  String get categories => 'Categories';
  @override
  String get allItems => 'All items';
  @override
  String get openTickets => 'Open tickets';
  @override
  String get tables => 'Tables';

  @override
  String get noTableYet => 'No table yet';
  @override
  String seatedTable(String table, int? guests) =>
      guests == null ? table : '$table · $guests guests';
  @override
  String walkIn(String orderType) => '$orderType · walk-in';
  @override
  String cartStatusLine(String cashier, bool online) =>
      'OPEN · ${cashier.toUpperCase()} · ${online ? 'LIVE' : 'OFFLINE'}';
  @override
  String get changeTable => 'Change table';
  @override
  String get cartEmptyHelp =>
      'Ticket is empty. Tap a product, or press F2 and type to search. '
      'Items with modifiers open a sheet first.';
  @override
  String alreadySent(int lines) => 'Already sent · $lines lines';
  @override
  String get newRound => 'New round';
  @override
  String get subtotal => 'Subtotal';
  @override
  String servicePercent(String percent) => 'Service $percent%';
  @override
  String vatPercent(String percent) => 'VAT $percent%';
  @override
  String get totalCaps => 'TOTAL';
  @override
  String get closeTableCta => 'CLOSE TABLE';
  @override
  String get chargeCta => 'CHARGE';
  @override
  String get sendRoundKey => 'Send round  F4';
  @override
  String get parkKey => 'Park  F4';
  @override
  String get voidTicket => 'Void ticket';

  @override
  String modifierGroupFull(String group, int max) =>
      '$group allows at most $max.';
  @override
  String pickGroupFirst(String group) => 'Pick a ${group.toLowerCase()} first.';
  @override
  String requiredPick(int count) => 'REQUIRED · PICK $count';
  @override
  String maxPick(int count) => 'MAX $count';
  @override
  String get addToTicket => 'Add to ticket';

  @override
  String get tenderCash => 'Cash';
  @override
  String get tenderCard => 'Card';
  @override
  String get tenderWallet => 'Wallet · InstaPay';
  @override
  String get tenderOnAccount => 'On account';
  @override
  String get payment => 'Payment';
  @override
  String get backToTicket => '← Back to ticket';
  @override
  String lineCount(int lines) => '$lines lines';
  @override
  String get amountDue => 'Amount due';
  @override
  String get remainingDue => 'Remaining due';
  @override
  String totalIs(String amount) => 'Total $amount';
  @override
  String paidOfTotal(String paid, String total, int tenders) =>
      '$paid paid of $total · $tenders tender${tenders == 1 ? '' : 's'}';
  @override
  String get tendersHeading => 'Tenders';
  @override
  String get noTenderYet =>
      'No tender yet — pick a method, key an amount or tap a quick-cash button.';
  @override
  String get amount => 'Amount';
  @override
  String get exact => 'Exact';
  @override
  String get clear => 'CLR';
  @override
  String get takePayment => 'TAKE PAYMENT';
  @override
  String get enterAmountAboveZero => 'Enter an amount above zero.';

  @override
  String get taxRegistrationLine => 'TAX REG 000-000-000';
  @override
  String get provisionalInvoice => 'PROVISIONAL';
  @override
  String get receiptSubtotal => 'SUBTOTAL';
  @override
  String receiptService(String percent) => 'SERVICE $percent%';
  @override
  String receiptVat(String percent) => 'VAT $percent%';
  @override
  String get receiptTotal => 'TOTAL';
  @override
  String get receiptPaid => 'PAID';
  @override
  String get receiptChange => 'CHANGE';
  @override
  String get receiptQueuedOffline => 'QUEUED OFFLINE — WILL SYNC';
  @override
  String get receiptSynced => 'SYNCED TO XORDER';
  @override
  String get receiptThanks => 'Thank you for your visit';
  @override
  String get receiptTaxFromDevice => 'TAX FROM DEVICE CONFIG';
  @override
  String get newSale => 'New sale';
  @override
  String get printAndNew => 'Print & new';
  @override
  String get receiptQueuedToast => 'Receipt queued for the default printer.';

  @override
  String get pickATable => 'Pick a table';
  @override
  String get pickATableHelp =>
      'Tap a table to open a new bill or add to an existing one.';
  @override
  String get floorHasNoTables =>
      'No tables on this branch yet. A manager adds them in Management, '
      'under Floor.';
  @override
  String get sellWithoutTable => 'Sell without a table';
  @override
  String legendFree(int count) => 'FREE $count';
  @override
  String legendOccupied(int count) => 'OCCUPIED $count';
  @override
  String legendBillAsked(int count) => 'BILL ASKED $count';
  @override
  String get tableFree => 'FREE';
  @override
  String tableLineCount(int lines) => '$lines LINES';
  @override
  String get tableBillAsked => 'BILL ASKED';
  @override
  String tableSeats(int seats) => '$seats seats';
  @override
  String tableOpenWith(String total) => 'Open · $total';
  @override
  String tableBillRequested(String total) => 'Bill requested · $total';

  @override
  String get terminalLocked => 'TERMINAL LOCKED';
  @override
  String get wrongPin => 'Wrong PIN — try again';
  @override
  String enterPinFor(String name) => '$name · enter PIN';

  @override
  String get pointOfSale => 'POINT OF SALE';
  @override
  String get renewLicence => 'Renew licence';
  @override
  String get manageLicence => 'Manage licence';
  @override
  String get licenceRequired => 'Licence required';
  @override
  String get startShift => 'Start shift';
  @override
  String resumeShift(String reference) => 'Resume $reference';
  @override
  String get cashUpStillAvailable =>
      'Cash-up and reprint for the last shift are still available.';
  @override
  String get startShiftHelp =>
      'You will be asked for your PIN and the cash already in the drawer.';
  @override
  String resumeShiftHelp(String openedBy) =>
      'Opened by $openedBy. The drawer was never closed, so the shift is still '
      'yours.';
  @override
  String get enterKeyCap => 'ENTER';
  @override
  String get tenantCell => 'TENANT';
  @override
  String get branchCell => 'BRANCH';
  @override
  String get terminalCell => 'TERMINAL';
  @override
  String get catalogCell => 'CATALOG';
  @override
  String get catalogSyncing => 'syncing…';
  @override
  String catalogCachedItems(int items) => 'cached · $items items';

  @override
  String get signIn => 'Sign in';
  @override
  String get openTheDrawer => 'Open the drawer';
  @override
  String get signInHelp => 'Enter your PIN. The shift is opened in your name.';
  @override
  String countTheDrawerHelp(String name) =>
      '$name · count what is in the drawer before you start.';
  @override
  String get pinNotRecognised => 'That PIN was not recognised.';
  @override
  String notPermittedToOpenShift(String name) =>
      '$name is not permitted to open a shift.';
  @override
  String get enterOpeningFloat =>
      'Enter the opening float, or 0.00 if the drawer is empty.';
  @override
  String get openShift => 'Open shift';
  @override
  String get openingFloat => 'Opening float';
  @override
  String get emptyDrawer => 'Empty';
  @override
  String get openingFloatHelp =>
      'This is the cash already in the drawer. Every variance at cash-up is '
      'measured from it, so a guess here is a discrepancy later.';
  @override
  String closeShiftTitle(String reference) => 'Close $reference';
  @override
  String closeShiftHelp(String openedBy) =>
      'Opened by $openedBy. Count the drawer, then confirm.';
  @override
  String closeShiftApproval(String reference) =>
      'Close $reference and count the drawer';
  @override
  String get countTheDrawer => 'Count the drawer and enter the total.';
  @override
  String get signInBeforeClosing => 'Sign in before closing a shift.';
  @override
  String get countedInDrawer => 'Counted in the drawer';
  @override
  String expectedInDrawerHelp(String expected, String float, String taken) =>
      'Expected $expected — float $float plus $taken taken in cash.';
  @override
  String get varianceBalances => 'BALANCES';
  @override
  String get varianceOver => 'OVER';
  @override
  String get varianceShort => 'SHORT';
  @override
  String shiftClosedTitle(String reference) => '$reference closed';
  @override
  String get drawerBalances => 'The drawer balances.';
  @override
  String closedWithVariance(String variance) =>
      'Recorded with a variance of $variance. It is on the shift record, not '
      'lost.';
  @override
  String get zSales => 'Sales';
  @override
  String get zGrossTaken => 'Gross taken';
  @override
  String zTenderRow(String label, int count) => '  $label × $count';
  @override
  String get zOpeningFloat => 'Opening float';
  @override
  String get zExpectedInDrawer => 'Expected in drawer';
  @override
  String get zCounted => 'Counted';

  @override
  String get licence => 'Licence';
  @override
  String get renewThisTerminal => 'Renew this terminal';
  @override
  String get licenceKeyHint => 'XORD-0000-0000-0000';
  @override
  String get activateKey => 'Activate key';
  @override
  String get importLicenceFile => 'Import licence file';
  @override
  String get checkForRenewal => 'Check for renewal';
  @override
  String get cannotCheckForRenewal =>
      'This build cannot reach the licence server, so it cannot check for a '
      'renewal. Import the licence file instead.';
  @override
  String get renewalOnlineHelp =>
      'Renewals bought on the platform arrive automatically — this terminal '
      're-checks at start-up and before each shift opens. The buttons above are '
      'for forcing it sooner.';
  @override
  String get renewalOfflineHelp =>
      'This terminal has no route to the platform, so renewals arrive as a '
      'file. Ask your supplier for the .xlic and import it — no internet is '
      'needed to verify it.';
  @override
  String get licenceUpdated => 'Licence updated.';
  @override
  String get noRouteToPlatform =>
      'This terminal is not connected to the XOrder platform, so it cannot '
      'check for a renewal. Enter a key or import the licence file instead.';
  @override
  String get licenceFileHint => '{"payload": "...", "signature": "..."}';
  @override
  String get capabilityOpenShift => 'Open a new shift';
  @override
  String get capabilitySell => 'Sell on an open shift';
  @override
  String get capabilityCashUp => 'Cash up, X/Z report';
  @override
  String get capabilityReprint => 'Reprint a receipt';
  @override
  String get capabilityExport => 'Export data';
  @override
  String get capabilityConfigure => 'Change configuration';
  @override
  String daysRemaining(int days) => '$days days remaining';
  @override
  String daysPastExpiry(int days) => '$days days past expiry';
  @override
  String get licensedHeadline => 'Licensed';
  @override
  String get renewalDueHeadline => 'Renewal due';
  @override
  String get expiredInGraceHeadline => 'Expired — in grace';
  @override
  String get expiredHeadline => 'Expired';
  @override
  String get notLicensedHeadline => 'Not licensed';
  @override
  String get licenceProblemHeadline => 'Licence problem';

  @override
  String licenceExpiresInDays(int days) =>
      'Licence expires in $days day${days == 1 ? '' : 's'}.';
  @override
  String licenceGraceRemaining(int days) =>
      'Licence expired. Trading continues for $days more '
      'day${days == 1 ? '' : 's'} — please renew.';
  @override
  String get licenceExpiredNewShiftBlocked =>
      'Licence expired. You can finish and cash up the open shift, but a new '
      'shift cannot be started until it is renewed.';
  @override
  String licenceTenantMismatch(String licenceTenant, String terminalTenant) =>
      'This licence belongs to $licenceTenant, but this terminal is set up for '
      '"$terminalTenant".';
  @override
  String licenceModeNotCovered(String mode) =>
      'This licence does not cover ${mode.toLowerCase()} installations.';
  @override
  String get licenceOtherTerminal =>
      'This licence is registered to a different terminal.';
  @override
  String licenceNotYetValid(String date) =>
      "This licence starts on $date. Check the terminal's date and time.";
  @override
  String get licenceFileDamaged => 'This licence file is damaged.';
  @override
  String get noLicenceInstalled => 'No licence installed.';
  @override
  String get licenceUnverifiable =>
      'This licence file could not be verified. Ask your supplier to reissue it.';
  @override
  String get noLicenceServer =>
      'There is no licence server to check a key against. Ask your supplier for '
      'the .xlic file and use "Activate from file".';
  @override
  String get notALicenceFile =>
      'That file is not a licence — it should be the .xlic file from your '
      'supplier.';
  @override
  String get licenceKeyNotRecognised => 'That licence key was not recognised.';
  @override
  String licenceKeyNotRecognisedBy(String address) =>
      '$address does not know this licence key. Check the key — and check that '
      'this is the right platform: a key issued somewhere else will always be '
      'refused here, however correctly it is typed.';
  @override
  String licenceServerUnreachable(String address) =>
      'Could not reach $address, so nothing is known about this key yet. Check '
      'the connection, or activate from the .xlic file instead — that needs no '
      'network at all.';
  @override
  String licenceServerRefused(String address, int status) =>
      '$address answered with an error ($status) instead of a licence. That is '
      'a problem at the platform, not with your key. Try again shortly, or '
      'activate from the .xlic file.';
  @override
  String get tooManyLicenceAttempts =>
      'Too many activation attempts in a short time. Wait a minute and try '
      'again — the key has not been rejected.';
  @override
  String get licenceRevokedByPlatform =>
      'This licence has been withdrawn. Nothing is wrong with the key — speak '
      'to your supplier.';

  @override
  String get productWordmark => 'XORDER POS';
  @override
  String get terminalSetup => 'TERMINAL SETUP';
  @override
  String get terminalNotSetUp => 'This terminal has not been set up.';
  @override
  String get switchToLight => 'Switch to light';
  @override
  String get switchToDark => 'Switch to dark';
  @override
  String stepOf(int step, int total) => 'Step $step of $total';
  @override
  String get openTheTill => 'Open the till';

  @override
  @override
  String get stepSetupType => 'Setup type';

  @override
  String get stepSetupTypeBlurb =>
      'Choose how this terminal runs. A cloud terminal syncs every sale to the '
      'platform; an offline one keeps its sales in the restaurant. Which of '
      'the two you may pick is decided by the licence, not by this screen.';
  @override
  String get setupTypeOfflineHelp =>
      'This terminal keeps its own menu, staff and money rules, and no sale '
      'ever leaves the restaurant. It still reaches the platform to activate '
      'and renew its licence — or you can install a licence file by hand.';
  @override
  String get setupTypeCloudHelp =>
      'The platform is the source of the menu, the staff and the money '
      'rules, and every sale syncs to it.';

  @override
  String get stepLanguage => 'Language';
  @override
  String get stepLanguageBlurb => 'Pick the language for this terminal.';
  @override
  String get stepConnection => 'Connection';
  @override
  String get stepConnectionBlurb => 'Where does this terminal send its sales?';
  @override
  String get stepAccount => 'Sign in';
  @override
  String get stepFirstAdministrator => 'First administrator';
  @override
  String get stepFirstAdministratorBlurb =>
      'Nobody can open this till yet. Create the person who will.';
  @override
  String get stepAccountBlurb =>
      'Identify the tenant and the person setting up.';
  @override
  String get stepLicence => 'Licence';
  @override
  String get stepLicenceBlurb => 'Activate this terminal.';
  @override
  String get stepBranch => 'Branch';
  @override
  String get stepBranchBlurb => 'Which branch is this terminal in?';
  @override
  String get stepTerminal => 'Terminal';
  @override
  String get stepTerminalBlurb =>
      'Name this till so it can be told apart in reports.';
  @override
  String get stepHardware => 'Hardware';
  @override
  String get stepHardwareBlurb => 'Printer, cash drawer and scanner.';
  @override
  String get stepMoney => 'Money';
  @override
  String get stepMoneyBlurb => 'Confirm currency, tax and service charge.';
  @override
  String get stepCatalogue => 'Catalogue';
  @override
  String get stepCatalogueBlurb => 'Download the menu for offline use.';
  @override
  String get stepReady => 'Ready';
  @override
  String get stepReadyBlurb => 'Check everything, then open the till.';

  @override
  String get englishBlurb => 'Left-to-right layout.';
  @override
  String get arabicBlurb =>
      'Right-to-left layout, Arabic-Indic digits accepted.';
  @override
  String get languagePaneHelp =>
      'This sets the till interface only. The menu is shown to diners in '
      'whichever languages the restaurant publishes.';

  @override
  String get modeCloud => 'Cloud';
  @override
  String get modeCloudBlurb =>
      'Sales sync to the XOrder platform when a connection allows.';
  @override
  String get modeOffline => 'Offline';
  @override
  String get modeOfflineBlurb =>
      'Sales stay in the restaurant. Only the licence goes out.';
  @override
  String get modeNotLicensed => 'Not covered by this licence.';
  @override
  String get notLicensedBadge => 'NOT LICENSED';
  @override
  String get syncAutomatic => 'Automatic';
  @override
  String get syncAutomaticBlurb =>
      'Send sales as soon as the connection allows.';
  @override
  String get syncManual => 'Manual';
  @override
  String get syncManualBlurb => 'Send sales when staff choose to.';
  @override
  String get platformAddress => 'Platform address';
  @override
  String get platformCaps => 'PLATFORM';
  @override
  String get platformAddressHelp =>
      'Where this terminal sends its sales. Selling never waits on it — the '
      'local database takes the sale first and the queue drains behind it.';
  @override
  String get trustWithoutCertificate =>
      'Trust this database without a certificate';
  @override
  String get trustWithoutCertificateBlurb =>
      'Only for a box on this local network. Never for a public address.';
  @override
  String get theDatabase => 'Database';
  @override
  String get databaseHost => 'Database address';
  @override
  String get databaseHostHelp =>
      'The machine on this network holding the database every till shares.';
  @override
  String get databaseName => 'Database name';
  @override
  String get databasePort => 'Port';
  @override
  String get databaseUser => 'Database user';
  @override
  String get databaseUserHelp =>
      'Use the restricted till account, not a superuser. It needs only to read '
      'the menu and write sales.';
  @override
  String get databasePassword => 'Database password';
  @override
  String get databasePasswordHelp =>
      'Kept on this machine only, and never written into the terminal’s '
      'configuration file. You will be asked for it again if this till is '
      'reinstalled.';
  @override
  String get keystoreUnavailable => 'This machine cannot store the password';
  @override
  String get keystoreUnavailableHelp =>
      'The operating system’s credential store did not answer, so a password '
      'typed here will work now but will be gone after a restart — and this '
      'wizard will open again. Setup can be finished either way. On macOS, '
      'unlock the login keychain; on Windows, check the Credential Manager '
      'service. If it keeps happening, the application may need reinstalling '
      'by someone who can sign it.';
  @override
  String get machineNowHasDatabase => 'This machine now has a database.';
  @override
  String get noDatabaseYet => 'This machine has no database yet';
  @override
  String get firstInstallHeading => 'FIRST INSTALL ON THIS MACHINE';
  @override
  String get firstInstallHelp =>
      'Creates the database, its tables, the four staff roles and the first '
      'person. The restaurant\'s name comes from the licence. Safe to run '
      'twice — anything already there is left alone.';
  @override
  String adminPasswordFor(String user) => '$user password';
  @override
  String get adminPasswordHelp =>
      'The PostgreSQL account that may create databases — not the till\'s. '
      'Used once, here, and never written to this machine.';
  @override
  String get firstPerson => 'First person';
  @override
  String get firstPersonHelp =>
      'The owner. Without somebody to sign in as, the next step has nobody '
      'to authenticate.';
  @override
  String get theirUsername => 'Their username';
  @override
  String get theirPin => 'Their PIN';
  @override
  String get theirPinHelp =>
      'What they type at the till, four to twelve digits. Stored as a '
      'PBKDF2 hash — it cannot be read back, only replaced.';
  @override
  String get buildingDatabase => 'Building…';
  @override
  String get buildTheDatabase => 'Build the database';

  @override
  String get installLicenceFirst =>
      'Install the licence first — it names the restaurant this database is '
      'for.';
  @override
  String get firstPersonIncomplete =>
      'The first person needs a name, a username and a PIN of at least four '
      'digits. Without one, nobody can sign in to the till that is about to '
      'exist.';
  @override
  String pinIsExactlyDigits(int length) =>
      'A PIN is exactly $length digits. It is typed on a keypad at the '
      'counter, which submits on the last one — a longer PIN could never be '
      'entered.';
  @override
  String exactlyDigits(int length) => 'Exactly $length digits.';
  @override
  String databaseNameInvalid(String name) =>
      '"$name" cannot be a database name — letters, digits and underscores '
      'only, starting with a letter. A hyphen is the usual culprit: try '
      '"${name.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_')}".';
  @override
  String permissionDenied(String user, String database) =>
      'PostgreSQL signed "$user" in and then refused the work: it may not '
      'create tables in "$database". Nothing is wrong with the password. This '
      'happens when the till points at a database somebody else created — the '
      'owner has to hand it over, or let the wizard create one of its own.';
  @override
  String createdDatabase(String database) => 'Created $database.';
  @override
  String databaseAlreadyThere(String database) =>
      '$database was already there.';
  @override
  String get schemaAlreadyCurrent => 'The schema was already current.';
  @override
  String migrationsApplied(int count) => 'Applied $count migration(s).';
  @override
  String restaurantSeeded(String restaurant) =>
      '$restaurant and its first branch are on this machine.';
  @override
  String get rolesAlreadyThere => 'The roles were already there.';
  @override
  String rolesCreated(int count) => 'Created $count system roles.';
  @override
  String ownerCreated(String name) => 'Created $name as the owner.';
  @override
  String ownerAlreadyHere(String username) =>
      '$username was already here — the PIN was left as it was.';
  @override
  String grantsApplied(String tillRole, String adminRole) =>
      'Granted $tillRole and $adminRole what each one needs.';
  @override
  String bootstrapAuthFailed(String user) =>
      'PostgreSQL rejected "$user" and that password. This is the '
      'ADMINISTRATOR account that creates the database, not the till\'s.';
  @override
  String bootstrapUnreachable(String host, int port) =>
      'Nothing answered at $host:$port. Check PostgreSQL is running on this '
      'machine.';
  @override
  String bootstrapRefused(Object raw) =>
      'Connected, but the database refused the work. $raw';
  @override
  String setupIncomplete(String missing) =>
      'Setup is missing $missing. Go back to the Terminal step and register '
      'this terminal, then try again.';
  @override
  String get missingTerminalName => 'a terminal name';
  @override
  String get missingRestaurantIdentity => 'the restaurant identity';
  @override
  String get missingBranch => 'a branch';
  @override
  String get missingBranchPrefix => 'the branch invoice prefix';
  @override
  String get missingTerminalId => 'a terminal id';
  @override
  String couldNotSaveSetup(Object error) =>
      'Could not save this terminal\'s setup: $error';
  @override
  String get platformAddressRequired =>
      'Enter the platform address first, or choose Offline if this terminal '
      'keeps its sales in the building.';
  @override
  String couldNotReach(String address) =>
      'Could not reach $address. Check the address, and that the server is '
      'switched on and on this network.';
  @override
  String get noPlatformAddressInForce =>
      'No platform address is in force. Go back to the Connection step and set '
      'one.';
  @override
  String get terminalNotRegisteredYet =>
      'This terminal is not registered yet, so the platform will not hand it a '
      'menu.';

  @override
  String get refusalPairingCodeInvalid =>
      'That setup code was not recognised. Check it with whoever added this '
      'till in the dashboard.';
  @override
  String get refusalPairingCodeSpent =>
      'That setup code has already been used. Issue a new one from the '
      'dashboard.';
  @override
  String get refusalCredentialsRejected =>
      'That username and password were not accepted. Check them with a '
      'manager, or use a setup code instead.';
  @override
  String get refusalNoBranches =>
      'This restaurant has no branches yet. Add one in the dashboard first.';
  @override
  String get refusalBranchUnknown =>
      'That branch is not on this server any more. Pick another.';
  @override
  String refusalTenantUnknown(String tenant) =>
      'No restaurant named "$tenant" exists on this server. Check the short '
      'name on the previous step.';
  @override
  String refusalWrongPlatform(String platform) =>
      '$platform did not answer like the XOrder platform. Check the platform '
      'address on the Connection step.';
  @override
  String refusalPlatformUnreachable(String platform) =>
      '$platform could not be reached. Check the platform address on the '
      'Connection step, then try again.';
  @override
  String get refusalClaimUnreadable =>
      'The platform answered in a shape this till does not understand. Update '
      'the app, or pair with a code from the dashboard.';
  @override
  String get refusalNoPlatformConfigured =>
      'This terminal has no platform address yet. Go back to the connection '
      'step and set one.';
  @override
  String get refusalNoDatabaseReachable =>
      'This terminal cannot reach a branch database yet. Go back to the '
      'connection step and test it.';
  @override
  String get refusalAdoptUnsupported =>
      'This server has no dashboard to have created a terminal in advance. '
      'Name this till and register it instead.';
  @override
  String get refusalValidationFailed =>
      'Enter the username and password of a staff account that may add a '
      'terminal.';
  @override
  String menuDownloadRefused(String address, String answer) =>
      '$address answered the menu download with $answer. Check the platform '
      'address and try again.';
  @override
  String get menuDownloadSilence => 'silence';
  @override
  String menuDownloadHttp(int? status) => 'HTTP $status';
  @override
  String menuShapeNotUnderstood(String address) =>
      '$address answered in a shape this till does not understand. Update '
      'the app and try again.';
  @override
  String get testConnection => 'Test connection';
  @override
  String get singleMachineHelp =>
      'This licence covers one terminal, so the database lives on this machine '
      'and there is no address to type. Back it up: there is no second copy.';
  @override
  String sharedDatabaseHelp(int terminals) =>
      'This licence covers $terminals terminals, so one machine holds the '
      'database and the others read it over this network. Give its address '
      'below — use this machine’s own if the database is here.';
  @override
  String get sendingSales => 'Sending sales';
  @override
  String get sendingSalesHelp =>
      'The till sells offline either way — this only decides when the queue '
      'drains. Licence renewal happens on its own schedule regardless.';

  @override
  String unreachable(String address) =>
      'Could not reach $address. Check the address, and that the server is '
      'switched on and on this network.';
  @override
  String dnsFailure() =>
      'The server name does not resolve. Use its IP address, or give the box a '
      'fixed address on the router.';
  @override
  String tcpFailure(int port) =>
      'Nothing answered on port $port. Check PostgreSQL is running, that '
      "listen_addresses includes this network, and the host's firewall allows "
      'the connection.';
  @override
  String authFailure(String user) =>
      'PostgreSQL rejected the username or password. Check the "$user" role '
      'exists and the password is right.';
  @override
  String tlsFailure() =>
      'PostgreSQL rejected the secure connection. Check its certificate, or '
      'tick the option above if this really is a box on this network.';
  @override
  String queryFailure(String database) =>
      'Connected, but the database did not answer as expected. Check that '
      '"$database" is the right database.';
  @override
  String connectionOk(String database) =>
      'Connected to "$database" and it answered. This till can reach its '
      'database.';
  @override
  String missingDatabase(String database) =>
      'Postgres is running and accepted the login, but there is no database '
      'called "$database" yet. That is expected on a first install — the next '
      'step builds it. Continue, create the first administrator, and this '
      'answers itself.';

  @override
  String get licenceKey => 'Licence key';
  @override
  String get licenceServer => 'Licence server';
  @override
  String get licenceServerHelp =>
      'Where this key is checked. Leave it as it is unless the licence was '
      'issued somewhere else — a key from one platform is always refused by '
      'another, however correctly it is typed. Blank it to return to the '
      'default. Every licence is signed and verified on this machine, so the '
      'address decides where the file comes from, never whether it counts.';
  @override
  String get activateOnline => 'Activate online';
  @override
  String get activateFromFile => 'Activate from file';
  @override
  String get licenceOnlineHelp =>
      'No internet at this site? Ask your supplier for the .xlic file and '
      'activate from it. The licence is verified on this machine — it does not '
      'need to phone home.';
  @override
  String get licenceOfflineHelp =>
      'Licences are issued as a .xlic file. The signature is checked on this '
      'machine against a key built into the app, so the till never has to phone '
      'home — and a file that was not signed by your supplier will not activate.';
  @override
  String get pasteLicenceFile => 'Paste licence file';
  @override
  String licenceCoverage(String tenant, String? plan, int terminals) =>
      '${_bidi(tenant)}${plan == null ? '' : ' · ${_bidi(plan)}'} · '
      '${terminals == 1 ? 'one terminal' : '$terminals terminals'}';
  @override
  String get cashUpNeverGated =>
      'Cash-up, reprint and data export stay available whatever the licence '
      'says.';

  @override
  String get restaurant => 'Restaurant';
  @override
  String get restaurantHelp =>
      'The restaurant’s short name, as in mahsoub.xorder.io. Staff usernames '
      'are unique within a restaurant, so this has to be set before anyone can '
      'sign in.';
  @override
  String get restaurantFromLicenceHelp =>
      'From your licence. Staff usernames are unique within a restaurant, so '
      'this is what a cashier signs in against.';
  @override
  String get methodPairingCode => 'Setup code';
  @override
  String get methodPairingCodeBlurb =>
      'This till was added in the dashboard and given a code.';
  @override
  String get methodManual => 'Set up manually';
  @override
  String get methodManualBlurb =>
      'No dashboard access — sign in and configure by hand.';
  @override
  String claimedAs(String terminal, String branch) =>
      'Claimed as $terminal · $branch';
  @override
  String get claimedHelp =>
      'The branch, the till name and the terminal id all came from the '
      'dashboard. The next two steps just confirm them.';
  @override
  String get claimedFromDashboardHelp =>
      'The branch, the till name and the terminal id all came from the '
      'dashboard. The next two steps just confirm them.';
  @override
  String get setupCode => 'Setup code';
  @override
  String get setupCodeHelp =>
      'From the dashboard, under Settings → Terminals. Codes are single-use and '
      'expire, so ask for a fresh one rather than reusing an old note.';
  @override
  String get claimThisTerminal => 'Claim this terminal';
  @override
  String get username => 'Username';
  @override
  String get password => 'Password';
  @override
  String get manualCredentialsWarning =>
      'Use the smallest account that may add a terminal, not the owner’s. This '
      'till sits in a public room, and a password typed here is a password that '
      'also opens the dashboard.';
  @override
  String connectedTo(String tenant) => 'Connected to $tenant';
  @override
  String branchesRetrieved(int branches) =>
      '$branches branch(es) retrieved. The next steps use this '
      'configuration — nothing has been registered yet.';
  @override
  String get connectAndPullConfiguration => 'Connect & pull configuration';

  @override
  String get noOrderTypesConfigured => 'No order types configured';
  @override
  String get branchPaneHelp =>
      'The branch decides which order types this till offers and supplies the '
      'invoice-number prefix.';
  @override
  String get terminalName => 'Terminal name';
  @override
  String get terminalNameProvisionedHelp =>
      'Set in the dashboard when this till was added. Change it there rather '
      'than here, so reports keep matching.';
  @override
  String get terminalNameManualHelp =>
      'Shown on receipts and in shift reports, so name it the way staff refer '
      'to it out loud.';
  @override
  String get registered => 'Registered';
  @override
  String get registerThisTerminal => 'Register this terminal';
  @override
  String get registerHelp =>
      'Registering writes this till into the restaurant\'s own database on this '
      'machine, which is what gives it an identity, an invoice prefix, and a '
      'shift its sales belong to. There is no dashboard and nothing to sync — '
      'this is the record.';
  @override
  String get whichTillIsThis => 'WHICH TILL IS THIS?';
  @override
  String get tillAwaitingDevice =>
      'Created in the dashboard, waiting for a device.';
  @override
  String get aNewTill => 'A new till';
  @override
  String get aNewTillBlurb =>
      'Not in the dashboard yet. Creating one uses a seat on the '
      'restaurant\'s plan.';
  @override
  String get terminalNameHint => 'Counter 1';
  @override
  String get alreadySetUp => 'Set up';
  @override
  String get useThisTill => 'Use this till';
  @override
  String get adoptTerminalHelp =>
      'Takes the till the dashboard already created — its name, branch and '
      'id come from there — and issues this machine\'s credential. No seat '
      'is used: that one was bought when the till was created.';
  @override
  String get registerCloudHelp =>
      'Registering issues this till\'s own credential and pulls the '
      'restaurant\'s configuration down — the menu on the next steps comes '
      'from it, so this step cannot be skipped.';
  @override
  String get terminalId => 'Terminal id';
  @override
  String get terminalIdHelp =>
      'Generated once on this machine and never reissued — shifts and orders '
      'are tied to it. Reinstalling keeps it; a new machine gets a new one.';
  @override
  String get findPrinters => 'Find printers';
  @override
  String get lookingForPrinters => 'Looking…';
  @override
  String get testPrint => 'Test print';
  @override
  String get testReceiptSent => 'Test receipt sent.';
  @override
  String get nothingPrinted =>
      'Nothing printed — the sale would still complete.';
  @override
  String get cashDrawerAttached => 'Cash drawer attached';
  @override
  String get cashDrawerAttachedBlurb => 'Opened by the printer kick port.';
  @override
  String get scannerAttached => 'Barcode scanner attached';
  @override
  String get scannerAttachedBlurb =>
      'Keyboard-wedge scanners need no configuration.';
  @override
  String get hardwareHelp =>
      'All optional. A till with nothing attached still sells — the receipt '
      'queues and the screen says so. Printing is never on the critical path of '
      'taking money.';

  @override
  String get currency => 'Currency';
  @override
  String currencyValue(String code, int decimals) =>
      '$code · $decimals decimals';
  @override
  String get serviceCharge => 'Service charge';
  @override
  String get serviceChargeValue => '12% · dine-in only';
  @override
  String get vat => 'VAT';
  @override
  String get vatValue => '14% · on subtotal + service';
  @override
  String get rounding => 'Rounding';
  @override
  String get roundingValue => 'Half-up, once at the tax line';
  @override
  String get moneyRules => 'Money';
  @override
  String get moneyRulesHint => 'Service charge, tax, and what they apply to';
  @override
  String get moneyComesFromPlatform =>
      'This terminal takes its tax rules from the platform.';
  @override
  String get serviceDineInOnly => 'Dine-in only';
  @override
  String get ratesFromThisTerminal =>
      'These rates are set here and priced into every ticket this till rings '
      'up. Changing them changes what the next customer pays.';
  @override
  String get ratesNotSetYet =>
      'Nothing has been set, so this till is pricing from its built-in '
      'default and saying so on every receipt. Set the real rates — zero is a '
      'valid answer.';
  @override
  String get saveRates => 'Save rates';
  @override
  String get ratesSaved => 'Saved. New tickets price with these.';
  @override
  String get floorPlan => 'Floor';
  @override
  String get floorPlanHint => 'The tables a waiter can seat somebody at';
  @override
  String get floorComesFromPlatform =>
      'This terminal takes its floor plan from the platform.';
  @override
  String get addTable => 'Add table';
  @override
  String get tableLabel => 'Label';
  @override
  String get tableSeatsLabel => 'Seats';
  @override
  String get tableArea => 'Area';
  @override
  String get takeOutOfService => 'Out of service';
  @override
  String get putBackInService => 'Back in service';
  @override
  String get noTablesYet =>
      'No tables yet. Add one so a waiter can seat somebody at it.';
  @override
  String tableSummary(int tables) => '\$tables tables';
  @override
  String get fromDeviceConfiguration => 'From device configuration';
  @override
  String get deviceTaxHelp =>
      'These rates are held on this terminal, not issued by the server. Every '
      'receipt printed from them says so on the slip. Once the server owns tax, '
      'this screen becomes read-only.';
  @override
  String get downloadMenu => 'Download menu';
  @override
  String get downloadAgain => 'Download again';
  @override
  String itemsCached(int items) => '$items items cached on this terminal.';
  @override
  String get menuEmpty => 'No menu on this terminal';
  @override
  String get menuEmptyHelp =>
      'The download worked, but this restaurant has no products yet, so the '
      'till has nothing to ring up. Setup can be finished — the menu refreshes '
      'in the background — but add the items before anyone tries to sell.';
  @override
  String get menuEmptyHelpOffline =>
      'This restaurant has no products yet, so the till has nothing to ring '
      'up. Nothing will arrive on its own — finish setup, then build the menu '
      'in Management before anyone tries to sell.';
  @override
  String get cataloguePaneHelp =>
      'The menu is cached so the till can sell before it has ever been online '
      'again. It refreshes in the background while trading.';
  @override
  String get readMenu => 'Check the menu';
  @override
  String get readMenuAgain => 'Check again';
  @override
  String get cataloguePaneHelpOffline =>
      'This reads the menu already on this machine — nothing is downloaded. '
      'An empty menu is normal on a new till: build it in Management once '
      'setup is finished.';
  @override
  String licenceModeChanged(Object chosen, Object landed) =>
      'This licence does not cover $chosen, so the terminal was set to '
      '$landed. Ask for a licence covering $chosen if that is what you need.';
  @override
  String catalogueDownloadFailed(Object error) =>
      'Catalogue download failed: $error';
  @override
  String get summaryLanguage => 'Language';
  @override
  String get summaryConnection => 'Connection';
  @override
  String get summaryServer => 'Server';
  @override
  String get summaryThisMachine => 'This machine';
  @override
  String get summaryUpstream => 'Upstream';
  @override
  String get summaryRestaurant => 'Restaurant';
  @override
  String get summaryBranch => 'Branch';
  @override
  String get summaryTerminal => 'Terminal';
  @override
  String get summaryPrinter => 'Printer';
  @override
  String get summaryNoPrinter => 'None — receipts will queue';
  @override
  String get summaryCashDrawer => 'Cash drawer';
  @override
  String get summaryScanner => 'Scanner';
  @override
  String get summaryAttached => 'Attached';
  @override
  String get summaryMenu => 'Menu';
  @override
  String summaryItemsCached(int items) => '$items items cached';
  @override
  String get summaryLicence => 'Licence';
  @override
  String get summaryHelp =>
      'You can change any of this later in Settings, except the terminal id.';
  @override
  String get notSet => '—';
  @override
  String get resetTerminal => 'Reset terminal';
  @override
  String get resetTerminalTitle => 'Reset this terminal?';
  @override
  String get resetTerminalBody =>
      'Setup runs again: branch, till name, database address and password. '
      'Sales already recorded are not touched — they are in the database, not '
      'on this machine. The terminal id is kept, so the licence stays valid.';
  @override
  String get resetTerminalShiftOpen =>
      'Close the open shift before resetting. Its drawer has not been counted yet.';
  @override
  String get resetTerminalShiftUnknown =>
      'Could not verify whether a shift is open. Check the database connection and try again.';
  @override
  String get resetTerminalConfirm => 'Reset and run setup';

  @override
  String get terminalRejectedTitle => 'This terminal is no longer recognised';
  @override
  String get terminalRejectedBody =>
      'The platform has stopped accepting this till\'s credential — it was '
      'removed, or paired somewhere else. Selling still works and nothing is '
      'lost, but nothing reaches the platform until it is set up again.';
  @override
  String get terminalRejectedQueued =>
      '{count} sale(s) waiting to be sent. They are held safely and will go '
      'once this terminal is paired again.';

  @override
  String get forceResetTitle => 'Delete this terminal and set it up again?';
  @override
  String get forceResetBody =>
      'This till\'s setup is removed from this machine — tenant, branch, '
      'terminal and its credential. The wizard starts from the beginning and '
      'you can pair it against a different account. Nothing on the platform '
      'is deleted.';
  @override
  String get forceResetShiftOpen =>
      '{ref} is still open. It will not be closed or counted, and its drawer '
      'will never be reconciled.';
  @override
  String get forceResetQueued =>
      '{count} sale(s) have not reached the platform. They stay on this '
      'machine but nothing will send them once the credential is gone.';
  @override
  String get forceResetConfirm => 'Delete and set up again';

  @override
  String get settings => 'Settings';
  @override
  String get syncNow => 'Sync now';
  @override
  String get management => 'Management';
  @override
  String get windowMenu => 'Window';

  @override
  String get capOperate => 'Sell at the till';
  @override
  String get capCatalogView => 'See the menu';
  @override
  String get capCatalogManage => 'Add and change menu items and prices';
  @override
  String get capStaffManage => 'Add staff, set roles and reset PINs';
  @override
  String get capTerminalManage => 'Register and reset terminals';
  @override
  String get capSettingsManage => 'Change restaurant settings and tax';
  @override
  String get capDiscountApply => 'Apply a discount';
  @override
  String get capPriceOverride => 'Override a price';
  @override
  String get capOrderVoid => 'Void an order or a sent line';
  @override
  String get capOrderItemCancel => 'Remove an item before the kitchen sees it';
  @override
  String get capOrderItemVoid => 'Remove an item the kitchen has already made';
  @override
  String get capOrderViewAll => 'See every order this branch has taken';
  @override
  String get capOrderRefund => 'Refund a sale';
  @override
  String get capReceiptReprint => 'Reprint a receipt';
  @override
  String get capShiftOpen => 'Open a shift';
  @override
  String get capShiftClose => 'Close a shift and count the drawer';
  @override
  String get capCashMovement => 'Cash in, cash out and petty expenses';
  @override
  String get capReportsView => 'See reports';
  @override
  String get capBackupManage => 'Back up and restore the database';

  @override
  String get capGroupSelling => 'Selling';
  @override
  String get capGroupMoney => 'Money and corrections';
  @override
  String get capGroupDrawer => 'The drawer';
  @override
  String get capGroupBackOffice => 'Back office';

  @override
  String get listAnd => ' and ';
  @override
  String get listSeparator => ', ';

  @override
  String refusalNotPermitted(String capability) =>
      'You need permission to $capability.';
  @override
  String refusalRoleStillHeld(String names) =>
      'This role is still held by $names. Move them to another role first.';
  @override
  String get refusalRoleIsSystemDefined =>
      'This is one of the roles the installer created. It can be renamed and '
      'its permissions changed, but not deleted — a restaurant with no roles '
      'left has nobody who can create one.';
  @override
  String refusalUserSeatsExhausted(int maxUsers) =>
      'This licence covers $maxUsers user '
      '${maxUsers == 1 ? 'account' : 'accounts'}, and they are all in use. '
      'Disable somebody who has left, or ask your supplier for a licence with '
      'more.';
  @override
  String refusalUsernameTaken(String username) =>
      '"$username" is already used by somebody here. Usernames have to be '
      'unique, because that is what makes a PIN resolve to one person.';
  @override
  String get refusalWouldLockEveryoneOut =>
      'This is the last account that can manage staff. Give somebody else that '
      'permission first, or nobody will be able to get back into this screen.';
  @override
  String get refusalEditedElsewhere =>
      'Somebody changed this from another till while you were editing. Close '
      'and reopen to see what it says now.';
  @override
  String get refusalAdministratorCredentialRequired =>
      'The back office needs its own database password, and this session has '
      'not been given one. Close this screen and open Management again to '
      'enter it.';
  @override
  String get refusalNoDatabaseConfigured =>
      'This terminal has no branch database yet, so there is nothing to '
      'manage. Finish setup first.';
  @override
  String get refusalOwnerMustKeepEverything =>
      'The owner role keeps every permission. If it could lose one, a '
      'restaurant could reach a state where nobody is able to grant it back.';
  @override
  String refusalCashiersAreNotAdministrators(String capabilities) =>
      'A cashier role cannot include $capabilities. Use a supervisor or '
      'manager role for that.';

  @override
  String get backToTill => 'Back to the till';
  @override
  String get paneStaff => 'Staff';
  @override
  String get paneStaffBlurb => 'Who works here, and what they may do';
  @override
  String get paneMenu => 'Menu';
  @override
  String get paneMenuBlurb => 'Categories, items and what they cost';
  @override
  String get paneRoles => 'Roles';
  @override
  String get paneRolesBlurb => 'The permissions behind each job title';
  @override
  String get paneActivity => 'Activity';
  @override
  String get paneActivityBlurb => 'What was changed, by whom';
  @override
  String get pinCannotOpenManagement => 'That PIN cannot open Management.';
  @override
  String get managementPinHelp =>
      'Enter the PIN of somebody who may manage staff.';
  @override
  String get managementPinRetryHelp =>
      'Try a manager or supervisor PIN, or go back to the till.';
  @override
  String cannotManageStaff(String name) => '$name cannot manage staff.';
  @override
  String get backOfficePassword => 'Back office password';
  @override
  String backOfficePasswordHelp(String name) =>
      'Signed in as $name. Changing staff, roles and the menu runs on a '
      'database account of its own, so the till\'s cannot. It is asked for '
      'once each session and never saved on this machine.';
  @override
  String backOfficeAuthFailed(String user) =>
      'PostgreSQL rejected that password for "$user".';
  @override
  String get backOfficeUnreachable =>
      'The database did not answer. The till can still sell; only the back '
      'office needs this connection.';
  @override
  String get backOfficeRefused =>
      'The database refused the back office connection.';
  @override
  String get checking => 'Checking…';
  @override
  String get openManagement => 'Open Management';

  @override
  String get addSomebody => 'Add somebody';
  @override
  String staffCount(int active, int total) =>
      '$active active · $total in total';
  @override
  String staffCountLicensed(int active, int total, int licensed) =>
      '$active of $licensed licensed · $total in all';
  @override
  String get notSaved => 'Not saved';
  @override
  String get close => 'Close';
  @override
  String get you => 'you';
  @override
  String extraCapabilities(int count) => '+$count extra';
  @override
  String get resetPin => 'Reset PIN';
  @override
  String newPinFor(String name) => 'New PIN for $name';
  @override
  String get disable => 'Disable';
  @override
  String get enable => 'Enable';
  @override
  String get noRole => 'no role';
  @override
  String get fieldName => 'Name';
  @override
  String get fieldUsername => 'Username';
  @override
  String get fieldPin => 'PIN';
  @override
  String get fieldRole => 'Role';
  @override
  String get add => 'Add';
  @override
  String get setPin => 'Set PIN';
  @override
  String get nameAndUsernameRequired =>
      'A name and a username, both. The username is what makes the PIN resolve '
      'to one person.';
  @override

  @override
  String get noRolesYet =>
      'No roles on this branch server yet. Run bin/pos_migrate.dart to create '
      'them.';
  @override
  String permissionCount(int held, int total) => '$held of $total permissions';
  @override
  String get createdByInstaller => ' · created by the installer';
  @override
  String get discard => 'Discard';
  @override
  String get save => 'Save';

  @override
  String get nothingRecordedYet =>
      'Nothing recorded on this branch server yet. Every change to staff, '
      'roles, prices and settings lands here.';
  @override
  String approvedByLine(String actor, String approver) =>
      '$actor, approved by $approver';

  @override
  String get supervisorApproval => 'Supervisor approval';
  @override
  String supervisorApprovalHelp(String action) =>
      '$action. A supervisor enters their PIN — both names go on the record.';
  @override
  String get pinCannotApprove => 'That PIN cannot approve this.';
  @override
  String get notPermittedTitle => 'Not permitted';
  @override
  String notPermittedBody(String capability) =>
      'This needs the "$capability" permission, which no supervisor can lend '
      'at the till. A manager can grant it in Management → Staff.';

  @override
  String get menuComesFromPlatform =>
      'This terminal takes its menu from the platform.';
  @override
  String menuSummary(int categories, int items) =>
      '$categories categories · $items items';
  @override
  String get noCategoriesYet =>
      'No categories yet. Add one, then add what goes in it.';
  @override
  String get nothingInCategoryYet => 'Nothing in this category yet.';
  @override
  String get addCategory => 'Add category';
  @override
  String get addItem => 'Add item';
  @override
  String get rename => 'Rename';
  @override
  String get takeOffTheRail => 'Take off the rail';
  @override
  String get edit => 'Edit';
  @override
  String get offSale => 'Off sale';
  @override
  String get backOnSale => 'Back on';
  @override
  String get newCategory => 'New category';
  @override
  String get renameCategory => 'Rename category';
  @override
  String get newItem => 'New item';
  @override
  String get editItem => 'Edit item';
  @override
  String get fieldNameArabic => 'Name in Arabic';
  @override
  String get fieldPrice => 'Price';
  @override
  String get fieldSku => 'SKU';
  @override
  String optionalField(String label) => '$label · optional';
  @override
  String get fieldOfferPrice => 'Offer price';
  @override
  String get rateIsNotANumber => 'A rate must be a number, and not below zero.';
  @override
  String get priceIsNotANumber => 'The price is not a number.';
  @override
  String get offerPriceIsNotANumber => 'The offer price is not a number.';
}

/// Arabic.
///
/// Translated for a cashier standing at a till, not for a manual: short
/// imperatives, the vocabulary restaurants in the region actually use
/// (وردية, درج, تيك أواي), and no transliterated English where a normal Arabic
/// word exists. Product and staff names are never translated — they arrive from
/// the catalogue with their own `name_ar`.
final class ArStrings extends AppStrings {
  const ArStrings();

  @override
  String get languageCode => 'ar';
  @override
  TextDirection get direction => TextDirection.rtl;
  @override
  String get languageName => 'العربية';

  @override
  String get reasonRequiredBadge => 'السبب مطلوب';
  @override
  String get reasonOptionalBadge => 'السبب اختياري';
  @override
  String get reasonNote => 'ملاحظة';
  @override
  String get reasonNoteHint => 'أي تفصيل يستحق التسجيل';
  @override
  String get reasonRequiredHelp =>
      'يُسجَّل السبب مع هذا الإجراء ويمكن الرجوع إليه في التقارير.';
  @override
  String get reasonOptionalHelp =>
      'السبب اختياري هنا. وما تكتبه يُحفظ مع السجل.';
  @override
  String get reasonNeedsNoteHelp => 'هذا السبب يحتاج إلى ملاحظة.';
  @override
  String get chooseAReason => 'اختر سببًا';
  @override
  String get cannotBeUndone => 'لا يمكن التراجع عنه';
  @override
  String get amountMicroLabel => 'المبلغ';
  @override
  String get destructiveKeyHint =>
      'Esc يُبقيه · زر التأكيد غير محدَّد افتراضيًا';
  @override
  String get approvalRequired => 'يلزم اعتماد';
  @override
  String get approvalAction => 'الإجراء';
  @override
  String get approvalRequestedBy => 'بطلب من';
  @override
  String get approvalPin => 'رمز المدير';
  @override
  String get approvalAboveLimit => 'أعلى من الحد المسموح';
  @override
  String get approvalDone => 'تم';
  @override
  String wrongPinAttemptsLeft(int attempts) => attempts == 1
      ? 'رمز غير صحيح. بقيت محاولة واحدة.'
      : 'رمز غير صحيح. بقيت $attempts محاولات.';
  @override
  String approvalRecorded(String approver, String requester) =>
      'اعتمد $approver هذا الإجراء بطلب من $requester. الاسمان مسجَّلان.';
  @override
  String get discountTitle => 'خصم';
  @override
  String get discountWholeOrder => 'الطلب كاملًا';
  @override
  String get discountThisLine => 'هذا السطر';
  @override
  String get discountPresets => 'المتاح هنا';
  @override
  String get discountCustom => 'أو اكتب خصمًا';
  @override
  String get discountPercent => 'نسبة';
  @override
  String get discountAmount => 'مبلغ';
  @override
  String get discountNoneOffered =>
      'لا توجد خصومات مُعدّة لهذا. ما زال بإمكانك كتابة خصم.';
  @override
  String get discountRemove => 'إزالة الخصم';
  @override
  String get discountApplyAction => 'تطبيق الخصم';
  @override
  String get discountNewTotal => 'الإجمالي الجديد';
  @override
  String get discountNotApplicable => 'هذا الخصم غير متاح على هذا الطلب الآن.';
  @override
  String get discountNeedsCustomer => 'هذا الخصم يحتاج إلى عميل على الطلب.';
  @override
  String get discountAlreadyOn => 'يوجد خصم هنا بالفعل. أزِله أولًا.';
  @override
  String get discountNothingToDiscount => 'لا يوجد ما يمكن خصمه.';
  @override
  String discountAboveLimitNote(String limit, String requested) =>
      'حد الخصم اليدوي هنا $limit. وهذا الخصم $requested.';
  @override
  String discountApprovalAct(String amount) => 'خصم $amount';
  @override
  String approvedByShort(String approver) => 'باعتماد $approver';
  @override
  String get cancelLineAction => 'حذف السطر';
  @override
  String get voidLineAction => 'إلغاء السطر';
  @override
  String get keepLineAction => 'الإبقاء عليه';
  @override
  String get lineVoidedChip => 'ملغى';
  @override
  String get cancelLineNothingMade =>
      'لم يُحضَّر شيء بعد، لذا سيُحذف من الفاتورة فقط.';
  @override
  String cancelLineTitle(String item) => 'حذف $item؟';
  @override
  String voidLineTitle(String item) => 'إلغاء $item؟';
  @override
  String voidLineConsequenceRemoved(String amount) =>
      'يخرج السطر من الفاتورة ولن يُحتسب $amount.';
  @override
  String get voidLineConsequenceKitchen =>
      'المطبخ حضّر هذا بالفعل. هذا هدر، ويُسجَّل على أنه هدر.';
  @override
  String get voidLineConsequenceIrreversible =>
      'لا يمكن التراجع عن هذا. يبقى السطر على الفاتورة مُعلَّمًا حتى يمكن أن يُعرض على العميل ما حدث.';
  @override
  String get voidOrderAction => 'إلغاء الطلب';
  @override
  String get keepOrderAction => 'الإبقاء على الطلب';
  @override
  String get clearTicketTitle => 'مسح هذه الفاتورة؟';
  @override
  String get clearTicketNothingSent =>
      'لم يُرسَل شيء إلى المطبخ، لذا لن يُسجَّل هذا في أي مكان.';
  @override
  String voidOrderTitle(String reference) => 'إلغاء $reference؟';
  @override
  String voidOrderConsequenceBill(String amount) =>
      'تُلغى الفاتورة بالكامل بمبلغ $amount ولا يُحتسب شيء.';
  @override
  String get voidOrderConsequenceKitchen =>
      'كل ما أُرسل إلى المطبخ يُعد هدرًا، ويُسجَّل على أنه هدر.';
  @override
  String get voidOrderConsequenceRecorded =>
      'لا يمكن التراجع عن هذا. يُسجَّل الطلب كملغى، باسمك وبالسبب الذي ذكرته.';
  @override
  String voidOrderRecorded(String invoice) => 'أُلغي وسُجِّل باسم $invoice';
  @override
  String get voidCouldNotBeRecorded =>
      'تعذّر تسجيل ذلك، لذا ما زالت الفاتورة هنا. حاول مرة أخرى.';

  @override
  String get orderHistoryTitle => 'الطلبات';
  @override
  String get orderHistoryToday => 'اليوم';
  @override
  String get orderHistoryLast7Days => 'آخر ٧ أيام';
  @override
  String get orderHistoryLast30Days => 'آخر ٣٠ يومًا';
  @override
  String get orderHistorySearchHint => 'رقم الفاتورة أو الطاولة';
  @override
  String get orderHistoryAllStatuses => 'كل الحالات';
  @override
  String get orderHistoryAllTypes => 'كل الأنواع';
  @override
  String get orderHistoryEveryone => 'الجميع';
  @override
  String orderHistoryCount(int count) =>
      count == 1 ? 'طلب واحد' : '$count طلبات';
  @override
  String orderHistoryTruncated(int limit) =>
      'يُعرض أحدث $limit طلبًا. ضيّق نطاق التاريخ للرجوع أبعد.';
  @override
  String get orderHistoryEmpty => 'لا توجد طلبات في هذه الفترة.';
  @override
  String get orderHistoryEmptyFiltered => 'لا توجد طلبات تطابق هذه المرشحات.';
  @override
  String get orderHistoryClearFilters => 'مسح المرشحات';
  @override
  String get orderHistoryPickAnOrder => 'اختر طلبًا لعرضه.';
  @override
  String get orderHistoryUnavailable =>
      'تعذّرت قراءة السجل من قاعدة بيانات الفرع.';
  @override
  String get orderHistoryNotPermitted => 'ليس لديك صلاحية للاطلاع على طلبات الفرع.';
  @override
  String get orderColumnInvoice => 'الفاتورة';
  @override
  String get orderColumnTime => 'الوقت';
  @override
  String get orderColumnType => 'النوع';
  @override
  String get orderColumnWhere => 'الطاولة';
  @override
  String get orderColumnStaff => 'الموظف';
  @override
  String get orderColumnTotal => 'الإجمالي';
  @override
  String get orderColumnStatus => 'الحالة';
  @override
  String get orderDetailLines => 'الأصناف';
  @override
  String get orderDetailPayments => 'طريقة الدفع';
  @override
  String get orderDetailDiscounts => 'الخصومات';
  @override
  String get orderDetailNoPayments => 'لم يُحصَّل أي مبلغ.';
  @override
  String get orderDetailSubtotal => 'المجموع الفرعي';
  @override
  String get orderDetailDiscount => 'الخصم';
  @override
  String get orderDetailService => 'الخدمة';
  @override
  String get orderDetailVat => 'ضريبة القيمة المضافة';
  @override
  String get orderDetailTotal => 'الإجمالي';
  @override
  String get orderDetailServedBy => 'قدّمه';
  @override
  String get orderDetailServedByUnknown => 'غير مسجَّل';
  @override
  String orderDetailVoidedBy(String name) => 'ألغاه $name';
  @override
  String get orderDetailVoidedLine => 'ملغى';
  @override
  String orderDetailGuests(int count) => count == 1 ? 'ضيف واحد' : '$count ضيوف';
  @override
  String orderDetailApprovedBy(String name) => 'اعتمده $name';
  @override
  String get orderActionsComingWithRefunds =>
      'إعادة الطباعة والاسترجاع تأتيان مع مسار الاسترجاع.';
  @override
  String get orderStatusDraft => 'مسودة';
  @override
  String get orderStatusOpen => 'مفتوح';
  @override
  String get orderStatusSentToKitchen => 'في المطبخ';
  @override
  String get orderStatusReady => 'جاهز';
  @override
  String get orderStatusPaid => 'مدفوع';
  @override
  String get orderStatusClosed => 'مغلق';
  @override
  String get orderStatusVoided => 'ملغى';
  @override
  String get orderStatusCancelled => 'مُلغى قبل الإرسال';
  @override
  String get orderStatusRefunded => 'مسترجع';
  @override
  String get orderStatusPartiallyRefunded => 'مسترجع جزئيًا';

  @override
  String get refundAction => 'استرجاع';
  @override
  String refundTitle(String invoice) => 'استرجاع $invoice';
  @override
  String get refundRemaining => 'المتبقي للاسترجاع';
  @override
  String get refundByItems => 'حسب الصنف';
  @override
  String get refundByAmount => 'حسب المبلغ';
  @override
  String get refundAmountLabel => 'المبلغ المُعاد';
  @override
  String get refundReturnTo => 'يُعاد إلى';
  @override
  String get refundSubtotal => 'المجموع الفرعي';
  @override
  String get refundDiscount => 'الخصم';
  @override
  String get refundService => 'الخدمة';
  @override
  String get refundVat => 'ضريبة القيمة المضافة';
  @override
  String get refundTotal => 'الاسترجاع';
  @override
  String refundConfirm(String amount) => 'استرجاع $amount';
  @override
  String get refundNothingSelected => 'اختر ما سيُعاد أولًا.';
  @override
  String get refundAlreadyRefunded => 'مسترجع بالفعل';
  @override
  String refundIssued(String amount) => 'تم استرجاع $amount';
  @override
  String get refundCouldNotBeIssued =>
      'تعذّر تسجيل ذلك، ولم يخرج أي مبلغ. حاول مرة أخرى.';
  @override
  String get refundNeedsApproval => 'يجب أن يعتمد مشرف هذا المبلغ.';
  @override
  String get refundItemsRemaining => 'متبقٍ';
  @override
  String get refundDisabled => 'الاسترجاع موقوف في هذا المطعم.';
  @override
  String refundOutsideWindow(String window) =>
      'هذه الفاتورة خارج مدة الاسترجاع ($window).';
  @override
  String get refundNothingLeft => 'لا يوجد ما يُسترجع في هذا الطلب.';
  @override
  String refundMoreThanRemains(int asked, int remaining) =>
      'طلبت $asked، والمتبقي $remaining.';
  @override
  String refundAboveLimit(String limit) =>
      'هذا يتجاوز حد الاسترجاع البالغ $limit. لا يمكن لأحد على الكاشير تجاوزه.';
  @override
  String refundAboveRemaining(String remaining) =>
      'المتبقي في هذا الطلب هو $remaining فقط.';
  @override
  String get refundReasonNeeded => 'اذكر سبب الاسترجاع.';
  @override
  String get refundTenderNeeded => 'حدّد كيف يُعاد المبلغ.';
  @override
  String get refundReceiptRequiredNote =>
      'يطلب هذا المطعم الفاتورة الأصلية.';
  @override
  String get refundWindowSameShift => 'نفس الوردية';
  @override
  String get refundWindowSameDay => 'نفس اليوم';
  @override
  String get refundWindow7Days => '٧ أيام';
  @override
  String get refundWindow30Days => '٣٠ يومًا';
  @override
  String get refundWindowUnlimited => 'بلا حد';
  @override
  String get refundsAlreadyGiven => 'مسترجع';
  @override
  String refundGivenBy(String name) => 'بواسطة $name';

  @override
  String get priceOverrideAction => 'تغيير السعر';
  @override
  String get priceOverrideChip => 'سعر';
  @override
  String priceOverrideTitle(String item) => 'تغيير سعر $item';
  @override
  String get priceOverrideMenuPrice => 'سعر المنيو';
  @override
  String get priceOverrideNewPrice => 'السعر الجديد للوحدة';
  @override
  String get priceOverrideLineTotal => 'إجمالي البند';
  @override
  String get priceOverrideRestore => 'العودة إلى سعر المنيو';
  @override
  String get priceOverrideNothingSelected => 'اختر بندًا من الفاتورة أولًا.';
  @override
  String get priceOverrideUnchanged => 'هذا هو السعر الحالي بالفعل.';
  @override
  String get priceOverrideBelowZero => 'لا يمكن أن يقل السعر عن صفر.';
  @override
  String priceOverrideAboveLimit(String reduction, String limit) =>
      'هذا يخصم $reduction، وحدّك $limit. يمكن لمشرف اعتماده.';
  @override
  String get priceOverrideNotPermitted => 'ليس لديك صلاحية لتغيير السعر.';
  @override
  String priceOverrideApplied(String price) => 'تم تغيير السعر إلى $price';

  @override
  String get cancel => 'إلغاء';
  @override
  String get done => 'تم';
  @override
  String get back => 'رجوع';
  @override
  String get backArrow => '→ رجوع';
  @override
  String get continueLabel => 'متابعة';
  @override
  String get importLabel => 'استيراد';
  @override
  String get activate => 'تفعيل';
  @override
  String get none => 'لا يوجد';

  @override
  String get orderTypeDineIn => 'صالة';
  @override
  String get orderTypeTakeaway => 'تيك أواي';
  @override
  String get orderTypeDelivery => 'دليفري';
  @override
  String get orderTypeDriveThru => 'من السيارة';

  @override
  @override
  String outOfStock(String product) =>
      'صنف $product غير متاح — موقوف في المنيو.';
  @override
  String get nothingToCharge => 'لا يوجد ما يُحصَّل.';
  @override
  String get ticketVoided => 'تم إلغاء الطلب.';
  @override
  String get ticketStillOpen =>
      'ما زال هناك طلب مفتوح على هذا الجهاز. حصِّل قيمته أو ألغِه قبل تقفيل '
      'الوردية.';
  @override
  String get roundSentToKitchen => 'تم إرسال الجولة إلى المطبخ.';
  @override
  String get drawerOpenedToast => 'تم فتح درج النقدية · F10';
  @override
  String get openTicketsNotBuilt => 'الطلبات المفتوحة — غير متاحة بعد.';
  @override
  String get customAmountNotBuilt => 'مبلغ مخصص — غير متاح بعد.';
  @override
  String get searchHint => 'امسح الباركود أو ابحث عن صنف / كود';
  @override
  String get customAmount => 'مبلغ مخصص';
  @override
  String get shortcutStrip => 'F2 بحث   F4 تعليق   F9 دفع   ESC إغلاق';
  @override
  String matchCount(int count) => '$count نتيجة';
  @override
  String catalogCached(int items) => 'المنيو محفوظ · $items صنف';
  @override
  String get noItemsMatch => 'لا توجد أصناف مطابقة.';
  @override
  String get outOfStockBadge => 'منتهي';

  @override
  String get openDrawer => 'فتح الدرج';
  @override
  String get syncingWithPlatform => 'جارٍ المزامنة مع المنصة…';
  @override
  String get syncStatusUnavailable => '● تعذّرت معرفة حالة المزامنة';
  @override
  String syncOfflineQueued(int? queued) =>
      '● غير متصل · ${queued ?? '—'} في الانتظار';
  @override
  String get syncChecking => '● جارٍ التحقق من المزامنة…';
  @override
  String syncSyncedQueued(int queued) =>
      '● تمت المزامنة · $queued في الانتظار';
  @override
  String get lock => 'قفل';
  @override
  String get closeShift => 'تقفيل الوردية';
  @override
  String get noShift => 'لا توجد وردية';

  @override
  String get categories => 'الأقسام';
  @override
  String get allItems => 'كل الأصناف';
  @override
  String get openTickets => 'الطلبات المفتوحة';
  @override
  String get tables => 'الطاولات';

  @override
  String get noTableYet => 'لم تُحدَّد طاولة';
  @override
  String seatedTable(String table, int? guests) =>
      guests == null ? table : '$table · $guests ضيف';
  @override
  String walkIn(String orderType) => '$orderType · بدون طاولة';
  @override
  String cartStatusLine(String cashier, bool online) =>
      'مفتوح · $cashier · ${online ? 'متصل' : 'غير متصل'}';
  @override
  String get changeTable => 'تغيير الطاولة';
  @override
  String get cartEmptyHelp =>
      'الطلب فارغ. اضغط على أي صنف، أو اضغط F2 واكتب للبحث. الأصناف التي لها '
      'إضافات تفتح نافذة أولاً.';
  @override
  String alreadySent(int lines) => 'أُرسل بالفعل · $lines بند';
  @override
  String get newRound => 'جولة جديدة';
  @override
  String get subtotal => 'المجموع';
  @override
  String servicePercent(String percent) => 'خدمة $percent٪';
  @override
  String vatPercent(String percent) => 'ضريبة $percent٪';
  @override
  String get totalCaps => 'الإجمالي';
  @override
  String get closeTableCta => 'إقفال الطاولة';
  @override
  String get chargeCta => 'تحصيل';
  @override
  String get sendRoundKey => 'إرسال الجولة  F4';
  @override
  String get parkKey => 'تعليق  F4';
  @override
  String get voidTicket => 'إلغاء الطلب';

  @override
  String modifierGroupFull(String group, int max) =>
      'مجموعة $group تسمح بـ $max على الأكثر.';
  @override
  String pickGroupFirst(String group) => 'اختر $group أولاً.';
  @override
  String requiredPick(int count) => 'مطلوب · اختر $count';
  @override
  String maxPick(int count) => 'حتى $count';
  @override
  String get addToTicket => 'إضافة إلى الطلب';

  @override
  String get tenderCash => 'نقدي';
  @override
  String get tenderCard => 'بطاقة';
  @override
  String get tenderWallet => 'محفظة · إنستاباي';
  @override
  String get tenderOnAccount => 'على الحساب';
  @override
  String get payment => 'الدفع';
  @override
  String get backToTicket => '→ رجوع إلى الطلب';
  @override
  String lineCount(int lines) => '$lines بند';
  @override
  String get amountDue => 'المبلغ المستحق';
  @override
  String get remainingDue => 'المتبقي';
  @override
  String totalIs(String amount) => 'الإجمالي $amount';
  @override
  String paidOfTotal(String paid, String total, int tenders) =>
      'دُفع $paid من $total · $tenders دفعة';
  @override
  String get tendersHeading => 'الدفعات';
  @override
  String get noTenderYet =>
      'لم تُسجَّل دفعة بعد — اختر طريقة الدفع، واكتب المبلغ أو اضغط أحد أزرار '
      'النقد السريع.';
  @override
  String get amount => 'المبلغ';
  @override
  String get exact => 'بالضبط';
  @override
  String get clear => 'مسح';
  @override
  String get takePayment => 'تحصيل الدفعة';
  @override
  String get enterAmountAboveZero => 'أدخل مبلغاً أكبر من صفر.';

  @override
  String get taxRegistrationLine => 'سجل ضريبي 000-000-000';
  @override
  String get provisionalInvoice => 'مبدئية';
  @override
  String get receiptSubtotal => 'المجموع';
  @override
  String receiptService(String percent) => 'خدمة $percent٪';
  @override
  String receiptVat(String percent) => 'ضريبة $percent٪';
  @override
  String get receiptTotal => 'الإجمالي';
  @override
  String get receiptPaid => 'المدفوع';
  @override
  String get receiptChange => 'الباقي';
  @override
  String get receiptQueuedOffline => 'في الانتظار — ستُرسَل عند الاتصال';
  @override
  String get receiptSynced => 'أُرسلت إلى XOrder';
  @override
  String get receiptThanks => 'شكراً لزيارتكم';
  @override
  String get receiptTaxFromDevice => 'الضريبة من إعدادات الجهاز';
  @override
  String get newSale => 'بيع جديد';
  @override
  String get printAndNew => 'طباعة وبيع جديد';
  @override
  String get receiptQueuedToast => 'أُرسلت الفاتورة إلى الطابعة الافتراضية.';

  @override
  String get pickATable => 'اختر طاولة';
  @override
  String get pickATableHelp =>
      'اضغط على طاولة لفتح فاتورة جديدة أو للإضافة إلى فاتورة قائمة.';
  @override
  String get floorHasNoTables =>
      'لا توجد طاولات في هذا الفرع بعد. يضيفها المدير من الإدارة، قسم الصالة.';
  @override
  String get sellWithoutTable => 'بيع بدون طاولة';
  @override
  String legendFree(int count) => 'فاضية $count';
  @override
  String legendOccupied(int count) => 'مشغولة $count';
  @override
  String legendBillAsked(int count) => 'طلبت الحساب $count';
  @override
  String get tableFree => 'فاضية';
  @override
  String tableLineCount(int lines) => '$lines بند';
  @override
  String get tableBillAsked => 'طلبت الحساب';
  @override
  String tableSeats(int seats) => '$seats مقعد';
  @override
  String tableOpenWith(String total) => 'مفتوحة · $total';
  @override
  String tableBillRequested(String total) => 'طلبت الحساب · $total';

  @override
  String get terminalLocked => 'الجهاز مقفل';
  @override
  String get wrongPin => 'رقم سري خاطئ — حاول مرة أخرى';
  @override
  String enterPinFor(String name) => '$name · أدخل الرقم السري';

  @override
  String get pointOfSale => 'نقطة بيع';
  @override
  String get renewLicence => 'تجديد الترخيص';
  @override
  String get manageLicence => 'إدارة الترخيص';
  @override
  String get licenceRequired => 'الترخيص مطلوب';
  @override
  String get startShift => 'بدء الوردية';
  @override
  String resumeShift(String reference) => 'متابعة $reference';
  @override
  String get cashUpStillAvailable =>
      'تقفيل الوردية السابقة وإعادة طباعة فواتيرها ما زالا متاحين.';
  @override
  String get startShiftHelp =>
      'سيُطلب منك رقمك السري والنقدية الموجودة في الدرج.';
  @override
  String resumeShiftHelp(String openedBy) =>
      'فتحها $openedBy. الدرج لم يُقفل، فالوردية ما زالت لك.';
  @override
  String get enterKeyCap => 'ENTER';
  @override
  String get tenantCell => 'المطعم';
  @override
  String get branchCell => 'الفرع';
  @override
  String get terminalCell => 'الجهاز';
  @override
  String get catalogCell => 'المنيو';
  @override
  String get catalogSyncing => 'جارٍ التحميل…';
  @override
  String catalogCachedItems(int items) => 'محفوظ · $items صنف';

  @override
  String get signIn => 'تسجيل الدخول';
  @override
  String get openTheDrawer => 'افتح الدرج';
  @override
  String get signInHelp => 'أدخل رقمك السري. ستُفتح الوردية باسمك.';
  @override
  String countTheDrawerHelp(String name) =>
      '$name · اعدّ ما في الدرج قبل أن تبدأ.';
  @override
  String get pinNotRecognised => 'هذا الرقم السري غير معروف.';
  @override
  String notPermittedToOpenShift(String name) =>
      '$name غير مصرّح له ببدء وردية.';
  @override
  String get enterOpeningFloat =>
      'أدخل رصيد بداية الوردية، أو 0.00 إذا كان الدرج فارغاً.';
  @override
  String get openShift => 'فتح الوردية';
  @override
  String get openingFloat => 'رصيد البداية';
  @override
  String get emptyDrawer => 'فارغ';
  @override
  String get openingFloatHelp =>
      'هذه هي النقدية الموجودة في الدرج بالفعل. كل فرق عند التقفيل يُحسب منها، '
      'فالتخمين هنا يعني عجزاً أو زيادة لاحقاً.';
  @override
  String closeShiftTitle(String reference) => 'تقفيل $reference';
  @override
  String closeShiftHelp(String openedBy) =>
      'فتحها $openedBy. اعدّ الدرج ثم أكّد.';
  @override
  String closeShiftApproval(String reference) => 'تقفيل $reference وعدّ الدرج';
  @override
  String get countTheDrawer => 'اعدّ الدرج وأدخل الإجمالي.';
  @override
  String get signInBeforeClosing => 'سجّل دخولك قبل تقفيل الوردية.';
  @override
  String get countedInDrawer => 'المعدود في الدرج';
  @override
  String expectedInDrawerHelp(String expected, String float, String taken) =>
      'المتوقع $expected — رصيد بداية $float زائد $taken محصَّلة نقداً.';
  @override
  String get varianceBalances => 'مطابق';
  @override
  String get varianceOver => 'زيادة';
  @override
  String get varianceShort => 'عجز';
  @override
  String shiftClosedTitle(String reference) => 'أُقفلت $reference';
  @override
  String get drawerBalances => 'الدرج مطابق.';
  @override
  String closedWithVariance(String variance) =>
      'سُجِّلت بفرق قدره $variance. الفرق مقيَّد على الوردية، ولم يضع.';
  @override
  String get zSales => 'عدد الفواتير';
  @override
  String get zGrossTaken => 'إجمالي المحصَّل';
  @override
  String zTenderRow(String label, int count) => '  $label × $count';
  @override
  String get zOpeningFloat => 'رصيد البداية';
  @override
  String get zExpectedInDrawer => 'المتوقع في الدرج';
  @override
  String get zCounted => 'المعدود';

  @override
  String get licence => 'الترخيص';
  @override
  String get renewThisTerminal => 'تجديد ترخيص هذا الجهاز';
  @override
  String get licenceKeyHint => 'XORD-0000-0000-0000';
  @override
  String get activateKey => 'تفعيل بالمفتاح';
  @override
  String get importLicenceFile => 'استيراد ملف الترخيص';
  @override
  String get checkForRenewal => 'التحقق من التجديد';
  @override
  String get cannotCheckForRenewal =>
      'هذه النسخة لا تصل إلى خادم التراخيص، فلا تستطيع البحث عن تجديد. '
      'ثبّت ملف الترخيص بدلاً من ذلك.';
  @override
  String get renewalOnlineHelp =>
      'التجديدات المشتراة من المنصّة تصل تلقائياً — يتحقق هذا الجهاز عند بدء '
      'التشغيل وقبل فتح كل وردية. الأزرار أعلاه لتعجيل ذلك فقط.';
  @override
  String get renewalOfflineHelp =>
      'لا يوجد لهذا الجهاز طريق إلى المنصّة، فالتجديدات تصل في صورة ملف. اطلب '
      'ملف ‎.xlic من مورّدك واستورده — التحقق منه لا يحتاج إنترنت.';
  @override
  String get licenceUpdated => 'تم تحديث الترخيص.';
  @override
  String get noRouteToPlatform =>
      'هذا الجهاز غير متصل بمنصّة XOrder، فلا يمكنه التحقق من التجديد. أدخل '
      'المفتاح أو استورد ملف الترخيص بدلاً من ذلك.';
  @override
  String get licenceFileHint => '{"payload": "...", "signature": "..."}';
  @override
  String get capabilityOpenShift => 'فتح وردية جديدة';
  @override
  String get capabilitySell => 'البيع في وردية مفتوحة';
  @override
  String get capabilityCashUp => 'التقفيل وتقارير X/Z';
  @override
  String get capabilityReprint => 'إعادة طباعة فاتورة';
  @override
  String get capabilityExport => 'تصدير البيانات';
  @override
  String get capabilityConfigure => 'تغيير الإعدادات';
  @override
  String daysRemaining(int days) => 'باقٍ $days يوم';
  @override
  String daysPastExpiry(int days) => 'مضى $days يوم على الانتهاء';
  @override
  String get licensedHeadline => 'مرخَّص';
  @override
  String get renewalDueHeadline => 'التجديد مستحق';
  @override
  String get expiredInGraceHeadline => 'منتهٍ — في فترة السماح';
  @override
  String get expiredHeadline => 'منتهٍ';
  @override
  String get notLicensedHeadline => 'غير مرخَّص';
  @override
  String get licenceProblemHeadline => 'مشكلة في الترخيص';

  @override
  String licenceExpiresInDays(int days) => 'ينتهي الترخيص خلال $days يوم.';
  @override
  String licenceGraceRemaining(int days) =>
      'انتهى الترخيص. البيع مستمر $days يوم إضافية — برجاء التجديد.';
  @override
  String get licenceExpiredNewShiftBlocked =>
      'انتهى الترخيص. يمكنك إنهاء الوردية المفتوحة وتقفيلها، لكن لا يمكن بدء '
      'وردية جديدة حتى يُجدَّد.';
  @override
  String licenceTenantMismatch(String licenceTenant, String terminalTenant) =>
      'هذا الترخيص يخص $licenceTenant، بينما هذا الجهاز مُعدّ لـ '
      '«$terminalTenant».';
  @override
  String licenceModeNotCovered(String mode) =>
      'هذا الترخيص لا يغطي التركيبات من نوع «$mode».';
  @override
  String get licenceOtherTerminal => 'هذا الترخيص مسجَّل على جهاز آخر.';
  @override
  String licenceNotYetValid(String date) =>
      'يبدأ هذا الترخيص في $date. راجع تاريخ الجهاز وساعته.';
  @override
  String get licenceFileDamaged => 'ملف الترخيص هذا تالف.';
  @override
  String get noLicenceInstalled => 'لا يوجد ترخيص مثبَّت.';
  @override
  String get licenceUnverifiable =>
      'تعذّر التحقق من ملف الترخيص هذا. اطلب من مورّدك إعادة إصداره.';
  @override
  String get noLicenceServer =>
      'لا يوجد خادم تراخيص للتحقق من المفتاح. اطلب ملف ‎.xlic من مورّدك '
      'واستخدم «تفعيل من ملف».';
  @override
  String get notALicenceFile =>
      'هذا الملف ليس ترخيصاً — المطلوب هو ملف ‎.xlic الذي أرسله مورّدك.';
  @override
  String get licenceKeyNotRecognised => 'مفتاح الترخيص هذا غير معروف.';
  @override
  String licenceKeyNotRecognisedBy(String address) =>
      '$address لا يعرف مفتاح الترخيص هذا. راجع المفتاح — وراجع أيضاً أن هذه هي '
      'المنصة الصحيحة: المفتاح الصادر من منصة أخرى سيُرفض هنا دائماً، مهما كانت '
      'كتابته سليمة.';
  @override
  String licenceServerUnreachable(String address) =>
      'تعذّر الوصول إلى $address، فلا يُعرف شيء عن هذا المفتاح بعد. راجع '
      'الاتصال، أو فعّل من ملف ‎.xlic بدلاً من ذلك — فهو لا يحتاج شبكة إطلاقاً.';
  @override
  String licenceServerRefused(String address, int status) =>
      'ردّ $address بخطأ ($status) بدلاً من الترخيص. المشكلة في المنصة وليست في '
      'مفتاحك. أعد المحاولة بعد قليل، أو فعّل من ملف ‎.xlic.';
  @override
  String get tooManyLicenceAttempts =>
      'محاولات تفعيل كثيرة في وقت قصير. انتظر دقيقة ثم أعد المحاولة — لم يُرفض '
      'المفتاح.';
  @override
  String get licenceRevokedByPlatform =>
      'تم سحب هذا الترخيص. لا خطأ في المفتاح — تواصل مع مورّدك.';

  @override
  String get productWordmark => 'XORDER POS';
  @override
  String get terminalSetup => 'إعداد الجهاز';
  @override
  String get terminalNotSetUp => 'لم يُجهَّز هذا الجهاز بعد.';
  @override
  String get switchToLight => 'التبديل إلى الفاتح';
  @override
  String get switchToDark => 'التبديل إلى الداكن';
  @override
  String stepOf(int step, int total) => 'خطوة $step من $total';
  @override
  String get openTheTill => 'افتح الكاشير';

  @override
  @override
  String get stepSetupType => 'نوع التشغيل';

  @override
  String get stepSetupTypeBlurb =>
      'اختر طريقة تشغيل هذا الجهاز. جهاز السحابة يُزامن كل عملية بيع مع '
      'المنصة، والجهاز غير المتصل يُبقي مبيعاته داخل المطعم. وأيُّهما متاح '
      'يُحدده الترخيص، لا هذه الشاشة.';
  @override
  String get setupTypeOfflineHelp =>
      'يحتفظ هذا الجهاز بمنيوه وموظفيه وقواعد أمواله، ولا تخرج أي مبيعة من '
      'المطعم. ويبقى يتصل بالمنصة لتفعيل الترخيص وتجديده — أو يمكنك تثبيت '
      'ملف ترخيص يدوياً.';
  @override
  String get setupTypeCloudHelp =>
      'المنصة هي مصدر المنيو والموظفين وقواعد الأموال، وكل مبيعة تُزامَن '
      'إليها.';

  @override
  String get stepLanguage => 'اللغة';
  @override
  String get stepLanguageBlurb => 'اختر لغة هذا الجهاز.';
  @override
  String get stepConnection => 'الاتصال';
  @override
  String get stepConnectionBlurb => 'إلى أين يرسل هذا الجهاز مبيعاته؟';
  @override
  String get stepAccount => 'تسجيل الدخول';
  @override
  String get stepFirstAdministrator => 'أول مدير';
  @override
  String get stepFirstAdministratorBlurb =>
      'لا يستطيع أحد فتح هذا الجهاز بعد. أنشئ الشخص الذي سيفعل.';
  @override
  String get stepAccountBlurb => 'حدِّد المطعم والشخص الذي يقوم بالإعداد.';
  @override
  String get stepLicence => 'الترخيص';
  @override
  String get stepLicenceBlurb => 'فعّل هذا الجهاز.';
  @override
  String get stepBranch => 'الفرع';
  @override
  String get stepBranchBlurb => 'في أي فرع هذا الجهاز؟';
  @override
  String get stepTerminal => 'الجهاز';
  @override
  String get stepTerminalBlurb =>
      'سمِّ هذا الكاشير حتى يمكن تمييزه في التقارير.';
  @override
  String get stepHardware => 'الأجهزة';
  @override
  String get stepHardwareBlurb => 'الطابعة ودرج النقدية وقارئ الباركود.';
  @override
  String get stepMoney => 'النقود';
  @override
  String get stepMoneyBlurb => 'أكّد العملة والضريبة ورسوم الخدمة.';
  @override
  String get stepCatalogue => 'المنيو';
  @override
  String get stepCatalogueBlurb => 'حمّل المنيو للعمل بدون إنترنت.';
  @override
  String get stepReady => 'جاهز';
  @override
  String get stepReadyBlurb => 'راجع كل شيء، ثم افتح الكاشير.';

  @override
  String get englishBlurb => 'تخطيط من اليسار إلى اليمين.';
  @override
  String get arabicBlurb =>
      'تخطيط من اليمين إلى اليسار، ويقبل الأرقام العربية.';
  @override
  String get languagePaneHelp =>
      'هذا يضبط واجهة الكاشير فقط. المنيو يُعرض للزبائن باللغات التي ينشرها '
      'المطعم.';

  @override
  String get modeCloud => 'سحابي';
  @override
  String get modeCloudBlurb =>
      'تُرفع المبيعات إلى منصّة XOrder عند توفر الاتصال.';
  @override
  String get modeOffline => 'بدون إنترنت';
  @override
  String get modeOfflineBlurb =>
      'المبيعات تبقى داخل المطعم. لا يخرج سوى الترخيص.';
  @override
  String get modeNotLicensed => 'غير مشمول بهذا الترخيص.';
  @override
  String get notLicensedBadge => 'غير مرخّص';
  @override
  String get syncAutomatic => 'تلقائي';
  @override
  String get syncAutomaticBlurb => 'أرسل المبيعات فور توفر الاتصال.';
  @override
  String get syncManual => 'يدوي';
  @override
  String get syncManualBlurb => 'أرسل المبيعات عندما يختار الموظفون.';
  @override
  String get platformAddress => 'عنوان المنصّة';
  @override
  String get platformCaps => 'المنصة';
  @override
  String get platformAddressHelp =>
      'الوجهة التي يرسل إليها هذا الجهاز مبيعاته. البيع لا ينتظرها أبداً — '
      'قاعدة البيانات المحلية تستقبل البيع أولاً ثم تُفرَّغ قائمة الانتظار.';
  @override
  String get trustWithoutCertificate => 'الوثوق بقاعدة البيانات هذه بدون شهادة';
  @override
  String get trustWithoutCertificateBlurb =>
      'فقط لجهاز على هذه الشبكة المحلية. لا تفعل ذلك أبداً لعنوان عام.';
  @override
  String get theDatabase => 'قاعدة البيانات';
  @override
  String get databaseHost => 'عنوان قاعدة البيانات';
  @override
  String get databaseHostHelp =>
      'الجهاز على هذه الشبكة الذي يحتفظ بقاعدة البيانات التي تشترك فيها كل '
      'الأجهزة.';
  @override
  String get databaseName => 'اسم قاعدة البيانات';
  @override
  String get databasePort => 'المنفذ';
  @override
  String get databaseUser => 'مستخدم قاعدة البيانات';
  @override
  String get databaseUserHelp =>
      'استخدم حساب الكاشير المحدود، لا حساباً بصلاحيات كاملة. هو يحتاج فقط قراءة '
      'المنيو وكتابة المبيعات.';
  @override
  String get databasePassword => 'كلمة مرور قاعدة البيانات';
  @override
  String get databasePasswordHelp =>
      'تُحفظ على هذا الجهاز فقط، ولا تُكتب أبداً في ملف إعدادات الجهاز. سيُطلب '
      'منك إدخالها مرة أخرى إذا أُعيد تثبيت هذا الكاشير.';
  @override
  String get keystoreUnavailable => 'هذا الجهاز لا يستطيع حفظ كلمة المرور';
  @override
  String get keystoreUnavailableHelp =>
      'لم يستجب مخزن بيانات الاعتماد في نظام التشغيل، لذلك ستعمل كلمة المرور '
      'التي تُدخل هنا الآن لكنها ستُفقد بعد إعادة التشغيل، وسيُفتح هذا المعالج '
      'من جديد. يمكن إكمال الإعداد في الحالتين. على macOS افتح قفل سلسلة '
      'المفاتيح، وعلى Windows تحقق من خدمة إدارة بيانات الاعتماد. إذا تكرر '
      'الأمر فقد يحتاج التطبيق إلى إعادة تثبيت من شخص يستطيع توقيعه.';
  @override
  String get machineNowHasDatabase => 'صار لهذا الجهاز قاعدة بيانات.';
  @override
  String get noDatabaseYet => 'لا توجد قاعدة بيانات على هذا الجهاز بعد';
  @override
  String get firstInstallHeading => 'أول تثبيت على هذا الجهاز';
  @override
  String get firstInstallHelp =>
      'يُنشئ قاعدة البيانات وجداولها وأدوار الموظفين الأربعة وأول شخص. اسم '
      'المطعم يأتي من الترخيص. تشغيله مرتين آمن — ما هو موجود يُترك كما هو.';
  @override
  String adminPasswordFor(String user) => 'كلمة مرور $user';
  @override
  String get adminPasswordHelp =>
      'حساب PostgreSQL المسموح له بإنشاء قواعد البيانات — وليس حساب '
      'الكاشير. يُستخدم مرة واحدة هنا، ولا يُكتب على هذا الجهاز.';
  @override
  String get firstPerson => 'أول شخص';
  @override
  String get firstPersonHelp =>
      'المالك. بدون شخص يسجّل الدخول باسمه، لن تجد الخطوة التالية من '
      'تتحقق منه.';
  @override
  String get theirUsername => 'اسم المستخدم';
  @override
  String get theirPin => 'الكود';
  @override
  String get theirPinHelp =>
      'ما يكتبه على الكاشير، من أربعة إلى اثني عشر رقماً. يُحفظ كبصمة '
      'PBKDF2 — لا يمكن قراءته، بل استبداله فقط.';
  @override
  String get buildingDatabase => 'جارٍ البناء…';
  @override
  String get buildTheDatabase => 'ابنِ قاعدة البيانات';

  @override
  String get installLicenceFirst =>
      'ثبّت الترخيص أولاً — فهو الذي يسمّي المطعم صاحب قاعدة البيانات هذه.';
  @override
  String get firstPersonIncomplete =>
      'أول شخص يحتاج اسماً واسم مستخدم وكوداً من أربعة أرقام على الأقل. بدونه '
      'لن يستطيع أحد تسجيل الدخول إلى الكاشير الذي على وشك أن يوجد.';
  @override
  String pinIsExactlyDigits(int length) =>
      'الكود $length أرقام بالضبط. يُكتب على لوحة أرقام عند الكاونتر تُرسله عند '
      'آخر رقم، فالكود الأطول لا يمكن إدخاله أصلًا.';
  @override
  String exactlyDigits(int length) => '$length أرقام بالضبط.';
  @override
  String databaseNameInvalid(String name) =>
      '«$name» لا يصلح اسماً لقاعدة بيانات — أحرف إنجليزية وأرقام وشرطات سفلية '
      'فقط، ويبدأ بحرف. الشرطة العادية هي السبب المعتاد: جرّب '
      '«${name.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_')}».';
  @override
  String permissionDenied(String user, String database) =>
      'قَبِل الخادم دخول «$user» ثم رفض العمل: لا يملك صلاحية إنشاء جداول في '
      '«$database». لا خطأ في كلمة المرور. يحدث هذا عندما يشير الجهاز إلى قاعدة '
      'بيانات أنشأها شخص آخر — على مالكها تسليمها، أو اترك المعالج ينشئ واحدة '
      'خاصة به.';
  @override
  String createdDatabase(String database) => 'أُنشئت $database.';
  @override
  String databaseAlreadyThere(String database) => '$database كانت موجودة.';
  @override
  String get schemaAlreadyCurrent => 'البنية كانت محدّثة بالفعل.';
  @override
  String migrationsApplied(int count) => 'طُبّقت $count ترحيلة.';
  @override
  String restaurantSeeded(String restaurant) =>
      '$restaurant وأول فرع له صارا على هذا الجهاز.';
  @override
  String get rolesAlreadyThere => 'الأدوار كانت موجودة.';
  @override
  String rolesCreated(int count) => 'أُنشئ $count دور من أدوار النظام.';
  @override
  String ownerCreated(String name) => 'أُنشئ $name كمالك.';
  @override
  String ownerAlreadyHere(String username) =>
      '$username كان موجوداً — وتُرك الكود كما هو.';
  @override
  String grantsApplied(String tillRole, String adminRole) =>
      'مُنح $tillRole و$adminRole ما يحتاجه كل منهما.';
  @override
  String bootstrapAuthFailed(String user) =>
      'رفضت PostgreSQL المستخدم «$user» وكلمة المرور هذه. هذا حساب المدير الذي '
      'يُنشئ قاعدة البيانات، وليس حساب الكاشير.';
  @override
  String bootstrapUnreachable(String host, int port) =>
      'لم يردّ شيء على $host:$port. تأكد أن PostgreSQL يعمل على هذا الجهاز.';
  @override
  String bootstrapRefused(Object raw) =>
      'تم الاتصال، لكن قاعدة البيانات رفضت التنفيذ. $raw';
  @override
  String setupIncomplete(String missing) =>
      'ينقص الإعداد $missing. ارجع إلى خطوة الجهاز وسجّل هذا الكاشير، ثم حاول '
      'مرة أخرى.';
  @override
  String get missingTerminalName => 'اسم الجهاز';
  @override
  String get missingRestaurantIdentity => 'هوية المطعم';
  @override
  String get missingBranch => 'الفرع';
  @override
  String get missingBranchPrefix => 'بادئة أرقام فواتير الفرع';
  @override
  String get missingTerminalId => 'رقم الجهاز';
  @override
  String couldNotSaveSetup(Object error) =>
      'تعذّر حفظ إعداد هذا الجهاز: $error';
  @override
  String get platformAddressRequired =>
      'أدخل عنوان المنصة أولاً، أو اختر «بدون اتصال» إن كان هذا الجهاز يحتفظ '
      'بمبيعاته داخل المبنى.';
  @override
  String couldNotReach(String address) =>
      'تعذّر الوصول إلى $address. تأكد من العنوان، ومن أن الخادم يعمل وعلى هذه '
      'الشبكة.';
  @override
  String get noPlatformAddressInForce =>
      'لا يوجد عنوان منصة سارٍ. ارجع إلى خطوة الاتصال وحدّد واحداً.';
  @override
  String get terminalNotRegisteredYet =>
      'لم يُسجَّل هذا الجهاز بعد، فلن تعطيه المنصة منيو.';

  @override
  String get refusalPairingCodeInvalid =>
      'كود الإعداد هذا غير معروف. راجعه مع من أضاف هذا الكاشير في لوحة '
      'التحكم.';
  @override
  String get refusalPairingCodeSpent =>
      'كود الإعداد هذا مستخدم بالفعل. أصدر واحداً جديداً من لوحة التحكم.';
  @override
  String get refusalCredentialsRejected =>
      'اسم المستخدم وكلمة المرور غير مقبولين. راجعهما مع مدير، أو استخدم كود '
      'إعداد بدلاً منهما.';
  @override
  String get refusalNoBranches =>
      'لا توجد فروع لهذا المطعم بعد. أضف فرعاً من لوحة التحكم أولاً.';
  @override
  String get refusalBranchUnknown =>
      'هذا الفرع لم يعد على هذا الخادم. اختر فرعاً آخر.';
  @override
  String refusalTenantUnknown(String tenant) =>
      'لا يوجد مطعم باسم «$tenant» على هذا الخادم. راجع الاسم المختصر في '
      'الخطوة السابقة.';
  @override
  String refusalWrongPlatform(String platform) =>
      'لم يردّ $platform كما تردّ منصة XOrder. راجع عنوان المنصة في خطوة '
      'الاتصال.';
  @override
  String refusalPlatformUnreachable(String platform) =>
      'تعذّر الوصول إلى $platform. راجع عنوان المنصة في خطوة الاتصال ثم حاول '
      'مرة أخرى.';
  @override
  String get refusalClaimUnreadable =>
      'ردّت المنصة بشكل لا يفهمه هذا الكاشير. حدّث التطبيق، أو اربطه بكود من '
      'لوحة التحكم.';
  @override
  String get refusalNoPlatformConfigured =>
      'لا يوجد عنوان منصة على هذا الجهاز بعد. ارجع إلى خطوة الاتصال وحدّد '
      'واحداً.';
  @override
  String get refusalNoDatabaseReachable =>
      'لا يستطيع هذا الجهاز الوصول إلى قاعدة بيانات فرع بعد. ارجع إلى خطوة '
      'الاتصال واختبرها.';
  @override
  String get refusalAdoptUnsupported =>
      'لا توجد لوحة تحكم على هذا الخادم لتكون قد أنشأت كاشيراً مسبقاً. سمِّ هذا '
      'الكاشير وسجّله بدلاً من ذلك.';
  @override
  String get refusalValidationFailed =>
      'أدخل اسم المستخدم وكلمة المرور لحساب موظف مصرّح له بإضافة جهاز.';
  @override
  String menuDownloadRefused(String address, String answer) =>
      'ردّ $address على تنزيل المنيو بـ$answer. تأكد من عنوان المنصة وحاول '
      'مرة أخرى.';
  @override
  String get menuDownloadSilence => 'صمت';
  @override
  String menuDownloadHttp(int? status) => 'HTTP $status';
  @override
  String menuShapeNotUnderstood(String address) =>
      'ردّ $address بشكل لا يفهمه هذا الكاشير. حدّث التطبيق وحاول مرة أخرى.';
  @override
  String get testConnection => 'اختبار الاتصال';
  @override
  String get singleMachineHelp =>
      'هذا الترخيص يغطي جهازاً واحداً، لذا تبقى قاعدة البيانات على هذا الجهاز '
      'ولا يوجد عنوان لإدخاله. خُذ نسخة احتياطية: لا توجد نسخة ثانية.';
  @override
  String sharedDatabaseHelp(int terminals) =>
      'هذا الترخيص يغطي $terminals أجهزة، لذا يحتفظ جهاز واحد بقاعدة البيانات '
      'ويقرأها الباقون عبر هذه الشبكة. أدخل عنوانه بالأسفل — استخدم عنوان هذا '
      'الجهاز نفسه إذا كانت قاعدة البيانات هنا.';
  @override
  String get sendingSales => 'إرسال المبيعات';
  @override
  String get sendingSalesHelp =>
      'الكاشير يبيع بدون إنترنت في الحالتين — هذا يحدد فقط متى تُفرَّغ قائمة '
      'الانتظار. تجديد الترخيص يتم وفق جدوله الخاص على أي حال.';

  @override
  String unreachable(String address) =>
      'تعذّر الوصول إلى $address. راجع العنوان، وتأكد أن الخادم يعمل وأنه على '
      'هذه الشبكة.';
  @override
  String dnsFailure() =>
      'اسم الخادم لا يُترجم إلى عنوان. استخدم عنوان IP، أو امنح الجهاز عنواناً '
      'ثابتاً على الراوتر.';
  @override
  String tcpFailure(int port) =>
      'لا يوجد رد على المنفذ $port. تأكد أن PostgreSQL يعمل، وأن '
      'listen_addresses يشمل هذه الشبكة، وأن جدار الحماية يسمح بالاتصال.';
  @override
  String authFailure(String user) =>
      'رفض PostgreSQL اسم المستخدم أو كلمة المرور. تأكد أن الدور «$user» موجود '
      'وأن كلمة المرور صحيحة.';
  @override
  String tlsFailure() =>
      'رفض PostgreSQL الاتصال المؤمَّن. راجع شهادته، أو فعّل الخيار أعلاه إذا '
      'كان هذا فعلاً جهازاً على هذه الشبكة.';
  @override
  String queryFailure(String database) =>
      'تم الاتصال، لكن قاعدة البيانات لم ترد كما هو متوقع. تأكد أن «$database» '
      'هي قاعدة البيانات الصحيحة.';
  @override
  String connectionOk(String database) =>
      'تم الاتصال بـ«$database» وردّت. هذا الجهاز يصل إلى قاعدة بياناته.';
  @override
  String missingDatabase(String database) =>
      'الخادم يعمل وقَبِل الدخول، لكن لا توجد قاعدة بيانات باسم «$database» بعد. '
      'هذا متوقَّع في التثبيت الأول — الخطوة التالية هي التي تبنيها. تابع، وأنشئ '
      'أول مدير، وستُحلّ هذه من نفسها.';

  @override
  String get licenceKey => 'مفتاح الترخيص';
  @override
  String get licenceServer => 'خادم الترخيص';
  @override
  String get licenceServerHelp =>
      'الجهة التي يُفحص عندها هذا المفتاح. اتركه كما هو إلا إذا صدر الترخيص من '
      'مكان آخر — فالمفتاح الصادر من منصة تُرفضه دائماً منصة أخرى، مهما كانت '
      'كتابته سليمة. اتركه فارغاً للعودة إلى الافتراضي. كل ترخيص موقَّع ويُتحقق '
      'منه على هذا الجهاز، فالعنوان يحدد مصدر الملف لا صلاحيته.';
  @override
  String get activateOnline => 'تفعيل عبر الإنترنت';
  @override
  String get activateFromFile => 'تفعيل من ملف';
  @override
  String get licenceOnlineHelp =>
      'لا يوجد إنترنت في الموقع؟ اطلب ملف ‎.xlic من مورّدك وفعّل منه. يتم التحقق '
      'من الترخيص على هذا الجهاز — لا يحتاج الاتصال بأي خادم.';
  @override
  String get licenceOfflineHelp =>
      'تُصدَر التراخيص في صورة ملف ‎.xlic. يُفحص التوقيع على هذا الجهاز مقابل '
      'مفتاح مدمج في التطبيق، فلا يحتاج الكاشير للاتصال بأي خادم — وأي ملف لم '
      'يوقّعه مورّدك لن يُفعِّل شيئاً.';
  @override
  String get pasteLicenceFile => 'الصق ملف الترخيص';
  @override
  String licenceCoverage(String tenant, String? plan, int terminals) =>
      '${_bidi(tenant)}${plan == null ? '' : ' · ${_bidi(plan)}'} · '
      '${switch (terminals) {
        1 => 'جهاز واحد',
        2 => 'جهازان',
        <= 10 => '$terminals أجهزة',
        _ => '$terminals جهازاً',
      }}';
  @override
  String get cashUpNeverGated =>
      'التقفيل وإعادة الطباعة وتصدير البيانات تبقى متاحة مهما كانت حالة '
      'الترخيص.';

  @override
  String get restaurant => 'المطعم';
  @override
  String get restaurantHelp =>
      'الاسم المختصر للمطعم، كما في mahsoub.xorder.io. أسماء مستخدمي الموظفين '
      'فريدة داخل المطعم الواحد، فيجب ضبط هذا قبل أن يسجّل أحد دخوله.';
  @override
  String get restaurantFromLicenceHelp =>
      'من ترخيصك. أسماء المستخدمين لا تتكرر داخل المطعم الواحد، فهذا ما '
      'يسجّل به الكاشير دخوله.';
  @override
  String get methodPairingCode => 'كود الإعداد';
  @override
  String get methodPairingCodeBlurb =>
      'أُضيف هذا الكاشير من لوحة التحكم وأُعطي كوداً.';
  @override
  String get methodManual => 'إعداد يدوي';
  @override
  String get methodManualBlurb =>
      'لا يوجد وصول للوحة التحكم — سجّل الدخول واضبط الإعدادات يدوياً.';
  @override
  String claimedAs(String terminal, String branch) =>
      'مسجَّل باسم $terminal · $branch';
  @override
  String get claimedHelp =>
      'الفرع واسم الكاشير ورقم الجهاز جاءت كلها من لوحة التحكم. الخطوتان '
      'التاليتان للتأكيد فقط.';
  @override
  String get claimedFromDashboardHelp =>
      'الفرع واسم الكاشير ورقم الجهاز كلها جاءت من لوحة التحكم. الخطوتان '
      'التاليتان للتأكيد فقط.';
  @override
  String get setupCode => 'كود الإعداد';
  @override
  String get setupCodeHelp =>
      'من لوحة التحكم، في الإعدادات ← الأجهزة. الأكواد تُستخدم مرة واحدة '
      'وتنتهي، فاطلب كوداً جديداً بدل إعادة استخدام ورقة قديمة.';
  @override
  String get claimThisTerminal => 'تسجيل هذا الجهاز';
  @override
  String get username => 'اسم المستخدم';
  @override
  String get password => 'كلمة المرور';
  @override
  String get manualCredentialsWarning =>
      'استخدم أقل حساب يملك صلاحية إضافة جهاز، لا حساب المالك. هذا الكاشير في '
      'مكان عام، وكلمة المرور التي تُكتب هنا تفتح لوحة التحكم أيضاً.';
  @override
  String connectedTo(String tenant) => 'متصل بـ $tenant';
  @override
  String branchesRetrieved(int branches) =>
      'تم جلب $branches فرع. الخطوات التالية تستخدم هذه الإعدادات — ولم '
      'يُسجَّل شيء بعد.';
  @override
  String get connectAndPullConfiguration => 'اتصل واجلب الإعدادات';

  @override
  String get noOrderTypesConfigured => 'لا توجد أنواع طلبات مُعدّة';
  @override
  String get branchPaneHelp =>
      'الفرع هو الذي يحدد أنواع الطلبات المتاحة على هذا الكاشير، ويمنح بادئة '
      'رقم الفاتورة.';
  @override
  String get terminalName => 'اسم الجهاز';
  @override
  String get terminalNameProvisionedHelp =>
      'حُدِّد في لوحة التحكم عند إضافة هذا الكاشير. غيّره هناك لا هنا، حتى تبقى '
      'التقارير متطابقة.';
  @override
  String get terminalNameManualHelp =>
      'يظهر على الفواتير وفي تقارير الورديات، فسمِّه بالاسم الذي يناديه به '
      'الموظفون.';
  @override
  String get registered => 'مسجَّل';
  @override
  String get registerThisTerminal => 'تسجيل هذا الجهاز';
  @override
  String get registerHelp =>
      'التسجيل يكتب هذا الجهاز في قاعدة بيانات المطعم على هذه الآلة، وهو ما '
      'يمنحه هويته وبادئة فواتيره ووردية تنتمي إليها مبيعاته. لا توجد لوحة تحكم '
      'ولا شيء يُزامَن — هذا هو السجل.';
  @override
  String get whichTillIsThis => 'أي كاشير هذا؟';
  @override
  String get tillAwaitingDevice => 'أُنشئ في لوحة التحكم وينتظر جهازاً.';
  @override
  String get aNewTill => 'كاشير جديد';
  @override
  String get aNewTillBlurb =>
      'غير موجود في لوحة التحكم بعد. إنشاؤه يستهلك مقعداً من باقة المطعم.';
  @override
  String get terminalNameHint => 'كاشير ١';
  @override
  String get alreadySetUp => 'تم الإعداد';
  @override
  String get useThisTill => 'استخدم هذا الكاشير';
  @override
  String get adoptTerminalHelp =>
      'يأخذ الكاشير الذي أنشأته لوحة التحكم بالفعل — اسمه وفرعه ورقمه '
      'تأتي من هناك — ويصدر بيانات اعتماد هذا الجهاز. لا يُستهلك مقعد: '
      'ذاك اشتُري وقت إنشاء الكاشير.';
  @override
  String get registerCloudHelp =>
      'التسجيل يصدر بيانات اعتماد هذا الكاشير ويجلب إعدادات المطعم — المنيو '
      'في الخطوات التالية يأتي منها، فلا يمكن تخطي هذه الخطوة.';
  @override
  String get terminalId => 'رقم الجهاز';
  @override
  String get terminalIdHelp =>
      'يُولَّد مرة واحدة على هذا الجهاز ولا يُعاد إصداره — الورديات والطلبات '
      'مرتبطة به. إعادة التثبيت تُبقيه؛ الجهاز الجديد يأخذ رقماً جديداً.';
  @override
  String get findPrinters => 'البحث عن طابعات';
  @override
  String get lookingForPrinters => 'جارٍ البحث…';
  @override
  String get testPrint => 'طباعة تجريبية';
  @override
  String get testReceiptSent => 'أُرسلت الفاتورة التجريبية.';
  @override
  String get nothingPrinted => 'لم تتم الطباعة — البيع كان سيكتمل على أي حال.';
  @override
  String get cashDrawerAttached => 'درج نقدية موصول';
  @override
  String get cashDrawerAttachedBlurb => 'يفتحه منفذ الطابعة.';
  @override
  String get scannerAttached => 'قارئ باركود موصول';
  @override
  String get scannerAttachedBlurb => 'قارئات لوحة المفاتيح لا تحتاج أي إعداد.';
  @override
  String get hardwareHelp =>
      'كلها اختيارية. الكاشير الذي لا يتصل به شيء يبيع أيضاً — تنتظر الفاتورة '
      'وتظهر الحالة على الشاشة. الطباعة ليست أبداً على مسار تحصيل النقود.';

  @override
  String get currency => 'العملة';
  @override
  String currencyValue(String code, int decimals) =>
      '$code · $decimals خانة عشرية';
  @override
  String get serviceCharge => 'رسوم الخدمة';
  @override
  String get serviceChargeValue => '12٪ · للصالة فقط';
  @override
  String get vat => 'ضريبة القيمة المضافة';
  @override
  String get vatValue => '14٪ · على المجموع زائد الخدمة';
  @override
  String get rounding => 'التقريب';
  @override
  String get roundingValue => 'لأعلى عند النصف، مرة واحدة عند سطر الضريبة';
  @override
  String get moneyRules => 'المال';
  @override
  String get moneyRulesHint => 'رسوم الخدمة والضريبة وما تنطبق عليه';
  @override
  String get moneyComesFromPlatform =>
      'يأخذ هذا الجهاز قواعد الضريبة من المنصة.';
  @override
  String get serviceDineInOnly => 'للصالة فقط';
  @override
  String get ratesFromThisTerminal =>
      'تُضبط هذه النسب هنا وتُحسب في كل فاتورة يصدرها هذا الجهاز. تغييرها '
      'يغيّر ما يدفعه العميل التالي.';
  @override
  String get ratesNotSetYet =>
      'لم يتم ضبط أي شيء، لذا يحسب هذا الجهاز من قيمته الافتراضية ويذكر ذلك '
      'في كل إيصال. اضبط النسب الحقيقية — والصفر إجابة صحيحة.';
  @override
  String get saveRates => 'حفظ النسب';
  @override
  String get ratesSaved => 'تم الحفظ. الفواتير الجديدة ستُحسب بهذه النسب.';
  @override
  String get floorPlan => 'الصالة';
  @override
  String get floorPlanHint => 'الطاولات التي يمكن للنادل إجلاس الضيوف عليها';
  @override
  String get floorComesFromPlatform => 'يأخذ هذا الجهاز مخطط الصالة من المنصة.';
  @override
  String get addTable => 'إضافة طاولة';
  @override
  String get tableLabel => 'الاسم';
  @override
  String get tableSeatsLabel => 'المقاعد';
  @override
  String get tableArea => 'المنطقة';
  @override
  String get takeOutOfService => 'خارج الخدمة';
  @override
  String get putBackInService => 'إعادة للخدمة';
  @override
  String get noTablesYet =>
      'لا توجد طاولات بعد. أضف واحدة ليتمكن النادل من إجلاس الضيوف عليها.';
  @override
  String tableSummary(int tables) => '\$tables طاولة';
  @override
  String get fromDeviceConfiguration => 'من إعدادات الجهاز';
  @override
  String get deviceTaxHelp =>
      'هذه النسب محفوظة على هذا الجهاز، ولم تصدر من الخادم. كل فاتورة تُطبع بها '
      'تذكر ذلك على الورق. وعندما يتولى الخادم الضريبة تصبح هذه الشاشة للقراءة '
      'فقط.';
  @override
  String get downloadMenu => 'تحميل المنيو';
  @override
  String get downloadAgain => 'تحميل مرة أخرى';
  @override
  String itemsCached(int items) => 'حُفظ $items صنف على هذا الجهاز.';
  @override
  String get menuEmpty => 'لا يوجد منيو على هذا الجهاز';
  @override
  String get menuEmptyHelp =>
      'تم التحميل بنجاح، لكن لا توجد أصناف لهذا المطعم بعد، لذلك ليس لدى '
      'الكاشير ما يبيعه. يمكن إنهاء الإعداد — فالمنيو يُحدَّث في الخلفية — '
      'لكن أضف الأصناف قبل أن يحاول أحد البيع.';
  @override
  String get menuEmptyHelpOffline =>
      'لا توجد أصناف لهذا المطعم بعد، فلا يوجد ما يبيعه الكاشير. لن يصل شيء من '
      'تلقاء نفسه — أكمل الإعداد ثم ابنِ المنيو من شاشة الإدارة قبل أن يحاول '
      'أحد البيع.';
  @override
  String get cataloguePaneHelp =>
      'يُحفظ المنيو حتى يستطيع الكاشير البيع قبل أن يتصل بالإنترنت مرة أخرى. '
      'ويُحدَّث في الخلفية أثناء العمل.';
  @override
  String get readMenu => 'فحص المنيو';
  @override
  String get readMenuAgain => 'إعادة الفحص';
  @override
  String get cataloguePaneHelpOffline =>
      'يقرأ هذا المنيو الموجود على هذا الجهاز — لا يتم تحميل أي شيء. المنيو '
      'الفارغ أمر طبيعي على جهاز جديد: يمكنك بناؤه من الإدارة بعد انتهاء '
      'الإعداد.';
  @override
  String licenceModeChanged(Object chosen, Object landed) =>
      'هذا الترخيص لا يغطي $chosen، لذا تم ضبط الجهاز على $landed. اطلب '
      'ترخيصًا يغطي $chosen إذا كان هذا ما تحتاجه.';
  @override
  String catalogueDownloadFailed(Object error) => 'فشل تحميل المنيو: $error';
  @override
  String get summaryLanguage => 'اللغة';
  @override
  String get summaryConnection => 'الاتصال';
  @override
  String get summaryServer => 'الخادم';
  @override
  String get summaryThisMachine => 'هذا الجهاز';
  @override
  String get summaryUpstream => 'الخادم الأعلى';
  @override
  String get summaryRestaurant => 'المطعم';
  @override
  String get summaryBranch => 'الفرع';
  @override
  String get summaryTerminal => 'الجهاز';
  @override
  String get summaryPrinter => 'الطابعة';
  @override
  String get summaryNoPrinter => 'لا توجد — ستنتظر الفواتير';
  @override
  String get summaryCashDrawer => 'درج النقدية';
  @override
  String get summaryScanner => 'قارئ الباركود';
  @override
  String get summaryAttached => 'موصول';
  @override
  String get summaryMenu => 'المنيو';
  @override
  String summaryItemsCached(int items) => 'حُفظ $items صنف';
  @override
  String get summaryLicence => 'الترخيص';
  @override
  String get summaryHelp =>
      'يمكنك تغيير أي من هذا لاحقاً من الإعدادات، عدا رقم الجهاز.';
  @override
  String get notSet => '—';
  @override
  String get resetTerminal => 'إعادة ضبط الجهاز';
  @override
  String get resetTerminalTitle => 'إعادة ضبط هذا الجهاز؟';
  @override
  String get resetTerminalBody =>
      'سيبدأ الإعداد من جديد: الفرع واسم الجهاز وعنوان قاعدة البيانات وكلمة المرور. '
      'المبيعات المسجلة لن تُمس — فهي في قاعدة البيانات وليست على هذا الجهاز. '
      'ويظل رقم الجهاز كما هو، فيبقى الترخيص صالحاً.';
  @override
  String get resetTerminalShiftOpen =>
      'أغلق الوردية المفتوحة قبل إعادة الضبط، فدرجها لم يُجرد بعد.';
  @override
  String get resetTerminalShiftUnknown =>
      'تعذر التحقق من الوردية المفتوحة. تحقق من اتصال قاعدة البيانات وحاول مرة أخرى.';
  @override
  String get resetTerminalConfirm => 'إعادة الضبط وبدء الإعداد';

  @override
  String get terminalRejectedTitle => 'لم يعد هذا الجهاز معروفًا لدى المنصة';
  @override
  String get terminalRejectedBody =>
      'توقفت المنصة عن قبول بيانات اعتماد هذا الجهاز — إما أنه حُذف أو تم '
      'اقترانه في مكان آخر. البيع ما زال يعمل ولا شيء يُفقد، لكن لا شيء يصل '
      'إلى المنصة حتى تتم إعادة إعداده.';
  @override
  String get terminalRejectedQueued =>
      'هناك {count} عملية بيع بانتظار الإرسال. محفوظة بأمان وسيتم إرسالها '
      'فور إعادة اقتران هذا الجهاز.';

  @override
  String get forceResetTitle => 'حذف هذا الجهاز وإعادة إعداده؟';
  @override
  String get forceResetBody =>
      'سيُحذف إعداد هذا الجهاز من هذا الحاسوب — المستأجر والفرع والجهاز '
      'وبيانات اعتماده. سيبدأ المعالج من جديد ويمكنك اقترانه بحساب آخر. لن '
      'يُحذف أي شيء على المنصة.';
  @override
  String get forceResetShiftOpen =>
      '{ref} ما زالت مفتوحة. لن يتم إغلاقها أو جردها، ولن تتم تسوية درج النقد '
      'الخاص بها أبدًا.';
  @override
  String get forceResetQueued =>
      'هناك {count} عملية بيع لم تصل إلى المنصة. ستبقى على هذا الحاسوب لكن لن '
      'يرسلها شيء بعد زوال بيانات الاعتماد.';
  @override
  String get forceResetConfirm => 'حذف وإعادة الإعداد';

  @override
  String get settings => 'الإعدادات';
  @override
  String get syncNow => 'مزامنة الآن';
  @override
  String get management => 'الإدارة';
  @override
  String get windowMenu => 'النافذة';

  @override
  String get capOperate => 'البيع على الكاشير';
  @override
  String get capCatalogView => 'عرض المنيو';
  @override
  String get capCatalogManage => 'إضافة وتعديل أصناف المنيو والأسعار';
  @override
  String get capStaffManage => 'إضافة موظفين وتحديد الأدوار وإعادة ضبط الأكواد';
  @override
  String get capTerminalManage => 'تسجيل الأجهزة وإعادة ضبطها';
  @override
  String get capSettingsManage => 'تغيير إعدادات المطعم والضريبة';
  @override
  String get capDiscountApply => 'عمل خصم';
  @override
  String get capPriceOverride => 'تعديل السعر';
  @override
  String get capOrderVoid => 'إلغاء طلب أو بند مُرسل';
  @override
  String get capOrderItemCancel => 'حذف صنف قبل أن يراه المطبخ';
  @override
  String get capOrderItemVoid => 'حذف صنف سبق أن أعدّه المطبخ';
  @override
  String get capOrderViewAll => 'الاطلاع على كل طلبات هذا الفرع';
  @override
  String get capOrderRefund => 'استرجاع مبيعة';
  @override
  String get capReceiptReprint => 'إعادة طباعة الإيصال';
  @override
  String get capShiftOpen => 'بدء وردية';
  @override
  String get capShiftClose => 'تقفيل وردية وعدّ الدرج';
  @override
  String get capCashMovement => 'إيداع وسحب نقدي ومصروفات نثرية';
  @override
  String get capReportsView => 'عرض التقارير';
  @override
  String get capBackupManage => 'أخذ نسخة احتياطية واستعادتها';

  @override
  String get capGroupSelling => 'البيع';
  @override
  String get capGroupMoney => 'النقود والتصحيحات';
  @override
  String get capGroupDrawer => 'الدرج';
  @override
  String get capGroupBackOffice => 'الإدارة';

  @override
  String get listAnd => ' و';
  @override
  String get listSeparator => '، ';

  @override
  String refusalNotPermitted(String capability) => 'تحتاج صلاحية $capability.';
  @override
  String refusalRoleStillHeld(String names) =>
      'ما زال هذا الدور مُسنداً إلى $names. انقلهم إلى دور آخر أولاً.';
  @override
  String get refusalRoleIsSystemDefined =>
      'هذا أحد الأدوار التي أنشأها المُثبِّت. يمكن تغيير اسمه وصلاحياته، لكن '
      'لا يمكن حذفه — مطعم بلا أدوار لا يبقى فيه من يستطيع إنشاء دور.';
  @override
  String refusalUserSeatsExhausted(int maxUsers) =>
      'يغطي هذا الترخيص ${switch (maxUsers) {
        1 => 'حساب مستخدم واحد',
        2 => 'حسابَي مستخدم',
        <= 10 => '$maxUsers حسابات مستخدمين',
        _ => '$maxUsers حساب مستخدم',
      }}، وكلها مستخدمة. عطّل من ترك العمل، أو اطلب من مورّدك ترخيصاً بعدد أكبر.';
  @override
  String refusalUsernameTaken(String username) =>
      '«$username» مستخدم بالفعل هنا. أسماء المستخدمين لا تتكرر، لأن هذا ما '
      'يجعل الكود يدل على شخص واحد.';
  @override
  String get refusalWouldLockEveryoneOut =>
      'هذا آخر حساب يستطيع إدارة الموظفين. امنح هذه الصلاحية لشخص آخر أولاً، '
      'وإلا لن يستطيع أحد الدخول إلى هذه الشاشة مرة أخرى.';
  @override
  String get refusalEditedElsewhere =>
      'غيّر أحدهم هذا من كاشير آخر أثناء تعديلك. أغلق الشاشة وافتحها لترى ما '
      'صارت عليه.';
  @override
  String get refusalAdministratorCredentialRequired =>
      'تحتاج الإدارة كلمة مرور قاعدة بيانات خاصة بها، ولم تُعطَ لهذه الجلسة. '
      'أغلق هذه الشاشة وافتح الإدارة من جديد لإدخالها.';
  @override
  String get refusalNoDatabaseConfigured =>
      'لا توجد قاعدة بيانات فرع على هذا الجهاز بعد، فليس هناك ما يُدار. أكمل '
      'الإعداد أولاً.';
  @override
  String get refusalOwnerMustKeepEverything =>
      'دور المالك يحتفظ بكل الصلاحيات. لو أمكن أن يفقد واحدة، لأمكن أن يصل '
      'المطعم إلى حال لا يستطيع فيها أحد إعادتها.';
  @override
  String refusalCashiersAreNotAdministrators(String capabilities) =>
      'دور الكاشير لا يصح أن يشمل $capabilities. استخدم دور مشرف أو مدير لذلك.';

  @override
  String get backToTill => 'رجوع إلى الكاشير';
  @override
  String get paneStaff => 'الموظفون';
  @override
  String get paneStaffBlurb => 'من يعمل هنا، وما المسموح له به';
  @override
  String get paneMenu => 'المنيو';
  @override
  String get paneMenuBlurb => 'الأقسام والأصناف وأسعارها';
  @override
  String get paneRoles => 'الأدوار';
  @override
  String get paneRolesBlurb => 'الصلاحيات وراء كل مسمى وظيفي';
  @override
  String get paneActivity => 'السجل';
  @override
  String get paneActivityBlurb => 'ما الذي تغيّر، وعلى يد من';
  @override
  String get pinCannotOpenManagement => 'هذا الكود لا يفتح الإدارة.';
  @override
  String get managementPinHelp => 'أدخل كود شخص مصرّح له بإدارة الموظفين.';
  @override
  String get managementPinRetryHelp =>
      'جرّب كود مدير أو مشرف، أو ارجع إلى الكاشير.';
  @override
  String cannotManageStaff(String name) =>
      '$name غير مصرّح له بإدارة الموظفين.';
  @override
  String get backOfficePassword => 'كلمة مرور الإدارة';
  @override
  String backOfficePasswordHelp(String name) =>
      'أنت داخل باسم $name. تعديل الموظفين والأدوار والمنيو يعمل على حساب '
      'قاعدة بيانات خاص به، لا يستطيعه حساب الكاشير. تُطلب مرة واحدة كل جلسة '
      'ولا تُحفظ على هذا الجهاز.';
  @override
  String backOfficeAuthFailed(String user) =>
      'رفضت PostgreSQL كلمة المرور هذه للمستخدم «$user».';
  @override
  String get backOfficeUnreachable =>
      'لم تردّ قاعدة البيانات. الكاشير ما زال يبيع؛ الإدارة وحدها هي التي '
      'تحتاج هذا الاتصال.';
  @override
  String get backOfficeRefused => 'رفضت قاعدة البيانات اتصال الإدارة.';
  @override
  String get checking => 'جارٍ التحقق…';
  @override
  String get openManagement => 'فتح الإدارة';

  @override
  String get addSomebody => 'إضافة شخص';
  @override
  String staffCount(int active, int total) => '$active نشط · $total في المجموع';
  @override
  String staffCountLicensed(int active, int total, int licensed) =>
      '$active من $licensed مرخّصة · $total في المجموع';
  @override
  String get notSaved => 'لم يُحفظ';
  @override
  String get close => 'إغلاق';
  @override
  String get you => 'أنت';
  @override
  String extraCapabilities(int count) => '+$count إضافية';
  @override
  String get resetPin => 'إعادة ضبط الكود';
  @override
  String newPinFor(String name) => 'كود جديد لـ $name';
  @override
  String get disable => 'إيقاف';
  @override
  String get enable => 'تفعيل';
  @override
  String get noRole => 'بلا دور';
  @override
  String get fieldName => 'الاسم';
  @override
  String get fieldUsername => 'اسم المستخدم';
  @override
  String get fieldPin => 'الكود';
  @override
  String get fieldRole => 'الدور';
  @override
  String get add => 'إضافة';
  @override
  String get setPin => 'تعيين الكود';
  @override
  String get nameAndUsernameRequired =>
      'اسم واسم مستخدم، الاثنان معاً. اسم المستخدم هو ما يجعل الكود يدل على '
      'شخص واحد.';
  @override

  @override
  String get noRolesYet =>
      'لا توجد أدوار على خادم هذا الفرع بعد. شغّل bin/pos_migrate.dart '
      'لإنشائها.';
  @override
  String permissionCount(int held, int total) => '$held من $total صلاحية';
  @override
  String get createdByInstaller => ' · أنشأه المُثبِّت';
  @override
  String get discard => 'تجاهل';
  @override
  String get save => 'حفظ';

  @override
  String get nothingRecordedYet =>
      'لم يُسجَّل شيء على خادم هذا الفرع بعد. كل تغيير في الموظفين والأدوار '
      'والأسعار والإعدادات يظهر هنا.';
  @override
  String approvedByLine(String actor, String approver) =>
      '$actor، بموافقة $approver';

  @override
  String get supervisorApproval => 'موافقة مشرف';
  @override
  String supervisorApprovalHelp(String action) =>
      '$action. يُدخل المشرف كوده — ويُسجَّل الاسمان معاً.';
  @override
  String get pinCannotApprove => 'هذا الكود لا يصلح للموافقة على هذا.';
  @override
  String get notPermittedTitle => 'غير مسموح';
  @override
  String notPermittedBody(String capability) =>
      'هذا يحتاج صلاحية «$capability»، ولا يستطيع أي مشرف إعارتها على '
      'الكاشير. يمنحها المدير من الإدارة ← الموظفون.';

  @override
  String get menuComesFromPlatform => 'هذا الجهاز يأخذ منيوه من المنصة.';
  @override
  String menuSummary(int categories, int items) =>
      '$categories قسم · $items صنف';
  @override
  String get noCategoriesYet => 'لا توجد أقسام بعد. أضف قسماً ثم أضف ما فيه.';
  @override
  String get nothingInCategoryYet => 'لا شيء في هذا القسم بعد.';
  @override
  String get addCategory => 'إضافة قسم';
  @override
  String get addItem => 'إضافة صنف';
  @override
  String get rename => 'إعادة تسمية';
  @override
  String get takeOffTheRail => 'إخفاء من الشريط';
  @override
  String get edit => 'تعديل';
  @override
  String get offSale => 'إيقاف البيع';
  @override
  String get backOnSale => 'إعادة للبيع';
  @override
  String get newCategory => 'قسم جديد';
  @override
  String get renameCategory => 'إعادة تسمية القسم';
  @override
  String get newItem => 'صنف جديد';
  @override
  String get editItem => 'تعديل الصنف';
  @override
  String get fieldNameArabic => 'الاسم بالعربية';
  @override
  String get fieldPrice => 'السعر';
  @override
  String get fieldSku => 'رمز الصنف';
  @override
  String optionalField(String label) => '$label · اختياري';
  @override
  String get fieldOfferPrice => 'سعر العرض';
  @override
  String get rateIsNotANumber => 'يجب أن تكون النسبة رقمًا وليست أقل من صفر.';
  @override
  String get priceIsNotANumber => 'السعر ليس رقماً.';
  @override
  String get offerPriceIsNotANumber => 'سعر العرض ليس رقماً.';
}

/// Makes [AppStrings] reachable from a [BuildContext], and tells Flutter which
/// locales the app actually has words for.
class AppLocalizations extends LocalizationsDelegate<AppStrings> {
  const AppLocalizations();

  static const supportedLocales = [Locale('en'), Locale('ar')];

  @override
  bool isSupported(Locale locale) =>
      supportedLocales.any((l) => l.languageCode == locale.languageCode);

  @override
  Future<AppStrings> load(Locale locale) async => AppStrings.of(locale);

  @override
  bool shouldReload(AppLocalizations old) => false;
}

extension AppStringsContext on BuildContext {
  /// The till's words, in the language it was set up in.
  ///
  /// Falls back to English rather than throwing when no delegate is above this
  /// context — a dialog pushed onto a bare test harness should still render.
  AppStrings get strings =>
      Localizations.of<AppStrings>(this, AppStrings) ?? const EnStrings();
}
