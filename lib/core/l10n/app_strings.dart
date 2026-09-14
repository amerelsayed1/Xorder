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
  String get searchHint;
  String get customAmount;

  // ── A one-off charge (§17 open item) ──────────────────────────────────────
  String get openItemTitle;
  String get openItemName;
  String get openItemNameHint;
  String get openItemPrice;
  String get openItemAdd;
  String get openItemNeedsName;
  String get openItemNeedsPrice;
  String get openItemNotPermitted;
  String openItemAdded(String name);
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

  /// An **offline** terminal's status pill.
  ///
  /// It never says "offline". That is this terminal's permanent and intended
  /// state, and announcing it reads as a fault on a machine where nothing is
  /// wrong. What can genuinely break is the branch server.
  String get branchDatabaseReady;
  String get branchDatabaseChecking;
  String get branchDatabaseUnreachable;
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
  String get chooseTableFirst;
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

  // ── Held tickets — parked with no table ───────────────────────────────────
  String get heldTickets;
  String heldTicketsKey(int count);
  String get heldTicketsHelp;
  String get noHeldTickets;

  /// `Takeaway · 3 items` — what one held ticket is, before its total.
  String heldTicketSummary(String orderType, int items);
  String get ticketParked;

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
  String taxRegistrationLine(String number);
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

  /// The three answers the till can honestly give after trying to print, plus
  /// the one it gives when the queue could not be written either. See
  /// `PrintOutcome` — the toast used to say "queued" in every case, including
  /// the case where nothing was printed and nothing was queued.
  String get receiptPrintedToast;
  String get receiptQueuedToast;
  String get receiptNotPrintedToast;
  String get receiptNoPrinterToast;
  String get printerPaperWidth;
  String get printerPaper80;
  String get printerPaper58;
  String get printerPaperWidthHelp;

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

  /// Asked of NOBODY in particular — the lock screen signs in whoever's PIN
  /// it is, so it cannot name a person before one has typed anything.
  String get enterYourPin;

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

  /// Handing the till to a colleague. The same door as Lock — the lock screen
  /// signs in whoever's PIN it is — named for what people are doing when they
  /// reach for it.
  String get switchUser;

  /// ONE message for both halves, on purpose: saying which of the two was wrong
  /// turns the lock screen into a way of finding out which usernames exist.
  String get wrongUsernameOrPin;
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

  /// Stated as the act a manager is being asked to approve: releasing a drawer
  /// that belongs to somebody else.
  String closeShiftNotYours(String openedBy);
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

  // A child tablet's wizard: it finds the main device rather than building
  // anything, and signs in with a manager the main device already has.
  String get stepMainDevice;
  String get stepMainDeviceBlurb;
  String get stepChildAccountBlurb;
  String get mainDeviceHelp;
  String get mainDeviceAddress;
  String get mainDeviceAddressHelp;
  String get mainDeviceIsThisTablet;
  String get connectToMainDevice;
  String mainDeviceLinked(String tenant);
  String get mainDeviceHasNoLicence;
  String allTerminalsTaken(int max);

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
  String schemaUpgradeFailed(String error);
  String restaurantSeeded(String restaurant);
  String get rolesAlreadyThere;
  String rolesCreated(int count);
  String ownerCreated(String name);
  String ownerAlreadyHere(String username);

  /// Somebody else is already this restaurant's owner, so the person typed
  /// into the form was not made one. Names them by username as well as name,
  /// because the first way forward is to type that username into this form.
  String ownerAlreadyExists(String name, String username);
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
  String get resetTerminalHint;
  String get paneTerminal;
  String get paneTerminalBlurb;

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
  String get forceResetSignInTitle;
  String get forceResetSignInHelp;
  String get forceResetSignInRefused;

  // ── Settings menu bar ─────────────────────────────────────────────────────
  String get settings;
  String get syncNow;
  String get management;

  /// The Settings menu's route to staff accounts.
  ///
  /// Named for what somebody is looking for rather than for the screen it
  /// happens to live on. "Management" is a place; this is an answer.
  String get staffAndAccounts;

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
  String get capPurchaseManage;
  String get capStaffManage;
  String get capTerminalManage;
  String get capSettingsManage;
  String get capDiscountApply;
  String get capPriceOverride;
  String get capOrderVoid;
  String get capOrderItemCancel;
  String get capOrderItemVoid;
  String get capOrderViewAll;
  String get capCashOpenWithoutSale;
  String get capShiftViewExpectedCash;
  String get capCashVarianceView;
  String get capDayClose;
  String get capDayForceClose;
  String get capOrderRefund;
  String get capReceiptReprint;
  String get capShiftOpen;
  String get capShiftClose;
  String get capCashMovement;
  String get capReportsView;
  String get capBackupManage;
  String get capAdminEnter;
  String get capPaymentRemove;
  String get capReportExport;

  /// Taking a payment back off an unsettled bill: the act, in words, for the
  /// supervisor prompt; its button; and what the screen says if it is still
  /// refused.
  String removePaymentTitle(String what);
  String get removePaymentAction;
  String get removePaymentRefused;

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
  String refusalCannotGrantWhatYouLack(String capabilities);
  String refusalManagedByPlatform(String what);

  /// One owner per restaurant. Each says how ownership actually moves —
  /// disable, then appoint — because a refusal that only says "no" is tried
  /// again.
  String refusalOwnerAlreadyExists(String ownerName);
  String get refusalOwnerIsFixed;
  String get refusalOwnerIsNotAnExtraRole;

  /// Says who CAN, so the manager asking knows the owner is the one to ask.
  String get refusalOwnerPinIsTheirs;

  /// Why a purchase order cannot move as asked. The button that was pressed
  /// was showing, so each says what changed and what to do instead.
  String get refusalPurchaseAlreadySent;
  String get refusalPurchaseGoodsArrived;
  String get refusalPurchaseCancelled;
  String get refusalPurchaseHasNoLines;
  String get refusalPurchaseQuantityNotPositive;
  String get refusalPurchaseCannotCancelArrived;
  String get refusalPurchaseAllArrived;
  String get refusalPurchaseFollowsTheGoods;

  /// Stock is never converted between units. [quantity] is already formatted,
  /// in Latin digits.
  String refusalStockHeldInAnotherUnit(
    String item,
    String quantity,
    String heldUnit,
    String askedUnit,
  );
  String get staffComesFromPlatform;

  // §107 — risk levels, on the role editor's badges.
  String get riskLow;
  String get riskMedium;
  String get riskHigh;
  String get riskCritical;
  String get roleCannotGrant;
  String get roleNew;
  String get roleTemplateExplain;
  String roleTemplateCount(int count);

  // §105, §16 — one person's exceptions and ceilings.
  String grantsFor(String name);
  String get grantsExplain;
  String get grantsExtraRoles;
  String get grantsCeilings;
  String get grantsDiscountCeiling;
  String get grantsNoCeiling;
  String get grantsExceptions;
  String get grantsFromRole;
  String get grantsAllowed;
  String get grantsDenied;
  String get grantsAction;

  // §40 — payment methods as data.
  String get tenderTypes;
  String get tenderTypesHint;
  String get tenderTypesComeFromPlatform;
  String get tenderNew;
  String get tenderEdit;
  String get tenderNameEn;
  String get tenderNameAr;
  String get tenderCode;
  String get tenderKind;
  String tenderKindName(String wire);
  String get tenderCountsAsCash;
  String get tenderCountsAsCashHint;
  String get tenderOpensDrawer;
  String get tenderOpensDrawerHint;
  String get tenderRequiresReference;
  String get tenderRefundAllowed;
  String get tenderActive;
  String get tenderActiveHint;
  String get tenderRetired;

  // §38 — service charges.
  String get serviceCharges;
  String get serviceChargesHint;
  String get serviceChargesFallback;
  String get chargeNew;
  String get chargeEdit;
  String get chargeName;
  String get chargeHow;
  String get chargePercentage;
  String get chargeFixed;
  String get chargeAppliesTo;
  String get chargeAppliesToHint;
  String get chargeTaxable;
  String get chargeTaxableHint;
  String get chargeAutomatic;
  String get chargeOptional;
  String get chargeOptionalHint;
  String get chargeActive;
  String get currencyEgp;

  // §36-37 — suppliers and purchase orders.
  String get suppliers;
  String get supplierNew;
  String get supplierEdit;
  String get supplierName;
  String get supplierContact;
  String get supplierEmail;
  String get supplierPaymentTerms;
  String get supplierTermsHint;
  String get supplierCode;
  String get supplierNotes;
  String get supplierActive;
  String get supplierActiveHint;
  String get supplierCashOnDelivery;
  String supplierTermDays(int days);
  String get purchaseOrders;
  String get purchaseOrderNew;
  String get purchaseOrderEdit;
  String get purchaseNoOrdersYet;
  String get purchaseNoSuppliersYet;
  String get purchaseNeedsASupplier;
  String get purchaseNeedsALine;
  String get purchaseItem;
  String get purchaseQty;
  String get purchaseUnitCost;
  String get purchaseAddLine;
  String purchaseLineCount(int count);
  String get purchaseSend;
  String get purchaseReceive;
  String purchaseReceiveInto(String reference);
  String get purchaseReceiveHint;
  String get purchaseOrdered;
  String get purchaseOutstanding;
  String get purchaseArrived;
  String purchaseBookIn(int lines);
  String get statusDraft;
  String get statusSent;
  String get statusPartReceived;
  String get statusReceived;
  String get statusCancelled;

  // §37 — supplier invoices and payments.
  String get supplierInvoices;
  String get invoiceNew;
  String get invoiceEdit;
  String get invoiceHint;
  String get invoiceNumber;
  String get invoiceTotal;
  String get invoiceTax;
  String get invoiceTaxFromRate;
  String get invoiceIssued;
  String get invoiceDue;
  String invoiceDueOnTerms(int days);
  String get invoiceAgainstOrder;
  String get invoiceNoOrder;
  String get invoiceAgreesWithDelivery;
  String get invoiceBilledMore;
  String get invoiceBilledLess;
  String invoiceDaysLate(int days);
  String get invoiceNoneOutstanding;
  String get invoiceOutstanding;
  String get invoiceVoid;
  String get invoiceVoidWhy;
  String get invoicePay;
  String get notes;
  String paymentTo(String supplier);
  String get paymentDoesNotTouchTheDrawer;
  String get paymentFromTheDrawer;
  String get paymentFromTheDrawerHint;
  String get paymentAgainst;
  String get paymentAmount;
  String get paymentMethod;
  String get methodCash;
  String get methodTransfer;
  String get methodCheque;
  String get methodCard;
  String get methodOther;
  String get paymentReference;
  String get paymentOnAccount;
  String get paymentOnAccountHint;
  String get paymentPay;
  String get paymentNeedsAnAmount;
  String paymentMoreThanTheBill(String room);
  String get paymentsList;
  String get paymentNonePaidYet;
  String get paymentVoid;
  String get paymentVoidWhy;
  String get reasonListEmpty;

  // The Activity pane (§49). One per audit action this build writes.
  String get actStaffCreated;
  String get actStaffUpdated;
  String get actStaffDisabled;
  String get actStaffReactivated;
  String get actStaffPinReset;
  String get actStaffRoleChanged;
  String get actStaffGrantsChanged;
  String get actRoleCreated;
  String get actRoleUpdated;
  String get actRoleDeleted;
  String get actPermissionOverridden;
  String get actShiftOpened;
  String get actShiftClosed;
  String get actReceiptReprinted;
  String get actCategoryCreated;
  String get actCategoryUpdated;
  String get actCategoryArchived;
  String get actCategoryRestored;
  String get actProductCreated;
  String get actProductUpdated;
  String get actProductArchived;
  String get actProductRestored;
  String get actProductRepriced;
  String get actMoneyConfigChanged;
  String get actReceiptProfileChanged;
  String get actTableCreated;
  String get actTableUpdated;
  String get actTableArchived;
  String get actTableRestored;
  String get actPurchaseOrderStatusChanged;
  String get actStockReceived;
  String get actSupplierSaved;
  String get actSupplierInvoiceSaved;
  String get actSupplierInvoiceVoided;
  String get actSupplierPaid;
  String get actSupplierPaymentVoided;
  String get actServiceChargeSaved;
  String get actTenderTypeSaved;
  String get actOrderTypeSaved;
  String get actTaxGroupSaved;
  String get actProductOptionsChanged;
  String get actOptionGroupSaved;
  String get actOptionGroupRepriced;
  String get actOptionGroupDeleted;
  String get fieldYes;
  String get fieldNo;
  String get unitEach;
  String get unitKilogram;
  String get unitGram;
  String get unitLitre;
  String get unitMillilitre;
  String get unitBox;
  String get unitPack;
  String get supplierOwes;
  String get supplierOverdue;

  // Management chrome.
  String get fieldTaxGroup;
  String get fieldTaxGroupHint;
  String get fieldTaxGroupDefault;
  String get taxGroups;
  String get taxGroupsHint;
  String get taxGroupsFallback;
  String get taxGroupNew;
  String get taxGroupEdit;
  String get taxGroupHint;
  String get taxGroupName;
  String get taxGroupNeedsAName;
  String get taxGroupRate;
  String get taxGroupRateNotValid;
  String get taxGroupDefault;
  String get taxGroupDefaultHint;
  String get taxGroupIsDefault;
  String get taxGroupActive;
  String get taxGroupActiveHint;
  String get orderTypes;
  String get orderTypesHint;
  String get orderTypesComeFromPlatform;
  String get orderTypeName;
  String get orderTypeNeedsAName;
  String get orderTypeRequiresTable;
  String get orderTypeRequiresTableHint;
  String get orderTypeRequiresCustomer;
  String get orderTypeRequiresCustomerHint;
  String get orderTypeRequiresAddress;
  String get orderTypeRequiresAddressHint;
  String get orderTypeOffered;
  String get orderTypeOfferedHint;
  String get orderTypeNotOffered;
  String get orderTypeChipTable;
  String get orderTypeChipCustomer;
  String get orderTypeChipAddress;
  String get paneTaxes;
  String get paneTaxesHint;

  // BO-1: the back office's tabs, and Settings' side nav.
  String get backOffice;
  String get tabHome;
  String get tabSales;
  String get tabReports;
  String get tabMenu;
  String get tabInventory;
  String get tabPurchasing;
  String get tabFinance;
  String get tabSystem;
  String get tabSettings;
  // The owner's map (14 Sep 2026): People as a tab again, and the map's words
  // for the items it names differently from the panes' own headings.
  String get tabPeople;
  String get reportsSummary;
  String get rolesAndPermissions;
  String get paneDevices;
  String get settingsOrdersInvoices;
  String get settingsLanguage;
  String get settingsLook;
  // BO-4: Home — the landing page's cards, tiles and quick actions.
  String get paneHomeBlurb;
  String homeWelcome(String name);
  String get homeCardConnection;
  String get homeCardLastSync;
  String get homeCardLastBackup;
  String get homeNotSet;
  String get homeNever;
  String homeSalesWaiting(int count);
  String get homeToday;
  String homeDayOpen(String date, String time);
  String homeDayClosed(String date);
  String get homeNoDayYet;
  String get homeSalesUnavailable;
  String get homeKpiNetSales;
  String get homeKpiOrders;
  String get homeKpiAverage;
  String get homeVsPreviousDay;
  String get homeNoComparison;
  String get homeQuickActions;
  String get homeActionReports;
  String get homeActionProducts;
  String get homeActionEmployees;
  // BO-9: Finance — overview, revenue, payments and taxes, read-only.
  String get financeOverview;
  String get financeOverviewBlurb;
  String get financeRevenue;
  String get financeRevenueBlurb;
  String get financePayments;
  String get financePaymentsBlurb;
  String get financeTaxes;
  String get financeTaxesBlurb;
  String get financePeriodToday;
  String get financePeriodThisWeek;
  String get financePeriodThisMonth;
  String get financePeriodLastMonth;
  String get financeBusinessDates;
  String get financeKpiRevenue;
  String get financeKpiCollected;
  String get financeKpiOnAccount;
  String get financeKpiTax;
  String get financeTendersTitle;
  String get financeOnAccountNote;
  String get financeNothingCollected;
  String get financeGross;
  String get financeDiscounts;
  String get financeRefunds;
  String get financeNet;
  String get financeOrders;
  String get financeAverage;
  String get financeDate;
  String get financeTotal;
  String get financeRefundsNote;
  String get financeByMethod;
  String get financeMethod;
  String get financePaymentCount;
  String get financeAmount;
  String get financeShare;
  String get financeLedgerTitle;
  String get financeInvoice;
  String get financeTime;
  String get financeLedgerTotal;
  String financeLedgerTruncated(int count);
  String get financeNoPayments;
  String get financeTaxName;
  String get financeTaxRate;
  String get financeTaxBase;
  String get financeTaxCharged;
  String get financeTaxRefunded;
  String get financeTaxNet;
  String get financeTaxUnattributed;
  String get financeTaxNote;
  String get financeNoTaxes;
  String get financeUnavailable;
  String get financeNoFigures;
  // BO-10: Finance — expenses, drawers, bills due and transactions.
  String get financeExpenses;
  String get financeExpensesBlurb;
  String get financeDrawers;
  String get financeDrawersBlurb;
  String get financeBills;
  String get financeBillsBlurb;
  String get financeTransactions;
  String get financeTransactionsBlurb;
  String get financeKpiExpenses;
  String get financeExpensesWithSuppliers;
  String get financeExpensesPayOutsOnly;
  String get financeSuppliersOnPlatform;
  String get financeSuppliersNotPermitted;
  String get financeCountedOnce;
  String get financePayOuts;
  String get financeSupplierPayments;
  String get financeNoExpenses;
  String get financeRecentExpenses;
  String get financeViewAll;
  String get financeType;
  String get financeDetails;
  String get financeKpiDrawers;
  String financeOpenDrawerCount(int count);
  String get financeNoOpenDrawers;
  String get financeOpenedBy;
  String get financeOpenedAt;
  String get financeFloat;
  String get financeCashTaken;
  String get financePaidIn;
  String get financePaidOut;
  String get financeExpected;
  String get financeDrawersNote;
  String get financeAsOf;
  String get financeBucketOverdue;
  String get financeBucketToday;
  String get financeBucketWeek;
  String get financeBucketLater;
  String get financeTotalOwed;
  String get financeSupplier;
  String get financeDueDate;
  String get financePaid;
  String get financeOutstanding;
  String get financeNoBills;
  String get financeBillsNote;
  String get financeRecentTransactions;
  String get financeReference;
  String get financeStatus;
  String get financeKindSale;
  String get financeKindPayOut;
  String get financeKindSupplierInvoice;
  String get financeKindSupplierPayment;
  String get financeStatusPaid;
  String get financeStatusPartlyPaid;
  String get financeStatusUnpaid;
  String get financeStatusPartlyRefunded;
  String get financeStatusRefunded;
  String get financeStatusOpen;
  String get financeStatusVoided;
  String get financeStatusRecorded;
  String get financeNoTransactions;
  String financeTransactionsTruncated(int count);
  String get financeTransactionsNote;
  String get settingsGeneral;
  // Settings › General's two cards, and Language and Appearance (BO-8).
  String get settingsAppearance;
  String get paneAppearanceBlurb;
  String get appearanceThisTerminal;
  String get appearanceLanguage;
  String get appearanceTheme;
  String get themeSystem;
  String get themeLight;
  String get themeDark;
  String get themeSystemHint;
  String get backupLastCopy;
  String get backupNowNeedsPermission;
  String get manage;
  String get manageMenuTooltip;
  String get backToTill;
  String get paneStaff;
  String get paneStaffBlurb;

  /// The Sales tab's one pane: the order history, re-hosted (BO-2).
  String get paneSalesBlurb;

  // BO-6: the Reports tab — period, tiles, charts, terminals and insights.
  // Net sales, orders and the average are Home's words (`homeKpi…`), and the
  // table's gross, discounts and till are the day close's and the history's:
  // one figure, one word, on every tab that shows it.
  String get paneReportsBlurb;
  String get reportPeriodToday;
  String get reportPeriodWeek;
  String get reportPeriodMonth;
  String get reportPeriodCustom;
  String get reportVsPrevious;
  String get reportNoComparison;
  String get reportKpiRefunds;
  String reportRefundCount(int count);
  String get reportTrend;
  String get reportTopProducts;
  String get reportTopProductsNote;
  String get reportRankQuantity;
  String get reportRankAmount;
  String get reportColumnQuantity;
  String get reportColumnAmount;
  String get reportNoProducts;
  String get reportPayments;
  String get reportOnAccount;
  String get reportNoPayments;
  String get reportTerminals;
  String get reportBranchTotal;
  String get reportUnregistered;
  String get reportInsights;
  String get reportInsightBestDay;
  String get reportInsightTopTerminal;
  String get reportInsightGrowth;
  String get reportInsightsNone;
  String get reportUnavailable;
  String get reportNoDatabase;

  // ── Excel export (BO-11) ──────────────────────────────────────────
  // The button on Reports and on the Sales list, and the words inside the
  // file. The file's headings are the screen's own words wherever the screen
  // has one; these are only what a sheet needs that a screen does not say.
  String get exportExcel;
  String get exportExcelDialogTitle;
  String exportExcelSaved(String path);
  String exportExcelFailed(String reason);
  String get exportSheetSummary;
  String get exportPeriodFrom;
  String get exportPeriodTo;
  String get exportColumnFigure;
  String get exportColumnValue;
  String get exportColumnNote;
  String get exportColumnDate;
  String get exportColumnOccurredAt;
  String get exportColumnShare;
  String get exportColumnRank;
  String get exportColumnProduct;
  String get paneMenu;
  String get paneMenuBlurb;
  String get panePurchasing;
  String get panePurchasingBlurb;
  String get paneRoles;
  String get paneRolesBlurb;
  String get paneActivity;
  String get paneActivityBlurb;

  // ── Backup and restore ────────────────────────────────────────────
  // One contiguous block here and in each implementation below, so this lands
  // as a single insert rather than forty interleavings.
  String get paneBackup;
  String get paneBackupBlurb;
  String get backupSameDiskWarning;
  String get backupToolsMissing;
  String get backupToolsMissingHelp;
  String get backupSearchedIn;
  String get backupDestination;
  String get backupDestinationHint;
  String get backupTakeNow;
  String get backupTaking;
  String get backupAutomatic;
  String get backupAutomaticHint;
  String get backupHistory;
  String get backupNoneYet;
  String get backupNoVerifiedCopy;
  String backupLastVerified(String when);
  String backupStale(int days);
  String get backupOutcomeVerified;
  String get backupOutcomeUnverified;
  String get backupOutcomeFailed;
  String get backupTriggerManual;
  String get backupTriggerDayClose;
  String get backupFailureToolsMissing;
  String get backupFailureDestinationUnwritable;
  String get backupFailureDumpRefused;
  String get backupFailureArchiveUnreadable;
  String get backupFailureArchiveIncomplete;
  String backupTablesFound(int count);
  String get backupRestoreAction;
  String backupRestoreTitle(String when);
  String get backupRestoreBlocked;
  String restoreBlockerOpenShifts(int count);
  String restoreBlockerOpenDay(int count);
  String backupRestoreOrdersLost(int count, String value);
  String get backupRestoreEverythingElseLost;
  String get backupRestoreNoWayBack;
  String get backupRestoreConfirm;
  String get backupRestoreKeep;
  String get backupRestoreDone;
  String backupRestoreFailed(String detail);
  String get backupAccount;
  String get backupAccountHint;
  String get backupAccountStored;
  String get backupAccountMissing;
  String get backupAccountSaved;
  String get backupCopyAction;
  String backupCopyDone(String path);
  String backupCopyFailed(String detail);
  String get backupRestoreFromFile;
  String get backupFileGone;
  String get backupOpenPane;
  String get backupDayCloseWorking;
  String get backupDayCloseFailed;
  String get actBackupTaken;
  String get actBackupRestored;
  String get actAdminEntered;
  String get actAdminExited;
  String get actAdminTimedOut;
  String get actAdminRefused;
  String get actAdminLockedOut;

  // ── Admin Mode ────────────────────────────────────────────────────────────
  //
  // The back office as a session: a hidden shortcut, a username and PIN, and
  // a lock when nobody has touched it for a while.
  /// The header inside Admin Mode: the product, the mode, the page — so nobody
  /// has to guess whether they are selling or administering.
  String adminTitle(String pane);
  String get exitAdminMode;
  String get adminSignInTitle;
  String adminSignInHelp(int minutes);
  String get yourPin;
  String get openAdminMode;

  /// One refusal for every way of being wrong — an unknown username, a wrong
  /// PIN, and the right PIN from somebody without `admin.enter` all read the
  /// same, so the form is no way of finding out who may get in.
  String get adminSignInRefused;

  /// The same refusal, and how many more tries this terminal allows before
  /// the door shuts for a while — the shape the supervisor's keypad uses.
  String adminSignInAttemptsLeft(int attempts);

  /// Too many wrong tries: nothing is checked until the wait is over.
  String adminSignInLockedOut(int seconds);

  /// Asked once per till, and only of somebody whose username and PIN already
  /// got them in: installs from before Admin Mode never kept this password.
  String get adminDatabasePasswordNeeded;
  String get adminDatabasePasswordRefused;
  String adminLockedAfter(int minutes);
  String get adminModeSettingsHint;
  String get adminLockAfter;
  String adminMinutes(int minutes);
  String get adminShortcut;
  // ── end of the backup block ────────────────────────────────────
  String get pinCannotOpenManagement;
  String get managementPinHelp;
  String get managementPinRetryHelp;
  String cannotManageStaff(String name);
  String get backOfficePassword;
  String get backOfficeSignInHelp;
  String get backOfficeSignInRefused;
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
  String get settingsOrders;
  String get settingsPrinter;
  String get settingsAbout;
  String get printerSettingsTitle;
  String get printerNoneChosen;
  String get aboutVersion;
  String get aboutMode;
  String get aboutTerminalId;
  String get aboutDatabase;
  String get receiptPreviewAction;
  String get receiptPreviewNote;
  String get paneUnits;
  String get paneUnitsBlurb;

  // CB-09: on a cloud till the platform authors buying and stock.
  String get purchasingComesFromPlatform;
  String get purchasingOnPlatformEntry;
  String get unitNew;
  String get unitEdit;
  String get unitNameEn;
  String get unitNameAr;
  String get unitCode;
  String get unitCodeHelp;
  String get unitEtaCode;
  String get unitEtaCodeHelp;
  String get unitAllowsFraction;
  String get unitAllowsFractionHelp;
  String get unitFractionChip;
  String get unitActive;
  String get unitRetired;
  String get actUnitSaved;
  String get paneItems;
  String get paneItemsBlurb;
  String get itemNew;
  String get itemEdit;
  String get itemName;
  String get itemNameAr;
  String get itemUnit;
  String get itemOnMenu;
  String get itemOnMenuHint;
  String get itemsEmpty;
  String get fieldTrackStock;
  String get fieldTrackStockHint;
  String get actStockItemSaved;
  String get paneStock;
  String get paneStockBlurb;
  String get stockColumnItem;
  String get stockColumnOnHand;
  String get stockColumnAvgCost;
  String get stockColumnValue;
  String stockTotalValue(String amount);
  String get stockEmpty;
  String get purchaseUnit;
  String purchaseAddAsItem(String name);
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

  // BO-7: Settings › Users — tiles, filters, table and the role matrix.
  String get usersKpiStaff;
  String get usersKpiActive;

  /// Under the active count: its share of every account, disabled included.
  String usersActiveShare(int percent);
  String get usersKpiShifts;
  String get usersKpiShiftsNote;
  String get usersKpiRoles;
  String get staffStatusAll;
  String get staffStatusActive;
  String get staffStatusDisabled;
  String get usersAllRoles;
  String get usersSearchHint;
  String get usersColumnStatus;

  /// "Last shift", never "last login": no sign-in is recorded, and a column
  /// that says login and shows shifts would be wrong about every cashier who
  /// signed in and sold without opening a drawer.
  String get usersColumnLastShift;
  String get usersOnShiftNow;
  String get usersNeverOnShift;
  String get usersNoneMatch;
  String get manageRoles;
  String get roleMatrixTitle;

  /// Under the matrix: it counts role grants, not what one person may do.
  String get roleMatrixNote;
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

  // ── Management: sizes and extras ──────────────────────────────────────────
  // The cloud dashboard's words, in both languages, taken from its i18n file
  // (`item.*`, `extras.*`) rather than rewritten: the owner's instruction is
  // that the desktop and the cloud say the same thing, and a manager who uses
  // both should not have to learn two names for one switch. Its "(s)" plurals
  // are kept as it writes them for the same reason.
  String get extrasTitle;
  String get extrasSubtitle;
  String get extrasNew;
  String get extrasEdit;
  String get extrasNone;
  String extrasUsedBy(int n);
  String get extrasNotUsed;
  String extrasDeleteWarning(int n);
  String extrasOptionsSummary(int n);
  String get extrasApplyTo;
  String get extrasScopeItems;
  String get extrasScopeItemsHint;
  String get extrasScopeCategories;
  String get extrasScopeAll;
  String get extrasPickCategories;
  String extrasAppliesCategories(int n);
  String get extrasLibraryNameEn;
  String get extrasLibraryNameAr;
  String get extrasLibraryNameHint;
  String get extrasMenuNameEn;
  String get extrasMenuNameAr;
  String get extrasMenuNamePlaceholder;
  String get extrasMenuNameHint;
  String extrasShownAs(String name);
  String get itemOptions;
  String get itemNoOptions;
  String get itemAddGroup;
  String get itemGroupNameEn;
  String get itemGroupNameAr;
  String get itemRequired;
  String get itemVariant;
  String get itemVariantHint;
  String get itemPricedBySize;
  String get itemDefaultSize;
  String get itemOptionDiscount;
  String get itemOptionDiscountHint;
  String get itemMaxSelect;
  String get itemOptionEn;
  String get itemOptionAr;
  String get itemAddOption;
  String get itemAddFromLibrary;
  String get itemFromLibrary;
  String get itemLibraryEmpty;
  String get itemManageLibrary;
  String get deleteLabel;
  String get deleteConfirmGeneric;
  String get savingLabel;

  // Why a size or extra was refused. See `OptionGroupProblem`.
  String get refusalGroupNameMissing;
  String get refusalGroupScopeNeedsLibrary;
  String get refusalGroupCategoriesMissing;
  String refusalGroupChoicesOutOfRange(int max);
  String get refusalGroupNegativeCounts;
  String get refusalGroupNeedsMoreThanAllows;
  String refusalGroupTooManyOptions(int max);
  String get refusalGroupRequiredButEmpty;
  String get refusalOptionNameMissing;
  String get refusalOptionTwice;
  String get refusalOptionNegativePrice;
  String get refusalOptionSaleNotBelowPrice;
  String get refusalGroupTwice;
  String get refusalGroupTypedOnAnotherItem;
  String refusalGroupNotInLibrary(String name);
  String refusalGroupAlreadyReaches(String name);
  String refusalGroupSecondSizes(int count, String names);
  String refusalGroupWouldGiveSecondSizes(String item);
  String get refusalGroupBelongsToOneItem;
  String get refusalGroupBelongsToLibrary;
  String get refusalGroupForeignOption;
  String get refusalGroupForeignCategory;

  // Why an item or a category was refused. See `CatalogProblem`.
  String get refusalItemNameMissing;
  String get refusalOfferAbovePrice;
  String get refusalCategoryNameMissing;

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

  // The strip over the list (BO-3). Each figure carries a line saying what it
  // leaves out, because four numbers that do not add up to each other are
  // otherwise a report somebody rings about.
  String get orderSummaryTotal;

  /// Voided and fully refunded sales are struck through on the list and left
  /// out of the total.
  String get orderSummaryTotalNote;
  String get orderSummaryCount;

  /// How many of the invoices counted are struck through. [count] > 0.
  String orderSummaryCountDead(int count);
  String get orderSummaryPaid;
  String get orderSummaryPaidNote;
  String get orderSummaryOutstanding;
  String get orderSummaryOutstandingNote;

  // The pager under the list: "Showing 51–100 of 213". Words and figures are
  // separate pieces, never one interpolated sentence, so each figure is its
  // own left-to-right run inside an Arabic line.
  String get orderPagerShowing;
  String get orderPagerOf;
  String get orderPagerPrevious;
  String get orderPagerNext;
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

  // Sales list and sale details (plan 17 S1).
  String get orderColumnPayment;

  /// The methods a sale was paid in, every one of a split bill (BO-2) —
  /// beside [orderColumnPayment], which says where the money stands.
  String get orderColumnMethod;

  /// The till that rang the sale up (BO-2).
  String get orderColumnTerminal;
  String get orderHistoryEveryMethod;
  String get orderHistoryEveryTerminal;

  /// The list is narrowed to the viewer's own sales because they do not hold
  /// `order.view_all`. Said on screen, or a cashier concludes the rest of the
  /// day's sales are missing.
  String get orderHistoryOwnSalesOnly;

  /// `served_by` before [reliableFrom] credited shared-PIN sales to one person.
  /// [reliableFrom] is a Latin-digit date in both languages.
  String orderHistoryAttributionCaveat(String reliableFrom);
  /// Followed by the date in mono, never interpolated: a date inside an
  /// Arabic sentence is one bidi run away from reading backwards.
  String get orderDetailBusinessDay;
  String get orderDetailTerminal;
  String get orderDetailActivity;
  String get saleEventPrinted;
  String get saleEventPrintPending;
  String get saleEventReprinted;
  String get saleEventReprintPending;
  String get saleEventReprintRequested;
  String get saleEventVoided;
  String get saleEventRefunded;
  String get paymentStatusUnpaid;
  String get paymentStatusPartiallyPaid;
  String get paymentStatusPaid;
  String get paymentStatusPartiallyRefunded;
  String get paymentStatusRefunded;

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

  // ── Reprinting a receipt ──────────────────────────────────────────────────

  /// Stamped across the top of a reprinted slip. Uppercase, mono, boxed — it
  /// has to survive being photographed and photocopied.
  String get receiptReprintMark;

  /// Also on the slip, so a reprint cannot be used to claim a refund that has
  /// already been given.
  String receiptRefundedMark(String amount);

  String get receiptReprintAction;
  String receiptReprintTitle(String invoice);
  String get receiptReprintExplain;
  String get receiptReprintConfirm;
  String get receiptReprintNotPermitted;

  /// The audit ledger could not be written, so nothing was printed. An
  /// unrecorded reprint is exactly the one somebody wanted.
  String get reprintCouldNotBeRecorded;

  // ── A line's note ─────────────────────────────────────────────────────────
  String lineNoteTitle(String item);
  String get lineNoteHint;

  // ── Combos (§17) ──────────────────────────────────────────────────────────
  String get comboBadge;
  String comboChoose(String group);
  String get comboAddToTicket;
  String comboPickMore(int count);
  String get comboIncluded;

  // ── Importing a menu from a spreadsheet ───────────────────────────────────
  // §17, §113 — the e-receipt queue.
  String get paneEta;
  String get paneEtaBlurb;
  String get etaQueueClear;
  String etaQueueOutstanding(int count);
  String etaQueueLate(int count);
  String etaQueueRejected(int count);
  String get etaQueueOldest;
  String get etaQueueNoSeal;
  String get etaQueueExplain;
  String get etaColumnReceipt;
  String get etaColumnIssued;
  String get etaColumnAge;
  String get etaColumnStatus;
  String etaAgeHours(int hours);
  String etaStatusLabel(String status);
  String get etaDueSoon;
  String get etaLate;
  String etaProblemProfile(int count);
  String etaProblemFailed(String detail);
  String get etaReconcileNow;
  String etaReconcileDone(int sales, int refunds, int waiting);
  String get etaOpenPane;

  // §17, §113 — who the receipt says sold the food.
  String get paneReceipt;
  String get paneReceiptBlurb;
  String get receiptProfileExplain;
  String get receiptProfileOnThePaper;
  String get receiptProfileForTheAuthority;
  String get receiptProfileSave;
  String get receiptProfileSaved;
  String get receiptProfileNoDatabase;
  String get receiptEtaReady;
  String get receiptEtaIncomplete;
  String get receiptEtaNotSetUp;
  String get receiptTradeName;
  String get receiptPhone;
  String get receiptHeaderNote;
  String get receiptFooterNote;
  String get receiptRegistrationNumber;
  String get receiptActivityCode;
  String get receiptBranchCode;
  String get receiptBranchAddress;
  String get receiptCountry;
  String get receiptGovernorate;
  String get receiptCity;
  String get receiptStreet;
  String get receiptBuildingNumber;
  String get receiptPostalCode;
  String get receiptFloor;
  String get receiptRoom;
  String get receiptLandmark;

  String get menuImportAction;
  String get menuImportTitle;
  String get menuImportExplain;
  String get menuImportChooseFile;
  String get menuImportReading;
  String menuImportWillCreate(int count);
  String menuImportWillUpdate(int count);
  String menuImportUnchanged(int count);
  String menuImportNewCategories(String names);
  String get menuImportNothingToDo;
  String get menuImportProblemsTitle;
  String menuImportProblemsCount(int count);

  /// A spreadsheet line, numbered as the spreadsheet numbers it.
  String menuImportLine(int lineNumber);
  String get menuImportNeverDeletes;
  String menuImportApply(int count);
  String menuImportDone(int created, int updated);
  String get menuImportFailed;

  // ── §27's expanded cash-up ────────────────────────────────────────────────
  String get zSubtotal;
  String get zDiscounts;
  String get zService;
  String get zVat;
  String get zRefunds;
  String get zVoids;
  String get zNet;
  String get zCashIn;
  String get zCashOut;
  String get zDrawerOpens;
  String get zVariance;

  /// Shown in place of the expected figure while a blind count is in progress.
  String get zHiddenUntilCounted;

  // ── Money in and out of the drawer (§22) ──────────────────────────────────
  String get payInTitle;
  String get payOutTitle;
  String get payInAction;
  String get payOutAction;
  String get cashAmountLabel;
  String get cashNothingEntered;
  String cashAboveCeiling(String ceiling);
  String get cashRecorded;
  String get cashCouldNotBeRecorded;
  String get cashNoOpenShift;

  // ── Opening the drawer with no sale (§23) ─────────────────────────────────
  String get drawerOpenTitle;
  String get drawerOpenExplain;
  String get drawerOpenAction;
  String get drawerOpened;

  // ── The trading day (§28) ─────────────────────────────────────────────────
  String get dayCloseTitle;
  String dayCloseFor(String date);
  String get dayCloseNothingOpen;
  String get dayCloseClear;
  String get dayCloseBlockersTitle;
  String dayBlockerOpenShifts(int count);
  /// Seated tables and held tickets together: both are money the till has
  /// taken responsibility for and not yet collected.
  String dayBlockerParkedTickets(int count);
  String dayBlockerUnpaidOrders(int count);
  String get dayCloseAction;
  String get dayForceCloseAction;
  String get dayForceReasonLabel;
  String get dayForceReasonNeeded;
  String dayClosed(String gross);
  String get dayCouldNotBeClosed;
  String get dayGross;
  String get dayNet;
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
  String get orderSummaryTotal => 'Total sales';
  @override
  String get orderSummaryTotalNote => 'Voided and refunded left out';
  @override
  String get orderSummaryCount => 'Invoices';
  @override
  String orderSummaryCountDead(int count) =>
      'Of which $count voided or refunded';
  @override
  String get orderSummaryPaid => 'Paid';
  @override
  String get orderSummaryPaidNote => 'Taken, before refunds';
  @override
  String get orderSummaryOutstanding => 'Outstanding';
  @override
  String get orderSummaryOutstandingNote => 'Owed on unpaid and part-paid sales';
  @override
  String get orderPagerShowing => 'Showing';
  @override
  String get orderPagerOf => 'of';
  @override
  String get orderPagerPrevious => 'Previous';
  @override
  String get orderPagerNext => 'Next';
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
  String get orderColumnPayment => 'Payment';
  @override
  String get orderColumnMethod => 'Paid with';
  @override
  String get orderColumnTerminal => 'Till';
  @override
  String get orderHistoryEveryMethod => 'Every payment method';
  @override
  String get orderHistoryEveryTerminal => 'Every till';
  @override
  String get orderHistoryOwnSalesOnly => 'Your sales only';
  @override
  String orderHistoryAttributionCaveat(String reliableFrom) =>
      'Who sold each order is reliable only from $reliableFrom. Before that, '
      'a PIN shared by two people credited all their sales to one of them, so '
      'per-cashier figures for earlier days are not accurate.';
  @override
  String get orderDetailBusinessDay => 'Business day';
  @override
  String get orderDetailTerminal => 'Till';
  @override
  String get orderDetailActivity => 'Activity';
  @override
  String get saleEventPrinted => 'Receipt printed';
  @override
  String get saleEventPrintPending => 'Receipt waiting for the printer';
  @override
  String get saleEventReprinted => 'Copy printed';
  @override
  String get saleEventReprintPending => 'Copy waiting for the printer';
  @override
  String get saleEventReprintRequested => 'Copy requested';
  @override
  String get saleEventVoided => 'Order voided';
  @override
  String get saleEventRefunded => 'Money refunded';
  @override
  String get paymentStatusUnpaid => 'Unpaid';
  @override
  String get paymentStatusPartiallyPaid => 'Part paid';
  @override
  String get paymentStatusPaid => 'Paid';
  @override
  String get paymentStatusPartiallyRefunded => 'Part refunded';
  @override
  String get paymentStatusRefunded => 'Refunded';
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
  String get receiptReprintMark => 'REPRINT — NOT AN ORIGINAL';
  @override
  String receiptRefundedMark(String amount) => 'REFUNDED $amount';
  @override
  String get receiptReprintAction => 'Reprint receipt';
  @override
  String receiptReprintTitle(String invoice) => 'Reprint $invoice';
  @override
  String get receiptReprintExplain =>
      'The slip is marked as a reprint, and this is recorded against your name.';
  @override
  String get receiptReprintConfirm => 'Print';
  @override
  @override
  String get receiptReprintNotPermitted =>
      'You do not have permission to reprint a receipt.';
  @override
  String get reprintCouldNotBeRecorded =>
      'This could not be recorded, so nothing was printed. Try again.';
  @override
  String lineNoteTitle(String item) => 'Note for $item';
  @override
  String get lineNoteHint => 'No onions, well done, on the side…';
  @override
  String get comboBadge => 'MEAL';
  @override
  String comboChoose(String group) => 'Choose $group';
  @override
  String get comboAddToTicket => 'Add meal';
  @override
  String comboPickMore(int count) =>
      count == 1 ? 'Choose 1 more' : 'Choose $count more';
  @override
  String get comboIncluded => 'included';
  @override
  String get paneEta => 'E-receipts';
  @override
  String get paneEtaBlurb => 'What the tax authority has not accepted yet';
  @override
  String get etaQueueClear => 'Everything has been filed.';
  @override
  String etaQueueOutstanding(int count) =>
      count == 1 ? '1 receipt waiting' : '$count receipts waiting';
  @override
  String etaQueueLate(int count) =>
      count == 1 ? '1 past its deadline' : '$count past their deadline';
  @override
  String etaQueueRejected(int count) =>
      count == 1 ? '1 refused' : '$count refused';
  @override
  String get etaQueueOldest => 'Oldest';
  @override
  String get etaQueueNoSeal =>
      'No e-seal is configured on this terminal, so nothing here can be '
      'filed. Receipts are still being recorded and will be sent once one is.';
  @override
  String get etaQueueExplain =>
      'Egypt gives 24 hours from the moment a receipt is issued. A receipt '
      'refused by the authority will not clear on its own.';
  @override
  String get etaColumnReceipt => 'Receipt';
  @override
  String get etaColumnIssued => 'Issued';
  @override
  String get etaColumnAge => 'Age';
  @override
  String get etaColumnStatus => 'Status';
  @override
  String etaAgeHours(int hours) => hours < 1 ? 'under an hour' : '${hours}h';
  @override
  String etaStatusLabel(String status) => switch (status) {
    'pending' => 'Not sealed',
    'signed' => 'Ready to send',
    'submitted' => 'Sent, awaiting a verdict',
    'accepted' => 'Filed',
    'rejected' => 'Refused',
    'cancelled' => 'Closed by hand',
    _ => status,
  };
  @override
  String get etaDueSoon => 'Due soon';
  @override
  String get etaLate => 'Late';
  @override
  String etaProblemProfile(int count) => count == 1
      ? 'E-receipts are not being filed: the receipt profile has 1 thing to '
            'fix.'
      : 'E-receipts are not being filed: the receipt profile has $count '
            'things to fix.';
  @override
  String etaProblemFailed(String detail) =>
      'E-receipts could not be queued. $detail';
  @override
  String get etaReconcileNow => 'File missing receipts now';
  @override
  String etaReconcileDone(int sales, int refunds, int waiting) {
    if (sales + refunds + waiting == 0) return 'Nothing was missing.';
    final parts = [
      if (sales > 0) sales == 1 ? '1 sale receipt' : '$sales sale receipts',
      if (refunds > 0)
        refunds == 1 ? '1 refund receipt' : '$refunds refund receipts',
    ];
    final queued = parts.isEmpty ? '' : 'Queued ${parts.join(' and ')}.';
    final waits = waiting == 0
        ? ''
        : waiting == 1
        ? ' 1 refund is waiting for its sale to be filed first.'
        : ' $waiting refunds are waiting for their sales to be filed first.';
    return '$queued$waits'.trim();
  }
  @override
  String get etaOpenPane => 'Open E-receipts';

  @override
  String get paneReceipt => 'Receipt';
  @override
  String get paneReceiptBlurb => 'What the slip says, and what ETA is told';
  @override
  String get receiptProfileExplain =>
      'Entered once. The top of every printed slip and the seller block of '
      'every e-receipt are the same facts, so they are typed here and read '
      'from here.';
  @override
  String get receiptProfileOnThePaper => 'On the paper';
  @override
  String get receiptProfileForTheAuthority => 'For the tax authority';
  @override
  String get receiptProfileSave => 'Save';
  @override
  String get receiptProfileSaved => 'Saved.';
  @override
  String get receiptProfileNoDatabase =>
      'This terminal has no database configured, so there is nothing to save '
      'a receipt profile to.';
  @override
  String get receiptEtaReady =>
      'Complete. Receipts from this branch carry everything ETA asks for.';
  @override
  String get receiptEtaIncomplete =>
      'Incomplete. Receipts still print, but they cannot be filed until the '
      'fields marked below are right.';
  @override
  String get receiptEtaNotSetUp =>
      'Not set up yet. Fill this in before the first receipt has to be filed.';
  @override
  String get receiptTradeName => 'Trade name';
  @override
  String get receiptPhone => 'Phone';
  @override
  String get receiptHeaderNote => 'Note above the items';
  @override
  String get receiptFooterNote => 'Note at the bottom';
  @override
  String get receiptRegistrationNumber => 'Tax registration number';
  @override
  String get receiptActivityCode => 'Activity code';
  @override
  String get receiptBranchCode => 'Branch code';
  @override
  String get receiptBranchAddress => 'Branch address';
  @override
  String get receiptCountry => 'Country';
  @override
  String get receiptGovernorate => 'Governorate';
  @override
  String get receiptCity => 'City';
  @override
  String get receiptStreet => 'Street';
  @override
  String get receiptBuildingNumber => 'Building number';
  @override
  String get receiptPostalCode => 'Postal code';
  @override
  String get receiptFloor => 'Floor';
  @override
  String get receiptRoom => 'Room';
  @override
  String get receiptLandmark => 'Landmark';

  @override
  String get menuImportAction => 'Import from a spreadsheet';
  @override
  String get menuImportTitle => 'Import the menu';
  @override
  String get menuImportExplain =>
      'A CSV or Excel file with a category, a name and a price on each row.';
  @override
  String get menuImportChooseFile => 'Choose a file';
  @override
  String get menuImportReading => 'Reading the file…';
  @override
  String menuImportWillCreate(int count) =>
      count == 1 ? 'Adds 1 item' : 'Adds $count items';
  @override
  String menuImportWillUpdate(int count) =>
      count == 1 ? 'Changes 1 item' : 'Changes $count items';
  @override
  String menuImportUnchanged(int count) =>
      count == 1 ? '1 row already matches' : '$count rows already match';
  @override
  String menuImportNewCategories(String names) => 'New categories: $names';
  @override
  String get menuImportNothingToDo =>
      'Every row already matches the menu. Nothing to do.';
  @override
  String get menuImportProblemsTitle => 'Fix these and try again';

  @override
  String menuImportLine(int lineNumber) => 'Line $lineNumber';
  @override
  String menuImportProblemsCount(int count) =>
      count == 1 ? '1 problem' : '$count problems';
  @override
  String get menuImportNeverDeletes =>
      'Nothing is removed. Items not in the file are left alone.';
  @override
  String menuImportApply(int count) =>
      count == 1 ? 'Import 1 item' : 'Import $count items';
  @override
  String menuImportDone(int created, int updated) =>
      'Imported — $created added, $updated changed';
  @override
  String get menuImportFailed =>
      'Nothing was imported. The menu is unchanged.';

  @override
  String get zSubtotal => 'Subtotal';
  @override
  String get zDiscounts => 'Discounts given';
  @override
  String get zService => 'Service';
  @override
  String get zVat => 'VAT';
  @override
  String get zRefunds => 'Refunded';
  @override
  String get zVoids => 'Voided';
  @override
  String get zNet => 'Net takings';
  @override
  String get zCashIn => 'Cash in';
  @override
  String get zCashOut => 'Cash out';
  @override
  String get zDrawerOpens => 'Drawer opened without a sale';
  @override
  String get zVariance => 'Difference';
  @override
  String get zHiddenUntilCounted => 'Hidden until you have counted';
  @override
  String get payInTitle => 'Cash in';
  @override
  String get payOutTitle => 'Cash out';
  @override
  String get payInAction => 'Record cash in';
  @override
  String get payOutAction => 'Record cash out';
  @override
  String get cashAmountLabel => 'Amount';
  @override
  String get cashNothingEntered => 'Enter an amount above zero.';
  @override
  String cashAboveCeiling(String ceiling) =>
      'That is above the $ceiling limit for one payment out.';
  @override
  String get cashRecorded => 'Recorded';
  @override
  String get cashCouldNotBeRecorded =>
      'That could not be recorded, so nothing has moved. Try again.';
  @override
  String get cashNoOpenShift => 'Open a shift before moving cash.';
  @override
  String get drawerOpenTitle => 'Open the drawer?';
  @override
  String get drawerOpenExplain =>
      'No sale is attached to this, so it is recorded with your name and the time.';
  @override
  String get drawerOpenAction => 'Open drawer';
  @override
  String get drawerOpened => 'Drawer opened, and recorded';
  @override
  String get dayCloseTitle => 'Close the day';
  @override
  String dayCloseFor(String date) => 'Trading day $date';
  @override
  String get dayCloseNothingOpen => 'No trading day is open at this branch.';
  @override
  String get dayCloseClear => 'Everything is settled. The day can close.';
  @override
  String get dayCloseBlockersTitle => 'These are still open';
  @override
  String dayBlockerOpenShifts(int count) =>
      count == 1 ? '1 till still has a drawer open' : '$count tills still have drawers open';
  @override
  String dayBlockerParkedTickets(int count) => count == 1
      ? '1 ticket is still parked'
      : '$count tickets are still parked';
  @override
  String dayBlockerUnpaidOrders(int count) =>
      count == 1 ? '1 order has not been paid' : '$count orders have not been paid';
  @override
  String get dayCloseAction => 'Close the day';
  @override
  String get dayForceCloseAction => 'Close anyway';
  @override
  String get dayForceReasonLabel => 'Why are you closing over these?';
  @override
  String get dayForceReasonNeeded =>
      'Closing over open work has to say why.';
  @override
  String dayClosed(String gross) => 'Day closed. Gross $gross';
  @override
  String get dayCouldNotBeClosed =>
      'The day could not be closed, so it is still open. Try again.';
  @override
  String get dayGross => 'Gross';
  @override
  String get dayNet => 'Net';

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
  @override
  @override
  String get searchHint => 'Scan barcode or search item / PLU';
  @override
  String get customAmount => 'Custom amount';
  @override
  String get openItemTitle => 'Charge for something not on the menu';
  @override
  String get openItemName => 'What is it?';
  @override
  String get openItemNameHint => 'Delivery, corkage, birthday cake…';
  @override
  String get openItemPrice => 'Price, each';
  @override
  String get openItemAdd => 'Add to ticket';
  @override
  String get openItemNeedsName =>
      'Give it a name. It is what the customer reads on the receipt.';
  @override
  String get openItemNeedsPrice => 'Enter a price of zero or more.';
  @override
  String get openItemNotPermitted =>
      'You do not have permission to charge a price that is not on the menu.';
  @override
  String openItemAdded(String name) => '$name added';
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
  String get branchDatabaseReady => '● Branch server';
  @override
  String get branchDatabaseChecking => '● Checking branch server…';
  @override
  String get branchDatabaseUnreachable => '● Branch server unreachable';
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
  String get chooseTableFirst =>
      'Choose a table first — this order is served at one.';
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
  String get heldTickets => 'Held tickets';
  @override
  String heldTicketsKey(int count) => 'Held  $count';
  @override
  String get heldTicketsHelp =>
      'Parked with no table. Tap one to bring it back — whatever is on screen '
      'is parked first, so nothing is lost.';
  @override
  String get noHeldTickets => 'Nothing is being held.';
  @override
  String heldTicketSummary(String orderType, int items) =>
      items == 1 ? '$orderType · 1 item' : '$orderType · $items items';
  @override
  String get ticketParked => 'Ticket parked. It is under Held.';

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
  String taxRegistrationLine(String number) => 'TAX REG $number';
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
  String get receiptPrintedToast => 'Receipt printed.';
  @override
  String get receiptQueuedToast =>
      'The printer did not answer. The receipt is queued and will print on the '
      'next attempt.';
  @override
  String get receiptNotPrintedToast =>
      'Not printed, and it could not be queued — check the printer and the '
      'branch connection.';
  @override
  String get receiptNoPrinterToast =>
      'No printer is set up on this till, so nothing was printed.';
  @override
  String get printerPaperWidth => 'Paper width';
  @override
  String get printerPaper80 => '80mm roll (576 dots)';
  @override
  String get printerPaper58 => '58mm roll (384 dots)';
  @override
  String get printerPaperWidthHelp =>
      'Measure the roll, not the printer. A receipt built for the wrong width '
      'is cut off at the edge rather than shrunk to fit.';

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
  String get enterYourPin => 'Enter your PIN';

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
  String get switchUser => 'Switch user';
  @override
  String get wrongUsernameOrPin => 'Wrong username or PIN — try again';
  @override
  String get openTheDrawer => 'Open the drawer';
  @override
  String get signInHelp =>
      'Your name and your PIN. The shift is opened in your name.';
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
  String closeShiftNotYours(String openedBy) =>
      'Close a drawer opened by $openedBy';
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
  String get stepMainDevice => 'Main device';
  @override
  String get stepMainDeviceBlurb =>
      'This tablet sells through the restaurant\'s main device.';
  @override
  String get stepChildAccountBlurb =>
      'A manager\'s username and PIN, from the main device.';
  @override
  String get mainDeviceHelp =>
      'Nothing is activated or built on this tablet. The licence, the '
      'restaurant, the staff and the menu all come from the main device — '
      'give its address and the till database password it was set up with.';
  @override
  String get mainDeviceAddress => 'Main device address';
  @override
  String get mainDeviceAddressHelp =>
      'Its address on the restaurant network. Settings on the main device '
      'shows it; a reserved address on the router keeps it from changing.';
  @override
  String get mainDeviceIsThisTablet =>
      'That address is this tablet itself. Enter the main device\'s address '
      'on the restaurant network, such as 192.168.1.20.';
  @override
  String get connectToMainDevice => 'Connect to the main device';
  @override
  String mainDeviceLinked(String tenant) =>
      'Connected to $tenant\'s main device. This tablet uses its licence.';
  @override
  String get mainDeviceHasNoLicence =>
      'The main device has not shared its licence yet. Open XOrder POS on '
      'the main device — it shares the licence when it reaches its start '
      'screen — then connect again.';
  @override
  String allTerminalsTaken(int max) =>
      'The licence covers $max terminals and all of them are registered. '
      'Retire one on the main device, or ask for a licence with more.';
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
  String schemaUpgradeFailed(String error) =>
      'This database is older than this version of XOrder POS and could not '
      'be brought up to date, so some screens may fail. Take a backup and '
      'call support. The database said: $error';
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
  String ownerAlreadyExists(String name, String username) =>
      '$name is already the owner of this restaurant, and a restaurant has '
      'one — so nobody new was made the owner. To set this till up as $name, '
      'put their username, $username, in the username field and build the '
      'database again; their PIN is left as it is. If the restaurant has a new '
      'owner, disable $name first — in Management, on a till that is already '
      'running — then build it again.';
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
  String get resetTerminalHint =>
      'For a till moving to another branch server, or one whose database '
      'password has been lost. Setup runs again; sales already recorded stay in '
      'the database. Not while a shift is open.';
  @override
  String get paneTerminal => 'Terminal';
  @override
  String get paneTerminalBlurb => "This till's setup, and running it again";

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
  String get forceResetSignInTitle => 'Who is resetting this terminal?';
  @override
  String get forceResetSignInHelp =>
      "Deleting a working terminal's setup needs somebody who may manage "
      'terminals: their username and PIN.';
  @override
  String get forceResetSignInRefused =>
      'That username and password cannot reset this terminal.';

  @override
  String get settings => 'Settings';
  @override
  String get syncNow => 'Sync now';
  @override
  String get management => 'Management';
  @override
  String get staffAndAccounts => 'Staff & accounts…';
  @override
  String get windowMenu => 'Window';

  @override
  String get capOperate => 'Sell at the till';
  @override
  String get capCatalogView => 'See the menu';
  @override
  String get capCatalogManage => 'Add and change menu items and prices';
  @override
  String get capPurchaseManage =>
      'Order stock, book in deliveries and pay suppliers';
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
  String get capCashOpenWithoutSale => 'Open the drawer without a sale';
  @override
  String get capShiftViewExpectedCash =>
      'See what the drawer should hold, before counting it';
  @override
  String get capCashVarianceView => 'See the difference after counting';
  @override
  String get capDayClose => 'Close the trading day';
  @override
  String get capDayForceClose =>
      'Close the day while tables or orders are still open';
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
  String get capAdminEnter => 'Open Admin Mode';
  @override
  String get capPaymentRemove => 'Take a payment off an unsettled bill';
  @override
  String get capReportExport => 'Export reports and sales to Excel';
  @override
  String removePaymentTitle(String what) => 'Take $what off this bill';
  @override
  String get removePaymentAction => 'Take it off';
  @override
  String get removePaymentRefused =>
      'That payment stays on the bill: taking it off needs a supervisor.';

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
  String refusalCannotGrantWhatYouLack(String capabilities) =>
      'You cannot grant $capabilities, because you do not hold it yourself. '
      'Ask somebody who does.';

  @override
  String refusalManagedByPlatform(String what) => switch (what) {
    'staff' =>
      'Who works here is set on XOrder, not on this till. A change made here '
      'would be undone by the next sync.',
    'catalogue' =>
      'The menu is set on XOrder, not on this till. A change made here would '
      'be undone by the next sync.',
    'floor' => 'The floor plan is set on XOrder, not on this till.',
    'money' => 'The money rules are set on XOrder, not on this till.',
    _ => 'This is set on XOrder, not on this till.',
  };

  @override
  String refusalOwnerAlreadyExists(String ownerName) =>
      '$ownerName is already the owner, and a restaurant has one. To hand '
      'ownership over, disable $ownerName first, then choose Owner for the new '
      'person.';
  @override
  String get refusalOwnerIsFixed =>
      "The owner's role and permissions cannot be changed. The owner already "
      'holds every permission, and one taken away from them could lock '
      'everybody out. To hand ownership over, disable the owner, then make '
      'somebody else the owner.';
  @override
  String get refusalOwnerPinIsTheirs =>
      "Only the owner can change the owner's PIN. It opens everything, so "
      'nobody else may set it — the owner changes it from their own row here.';
  @override
  String get refusalOwnerIsNotAnExtraRole =>
      'Owner cannot be an extra role. To make somebody the owner, choose Owner '
      'as their role instead.';

  @override
  String get refusalPurchaseAlreadySent =>
      'That order has already gone to the supplier, so it cannot be sent '
      'again or changed.';
  @override
  String get refusalPurchaseGoodsArrived =>
      'Goods have already arrived against that order, so it cannot be '
      'changed.';
  @override
  String get refusalPurchaseCancelled =>
      'That order was cancelled, and a cancelled order does not reopen. Write '
      'a new one.';
  @override
  String get refusalPurchaseHasNoLines =>
      'There is nothing on this order yet. Add what you are ordering before '
      'sending it.';
  @override
  String get refusalPurchaseQuantityNotPositive =>
      'Every line needs a quantity above zero.';
  @override
  String get refusalPurchaseCannotCancelArrived =>
      'Goods have already arrived against this order, so it cannot be '
      'cancelled — they are in stock, and this order is their record. It '
      'stays open for the rest.';
  @override
  String get refusalPurchaseAllArrived =>
      'Everything on this order has arrived, so there is nothing left to '
      'cancel.';
  @override
  String get refusalPurchaseFollowsTheGoods =>
      'An order becomes received by booking the goods in, not by choosing it.';
  @override
  String refusalStockHeldInAnotherUnit(
    String item,
    String quantity,
    String heldUnit,
    String askedUnit,
  ) =>
      '$item has $quantity $heldUnit in stock. Stock is never converted from '
      'one unit to another, so while any is held it is counted and booked in '
      'as $heldUnit only, not $askedUnit.';

  @override
  String get staffComesFromPlatform =>
      'Who works here comes from XOrder. You can still set what each person '
      'may do — roles and permissions live on this till.';

  @override
  String get riskLow => 'Low';
  @override
  String get riskMedium => 'Medium';
  @override
  String get riskHigh => 'High';
  @override
  String get riskCritical => 'Critical';
  @override
  String get roleCannotGrant => 'you do not hold this';
  @override
  String get roleNew => 'New role';
  @override
  String get roleTemplateExplain =>
      'Start from one of these and edit it. Nothing about it stays special.';
  @override
  String roleTemplateCount(int count) =>
      count == 1 ? '1 permission' : '$count permissions';

  @override
  String grantsFor(String name) => 'Permissions for $name';
  @override
  String get grantsExplain =>
      'Exceptions to what their role already gives them. Tap a permission to '
      'take it away, or to grant it to this person alone.';
  @override
  String get grantsExtraRoles => 'Also holds';
  @override
  String get grantsCeilings => 'Limits';
  @override
  String get grantsDiscountCeiling => 'Largest discount';
  @override
  String get grantsNoCeiling => 'none';
  @override
  String get grantsExceptions => 'Permissions';
  @override
  String get grantsFromRole => 'from their role';
  @override
  String get grantsAllowed => 'granted';
  @override
  String get grantsDenied => 'taken away';
  @override
  String get grantsAction => 'Permissions';

  @override
  String get tenderTypes => 'Payment methods';
  @override
  String get tenderTypesHint =>
      'What the till offers at payment, and which of them end up in the '
      'drawer.';
  @override
  String get tenderTypesComeFromPlatform =>
      'On this till, payment methods come from XOrder. Add or change them on '
      'the dashboard; they arrive here at the next sync.';
  @override
  String get tenderNew => 'New payment method';
  @override
  String get tenderEdit => 'Payment method';
  @override
  String get tenderNameEn => 'Name';
  @override
  String get tenderNameAr => 'Arabic name';
  @override
  String get tenderCode => 'Code';
  @override
  String get tenderKind => 'Kind';
  @override
  String tenderKindName(String wire) => switch (wire) {
    'cash' => 'Cash',
    'card' => 'Card',
    'wallet' => 'Wallet',
    'account' => 'On account',
    'voucher' => 'Voucher',
    _ => 'Other',
  };
  @override
  String get tenderCountsAsCash => 'Counts as cash';
  @override
  String get tenderCountsAsCashHint =>
      'The drawer is expected to hold it at cash-up.';
  @override
  String get tenderOpensDrawer => 'Opens the drawer';
  @override
  String get tenderOpensDrawerHint =>
      'Not the same question — vouchers kept in the till open it without being '
      'cash.';
  @override
  String get tenderRequiresReference => 'Needs a reference';
  @override
  String get tenderRefundAllowed => 'Money can go back this way';
  @override
  String get tenderActive => 'Offered at the till';
  @override
  String get tenderActiveHint =>
      'Turning this off retires it. Sales already taken on it keep their name.';
  @override
  String get tenderRetired => 'retired';

  @override
  String get serviceCharges => 'Service charges';
  @override
  String get serviceChargesHint =>
      'What is added on top of the food, and which orders it applies to.';
  @override
  String get serviceChargesFallback =>
      'None configured — the single rate above is being charged.';
  @override
  String get chargeNew => 'New charge';
  @override
  String get chargeEdit => 'Charge';
  @override
  String get chargeName => 'Name on the bill';
  @override
  String get chargeHow => 'How it is worked out';
  @override
  String get chargePercentage => 'A percentage';
  @override
  String get chargeFixed => 'A fixed amount';
  @override
  String get chargeAppliesTo => 'Applies to';
  @override
  String get chargeAppliesToHint => 'Choose none and it applies to every order.';
  @override
  String get chargeTaxable => 'VAT is charged on it';
  @override
  String get chargeTaxableHint =>
      'Off for a fee collected on somebody else\'s behalf.';
  @override
  String get chargeAutomatic => 'Added without being asked';
  @override
  String get chargeOptional => 'The customer may decline it';
  @override
  String get chargeOptionalHint =>
      'Removing it is then not an override and needs no permission.';
  @override
  String get chargeActive => 'In use';
  @override
  String get currencyEgp => 'EGP';

  @override
  String get suppliers => 'Suppliers';
  @override
  String get supplierNew => 'New supplier';
  @override
  String get supplierEdit => 'Supplier';
  @override
  String get supplierName => 'Name';
  @override
  String get supplierContact => 'Who to call';
  @override
  String get supplierEmail => 'Email';
  @override
  String get supplierPaymentTerms => 'Days to pay';
  @override
  String get supplierTermsHint =>
      'Zero means cash on delivery. This is what an invoice is due by, not a limit on it.';
  @override
  String get supplierCode => 'Your reference for them';
  @override
  String get supplierNotes => 'Notes';
  @override
  String get supplierActive => 'Still buying from them';
  @override
  String get supplierActiveHint =>
      'Turning this off keeps the history and stops them appearing on new orders.';
  @override
  String get supplierCashOnDelivery => 'cash on delivery';
  @override
  String supplierTermDays(int days) => '$days days';
  @override
  String get purchaseOrders => 'Purchase orders';
  @override
  String get purchaseOrderNew => 'New order';
  @override
  String get purchaseOrderEdit => 'Order';
  @override
  String get purchaseNoOrdersYet => 'Nothing has been ordered yet.';
  @override
  String get purchaseNoSuppliersYet =>
      'No suppliers yet. Add the people you buy from and orders follow.';
  @override
  String get purchaseNeedsASupplier =>
      'Add a supplier first — an order has to be addressed to somebody.';
  @override
  String get purchaseNeedsALine =>
      'Nothing to order. A line needs a name, a quantity and a unit cost.';
  @override
  String get purchaseItem => 'Item';
  @override
  String get purchaseQty => 'Quantity';
  @override
  String get purchaseUnitCost => 'Unit cost';
  @override
  String get purchaseAddLine => 'Add a line';
  @override
  String purchaseLineCount(int count) => count == 1 ? '1 line' : '$count lines';
  @override
  String get purchaseSend => 'Send';
  @override
  String get purchaseReceive => 'Receive';
  @override
  String purchaseReceiveInto(String reference) => 'Receive against $reference';
  @override
  String get purchaseReceiveHint =>
      'Each box starts at what is still owed. Change one where less arrived.';
  @override
  String get purchaseOrdered => 'Ordered';
  @override
  String get purchaseOutstanding => 'Still owed';
  @override
  String get purchaseArrived => 'Arrived';
  @override
  String purchaseBookIn(int lines) =>
      lines == 1 ? 'Book in 1 line' : 'Book in $lines lines';
  @override
  String get statusDraft => 'draft';
  @override
  String get statusSent => 'sent';
  @override
  String get statusPartReceived => 'part received';
  @override
  String get statusReceived => 'received';
  @override
  String get statusCancelled => 'cancelled';

  @override
  String get supplierInvoices => 'Invoices';
  @override
  String get invoiceNew => 'Enter an invoice';
  @override
  String get invoiceEdit => 'Invoice';
  @override
  String get invoiceHint =>
      'Type the total and the tax as they are printed. The net is worked out.';
  @override
  String get invoiceNumber => 'Their invoice number';
  @override
  String get invoiceTotal => 'Total on the invoice';
  @override
  String get invoiceTax => 'Of which VAT';
  @override
  String get invoiceTaxFromRate => 'or take it out at';
  @override
  String get invoiceIssued => 'Invoice date';
  @override
  String get invoiceDue => 'Due';
  @override
  String invoiceDueOnTerms(int days) =>
      days == 0 ? 'Due · on delivery' : 'Due · $days day terms';
  @override
  String get invoiceAgainstOrder => 'Billing which order';
  @override
  String get invoiceNoOrder => 'No order';
  @override
  String get invoiceAgreesWithDelivery => 'Agrees with what arrived.';
  @override
  String get invoiceBilledMore =>
      'More than what arrived. Worth a call before paying it.';
  @override
  String get invoiceBilledLess =>
      'Less than what arrived — the rest is probably still to be invoiced.';
  @override
  String invoiceDaysLate(int days) => days == 1 ? '1 day late' : '$days days late';
  @override
  String get invoiceNoneOutstanding => 'Nothing owed. Every invoice is paid.';
  @override
  String get invoiceOutstanding => 'Outstanding';
  @override
  String get invoiceVoid => 'Cancel';
  @override
  String get invoiceVoidWhy => 'Why is this invoice being cancelled?';
  @override
  String get invoicePay => 'Pay';
  @override
  String get notes => 'Notes';
  @override
  String paymentTo(String supplier) => 'Pay $supplier';
  @override
  String get paymentDoesNotTouchTheDrawer =>
      'No shift is open on this terminal, so this does not change the till '
      'drawer. It records the money as paid from the office.';
  @override
  String get paymentFromTheDrawer => 'Take it out of the till drawer';
  @override
  String get paymentFromTheDrawerHint =>
      'Records a pay-out on the open shift, so the drawer is not short at '
      'cash-up. Leave it off for money paid from the office safe.';
  @override
  String get paymentAgainst => 'Against';
  @override
  String get paymentAmount => 'Amount';
  @override
  String get paymentMethod => 'How it was paid';
  @override
  String get methodCash => 'Cash';
  @override
  String get methodTransfer => 'Transfer';
  @override
  String get methodCheque => 'Cheque';
  @override
  String get methodCard => 'Card';
  @override
  String get methodOther => 'Other';
  @override
  String get paymentReference => 'Reference';
  @override
  String get paymentOnAccount => 'On account';
  @override
  String get paymentOnAccountHint =>
      'Money against the running tab. It does not clear a particular invoice.';
  @override
  String get paymentPay => 'Record the payment';
  @override
  String get paymentNeedsAnAmount => 'How much was paid?';
  @override
  String paymentMoreThanTheBill(String room) =>
      'Only $room is left on that invoice. Put the rest on account.';
  @override
  String get paymentsList => 'Payments';
  @override
  String get paymentNonePaidYet => 'Nothing has been paid yet.';
  @override
  String get paymentVoid => 'Reverse';
  @override
  String get paymentVoidWhy => 'Why is this payment being reversed?';
  @override
  String get reasonListEmpty =>
      'No reasons are configured for this. Add some in Settings first.';

  @override
  String get actStaffCreated => 'Added somebody';
  @override
  String get actStaffUpdated => 'Changed a staff record';
  @override
  String get actStaffDisabled => 'Disabled somebody';
  @override
  String get actStaffReactivated => 'Brought somebody back';
  @override
  String get actStaffPinReset => 'Reset a PIN';
  @override
  String get actStaffRoleChanged => 'Changed somebody\'s role';
  @override
  String get actStaffGrantsChanged => 'Changed somebody\'s permissions';
  @override
  String get actRoleCreated => 'Created a role';
  @override
  String get actRoleUpdated => 'Changed a role';
  @override
  String get actRoleDeleted => 'Deleted a role';
  @override
  String get actPermissionOverridden => 'Approved something for somebody';
  @override
  String get actShiftOpened => 'Opened a shift';
  @override
  String get actShiftClosed => 'Closed a shift';
  @override
  String get actReceiptReprinted => 'Reprinted a receipt';
  @override
  String get actCategoryCreated => 'Added a category';
  @override
  String get actCategoryUpdated => 'Changed a category';
  @override
  String get actCategoryArchived => 'Archived a category';
  @override
  String get actCategoryRestored => 'Restored a category';
  @override
  String get actProductCreated => 'Added a menu item';
  @override
  String get actProductUpdated => 'Changed a menu item';
  @override
  String get actProductArchived => 'Archived a menu item';
  @override
  String get actProductRestored => 'Restored a menu item';
  @override
  String get actProductRepriced => 'Changed a price';
  @override
  String get actMoneyConfigChanged => 'Changed the tax and rounding rules';
  @override
  String get actReceiptProfileChanged => 'Changed what the receipt says';
  @override
  String get actTableCreated => 'Added a table';
  @override
  String get actTableUpdated => 'Changed a table';
  @override
  String get actTableArchived => 'Archived a table';
  @override
  String get actTableRestored => 'Restored a table';
  @override
  String get actPurchaseOrderStatusChanged => 'Moved a purchase order on';
  @override
  String get actStockReceived => 'Booked in a delivery';
  @override
  String get actSupplierSaved => 'Added or changed a supplier';
  @override
  String get actSupplierInvoiceSaved => 'Entered a supplier invoice';
  @override
  String get actSupplierInvoiceVoided => 'Cancelled a supplier invoice';
  @override
  String get actSupplierPaid => 'Paid a supplier';
  @override
  String get actSupplierPaymentVoided => 'Reversed a payment to a supplier';
  @override
  String get actServiceChargeSaved => 'Changed a service charge';
  @override
  String get actTenderTypeSaved => 'Changed a payment method';
  @override
  String get actOrderTypeSaved => 'Changed an order type';
  @override
  String get actTaxGroupSaved => 'Changed a tax rate';
  @override
  String get actProductOptionsChanged => "Changed an item's sizes or extras";
  @override
  String get actOptionGroupSaved => 'Changed a sizes or extras group';
  @override
  String get actOptionGroupRepriced => 'Changed the price of a size or extra';
  @override
  String get actOptionGroupDeleted => 'Deleted a sizes or extras group';
  @override
  String get fieldYes => 'yes';
  @override
  String get fieldNo => 'no';
  @override
  String get unitEach => 'each';
  @override
  String get unitKilogram => 'kg';
  @override
  String get unitGram => 'g';
  @override
  String get unitLitre => 'L';
  @override
  String get unitMillilitre => 'ml';
  @override
  String get unitBox => 'box';
  @override
  String get unitPack => 'pack';
  @override
  String get supplierOwes => 'owed';
  @override
  String get supplierOverdue => 'overdue';

  @override
  String get fieldTaxGroup => 'Tax rate';
  @override
  String get fieldTaxGroupHint =>
      'Leave this on the default unless the item is taxed differently — a '
      'zero-rated bottle of water, say.';
  @override
  String get fieldTaxGroupDefault => 'Default';
  @override
  String get taxGroups => 'Named rates';
  @override
  String get taxGroupsHint =>
      'A rate per kind of thing you sell. A menu item is charged its own '
      'group\'s rate, or the fallback below if it names none.';
  @override
  String get taxGroupsFallback =>
      'None configured — every item is charged the single rate above, including '
      'anything you sell zero-rated.';
  @override
  String get taxGroupNew => 'New rate';
  @override
  String get taxGroupEdit => 'Rate';
  @override
  String get taxGroupHint =>
      'Zero-rated and exempt are both 0% and are different things on a filing. '
      'The name is the only place that difference lives.';
  @override
  String get taxGroupName => 'What your accountant calls it';
  @override
  String get taxGroupNeedsAName => 'A rate needs a name.';
  @override
  String get taxGroupRate => 'Rate';
  @override
  String get taxGroupRateNotValid => 'A rate is a number between 0 and 100.';
  @override
  String get taxGroupDefault => 'The fallback rate';
  @override
  String get taxGroupDefaultHint =>
      'What an item is charged when it names no rate of its own. Exactly one '
      'group is the fallback; making this one takes it off the other.';
  @override
  String get taxGroupIsDefault => 'FALLBACK';
  @override
  String get taxGroupActive => 'In use';
  @override
  String get taxGroupActiveHint =>
      'Turning this off retires it. Items already on it fall back to the '
      'default rate, so check what is on it first.';
  @override
  String get orderTypes => 'Order types';
  @override
  String get orderTypesHint =>
      'What each kind of order needs before it can be settled.';
  @override
  String get orderTypesComeFromPlatform =>
      'These come from XOrder on this till. You can see them; the platform sets '
      'them.';
  @override
  String get orderTypeName => 'What you call it';
  @override
  String get orderTypeNeedsAName => 'An order type needs a name.';
  @override
  String get orderTypeRequiresTable => 'Has a table';
  @override
  String get orderTypeRequiresTableHint =>
      'Turns on the floor plan for this kind of order. On for a caterer who '
      'seats people, or a drive-thru with numbered bays.';
  @override
  String get orderTypeRequiresCustomer => 'Needs a customer';
  @override
  String get orderTypeRequiresCustomerHint =>
      'Nothing asks for one yet — customers are still being built — and it is '
      'saved so it is right when they arrive.';
  @override
  String get orderTypeRequiresAddress => 'Needs an address';
  @override
  String get orderTypeRequiresAddressHint => 'For delivery, and only delivery.';
  @override
  String get orderTypeOffered => 'Sold here';
  @override
  String get orderTypeOfferedHint =>
      'Turning this off takes it off the till. Orders already taken keep it.';
  @override
  String get orderTypeNotOffered => 'not sold';
  @override
  String get orderTypeChipTable => 'TABLE';
  @override
  String get orderTypeChipCustomer => 'CUSTOMER';
  @override
  String get orderTypeChipAddress => 'ADDRESS';
  @override
  String get paneTaxes => 'Tax';
  @override
  String get paneTaxesHint => 'The rates this restaurant charges, and on what.';
  @override
  String get backOffice => 'Back office';
  @override
  String get tabHome => 'Home';
  @override
  String get tabSales => 'Sales';
  @override
  String get tabReports => 'Reports';
  @override
  String get tabMenu => 'Menu';
  @override
  String get tabInventory => 'Inventory';
  @override
  String get tabPurchasing => 'Purchasing';
  @override
  String get tabFinance => 'Finance';
  @override
  String get tabSystem => 'System';
  @override
  String get tabSettings => 'Settings';
  @override
  String get tabPeople => 'People';
  @override
  String get reportsSummary => 'Business summary';
  @override
  String get rolesAndPermissions => 'Roles & permissions';
  @override
  String get paneDevices => 'Devices';
  @override
  String get settingsOrdersInvoices => 'Orders & invoices settings';
  @override
  String get settingsLanguage => 'Language';
  @override
  String get settingsLook => 'Appearance';
  @override
  String get paneHomeBlurb =>
      'This till, how today is going, and the way to the rest.';
  @override
  String homeWelcome(String name) => 'Welcome, $name';
  @override
  String get homeCardConnection => 'Connection';
  @override
  String get homeCardLastSync => 'Last sync';
  @override
  String get homeCardLastBackup => 'Last backup';
  @override
  String get homeNotSet => 'Not set';
  @override
  String get homeNever => 'Never';
  @override
  String homeSalesWaiting(int count) => count == 1
      ? '1 sale waiting to send'
      : '$count sales waiting to send';
  @override
  String get homeToday => 'Today';
  @override
  String homeDayOpen(String date, String time) =>
      'Business day $date · open since $time';
  @override
  String homeDayClosed(String date) =>
      'No business day is open. These are the figures for $date, the last '
      'day closed.';
  @override
  String get homeNoDayYet =>
      'No business day has been opened yet, so there are no sales to show.';
  @override
  String get homeSalesUnavailable =>
      'Today\'s figures could not be read from the database.';
  @override
  String get homeKpiNetSales => 'Net sales';
  @override
  String get homeKpiOrders => 'Orders';
  @override
  String get homeKpiAverage => 'Average order';
  @override
  String get homeVsPreviousDay =>
      'vs the previous day, same time since opening';
  @override
  String get homeNoComparison => 'No earlier day to compare with';
  @override
  String get homeQuickActions => 'Quick actions';
  @override
  String get homeActionReports => 'Sales reports';
  @override
  String get homeActionProducts => 'Product management';
  @override
  String get homeActionEmployees => 'Employees';
  @override
  String get financeOverview => 'Overview';
  @override
  String get financeOverviewBlurb =>
      'What the period took in, and how it was paid.';
  @override
  String get financeRevenue => 'Revenue';
  @override
  String get financeRevenueBlurb =>
      'Sales, discounts and refunds by business day — the same figures as '
      'Reports.';
  @override
  String get financePayments => 'Payment methods';
  @override
  String get financePaymentsBlurb =>
      "Every payment taken on the period's sales, one row each.";
  @override
  String get financeTaxes => 'Taxes';
  @override
  String get financeTaxesBlurb =>
      'Tax charged by rate, less what refunds gave back.';
  @override
  String get financePeriodToday => 'Today';
  @override
  String get financePeriodThisWeek => 'This week';
  @override
  String get financePeriodThisMonth => 'This month';
  @override
  String get financePeriodLastMonth => 'Last month';
  @override
  String get financeBusinessDates => 'Business dates';
  @override
  String get financeKpiRevenue => 'Revenue (net sales)';
  @override
  String get financeKpiCollected => 'Collected';
  @override
  String get financeKpiOnAccount => 'On account';
  @override
  String get financeKpiTax => 'Tax, net of refunds';
  @override
  String get financeTendersTitle => 'Collected by payment method';
  @override
  String get financeOnAccountNote =>
      'On account is owed, not collected, so it has no share of the bar.';
  @override
  String get financeNothingCollected => 'Nothing was collected in this period.';
  @override
  String get financeGross => 'Gross sales';
  @override
  String get financeDiscounts => 'Discounts';
  @override
  String get financeRefunds => 'Refunds';
  @override
  String get financeNet => 'Net sales';
  @override
  String get financeOrders => 'Sales';
  @override
  String get financeAverage => 'Average sale';
  @override
  String get financeDate => 'Business date';
  @override
  String get financeTotal => 'Total';
  @override
  String get financeRefundsNote =>
      'A refund is counted on the day it was given, whatever day the sale was.';
  @override
  String get financeByMethod => 'By payment method';
  @override
  String get financeMethod => 'Method';
  @override
  String get financePaymentCount => 'Payments';
  @override
  String get financeAmount => 'Amount';
  @override
  String get financeShare => 'Share';
  @override
  String get financeLedgerTitle => 'Payments, newest first';
  @override
  String get financeInvoice => 'Invoice';
  @override
  String get financeTime => 'Time';
  @override
  String get financeLedgerTotal => 'Total of the payments listed';
  @override
  String financeLedgerTruncated(int count) =>
      'Only the newest $count payments are listed. The totals by method cover '
      'the whole period.';
  @override
  String get financeNoPayments => 'No payments were taken in this period.';
  @override
  String get financeTaxName => 'Tax';
  @override
  String get financeTaxRate => 'Rate';
  @override
  String get financeTaxBase => 'Taxable sales';
  @override
  String get financeTaxCharged => 'Charged';
  @override
  String get financeTaxRefunded => 'Refunded';
  @override
  String get financeTaxNet => 'Net';
  @override
  String get financeTaxUnattributed => 'Refunded on sales that recorded no rate';
  @override
  String get financeTaxNote =>
      "Charged is filed under the sale's business date; refunded under the "
      "day the refund was given, split across the sale's rates as its credit "
      'note splits it. Taxable sales are before refunds.';
  @override
  String get financeNoTaxes =>
      'No tax was charged or refunded in this period.';
  @override
  String get financeUnavailable =>
      'The figures could not be read from the branch database.';
  @override
  String get financeNoFigures =>
      'This till has no branch database to read figures from yet.';
  @override
  String get financeExpenses => 'Expenses';
  @override
  String get financeExpensesBlurb =>
      'Money paid out of the drawers, and paid to suppliers.';
  @override
  String get financeDrawers => 'Treasury';
  @override
  String get financeDrawersBlurb =>
      'The cash each open drawer should hold right now.';
  @override
  String get financeBills => 'Bills due';
  @override
  String get financeBillsBlurb =>
      'What is owed to suppliers, by when it falls due.';
  @override
  String get financeTransactions => 'Transactions';
  @override
  String get financeTransactionsBlurb =>
      'Sales, pay-outs, supplier invoices and supplier payments, newest '
      'first.';
  @override
  String get financeKpiExpenses => 'Expenses';
  @override
  String get financeExpensesWithSuppliers =>
      'Drawer pay-outs plus supplier payments that were not voided.';
  @override
  String get financeExpensesPayOutsOnly => 'Drawer pay-outs only.';
  @override
  String get financeSuppliersOnPlatform =>
      'Supplier payments are kept on the platform for this restaurant, so '
      'they are not counted here.';
  @override
  String get financeSuppliersNotPermitted =>
      'Supplier payments are not counted: reading them needs the purchasing '
      'permission.';
  @override
  String get financeCountedOnce =>
      'A supplier paid out of a till drawer is counted once, as the supplier '
      'payment.';
  @override
  String get financePayOuts => 'Drawer pay-outs';
  @override
  String get financeSupplierPayments => 'Supplier payments';
  @override
  String get financeNoExpenses => 'Nothing was paid out in this period.';
  @override
  String get financeRecentExpenses => 'Recent expenses';
  @override
  String get financeViewAll => 'View all';
  @override
  String get financeType => 'Type';
  @override
  String get financeDetails => 'Details';
  @override
  String get financeKpiDrawers => 'Cash expected in open drawers';
  @override
  String financeOpenDrawerCount(int count) =>
      count == 1 ? '1 drawer open' : '$count drawers open';
  @override
  String get financeNoOpenDrawers => 'No drawer is open at this branch.';
  @override
  String get financeOpenedBy => 'Opened by';
  @override
  String get financeOpenedAt => 'Opened';
  @override
  String get financeFloat => 'Float';
  @override
  String get financeCashTaken => 'Cash taken';
  @override
  String get financePaidIn => 'Paid in';
  @override
  String get financePaidOut => 'Paid out';
  @override
  String get financeExpected => 'Expected';
  @override
  String get financeDrawersNote =>
      'Expected is the figure the Z report counts the drawer against: the '
      'float, plus cash taken, plus paid in, less paid out. Bank and wallet '
      'balances are not kept here.';
  @override
  String get financeAsOf => 'As of business date';
  @override
  String get financeBucketOverdue => 'Overdue';
  @override
  String get financeBucketToday => 'Due today';
  @override
  String get financeBucketWeek => 'Due in the next 7 days';
  @override
  String get financeBucketLater => 'Due later';
  @override
  String get financeTotalOwed => 'Total owed';
  @override
  String get financeSupplier => 'Supplier';
  @override
  String get financeDueDate => 'Due';
  @override
  String get financePaid => 'Paid';
  @override
  String get financeOutstanding => 'Outstanding';
  @override
  String get financeNoBills => 'Nothing is owed to suppliers.';
  @override
  String get financeBillsNote =>
      'Each unpaid invoice is in exactly one group, by its due date against '
      'the business date. Money paid on account lowers what a supplier is '
      'owed but clears no particular bill, so it is not taken off here.';
  @override
  String get financeRecentTransactions => 'Recent transactions';
  @override
  String get financeReference => 'Reference';
  @override
  String get financeStatus => 'Status';
  @override
  String get financeKindSale => 'Sale';
  @override
  String get financeKindPayOut => 'Pay-out';
  @override
  String get financeKindSupplierInvoice => 'Supplier invoice';
  @override
  String get financeKindSupplierPayment => 'Supplier payment';
  @override
  String get financeStatusPaid => 'Paid';
  @override
  String get financeStatusPartlyPaid => 'Part paid';
  @override
  String get financeStatusUnpaid => 'Unpaid';
  @override
  String get financeStatusPartlyRefunded => 'Part refunded';
  @override
  String get financeStatusRefunded => 'Refunded';
  @override
  String get financeStatusOpen => 'Open';
  @override
  String get financeStatusVoided => 'Void';
  @override
  String get financeStatusRecorded => 'Recorded';
  @override
  String get financeNoTransactions => 'Nothing moved in this period.';
  @override
  String financeTransactionsTruncated(int count) =>
      'Only the newest $count are listed. Choose a shorter period to see '
      'older ones.';
  @override
  String get financeTransactionsNote =>
      'A supplier invoice is a bill, not money that moved; paying it is a row '
      'of its own. The sales listed are the ones the Sales tab shows you.';
  @override
  String get settingsGeneral => 'General';
  @override
  String get settingsAppearance => 'Language & appearance';
  @override
  String get paneAppearanceBlurb => 'The language and theme of this terminal';
  @override
  String get appearanceThisTerminal =>
      'For this terminal only. Every other till keeps its own language and '
      'theme, whoever signs in.';
  @override
  String get appearanceLanguage => 'Language';
  @override
  String get appearanceTheme => 'Theme';
  @override
  String get themeSystem => 'Automatic';
  @override
  String get themeLight => 'Light';
  @override
  String get themeDark => 'Dark';
  @override
  String get themeSystemHint =>
      'Automatic follows this computer\'s own light or dark setting.';
  @override
  String get backupLastCopy => 'Last copy';
  @override
  String get backupNowNeedsPermission =>
      'Taking a copy on demand needs the backup permission.';
  @override
  String get manage => 'Manage';
  @override
  String get manageMenuTooltip => 'Open a back-office area';
  @override
  String get backToTill => 'Back to the till';
  @override
  String get paneStaff => 'Staff';
  @override
  String get paneStaffBlurb => 'Who works here, and what they may do';
  @override
  String get paneSalesBlurb =>
      'Every sale this branch has rung up, with its receipt and refunds';
  @override
  String get paneReportsBlurb =>
      'What this branch sold over a period, and how it compares with the one '
      'before';
  @override
  String get reportPeriodToday => 'Today';
  @override
  String get reportPeriodWeek => 'This week';
  @override
  String get reportPeriodMonth => 'This month';
  @override
  String get reportPeriodCustom => 'Custom range';
  @override
  String get reportVsPrevious => 'vs the previous period of the same length';
  @override
  String get reportNoComparison =>
      'Nothing in the previous period to compare with';
  @override
  String get reportKpiRefunds => 'Refunds';
  @override
  String reportRefundCount(int count) =>
      count == 1 ? '1 refund' : '$count refunds';
  @override
  String get reportTrend => 'Sales by business day';
  @override
  String get reportTopProducts => 'Top products';
  @override
  String get reportTopProductsNote =>
      'Units kept after refunds and voids, at the price sold — before '
      'discounts';
  @override
  String get reportRankQuantity => 'By quantity';
  @override
  String get reportRankAmount => 'By amount';
  @override
  String get reportColumnQuantity => 'Qty';
  @override
  String get reportColumnAmount => 'Amount';
  @override
  String get reportNoProducts => 'Nothing was sold in this period.';
  @override
  String get reportPayments => 'Payment methods';
  @override
  String get reportOnAccount => 'On account — owed, not collected';
  @override
  String get reportNoPayments => 'Nothing was collected in this period.';
  @override
  String get reportTerminals => 'By till';
  @override
  String get reportBranchTotal => 'Branch total';
  @override
  String get reportUnregistered => 'Not registered to this branch';
  @override
  String get reportInsights => 'Key insights';
  @override
  String get reportInsightBestDay => 'Best day';
  @override
  String get reportInsightTopTerminal => 'Busiest till';
  @override
  String get reportInsightGrowth => 'Net sales vs the previous period';
  @override
  String get reportInsightsNone =>
      'Not enough sales in this period to point anything out.';
  @override
  String get reportUnavailable =>
      'The report could not be read from the database.';
  @override
  String get reportNoDatabase =>
      'Reports read this branch\'s database, and this terminal is not '
      'connected to one yet.';
  @override
  String get exportExcel => 'Export to Excel';
  @override
  String get exportExcelDialogTitle => 'Save the Excel file';
  @override
  String exportExcelSaved(String path) => 'Saved to $path';
  @override
  String exportExcelFailed(String reason) =>
      'The Excel file could not be written: $reason';
  @override
  String get exportSheetSummary => 'Summary';
  @override
  String get exportPeriodFrom => 'From';
  @override
  String get exportPeriodTo => 'To';
  @override
  String get exportColumnFigure => 'Figure';
  @override
  String get exportColumnValue => 'Value';
  @override
  String get exportColumnNote => 'Note';
  @override
  String get exportColumnDate => 'Date';
  @override
  String get exportColumnOccurredAt => 'Date and time';
  @override
  String get exportColumnShare => 'Share';
  @override
  String get exportColumnRank => 'Rank';
  @override
  String get exportColumnProduct => 'Product';
  @override
  String get paneMenu => 'Menu';
  @override
  String get paneMenuBlurb => 'Categories, items and what they cost';
  @override
  String get panePurchasing => 'Purchasing';
  @override
  String get panePurchasingBlurb =>
      'Who you buy from, what you have ordered, and booking in what arrives.';
  @override
  String get paneRoles => 'Roles';
  @override
  String get paneRolesBlurb => 'The permissions behind each job title';
  @override
  String get paneActivity => 'Activity';
  @override
  String get paneActivityBlurb => 'What was changed, by whom';
  // ── Backup and restore ────────────────────────────────────────────
  @override
  String get paneBackup => 'Backup';
  @override
  String get paneBackupBlurb => 'Copies of this database, and putting one back';
  @override
  String get backupSameDiskWarning =>
      'Copies are written to this machine\'s own disk. That survives a bad '
      'edit or a dropped table. It does not survive the disk failing, the '
      'machine being stolen, a fire, or software that encrypts every file this '
      'account can write — which is the list of things that actually happen. '
      'Copy the newest one to a USB drive regularly — "Copy to…" on any '
      'verified copy — and keep the drive somewhere other than this machine.';
  @override
  String get backupToolsMissing =>
      'PostgreSQL\'s command-line tools are not on this machine, so no backup '
      'can be taken and none can be restored.';
  @override
  String get backupToolsMissingHelp =>
      'Install the PostgreSQL client tools — pg_dump and pg_restore — from '
      'postgresql.org, then open this screen again.';
  @override
  String get backupSearchedIn => 'Looked in';
  @override
  String get backupDestination => 'Where copies go';
  @override
  String get backupDestinationHint =>
      'A folder on this machine. It is created if it is not there.';
  @override
  String get backupTakeNow => 'Back up now';
  @override
  String get backupTaking => 'Backing up…';
  @override
  String get backupAutomatic => 'Take one when the trading day is closed';
  @override
  String get backupAutomaticHint =>
      'On by default. A backup nobody remembers to take is not a backup.';
  @override
  String get backupHistory => 'Copies taken';
  @override
  String get backupNoneYet => 'No copy of this database has ever been taken.';
  @override
  String get backupNoVerifiedCopy =>
      'No copy has been verified. This restaurant does not have a backup.';
  @override
  String backupLastVerified(String when) => 'Last verified copy: $when';
  @override
  String backupStale(int days) => days == 1
      ? 'The last verified copy is a day old.'
      : 'The last verified copy is $days days old.';
  @override
  String get backupOutcomeVerified => 'Verified';
  @override
  String get backupOutcomeUnverified => 'Not a backup';
  @override
  String get backupOutcomeFailed => 'Failed';
  @override
  String get backupTriggerManual => 'By hand';
  @override
  String get backupTriggerDayClose => 'Day close';
  @override
  String get backupFailureToolsMissing =>
      'pg_dump is not installed on this machine.';
  @override
  String get backupFailureDestinationUnwritable =>
      'The folder could not be written to.';
  @override
  String get backupFailureDumpRefused =>
      'PostgreSQL refused to produce the copy.';
  @override
  String get backupFailureArchiveUnreadable =>
      'The file was written and could not be read back.';
  @override
  String get backupFailureArchiveIncomplete =>
      'The file is missing tables the restaurant could not trade without.';
  @override
  String backupTablesFound(int count) =>
      count == 1 ? '1 table' : '$count tables';
  @override
  String get backupRestoreAction => 'Restore…';
  @override
  String backupRestoreTitle(String when) =>
      'Replace this database with the copy taken $when?';
  @override
  String get backupRestoreBlocked =>
      'This cannot be restored while the till is still trading.';
  @override
  String restoreBlockerOpenShifts(int count) => count == 1
      ? '1 till still has a shift open'
      : '$count tills still have shifts open';
  @override
  String restoreBlockerOpenDay(int count) =>
      'The trading day has not been closed';
  @override
  String backupRestoreOrdersLost(int count, String value) => count == 1
      ? '1 order taken since then, worth $value, will be discarded.'
      : '$count orders taken since then, worth $value, will be discarded.';
  @override
  String get backupRestoreEverythingElseLost =>
      'So does everything else recorded since — shifts, cash movements, staff '
      'changes and the audit trail.';
  @override
  String get backupRestoreNoWayBack =>
      'There is no way back. Nothing here keeps a copy of what is about to be '
      'replaced.';
  @override
  String get backupRestoreConfirm => 'Replace the database';
  @override
  String get backupRestoreKeep => 'Keep this database';
  @override
  String get backupRestoreDone =>
      'The database was replaced. Close the app and start it again.';
  @override
  String backupRestoreFailed(String detail) =>
      'The restore did not complete and nothing was changed. $detail';
  @override
  String get backupAccount => 'Backup account';
  @override
  String get backupAccountHint =>
      'Backups sign in to PostgreSQL as pos_backup, a read-only account '
      'created when PostgreSQL was installed. Enter its password once. It is '
      'kept on this machine, so the backup at day close works with nobody '
      'signed in here.';
  @override
  String get backupAccountStored => 'A password is saved on this machine.';
  @override
  String get backupAccountMissing => 'No password saved on this machine yet.';
  @override
  String get backupAccountSaved =>
      'Saved. The next backup signs in with it.';
  @override
  String get backupCopyAction => 'Copy to…';
  @override
  String backupCopyDone(String path) =>
      'Copied to $path and checked against the original.';
  @override
  String backupCopyFailed(String detail) => 'The copy was not made. $detail';
  @override
  String get backupRestoreFromFile => 'Restore from a file…';
  @override
  String get backupFileGone =>
      'No longer on this machine — only the newest 14 copies are kept here.';
  @override
  String get backupOpenPane => 'Open Backup';
  @override
  String get backupDayCloseWorking => 'Closing the day and taking a backup…';
  @override
  String get backupDayCloseFailed =>
      'The day is closed. The automatic backup did not succeed — open '
      'Management, then Backup, to see why.';
  @override
  String get actBackupTaken => 'Took a backup';
  @override
  String get actBackupRestored => 'Restored the database from a backup';
  @override
  String get actAdminEntered => 'Opened Admin Mode';
  @override
  String get actAdminExited => 'Left Admin Mode';
  @override
  String get actAdminTimedOut => 'Admin Mode locked itself for inactivity';
  @override
  String get actAdminLockedOut =>
      'Admin Mode shut its door after repeated wrong PINs for this username';
  @override
  String get actAdminRefused => 'Was refused Admin Mode';
  @override
  String adminTitle(String pane) => 'XOrder POS › Admin › $pane';
  @override
  String get exitAdminMode => 'Exit Admin Mode';
  @override
  String get adminSignInTitle => 'Admin Mode';
  @override
  String adminSignInHelp(int minutes) =>
      'Your username and PIN. Admin Mode locks itself after $minutes minutes '
      'without a tap or a key press.';
  @override
  String get yourPin => 'Your PIN';
  @override
  String get openAdminMode => 'Open Admin Mode';
  @override
  String get adminSignInRefused =>
      'That username and PIN cannot open Admin Mode.';
  @override
  String adminSignInAttemptsLeft(int attempts) => attempts == 1
      ? '$adminSignInRefused One attempt left.'
      : '$adminSignInRefused $attempts attempts left.';
  @override
  String adminSignInLockedOut(int seconds) => seconds < 60
      ? 'Too many wrong attempts. Admin Mode can be tried again in $seconds '
            '${seconds == 1 ? 'second' : 'seconds'}.'
      : 'Too many wrong attempts. Admin Mode can be tried again in '
            '${(seconds + 59) ~/ 60} '
            '${(seconds + 59) ~/ 60 == 1 ? 'minute' : 'minutes'}.';
  @override
  String get adminDatabasePasswordNeeded =>
      'The first time on this till, Admin Mode also needs the back-office '
      'database password — once. It is kept on this machine from then on.';
  @override
  String get adminDatabasePasswordRefused =>
      'PostgreSQL did not accept that back-office password.';
  @override
  String adminLockedAfter(int minutes) =>
      'Admin Mode locked itself after $minutes minutes without activity. Sign '
      'in again to carry on.';
  @override
  String get adminModeSettingsHint =>
      'How this till lets somebody into Admin Mode. The shortcut is only a '
      'hidden way in — the username and PIN are the lock.';
  @override
  String get adminLockAfter => 'Lock after';
  @override
  String adminMinutes(int minutes) => '$minutes min';
  @override
  String get adminShortcut => 'Shortcut';
  // ── end of the backup block ────────────────────────────────────
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
  String get backOfficeSignInHelp =>
      "Sign in with the administrator's username and the back-office "
      'password — the admin password set when XOrder POS was installed.';
  @override
  String get backOfficeSignInRefused =>
      'That username and password cannot open Management.';
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
  String get settingsOrders => 'Orders & invoices';
  @override
  String get settingsPrinter => 'Printer & cash drawer…';
  @override
  String get settingsAbout => 'About XOrder POS';
  @override
  String get printerSettingsTitle => 'Printer & cash drawer';
  @override
  String get printerNoneChosen =>
      'No printer chosen. Find the printers on this network, then pick one.';
  @override
  String get aboutVersion => 'Version';
  @override
  String get aboutMode => 'Mode';
  @override
  String get aboutTerminalId => 'Terminal id';
  @override
  String get aboutDatabase => 'Database';
  @override
  String get receiptPreviewAction => 'Preview';
  @override
  String get receiptPreviewNote =>
      'A preview only — nothing is printed and nothing is recorded.';
  @override
  String get paneUnits => 'Units';
  @override
  String get paneUnitsBlurb => 'What stock is counted and bought in';
  @override
  String get purchasingComesFromPlatform =>
      'On this till, purchasing, suppliers, units and stock are managed on the '
      'XOrder dashboard at xorder.io. Order, receive and pay suppliers there; '
      'none of it comes to this till.';
  @override
  String get purchasingOnPlatformEntry => 'Purchasing & stock — on xorder.io…';
  @override
  String get unitNew => 'Add a unit';
  @override
  String get unitEdit => 'Edit unit';
  @override
  String get unitNameEn => 'Name';
  @override
  String get unitNameAr => 'Name in Arabic';
  @override
  String get unitCode => 'Code';
  @override
  String get unitCodeHelp =>
      'Short, and fixed once saved — purchase lines store it. Lowercase '
      'letters and digits: kg, tray, box6.';
  @override
  String get unitEtaCode => 'Tax authority unit code';
  @override
  String get unitEtaCodeHelp =>
      'What e-receipts say the item was sold in: EA each, KGM kilogram, '
      'LTR litre.';
  @override
  String get unitAllowsFraction => 'Can be part of one';
  @override
  String get unitAllowsFractionHelp =>
      '12.5 kg is a real amount; 12.5 boxes is not.';
  @override
  String get unitFractionChip => 'fractions';
  @override
  String get unitActive => 'In use';
  @override
  String get unitRetired => 'Not in use';
  @override
  String get actUnitSaved => 'Saved a unit';
  @override
  String get paneItems => 'Stock items';
  @override
  String get paneItemsBlurb => 'What you buy and count — on the menu or not';
  @override
  String get itemNew => 'Add an item';
  @override
  String get itemEdit => 'Edit item';
  @override
  String get itemName => 'Name';
  @override
  String get itemNameAr => 'Name in Arabic';
  @override
  String get itemUnit => 'Counted in';
  @override
  String get itemOnMenu => 'On the menu';
  @override
  String get itemOnMenuHint =>
      'Its name and price are set in Menu; only the unit it is counted in is '
      'set here.';
  @override
  String get itemsEmpty =>
      'Nothing is counted in stock yet. Add what you buy — chicken, oil, gas.';
  @override
  String get fieldTrackStock => 'Track stock';
  @override
  String get fieldTrackStockHint =>
      'Count it when it is bought, and see how much is left.';
  @override
  String get actStockItemSaved => 'Saved a stock item';
  @override
  String get paneStock => 'Stock on hand';
  @override
  String get paneStockBlurb =>
      'How much of each counted item this branch holds, and what it is worth';
  @override
  String get stockColumnItem => 'Item';
  @override
  String get stockColumnOnHand => 'On hand';
  @override
  String get stockColumnAvgCost => 'Average cost';
  @override
  String get stockColumnValue => 'Value';
  @override
  String stockTotalValue(String amount) => 'Stock value: $amount';
  @override
  String get stockEmpty =>
      'Nothing is counted yet. Add what you buy in Stock items, then receive '
      'a delivery.';
  @override
  String get purchaseUnit => 'Unit';
  @override
  String purchaseAddAsItem(String name) => 'Add “$name” as a new item';
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
  String get usersKpiStaff => 'Staff';
  @override
  String get usersKpiActive => 'Active';
  @override
  String usersActiveShare(int percent) => '$percent% of all accounts';
  @override
  String get usersKpiShifts => 'Current shifts';
  @override
  String get usersKpiShiftsNote => "Open drawers on this branch's tills";
  @override
  String get usersKpiRoles => 'Roles';
  @override
  String get staffStatusAll => 'All';
  @override
  String get staffStatusActive => 'Active';
  @override
  String get staffStatusDisabled => 'Disabled';
  @override
  String get usersAllRoles => 'All roles';
  @override
  String get usersSearchHint => 'Name or username';
  @override
  String get usersColumnStatus => 'Status';
  @override
  String get usersColumnLastShift => 'Last shift';
  @override
  String get usersOnShiftNow => 'On shift now';
  @override
  String get usersNeverOnShift => 'Never';
  @override
  String get usersNoneMatch =>
      'Nobody matches these filters. Clear the search or pick another role.';
  @override
  String get manageRoles => 'Manage roles';
  @override
  String get roleMatrixTitle => 'What each role may do';
  @override
  String get roleMatrixNote =>
      'Permissions each role grants. A person’s own exceptions are not '
      'counted here — open their Permissions to see those.';
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

  @override
  String get extrasTitle => 'Extras library';
  @override
  String get extrasSubtitle =>
      'Reusable option groups you can attach to any item. Editing one updates '
      'it everywhere it is used.';
  @override
  String get extrasNew => 'Add extra';
  @override
  String get extrasEdit => 'Edit extra';
  @override
  String get extrasNone =>
      'No shared extras yet. Create one to reuse across items.';
  @override
  String extrasUsedBy(int n) => '$n item(s)';
  @override
  String get extrasNotUsed => 'Not used yet';
  @override
  String extrasDeleteWarning(int n) =>
      'Delete this extra? It will be removed from the $n item(s) currently '
      'using it.';
  @override
  String extrasOptionsSummary(int n) => '$n option(s)';
  @override
  String get extrasApplyTo => 'Applies to';
  @override
  String get extrasScopeItems => 'Specific items';
  @override
  String get extrasScopeItemsHint =>
      'Attach it to items from each item’s page.';
  @override
  String get extrasScopeCategories => 'Categories';
  @override
  String get extrasScopeAll => 'All items';
  @override
  String get extrasPickCategories => 'Choose categories';
  @override
  String extrasAppliesCategories(int n) => '$n categor(y/ies)';
  @override
  String get extrasLibraryNameEn => 'Name in your list (English)';
  @override
  String get extrasLibraryNameAr => 'Name in your list (Arabic)';
  @override
  String get extrasLibraryNameHint =>
      'How you find this group here. Only you see it.';
  @override
  String get extrasMenuNameEn => 'Menu heading (English)';
  @override
  String get extrasMenuNameAr => 'Menu heading (Arabic)';
  @override
  String get extrasMenuNamePlaceholder => 'e.g. Choose your size';
  @override
  String get extrasMenuNameHint =>
      'What diners read above the choices. Leave blank to use the name above.';
  @override
  String extrasShownAs(String name) => 'On the menu: $name';
  @override
  String get itemOptions => 'Options & add-ons';
  @override
  String get itemNoOptions =>
      'No option groups. Add one for sizes, add-ons, or "without…".';
  @override
  String get itemAddGroup => 'Add group';
  @override
  String get itemGroupNameEn => 'Group name (e.g. Size)';
  // Arabic in both languages: a placeholder is written in the language of
  // the field it sits in, which is the cloud's choice too.
  @override
  String get itemGroupNameAr => 'اسم المجموعة';
  @override
  String get itemRequired => 'Required';
  @override
  String get itemVariant => 'Size / variant';
  @override
  String get itemVariantHint =>
      'Each option sets the item price (small/medium/large). One choice '
      'required, and the first size listed is the default the menu opens on.';
  @override
  String get itemPricedBySize =>
      'Priced by its sizes below. The price above mirrors the default — the '
      'first size listed — so edit that size to change it.';
  @override
  String get itemDefaultSize => 'Default';
  @override
  String get itemOptionDiscount => 'Sale';
  @override
  String get itemOptionDiscountHint =>
      'Optional sale price for this size. Diners see it with the normal price '
      'struck through. Must be lower than the price.';
  @override
  String get itemMaxSelect => 'Max select';
  @override
  String get itemOptionEn => 'Option (English)';
  @override
  String get itemOptionAr => 'الخيار';
  @override
  String get itemAddOption => 'Add option';
  @override
  String get itemAddFromLibrary => 'Add from library';
  @override
  String get itemFromLibrary => 'From library';
  @override
  String get itemLibraryEmpty =>
      'No shared extras yet. Create them under Extras.';
  @override
  String get itemManageLibrary => 'Manage extras';
  @override
  String get deleteLabel => 'Delete';
  @override
  String get deleteConfirmGeneric => 'Are you sure you want to delete this?';
  @override
  String get savingLabel => 'Saving…';

  @override
  String get refusalGroupNameMissing =>
      'An option group needs a name — it is how the group is found again.';
  @override
  String get refusalGroupScopeNeedsLibrary =>
      'Only a library group can apply to whole categories or to every item.';
  @override
  String get refusalGroupCategoriesMissing =>
      'A group for chosen categories needs at least one category.';
  @override
  String refusalGroupChoicesOutOfRange(int max) =>
      'A group allows between 1 and $max choices.';
  @override
  String get refusalGroupNegativeCounts =>
      'A group cannot need, or include, fewer than none.';
  @override
  String get refusalGroupNeedsMoreThanAllows =>
      'A group cannot need more choices than it allows.';
  @override
  String refusalGroupTooManyOptions(int max) =>
      'A group holds at most $max options.';
  @override
  String get refusalGroupRequiredButEmpty =>
      'A required group needs at least one option, or the item it is on could '
      'never be sold.';
  @override
  String get refusalOptionNameMissing => 'Every option needs a name.';
  @override
  String get refusalOptionTwice => 'The same option is in this group twice.';
  @override
  String get refusalOptionNegativePrice =>
      'An option cannot cost less than nothing.';
  @override
  String get refusalOptionSaleNotBelowPrice =>
      "A sale price has to be below the size's normal price.";
  @override
  String get refusalGroupTwice => 'The same group is on this item twice.';
  @override
  String get refusalGroupTypedOnAnotherItem =>
      'That group was typed on another item. Put it in the library to use it '
      'on more than one.';
  @override
  String refusalGroupNotInLibrary(String name) =>
      '"$name" was typed on one item. Put it in the library to use it on more '
      'than one.';
  @override
  String refusalGroupAlreadyReaches(String name) =>
      '"$name" already reaches this item by itself, so it cannot also be '
      'added to it.';
  @override
  String refusalGroupSecondSizes(int count, String names) =>
      'An item has one set of sizes, and this would give it $count: $names. '
      'Keep one.';
  @override
  String refusalGroupWouldGiveSecondSizes(String item) =>
      '"$item" already has sizes. An item has one set, and this group would '
      'give it a second — take the other off it first.';
  @override
  String get refusalGroupBelongsToOneItem =>
      'That group belongs to one item. Change it on the item.';
  @override
  String get refusalGroupBelongsToLibrary =>
      'That group is in the library. Change it there, and every item using it '
      'follows.';
  @override
  String get refusalGroupForeignOption =>
      'One of those options belongs to another group.';
  @override
  String get refusalGroupForeignCategory =>
      'One of those categories is not on this menu.';

  @override
  String get refusalItemNameMissing => 'An item needs a name.';
  @override
  String get refusalOfferAbovePrice =>
      'The offer price is higher than the normal price.';
  @override
  String get refusalCategoryNameMissing => 'A category needs a name.';
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
  String get orderSummaryTotal => 'إجمالي المبيعات';
  @override
  String get orderSummaryTotalNote => 'دون الملغاة والمستردة بالكامل';
  @override
  String get orderSummaryCount => 'الفواتير';
  @override
  String orderSummaryCountDead(int count) => 'منها $count ملغاة أو مستردة';
  @override
  String get orderSummaryPaid => 'المدفوع';
  @override
  String get orderSummaryPaidNote => 'المحصَّل قبل المرتجعات';
  @override
  String get orderSummaryOutstanding => 'المتبقي';
  @override
  String get orderSummaryOutstandingNote =>
      'المستحق على المبيعات غير المدفوعة أو المدفوعة جزئيًا';
  @override
  String get orderPagerShowing => 'عرض';
  @override
  String get orderPagerOf => 'من';
  @override
  String get orderPagerPrevious => 'السابق';
  @override
  String get orderPagerNext => 'التالي';
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
  String get orderColumnPayment => 'الدفع';
  @override
  String get orderColumnMethod => 'طريقة الدفع';
  @override
  String get orderColumnTerminal => 'نقطة البيع';
  @override
  String get orderHistoryEveryMethod => 'كل طرق الدفع';
  @override
  String get orderHistoryEveryTerminal => 'كل نقاط البيع';
  @override
  String get orderHistoryOwnSalesOnly => 'مبيعاتك فقط';
  @override
  String orderHistoryAttributionCaveat(String reliableFrom) =>
      'اسم البائع المسجَّل على كل طلب موثوق ابتداءً من '
      '\u2066$reliableFrom\u2069 فقط. '
      'قبل ذلك كان رمز PIN المشترك بين شخصين ينسب كل مبيعاتهما إلى أحدهما، '
      'لذا فأرقام كل كاشير في الأيام السابقة غير دقيقة.';
  @override
  String get orderDetailBusinessDay => 'يوم العمل';
  @override
  String get orderDetailTerminal => 'نقطة البيع';
  @override
  String get orderDetailActivity => 'السجل';
  @override
  String get saleEventPrinted => 'طُبعت الفاتورة';
  @override
  String get saleEventPrintPending => 'الفاتورة بانتظار الطابعة';
  @override
  String get saleEventReprinted => 'طُبعت نسخة';
  @override
  String get saleEventReprintPending => 'النسخة بانتظار الطابعة';
  @override
  String get saleEventReprintRequested => 'طُلبت نسخة';
  @override
  String get saleEventVoided => 'أُلغي الطلب';
  @override
  String get saleEventRefunded => 'استُرجع مبلغ';
  @override
  String get paymentStatusUnpaid => 'غير مدفوع';
  @override
  String get paymentStatusPartiallyPaid => 'مدفوع جزئيًا';
  @override
  String get paymentStatusPaid => 'مدفوع';
  @override
  String get paymentStatusPartiallyRefunded => 'مسترد جزئيًا';
  @override
  String get paymentStatusRefunded => 'مسترد بالكامل';
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
  String get receiptReprintMark => 'إعادة طباعة — ليست الأصل';
  @override
  String receiptRefundedMark(String amount) => 'مسترجع $amount';
  @override
  String get receiptReprintAction => 'إعادة طباعة الفاتورة';
  @override
  String receiptReprintTitle(String invoice) => 'إعادة طباعة $invoice';
  @override
  String get receiptReprintExplain =>
      'تُوسم الورقة بأنها إعادة طباعة، ويُسجَّل ذلك باسمك.';
  @override
  String get receiptReprintConfirm => 'طباعة';
  @override
  @override
  String get receiptReprintNotPermitted =>
      'ليس لديك صلاحية لإعادة طباعة الفاتورة.';
  @override
  String get reprintCouldNotBeRecorded =>
      'تعذّر تسجيل ذلك، فلم تتم الطباعة. حاول مرة أخرى.';
  @override
  String lineNoteTitle(String item) => 'ملاحظة على $item';
  @override
  String get lineNoteHint => 'بدون بصل، جيد الاستواء، على جانب…';
  @override
  String get comboBadge => 'وجبة';
  @override
  String comboChoose(String group) => 'اختر $group';
  @override
  String get comboAddToTicket => 'إضافة الوجبة';
  @override
  String comboPickMore(int count) =>
      count == 1 ? 'اختر واحدًا آخر' : 'اختر $count أخرى';
  @override
  String get comboIncluded => 'مشمول';
  @override
  String get paneEta => 'الإيصالات الإلكترونية';
  @override
  String get paneEtaBlurb => 'ما لم تقبله المصلحة بعد';
  @override
  String get etaQueueClear => 'تم إرسال كل شيء.';
  @override
  String etaQueueOutstanding(int count) =>
      count == 1 ? 'إيصال واحد في الانتظار' : '$count إيصالات في الانتظار';
  @override
  String etaQueueLate(int count) =>
      count == 1 ? 'واحد تجاوز موعده' : '$count تجاوزت موعدها';
  @override
  String etaQueueRejected(int count) =>
      count == 1 ? 'واحد مرفوض' : '$count مرفوضة';
  @override
  String get etaQueueOldest => 'الأقدم';
  @override
  String get etaQueueNoSeal =>
      'لا يوجد ختم إلكتروني على هذه النقطة، فلا يمكن إرسال أي مما هنا. '
      'الإيصالات تُسجَّل وستُرسل بمجرد ضبط الختم.';
  @override
  String get etaQueueExplain =>
      'تمنح مصلحة الضرائب ٢٤ ساعة من لحظة إصدار الإيصال. والإيصال المرفوض '
      'لا يُقبل من تلقاء نفسه.';
  @override
  String get etaColumnReceipt => 'الإيصال';
  @override
  String get etaColumnIssued => 'وقت الإصدار';
  @override
  String get etaColumnAge => 'المدة';
  @override
  String get etaColumnStatus => 'الحالة';
  @override
  String etaAgeHours(int hours) => hours < 1 ? 'أقل من ساعة' : '$hours س';
  @override
  String etaStatusLabel(String status) => switch (status) {
    'pending' => 'لم يُختم',
    'signed' => 'جاهز للإرسال',
    'submitted' => 'أُرسل، في انتظار الرد',
    'accepted' => 'مُقدَّم',
    'rejected' => 'مرفوض',
    'cancelled' => 'أُغلق يدويًا',
    _ => status,
  };
  @override
  String get etaDueSoon => 'يقترب موعده';
  @override
  String get etaLate => 'متأخر';
  @override
  String etaProblemProfile(int count) => count == 1
      ? 'لا يتم إرسال الإيصالات الإلكترونية: في ملف الإيصال أمر واحد يجب '
            'إصلاحه.'
      : 'لا يتم إرسال الإيصالات الإلكترونية: في ملف الإيصال $count أمور يجب '
            'إصلاحها.';
  @override
  String etaProblemFailed(String detail) =>
      'تعذّر إدراج الإيصالات الإلكترونية في قائمة الإرسال. $detail';
  @override
  String get etaReconcileNow => 'أرسل الإيصالات الناقصة الآن';
  @override
  String etaReconcileDone(int sales, int refunds, int waiting) {
    if (sales + refunds + waiting == 0) return 'لم يكن هناك شيء ناقص.';
    final parts = [
      if (sales > 0) 'إيصالات بيع: $sales',
      if (refunds > 0) 'إيصالات مرتجع: $refunds',
    ];
    final queued = parts.isEmpty ? '' : 'أُدرجت ${parts.join(' · ')}.';
    final waits = waiting == 0
        ? ''
        : ' مرتجعات تنتظر إرسال فاتورة البيع أولاً: $waiting.';
    return '$queued$waits'.trim();
  }
  @override
  String get etaOpenPane => 'افتح الإيصالات الإلكترونية';

  @override
  String get paneReceipt => 'الإيصال';
  @override
  String get paneReceiptBlurb => 'ما يُطبع على الإيصال وما يُرسل للمصلحة';
  @override
  String get receiptProfileExplain =>
      'تُكتب مرة واحدة. أعلى كل إيصال مطبوع وبيانات البائع في كل إيصال '
      'إلكتروني هي نفس البيانات، فتُكتب هنا وتُقرأ من هنا.';
  @override
  String get receiptProfileOnThePaper => 'على الورق';
  @override
  String get receiptProfileForTheAuthority => 'لمصلحة الضرائب';
  @override
  String get receiptProfileSave => 'حفظ';
  @override
  String get receiptProfileSaved => 'تم الحفظ.';
  @override
  String get receiptProfileNoDatabase =>
      'لا توجد قاعدة بيانات على هذه النقطة، فلا مكان لحفظ بيانات الإيصال.';
  @override
  String get receiptEtaReady =>
      'مكتملة. إيصالات هذا الفرع تحمل كل ما تطلبه المصلحة.';
  @override
  String get receiptEtaIncomplete =>
      'غير مكتملة. الإيصالات تُطبع، لكنها لا تُرسل حتى تُصحَّح الحقول المُعلَّمة.';
  @override
  String get receiptEtaNotSetUp =>
      'لم تُضبط بعد. أكملها قبل أن يلزم إرسال أول إيصال.';
  @override
  String get receiptTradeName => 'الاسم التجاري';
  @override
  String get receiptPhone => 'الهاتف';
  @override
  String get receiptHeaderNote => 'ملاحظة أعلى الأصناف';
  @override
  String get receiptFooterNote => 'ملاحظة في الأسفل';
  @override
  String get receiptRegistrationNumber => 'رقم التسجيل الضريبي';
  @override
  String get receiptActivityCode => 'كود النشاط';
  @override
  String get receiptBranchCode => 'كود الفرع';
  @override
  String get receiptBranchAddress => 'عنوان الفرع';
  @override
  String get receiptCountry => 'الدولة';
  @override
  String get receiptGovernorate => 'المحافظة';
  @override
  String get receiptCity => 'المدينة';
  @override
  String get receiptStreet => 'الشارع';
  @override
  String get receiptBuildingNumber => 'رقم المبنى';
  @override
  String get receiptPostalCode => 'الرمز البريدي';
  @override
  String get receiptFloor => 'الطابق';
  @override
  String get receiptRoom => 'الغرفة';
  @override
  String get receiptLandmark => 'علامة مميزة';

  @override
  String get menuImportAction => 'استيراد من ملف';
  @override
  String get menuImportTitle => 'استيراد المنيو';
  @override
  String get menuImportExplain =>
      'ملف CSV أو Excel، كل صف فيه قسم واسم وسعر.';
  @override
  String get menuImportChooseFile => 'اختر ملفًا';
  @override
  String get menuImportReading => 'جارٍ قراءة الملف…';
  @override
  String menuImportWillCreate(int count) =>
      count == 1 ? 'يضيف صنفًا واحدًا' : 'يضيف $count أصناف';
  @override
  String menuImportWillUpdate(int count) =>
      count == 1 ? 'يعدّل صنفًا واحدًا' : 'يعدّل $count أصناف';
  @override
  String menuImportUnchanged(int count) =>
      count == 1 ? 'صف واحد مطابق بالفعل' : '$count صفوف مطابقة بالفعل';
  @override
  String menuImportNewCategories(String names) => 'أقسام جديدة: $names';
  @override
  String get menuImportNothingToDo =>
      'كل الصفوف مطابقة للمنيو. لا يوجد ما يُنفَّذ.';
  @override
  String get menuImportProblemsTitle => 'صحّح هذه ثم أعد المحاولة';

  @override
  String menuImportLine(int lineNumber) => 'سطر $lineNumber';
  @override
  String menuImportProblemsCount(int count) =>
      count == 1 ? 'مشكلة واحدة' : '$count مشاكل';
  @override
  String get menuImportNeverDeletes =>
      'لا يُحذف شيء. الأصناف غير الموجودة في الملف تبقى كما هي.';
  @override
  String menuImportApply(int count) =>
      count == 1 ? 'استيراد صنف واحد' : 'استيراد $count أصناف';
  @override
  String menuImportDone(int created, int updated) =>
      'تم الاستيراد — أُضيف $created وعُدِّل $updated';
  @override
  String get menuImportFailed => 'لم يُستورد شيء. المنيو كما هو.';

  @override
  String get zSubtotal => 'المجموع الفرعي';
  @override
  String get zDiscounts => 'الخصومات الممنوحة';
  @override
  String get zService => 'الخدمة';
  @override
  String get zVat => 'ضريبة القيمة المضافة';
  @override
  String get zRefunds => 'المسترجع';
  @override
  String get zVoids => 'الملغى';
  @override
  String get zNet => 'صافي المحصَّل';
  @override
  String get zCashIn => 'نقد داخل';
  @override
  String get zCashOut => 'نقد خارج';
  @override
  String get zDrawerOpens => 'فتح الدرج دون بيع';
  @override
  String get zVariance => 'الفرق';
  @override
  String get zHiddenUntilCounted => 'مخفي حتى تُتم الجرد';
  @override
  String get payInTitle => 'إدخال نقد';
  @override
  String get payOutTitle => 'إخراج نقد';
  @override
  String get payInAction => 'تسجيل إدخال نقد';
  @override
  String get payOutAction => 'تسجيل إخراج نقد';
  @override
  String get cashAmountLabel => 'المبلغ';
  @override
  String get cashNothingEntered => 'أدخل مبلغًا أكبر من صفر.';
  @override
  String cashAboveCeiling(String ceiling) =>
      'هذا يتجاوز حد $ceiling للدفعة الواحدة.';
  @override
  String get cashRecorded => 'تم التسجيل';
  @override
  String get cashCouldNotBeRecorded =>
      'تعذّر التسجيل، ولم يتحرك شيء. حاول مرة أخرى.';
  @override
  String get cashNoOpenShift => 'افتح وردية قبل تحريك النقد.';
  @override
  String get drawerOpenTitle => 'فتح الدرج؟';
  @override
  String get drawerOpenExplain =>
      'لا ترتبط بهذا أي عملية بيع، لذا يُسجَّل باسمك وبوقته.';
  @override
  String get drawerOpenAction => 'فتح الدرج';
  @override
  String get drawerOpened => 'فُتح الدرج وسُجِّل';
  @override
  String get dayCloseTitle => 'إقفال اليوم';
  @override
  String dayCloseFor(String date) => 'يوم العمل $date';
  @override
  String get dayCloseNothingOpen => 'لا يوجد يوم عمل مفتوح في هذا الفرع.';
  @override
  String get dayCloseClear => 'كل شيء مُسوّى. يمكن إقفال اليوم.';
  @override
  String get dayCloseBlockersTitle => 'ما زال مفتوحًا';
  @override
  String dayBlockerOpenShifts(int count) =>
      count == 1 ? 'كاشير واحد ما زال درجه مفتوحًا' : '$count كاشيرات ما زالت أدراجها مفتوحة';
  @override
  String dayBlockerParkedTickets(int count) => count == 1
      ? 'طلب واحد ما زال معلَّقًا'
      : '$count طلبات ما زالت معلَّقة';
  @override
  String dayBlockerUnpaidOrders(int count) =>
      count == 1 ? 'طلب واحد لم يُدفع' : '$count طلبات لم تُدفع';
  @override
  String get dayCloseAction => 'إقفال اليوم';
  @override
  String get dayForceCloseAction => 'إقفال رغم ذلك';
  @override
  String get dayForceReasonLabel => 'لماذا تُقفل رغم ما هو مفتوح؟';
  @override
  String get dayForceReasonNeeded => 'الإقفال رغم العمل المفتوح يجب أن يُعلَّل.';
  @override
  String dayClosed(String gross) => 'أُقفل اليوم. الإجمالي $gross';
  @override
  String get dayCouldNotBeClosed =>
      'تعذّر إقفال اليوم، وما زال مفتوحًا. حاول مرة أخرى.';
  @override
  String get dayGross => 'الإجمالي';
  @override
  String get dayNet => 'الصافي';

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
  @override
  @override
  String get searchHint => 'امسح الباركود أو ابحث عن صنف / كود';
  @override
  String get customAmount => 'مبلغ مخصص';
  @override
  String get openItemTitle => 'تحصيل مبلغ لصنف خارج المنيو';
  @override
  String get openItemName => 'ما هو؟';
  @override
  String get openItemNameHint => 'توصيل، فتح زجاجة، تورتة…';
  @override
  String get openItemPrice => 'السعر للوحدة';
  @override
  String get openItemAdd => 'إضافة إلى الفاتورة';
  @override
  String get openItemNeedsName => 'اكتب اسمًا له. هذا ما يقرأه العميل في الفاتورة.';
  @override
  String get openItemNeedsPrice => 'أدخل سعرًا يساوي صفرًا أو أكثر.';
  @override
  String get openItemNotPermitted => 'ليس لديك صلاحية لتحصيل سعر خارج المنيو.';
  @override
  String openItemAdded(String name) => 'تمت إضافة $name';
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
  String get branchDatabaseReady => '● خادم الفرع';
  @override
  String get branchDatabaseChecking => '● جارٍ التحقق من خادم الفرع…';
  @override
  String get branchDatabaseUnreachable => '● تعذّر الوصول إلى خادم الفرع';
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
  String get chooseTableFirst =>
      'اختر طاولة أولاً — هذا الطلب يُقدَّم على طاولة.';
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
  String get heldTickets => 'الطلبات المعلَّقة';
  @override
  String heldTicketsKey(int count) => 'المعلَّقة  $count';
  @override
  String get heldTicketsHelp =>
      'طلبات معلَّقة بدون طاولة. اضغط على أحدها لاستعادته — وما هو على الشاشة '
      'الآن يُعلَّق أولاً، فلا يضيع شيء.';
  @override
  String get noHeldTickets => 'لا توجد طلبات معلَّقة.';
  @override
  String heldTicketSummary(String orderType, int items) =>
      items == 1 ? '$orderType · بند واحد' : '$orderType · $items بند';
  @override
  String get ticketParked => 'تم تعليق الطلب. تجده في «المعلَّقة».';

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
  String taxRegistrationLine(String number) => 'TAX REG $number';
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
  String get receiptPrintedToast => 'تمت طباعة الفاتورة.';
  @override
  String get receiptQueuedToast =>
      'الطابعة لم تستجب. الفاتورة في قائمة الانتظار وستُطبع مع المحاولة '
      'التالية.';
  @override
  String get receiptNotPrintedToast =>
      'لم تتم الطباعة ولم يمكن حفظها في قائمة الانتظار — راجع الطابعة والاتصال '
      'بالفرع.';
  @override
  String get receiptNoPrinterToast =>
      'لا توجد طابعة معدَّة على هذه الكاشير، فلم تتم أي طباعة.';
  @override
  String get printerPaperWidth => 'عرض الورق';
  @override
  String get printerPaper80 => 'رول 80 مم (576 نقطة)';
  @override
  String get printerPaper58 => 'رول 58 مم (384 نقطة)';
  @override
  String get printerPaperWidthHelp =>
      'قِس الرول نفسه لا الطابعة. الفاتورة المبنية على عرض خاطئ تُقتص من الحافة '
      'ولا تُصغَّر لتناسب الورق.';

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
  String get enterYourPin => 'أدخل رقمك السري';

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
  String get switchUser => 'تبديل المستخدم';
  @override
  String get wrongUsernameOrPin =>
      'اسم المستخدم أو الرقم السري خاطئ — حاول مرة أخرى';
  @override
  String get openTheDrawer => 'افتح الدرج';
  @override
  String get signInHelp =>
      'اسمك ورقمك السري. ستُفتح الوردية باسمك.';
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
  String closeShiftNotYours(String openedBy) =>
      'تقفيل درج فتحه $openedBy';
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
  String get stepMainDevice => 'الجهاز الرئيسي';
  @override
  String get stepMainDeviceBlurb =>
      'يبيع هذا الجهاز اللوحي من خلال الجهاز الرئيسي للمطعم.';
  @override
  String get stepChildAccountBlurb =>
      'اسم مستخدم ورمز PIN لمدير، من الجهاز الرئيسي.';
  @override
  String get mainDeviceHelp =>
      'لا يُفعَّل ولا يُنشأ شيء على هذا الجهاز اللوحي. الترخيص والمطعم '
      'والموظفون والمنيو كلها تأتي من الجهاز الرئيسي — أدخل عنوانه وكلمة '
      'مرور قاعدة بيانات نقطة البيع التي أُعدّ بها.';
  @override
  String get mainDeviceAddress => 'عنوان الجهاز الرئيسي';
  @override
  String get mainDeviceAddressHelp =>
      'عنوانه على شبكة المطعم، وتجده في الإعدادات على الجهاز الرئيسي. حجز '
      'العنوان على الراوتر يمنعه من التغيّر.';
  @override
  String get mainDeviceIsThisTablet =>
      'هذا العنوان هو هذا الجهاز اللوحي نفسه. أدخل عنوان الجهاز الرئيسي على '
      'شبكة المطعم، مثل 192.168.1.20.';
  @override
  String get connectToMainDevice => 'الاتصال بالجهاز الرئيسي';
  @override
  String mainDeviceLinked(String tenant) =>
      'متصل بالجهاز الرئيسي لـ $tenant. يستخدم هذا الجهاز اللوحي ترخيصه.';
  @override
  String get mainDeviceHasNoLicence =>
      'لم يشارك الجهاز الرئيسي ترخيصه بعد. افتح XOrder POS على الجهاز '
      'الرئيسي — يشارك الترخيص عند وصوله إلى شاشة البدء — ثم اتصل مرة أخرى.';
  @override
  String allTerminalsTaken(int max) =>
      'يغطي الترخيص $max أجهزة وكلها مسجّلة. أوقف أحدها من الجهاز الرئيسي، '
      'أو اطلب ترخيصاً بعدد أكبر.';
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
  String schemaUpgradeFailed(String error) =>
      'قاعدة البيانات أقدم من هذا الإصدار من XOrder POS وتعذّر تحديثها، لذلك '
      'قد تتعطل بعض الشاشات. خذ نسخة احتياطية واتصل بالدعم. رسالة قاعدة '
      'البيانات: $error';
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
  String ownerAlreadyExists(String name, String username) =>
      '$name هو مالك هذا المطعم بالفعل، وللمطعم مالك واحد فقط — لذلك لم '
      'يُعيَّن مالك جديد. لإعداد هذا الجهاز باسم $name، اكتب اسم المستخدم '
      'الخاص به، $username، في خانة اسم المستخدم ثم ابنِ قاعدة البيانات مرة '
      'أخرى؛ ويبقى الكود كما هو. وإن كان للمطعم مالك جديد، فعطّل $name أولاً — '
      'من الإدارة، على جهاز يعمل بالفعل — ثم ابنِها مرة أخرى.';
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
  String get resetTerminalHint =>
      'لجهاز ينتقل إلى خادم فرع آخر، أو فُقدت كلمة مرور قاعدة بياناته. '
      'يبدأ الإعداد من جديد، وتبقى المبيعات المسجلة في قاعدة البيانات. '
      'غير متاح أثناء وجود وردية مفتوحة.';
  @override
  String get paneTerminal => 'الجهاز';
  @override
  String get paneTerminalBlurb => 'إعداد هذا الجهاز، وإعادته من البداية';

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
  String get forceResetSignInTitle => 'من يعيد ضبط هذا الجهاز؟';
  @override
  String get forceResetSignInHelp =>
      'حذف إعداد جهاز يعمل يحتاج إلى شخص مخوّل بإدارة الأجهزة: '
      'اسم المستخدم والكود الخاص به.';
  @override
  String get forceResetSignInRefused =>
      'اسم المستخدم وكلمة المرور هذان لا يسمحان بإعادة ضبط هذا الجهاز.';

  @override
  String get settings => 'الإعدادات';
  @override
  String get syncNow => 'مزامنة الآن';
  @override
  String get management => 'الإدارة';
  @override
  String get staffAndAccounts => 'الموظفون والحسابات…';
  @override
  String get windowMenu => 'النافذة';

  @override
  String get capOperate => 'البيع على الكاشير';
  @override
  String get capCatalogView => 'عرض المنيو';
  @override
  String get capCatalogManage => 'إضافة وتعديل أصناف المنيو والأسعار';
  @override
  String get capPurchaseManage =>
      'طلب المخزون وتسجيل التوريدات وسداد المورّدين';
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
  String get capCashOpenWithoutSale => 'فتح الدرج دون عملية بيع';
  @override
  String get capShiftViewExpectedCash =>
      'الاطلاع على الرصيد المتوقع في الدرج قبل الجرد';
  @override
  String get capCashVarianceView => 'الاطلاع على الفرق بعد الجرد';
  @override
  String get capDayClose => 'إقفال يوم العمل';
  @override
  String get capDayForceClose => 'إقفال اليوم رغم وجود طاولات أو طلبات مفتوحة';
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
  String get capAdminEnter => 'فتح وضع المسؤول';
  @override
  String get capPaymentRemove => 'حذف دفعة من فاتورة لم تُسدَّد بعد';
  @override
  String get capReportExport => 'تصدير التقارير والمبيعات إلى Excel';
  @override
  String removePaymentTitle(String what) => 'حذف $what من هذه الفاتورة';
  @override
  String get removePaymentAction => 'احذفها';
  @override
  String get removePaymentRefused =>
      'تبقى هذه الدفعة على الفاتورة: حذفها يحتاج إلى مشرف.';

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
  String refusalCannotGrantWhatYouLack(String capabilities) =>
      'لا يمكنك منح $capabilities لأنك لا تملكها بنفسك. اطلب ذلك ممن يملكها.';

  @override
  String refusalManagedByPlatform(String what) => switch (what) {
    'staff' =>
      'من يعمل هنا يُضبط على XOrder لا على هذه النقطة. أي تعديل هنا سيُلغى '
      'مع أول مزامنة.',
    'catalogue' =>
      'المنيو يُضبط على XOrder لا على هذه النقطة. أي تعديل هنا سيُلغى مع أول '
      'مزامنة.',
    'floor' => 'مخطط الصالة يُضبط على XOrder لا على هذه النقطة.',
    'money' => 'قواعد المال تُضبط على XOrder لا على هذه النقطة.',
    _ => 'هذا يُضبط على XOrder لا على هذه النقطة.',
  };

  @override
  String refusalOwnerAlreadyExists(String ownerName) =>
      '$ownerName هو المالك بالفعل، وللمطعم مالك واحد فقط. لنقل الملكية، عطّل '
      '$ownerName أولاً، ثم اختر دور المالك للشخص الجديد.';
  @override
  String get refusalOwnerIsFixed =>
      'لا يمكن تغيير دور المالك ولا صلاحياته. المالك يملك كل الصلاحيات أصلاً، '
      'وأي صلاحية تُسحب منه قد تمنع الجميع من الدخول. لنقل الملكية، عطّل المالك '
      'ثم اجعل شخصاً آخر هو المالك.';
  @override
  String get refusalOwnerPinIsTheirs =>
      'لا يغيّر كود المالك إلا المالك نفسه. هذا الكود يفتح كل شيء، لذلك لا يحق '
      'لأحد غيره تعيينه — يغيّره المالك من السطر الخاص به هنا.';
  @override
  String get refusalOwnerIsNotAnExtraRole =>
      'لا يمكن أن يكون المالك دوراً إضافياً. لتجعل شخصاً ما هو المالك، اختر '
      'المالك دوراً أساسياً له.';

  @override
  String get refusalPurchaseAlreadySent =>
      'أُرسل هذا الطلب إلى المورّد بالفعل، فلا يمكن إرساله مرة أخرى ولا '
      'تعديله.';
  @override
  String get refusalPurchaseGoodsArrived =>
      'وصلت بضاعة على هذا الطلب بالفعل، فلا يمكن تعديله.';
  @override
  String get refusalPurchaseCancelled =>
      'أُلغي هذا الطلب، والطلب الملغى لا يُعاد فتحه. اكتب طلباً جديداً.';
  @override
  String get refusalPurchaseHasNoLines =>
      'لا يوجد شيء على هذا الطلب بعد. أضف ما تطلبه قبل إرساله.';
  @override
  String get refusalPurchaseQuantityNotPositive =>
      'كل سطر يحتاج كمية أكبر من صفر.';
  @override
  String get refusalPurchaseCannotCancelArrived =>
      'وصلت بضاعة على هذا الطلب بالفعل، فلا يمكن إلغاؤه — فهي في المخزن وهذا '
      'الطلب سجلها. ويبقى مفتوحاً لما تبقّى.';
  @override
  String get refusalPurchaseAllArrived =>
      'وصل كل ما في هذا الطلب، فلم يبقَ شيء لإلغائه.';
  @override
  String get refusalPurchaseFollowsTheGoods =>
      'يصبح الطلب مستلَماً باستلام البضاعة، لا باختيار ذلك.';
  @override
  String refusalStockHeldInAnotherUnit(
    String item,
    String quantity,
    String heldUnit,
    String askedUnit,
  ) =>
      'في المخزن $quantity $heldUnit من $item. المخزون لا يُحوَّل من وحدة إلى '
      'أخرى، فما دام منه شيء فلا يُعدّ ولا يُستلم إلا بوحدة $heldUnit، لا '
      'بوحدة $askedUnit.';

  @override
  String get staffComesFromPlatform =>
      'من يعمل هنا يأتي من XOrder. ويمكنك مع ذلك ضبط ما يفعله كلٌّ منهم — '
      'الأدوار والصلاحيات تعيش على هذه النقطة.';

  @override
  String get riskLow => 'منخفض';
  @override
  String get riskMedium => 'متوسط';
  @override
  String get riskHigh => 'مرتفع';
  @override
  String get riskCritical => 'حرج';
  @override
  String get roleCannotGrant => 'لا تملكها';
  @override
  String get roleNew => 'دور جديد';
  @override
  String get roleTemplateExplain =>
      'ابدأ من أحد هذه ثم عدّله. لا شيء فيه يبقى مميزًا.';
  @override
  String roleTemplateCount(int count) =>
      count == 1 ? 'صلاحية واحدة' : '$count صلاحيات';

  @override
  String grantsFor(String name) => 'صلاحيات $name';
  @override
  String get grantsExplain =>
      'استثناءات على ما يمنحه دوره بالفعل. اضغط على صلاحية لسحبها، أو لمنحها '
      'لهذا الشخص وحده.';
  @override
  String get grantsExtraRoles => 'يشغل أيضًا';
  @override
  String get grantsCeilings => 'الحدود';
  @override
  String get grantsDiscountCeiling => 'أقصى خصم';
  @override
  String get grantsNoCeiling => 'بلا حد';
  @override
  String get grantsExceptions => 'الصلاحيات';
  @override
  String get grantsFromRole => 'من دوره';
  @override
  String get grantsAllowed => 'ممنوحة';
  @override
  String get grantsDenied => 'مسحوبة';
  @override
  String get grantsAction => 'الصلاحيات';

  @override
  String get tenderTypes => 'طرق الدفع';
  @override
  String get tenderTypesHint =>
      'ما تعرضه نقطة البيع عند الدفع، وأيّها ينتهي في الدرج.';
  @override
  String get tenderTypesComeFromPlatform =>
      'على هذا الجهاز تأتي طرق الدفع من XOrder. أضفها أو عدّلها من لوحة '
      'التحكم، وتصل إلى هنا مع المزامنة التالية.';
  @override
  String get tenderNew => 'طريقة دفع جديدة';
  @override
  String get tenderEdit => 'طريقة الدفع';
  @override
  String get tenderNameEn => 'الاسم';
  @override
  String get tenderNameAr => 'الاسم بالعربية';
  @override
  String get tenderCode => 'الكود';
  @override
  String get tenderKind => 'النوع';
  @override
  String tenderKindName(String wire) => switch (wire) {
    'cash' => 'نقدي',
    'card' => 'بطاقة',
    'wallet' => 'محفظة',
    'account' => 'على الحساب',
    'voucher' => 'قسيمة',
    _ => 'أخرى',
  };
  @override
  String get tenderCountsAsCash => 'يُحتسب نقدًا';
  @override
  String get tenderCountsAsCashHint => 'يُتوقَّع وجوده في الدرج عند الجرد.';
  @override
  String get tenderOpensDrawer => 'يفتح الدرج';
  @override
  String get tenderOpensDrawerHint =>
      'ليس السؤال نفسه — القسائم المحفوظة في الدرج تفتحه دون أن تكون نقدًا.';
  @override
  String get tenderRequiresReference => 'يتطلب رقمًا مرجعيًا';
  @override
  String get tenderRefundAllowed => 'يمكن ردّ المال بهذه الطريقة';
  @override
  String get tenderActive => 'متاحة على الكاشير';
  @override
  String get tenderActiveHint =>
      'إيقافها يُخرجها من الخدمة. المبيعات السابقة تحتفظ باسمها.';
  @override
  String get tenderRetired => 'خارج الخدمة';

  @override
  String get serviceCharges => 'رسوم الخدمة';
  @override
  String get serviceChargesHint =>
      'ما يُضاف فوق قيمة الطعام، وعلى أي الطلبات ينطبق.';
  @override
  String get serviceChargesFallback =>
      'لا توجد رسوم مضبوطة — تُحتسب النسبة الواحدة أعلاه.';
  @override
  String get chargeNew => 'رسم جديد';
  @override
  String get chargeEdit => 'الرسم';
  @override
  String get chargeName => 'الاسم على الفاتورة';
  @override
  String get chargeHow => 'طريقة الاحتساب';
  @override
  String get chargePercentage => 'نسبة مئوية';
  @override
  String get chargeFixed => 'مبلغ ثابت';
  @override
  String get chargeAppliesTo => 'ينطبق على';
  @override
  String get chargeAppliesToHint => 'إن لم تختر شيئًا فهو ينطبق على كل الطلبات.';
  @override
  String get chargeTaxable => 'تُحتسب عليه ضريبة القيمة المضافة';
  @override
  String get chargeTaxableHint => 'أوقفها للرسوم المُحصَّلة لحساب جهة أخرى.';
  @override
  String get chargeAutomatic => 'يُضاف تلقائيًا';
  @override
  String get chargeOptional => 'يمكن للعميل رفضه';
  @override
  String get chargeOptionalHint => 'عندئذٍ لا يُعد حذفه تجاوزًا ولا يحتاج صلاحية.';
  @override
  String get chargeActive => 'قيد الاستخدام';
  @override
  String get currencyEgp => 'ج.م';

  @override
  String get suppliers => 'المورّدون';
  @override
  String get supplierNew => 'مورّد جديد';
  @override
  String get supplierEdit => 'المورّد';
  @override
  String get supplierName => 'الاسم';
  @override
  String get supplierContact => 'جهة الاتصال';
  @override
  String get supplierEmail => 'البريد الإلكتروني';
  @override
  String get supplierPaymentTerms => 'مدة السداد بالأيام';
  @override
  String get supplierTermsHint =>
      'صفر تعني الدفع عند التسليم. هذه مدة استحقاق الفاتورة، لا حد لقيمتها.';
  @override
  String get supplierCode => 'الرمز الذي تعرفه به';
  @override
  String get supplierNotes => 'ملاحظات';
  @override
  String get supplierActive => 'ما زلت تشتري منه';
  @override
  String get supplierActiveHint =>
      'إيقافه يحفظ السجل ويمنع ظهوره في الأوامر الجديدة.';
  @override
  String get supplierCashOnDelivery => 'دفع عند التسليم';
  @override
  String supplierTermDays(int days) => '$days يوم';
  @override
  String get purchaseOrders => 'أوامر الشراء';
  @override
  String get purchaseOrderNew => 'أمر جديد';
  @override
  String get purchaseOrderEdit => 'الأمر';
  @override
  String get purchaseNoOrdersYet => 'لم يُطلب شيء بعد.';
  @override
  String get purchaseNoSuppliersYet =>
      'لا مورّدين بعد. أضف من تشتري منهم ثم تأتي الأوامر.';
  @override
  String get purchaseNeedsASupplier =>
      'أضف مورّدًا أولًا — لا بد أن يكون الأمر موجهًا إلى أحد.';
  @override
  String get purchaseNeedsALine =>
      'لا شيء لطلبه. يحتاج السطر إلى اسم وكمية وسعر وحدة.';
  @override
  String get purchaseItem => 'الصنف';
  @override
  String get purchaseQty => 'الكمية';
  @override
  String get purchaseUnitCost => 'سعر الوحدة';
  @override
  String get purchaseAddLine => 'أضف سطرًا';
  @override
  String purchaseLineCount(int count) => count == 1 ? 'سطر واحد' : '$count أسطر';
  @override
  String get purchaseSend => 'إرسال';
  @override
  String get purchaseReceive => 'استلام';
  @override
  String purchaseReceiveInto(String reference) => 'استلام على $reference';
  @override
  String get purchaseReceiveHint =>
      'كل خانة تبدأ بما هو مستحق. عدّل ما وصل منه أقل.';
  @override
  String get purchaseOrdered => 'المطلوب';
  @override
  String get purchaseOutstanding => 'المتبقي';
  @override
  String get purchaseArrived => 'الواصل';
  @override
  String purchaseBookIn(int lines) =>
      lines == 1 ? 'تسجيل سطر واحد' : 'تسجيل $lines أسطر';
  @override
  String get statusDraft => 'مسودة';
  @override
  String get statusSent => 'مُرسل';
  @override
  String get statusPartReceived => 'استلام جزئي';
  @override
  String get statusReceived => 'مستلم';
  @override
  String get statusCancelled => 'ملغى';

  @override
  String get supplierInvoices => 'فواتير الشراء';
  @override
  String get invoiceNew => 'إدخال فاتورة';
  @override
  String get invoiceEdit => 'الفاتورة';
  @override
  String get invoiceHint =>
      'أدخل الإجمالي والضريبة كما هما مطبوعان. يُحتسب الصافي تلقائيًا.';
  @override
  String get invoiceNumber => 'رقم فاتورتهم';
  @override
  String get invoiceTotal => 'إجمالي الفاتورة';
  @override
  String get invoiceTax => 'منها ضريبة القيمة المضافة';
  @override
  String get invoiceTaxFromRate => 'أو استخرجها بنسبة';
  @override
  String get invoiceIssued => 'تاريخ الفاتورة';
  @override
  String get invoiceDue => 'الاستحقاق';
  @override
  String invoiceDueOnTerms(int days) =>
      days == 0 ? 'الاستحقاق · عند التسليم' : 'الاستحقاق · $days يوم';
  @override
  String get invoiceAgainstOrder => 'على أي أمر شراء';
  @override
  String get invoiceNoOrder => 'بدون أمر';
  @override
  String get invoiceAgreesWithDelivery => 'مطابقة لما وصل.';
  @override
  String get invoiceBilledMore =>
      'أكثر مما وصل. يستحق مراجعة المورّد قبل السداد.';
  @override
  String get invoiceBilledLess =>
      'أقل مما وصل — الباقي على الأرجح في فاتورة أخرى.';
  @override
  String invoiceDaysLate(int days) =>
      days == 1 ? 'متأخرة يومًا' : 'متأخرة $days يوم';
  @override
  String get invoiceNoneOutstanding => 'لا مديونية. كل الفواتير مسدَّدة.';
  @override
  String get invoiceOutstanding => 'المتبقي';
  @override
  String get invoiceVoid => 'إلغاء';
  @override
  String get invoiceVoidWhy => 'ما سبب إلغاء هذه الفاتورة؟';
  @override
  String get invoicePay => 'سداد';
  @override
  String get notes => 'ملاحظات';
  @override
  String paymentTo(String supplier) => 'سداد إلى $supplier';
  @override
  String get paymentDoesNotTouchTheDrawer =>
      'لا توجد وردية مفتوحة على هذا الجهاز، فلن يتغيّر درج الكاشير. يُسجَّل '
      'المبلغ كأنه مدفوع من المكتب.';
  @override
  String get paymentFromTheDrawer => 'صرف المبلغ من درج الكاشير';
  @override
  String get paymentFromTheDrawerHint =>
      'يُسجَّل صرفًا على الوردية المفتوحة، حتى لا يظهر الدرج ناقصًا عند '
      'التقفيل. اترك المفتاح مغلقًا إذا كان المبلغ مدفوعًا من خزنة المكتب.';
  @override
  String get paymentAgainst => 'مقابل';
  @override
  String get paymentAmount => 'المبلغ';
  @override
  String get paymentMethod => 'طريقة السداد';
  @override
  String get methodCash => 'نقدًا';
  @override
  String get methodTransfer => 'تحويل';
  @override
  String get methodCheque => 'شيك';
  @override
  String get methodCard => 'بطاقة';
  @override
  String get methodOther => 'أخرى';
  @override
  String get paymentReference => 'المرجع';
  @override
  String get paymentOnAccount => 'على الحساب';
  @override
  String get paymentOnAccountHint =>
      'مبلغ على الحساب الجاري، لا يُسدِّد فاتورة معيّنة.';
  @override
  String get paymentPay => 'تسجيل السداد';
  @override
  String get paymentNeedsAnAmount => 'كم المبلغ المسدَّد؟';
  @override
  String paymentMoreThanTheBill(String room) =>
      'المتبقي على تلك الفاتورة $room فقط. ضع الباقي على الحساب.';
  @override
  String get paymentsList => 'المدفوعات';
  @override
  String get paymentNonePaidYet => 'لم يُسدَّد شيء بعد.';
  @override
  String get paymentVoid => 'عكس';
  @override
  String get paymentVoidWhy => 'ما سبب عكس هذه الدفعة؟';
  @override
  String get reasonListEmpty =>
      'لا توجد أسباب مضبوطة لهذا. أضفها من الإعدادات أولًا.';

  @override
  String get actStaffCreated => 'إضافة موظف';
  @override
  String get actStaffUpdated => 'تعديل بيانات موظف';
  @override
  String get actStaffDisabled => 'إيقاف موظف';
  @override
  String get actStaffReactivated => 'إعادة تنشيط موظف';
  @override
  String get actStaffPinReset => 'إعادة ضبط رمز الدخول';
  @override
  String get actStaffRoleChanged => 'تغيير دور موظف';
  @override
  String get actStaffGrantsChanged => 'تغيير صلاحيات موظف';
  @override
  String get actRoleCreated => 'إنشاء دور';
  @override
  String get actRoleUpdated => 'تعديل دور';
  @override
  String get actRoleDeleted => 'حذف دور';
  @override
  String get actPermissionOverridden => 'اعتماد إجراء لموظف';
  @override
  String get actShiftOpened => 'بدء وردية';
  @override
  String get actShiftClosed => 'إغلاق وردية';
  @override
  String get actReceiptReprinted => 'إعادة طباعة فاتورة';
  @override
  String get actCategoryCreated => 'إضافة تصنيف';
  @override
  String get actCategoryUpdated => 'تعديل تصنيف';
  @override
  String get actCategoryArchived => 'أرشفة تصنيف';
  @override
  String get actCategoryRestored => 'استعادة تصنيف';
  @override
  String get actProductCreated => 'إضافة صنف';
  @override
  String get actProductUpdated => 'تعديل صنف';
  @override
  String get actProductArchived => 'أرشفة صنف';
  @override
  String get actProductRestored => 'استعادة صنف';
  @override
  String get actProductRepriced => 'تغيير سعر';
  @override
  String get actMoneyConfigChanged => 'تعديل قواعد الضريبة والتقريب';
  @override
  String get actReceiptProfileChanged => 'تعديل بيانات الفاتورة';
  @override
  String get actTableCreated => 'إضافة طاولة';
  @override
  String get actTableUpdated => 'تعديل طاولة';
  @override
  String get actTableArchived => 'أرشفة طاولة';
  @override
  String get actTableRestored => 'استعادة طاولة';
  @override
  String get actPurchaseOrderStatusChanged => 'تحديث حالة أمر شراء';
  @override
  String get actStockReceived => 'تسجيل توريد';
  @override
  String get actSupplierSaved => 'إضافة أو تعديل مورّد';
  @override
  String get actSupplierInvoiceSaved => 'إدخال فاتورة مورّد';
  @override
  String get actSupplierInvoiceVoided => 'إلغاء فاتورة مورّد';
  @override
  String get actSupplierPaid => 'سداد لمورّد';
  @override
  String get actSupplierPaymentVoided => 'عكس سداد لمورّد';
  @override
  String get actServiceChargeSaved => 'تعديل رسم خدمة';
  @override
  String get actTenderTypeSaved => 'تعديل طريقة سداد';
  @override
  String get actOrderTypeSaved => 'تعديل نوع طلب';
  @override
  String get actTaxGroupSaved => 'تعديل نسبة ضريبة';
  @override
  String get actProductOptionsChanged => 'تعديل أحجام أو إضافات صنف';
  @override
  String get actOptionGroupSaved => 'تعديل مجموعة أحجام أو إضافات';
  @override
  String get actOptionGroupRepriced => 'تغيير سعر حجم أو إضافة';
  @override
  String get actOptionGroupDeleted => 'حذف مجموعة أحجام أو إضافات';
  @override
  String get fieldYes => 'نعم';
  @override
  String get fieldNo => 'لا';
  @override
  String get unitEach => 'قطعة';
  @override
  String get unitKilogram => 'كجم';
  @override
  String get unitGram => 'جم';
  @override
  String get unitLitre => 'لتر';
  @override
  String get unitMillilitre => 'مل';
  @override
  String get unitBox => 'صندوق';
  @override
  String get unitPack => 'عبوة';
  @override
  String get supplierOwes => 'مستحق';
  @override
  String get supplierOverdue => 'متأخر';

  @override
  String get fieldTaxGroup => 'نسبة الضريبة';
  @override
  String get fieldTaxGroupHint =>
      'اتركها على الافتراضية إلا إذا كان الصنف يخضع لنسبة مختلفة — زجاجة مياه '
      'بنسبة صفر مثلًا.';
  @override
  String get fieldTaxGroupDefault => 'الافتراضية';
  @override
  String get taxGroups => 'النسب المسمّاة';
  @override
  String get taxGroupsHint =>
      'نسبة لكل نوع مما تبيعه. يُحتسب على الصنف نسبة مجموعته، أو النسبة '
      'الافتراضية أدناه إن لم يذكر مجموعة.';
  @override
  String get taxGroupsFallback =>
      'لا توجد نسب مضبوطة — تُحتسب النسبة الواحدة أعلاه على كل الأصناف، بما فيها '
      'ما تبيعه بنسبة صفر.';
  @override
  String get taxGroupNew => 'نسبة جديدة';
  @override
  String get taxGroupEdit => 'النسبة';
  @override
  String get taxGroupHint =>
      'النسبة صفر والإعفاء كلاهما ٠٪ وهما مختلفان في الإقرار الضريبي، والاسم هو '
      'المكان الوحيد الذي يظهر فيه هذا الفرق.';
  @override
  String get taxGroupName => 'الاسم كما يعرفه محاسبك';
  @override
  String get taxGroupNeedsAName => 'النسبة تحتاج اسمًا.';
  @override
  String get taxGroupRate => 'النسبة';
  @override
  String get taxGroupRateNotValid => 'النسبة رقم بين ٠ و ١٠٠.';
  @override
  String get taxGroupDefault => 'النسبة الافتراضية';
  @override
  String get taxGroupDefaultHint =>
      'ما يُحتسب على الصنف الذي لا يذكر نسبة خاصة به. مجموعة واحدة فقط تكون '
      'الافتراضية، وجعل هذه افتراضية يُلغيها عن الأخرى.';
  @override
  String get taxGroupIsDefault => 'الافتراضية';
  @override
  String get taxGroupActive => 'قيد الاستخدام';
  @override
  String get taxGroupActiveHint =>
      'إيقافها يُخرجها من الخدمة، وتعود الأصناف التي عليها إلى النسبة '
      'الافتراضية — فراجع ما عليها أولًا.';
  @override
  String get orderTypes => 'أنواع الطلبات';
  @override
  String get orderTypesHint => 'ما يحتاجه كل نوع من الطلبات قبل أن يُحاسب.';
  @override
  String get orderTypesComeFromPlatform =>
      'هذه تأتي من XOrder على هذا الجهاز. يمكنك رؤيتها، والمنصة تضبطها.';
  @override
  String get orderTypeName => 'الاسم الذي تستخدمه';
  @override
  String get orderTypeNeedsAName => 'نوع الطلب يحتاج اسمًا.';
  @override
  String get orderTypeRequiresTable => 'له طاولة';
  @override
  String get orderTypeRequiresTableHint =>
      'يفعّل مخطط الصالة لهذا النوع. شغّله لخدمة الحفلات التي تُجلس العملاء، أو '
      'لمسارات السيارات المرقّمة.';
  @override
  String get orderTypeRequiresCustomer => 'يحتاج عميلًا';
  @override
  String get orderTypeRequiresCustomerHint =>
      'لا شيء يطلبه بعد — ملف العملاء قيد الإنشاء — ويُحفظ الآن ليكون صحيحًا حين '
      'يصل.';
  @override
  String get orderTypeRequiresAddress => 'يحتاج عنوانًا';
  @override
  String get orderTypeRequiresAddressHint => 'للدليفري، وللدليفري وحده.';
  @override
  String get orderTypeOffered => 'متاح هنا';
  @override
  String get orderTypeOfferedHint =>
      'إيقافه يُخرجه من الكاشير. الطلبات السابقة تحتفظ به.';
  @override
  String get orderTypeNotOffered => 'غير متاح';
  @override
  String get orderTypeChipTable => 'طاولة';
  @override
  String get orderTypeChipCustomer => 'عميل';
  @override
  String get orderTypeChipAddress => 'عنوان';
  @override
  String get paneTaxes => 'الضريبة';
  @override
  String get paneTaxesHint => 'النسب التي يحتسبها المطعم، وعلى ماذا.';
  @override
  String get backOffice => 'الإدارة';
  @override
  String get tabHome => 'الرئيسية';
  @override
  String get tabSales => 'المبيعات';
  @override
  String get tabReports => 'التقارير';
  @override
  String get tabMenu => 'المنيو';
  @override
  String get tabInventory => 'المخزون';
  @override
  String get tabPurchasing => 'المشتريات';
  @override
  String get tabFinance => 'المالية';
  @override
  String get tabSystem => 'النظام';
  @override
  String get tabSettings => 'الإعدادات';
  @override
  String get tabPeople => 'الأفراد';
  @override
  String get reportsSummary => 'ملخص الأعمال';
  @override
  String get rolesAndPermissions => 'الأدوار والصلاحيات';
  @override
  String get paneDevices => 'الأجهزة';
  @override
  String get settingsOrdersInvoices => 'إعدادات الطلبات والفواتير';
  @override
  String get settingsLanguage => 'اللغة';
  @override
  String get settingsLook => 'المظهر';
  @override
  String get paneHomeBlurb => 'هذا الجهاز، وسير اليوم، والطريق إلى بقية الأقسام.';
  @override
  String homeWelcome(String name) => 'أهلاً، $name';
  @override
  String get homeCardConnection => 'الاتصال';
  @override
  String get homeCardLastSync => 'آخر مزامنة';
  @override
  String get homeCardLastBackup => 'آخر نسخة احتياطية';
  @override
  String get homeNotSet => 'غير محدد';
  @override
  String get homeNever => 'لم يحدث بعد';
  @override
  String homeSalesWaiting(int count) => 'مبيعات بانتظار الإرسال: $count';
  @override
  String get homeToday => 'اليوم';
  @override
  String homeDayOpen(String date, String time) =>
      'يوم العمل $date · مفتوح منذ $time';
  @override
  String homeDayClosed(String date) =>
      'لا يوجد يوم عمل مفتوح. هذه أرقام يوم $date، آخر يوم أُغلق.';
  @override
  String get homeNoDayYet => 'لم يُفتح أي يوم عمل بعد، فلا توجد مبيعات لعرضها.';
  @override
  String get homeSalesUnavailable => 'تعذّرت قراءة أرقام اليوم من قاعدة البيانات.';
  @override
  String get homeKpiNetSales => 'صافي المبيعات';
  @override
  String get homeKpiOrders => 'الطلبات';
  @override
  String get homeKpiAverage => 'متوسط الطلب';
  @override
  String get homeVsPreviousDay => 'مقارنة باليوم السابق، بنفس المدة منذ الفتح';
  @override
  String get homeNoComparison => 'لا يوجد يوم سابق للمقارنة';
  @override
  String get homeQuickActions => 'إجراءات سريعة';
  @override
  String get homeActionReports => 'تقارير المبيعات';
  @override
  String get homeActionProducts => 'إدارة المنتجات';
  @override
  String get homeActionEmployees => 'الموظفون';
  @override
  String get financeOverview => 'نظرة عامة';
  @override
  String get financeOverviewBlurb => 'ما دخل خلال الفترة، وكيف دُفع.';
  @override
  String get financeRevenue => 'الإيرادات';
  @override
  String get financeRevenueBlurb =>
      'المبيعات والخصومات والمرتجعات لكل يوم عمل، بأرقام التقارير نفسها.';
  @override
  String get financePayments => 'طرق الدفع';
  @override
  String get financePaymentsBlurb => 'كل دفعة على مبيعات الفترة، كلٌّ في سطر.';
  @override
  String get financeTaxes => 'الضرائب';
  @override
  String get financeTaxesBlurb =>
      'الضريبة المحصَّلة لكل نسبة، مخصوماً منها ما رُدّ مع المرتجعات.';
  @override
  String get financePeriodToday => 'اليوم';
  @override
  String get financePeriodThisWeek => 'هذا الأسبوع';
  @override
  String get financePeriodThisMonth => 'هذا الشهر';
  @override
  String get financePeriodLastMonth => 'الشهر الماضي';
  @override
  String get financeBusinessDates => 'أيام العمل';
  @override
  String get financeKpiRevenue => 'الإيرادات (صافي المبيعات)';
  @override
  String get financeKpiCollected => 'المحصَّل';
  @override
  String get financeKpiOnAccount => 'على الحساب';
  @override
  String get financeKpiTax => 'الضريبة بعد المرتجعات';
  @override
  String get financeTendersTitle => 'المحصَّل حسب طريقة الدفع';
  @override
  String get financeOnAccountNote =>
      'المبلغ على الحساب دَين لم يُحصَّل بعد، فلا نصيب له في الشريط.';
  @override
  String get financeNothingCollected => 'لم يُحصَّل شيء في هذه الفترة.';
  @override
  String get financeGross => 'إجمالي المبيعات';
  @override
  String get financeDiscounts => 'الخصومات';
  @override
  String get financeRefunds => 'المرتجعات';
  @override
  String get financeNet => 'صافي المبيعات';
  @override
  String get financeOrders => 'عدد المبيعات';
  @override
  String get financeAverage => 'متوسط البيع';
  @override
  String get financeDate => 'يوم العمل';
  @override
  String get financeTotal => 'الإجمالي';
  @override
  String get financeRefundsNote =>
      'يُحتسب المرتجع في يوم ردّه، أياً كان يوم البيع.';
  @override
  String get financeByMethod => 'حسب طريقة الدفع';
  @override
  String get financeMethod => 'الطريقة';
  @override
  String get financePaymentCount => 'الدفعات';
  @override
  String get financeAmount => 'المبلغ';
  @override
  String get financeShare => 'الحصة';
  @override
  String get financeLedgerTitle => 'الدفعات، الأحدث أولاً';
  @override
  String get financeInvoice => 'الفاتورة';
  @override
  String get financeTime => 'الوقت';
  @override
  String get financeLedgerTotal => 'إجمالي الدفعات المعروضة';
  @override
  String financeLedgerTruncated(int count) =>
      'تُعرض أحدث $count دفعة فقط، أما الإجماليات حسب الطريقة فتشمل الفترة '
      'كلها.';
  @override
  String get financeNoPayments => 'لم تُسجَّل دفعات في هذه الفترة.';
  @override
  String get financeTaxName => 'الضريبة';
  @override
  String get financeTaxRate => 'النسبة';
  @override
  String get financeTaxBase => 'المبيعات الخاضعة';
  @override
  String get financeTaxCharged => 'المحصَّلة';
  @override
  String get financeTaxRefunded => 'المردودة';
  @override
  String get financeTaxNet => 'الصافي';
  @override
  String get financeTaxUnattributed => 'مردودة على مبيعات لم تُسجَّل لها نسبة';
  @override
  String get financeTaxNote =>
      'تُحتسب الضريبة المحصَّلة في يوم عمل البيع، والمردودة في يوم الرد، '
      'موزعةً على نسب البيع كما يوزعها الإشعار الدائن. المبيعات الخاضعة قبل '
      'المرتجعات.';
  @override
  String get financeNoTaxes => 'لم تُحصَّل أو تُردّ أي ضريبة في هذه الفترة.';
  @override
  String get financeUnavailable => 'تعذّرت قراءة الأرقام من قاعدة بيانات الفرع.';
  @override
  String get financeNoFigures =>
      'لا توجد لهذا الجهاز بعدُ قاعدة بيانات فرع يقرأ منها الأرقام.';
  @override
  String get financeExpenses => 'المصروفات';
  @override
  String get financeExpensesBlurb =>
      'ما خرج من الأدراج نقداً، وما دُفع للموردين.';
  @override
  String get financeDrawers => 'الخزينة';
  @override
  String get financeDrawersBlurb =>
      'النقد الذي يجب أن يكون في كل درج مفتوح الآن.';
  @override
  String get financeBills => 'الفواتير المستحقة';
  @override
  String get financeBillsBlurb => 'ما على المطعم للموردين، حسب موعد استحقاقه.';
  @override
  String get financeTransactions => 'الحركات';
  @override
  String get financeTransactionsBlurb =>
      'المبيعات وإخراج النقد وفواتير الموردين ومدفوعاتهم، الأحدث أولاً.';
  @override
  String get financeKpiExpenses => 'المصروفات';
  @override
  String get financeExpensesWithSuppliers =>
      'النقد الخارج من الأدراج، مضافاً إليه مدفوعات الموردين غير الملغاة.';
  @override
  String get financeExpensesPayOutsOnly => 'النقد الخارج من الأدراج فقط.';
  @override
  String get financeSuppliersOnPlatform =>
      'مدفوعات الموردين لهذا المطعم تُسجَّل على المنصة، فلا تُحتسب هنا.';
  @override
  String get financeSuppliersNotPermitted =>
      'مدفوعات الموردين غير محتسبة: قراءتها تتطلب صلاحية المشتريات.';
  @override
  String get financeCountedOnce =>
      'المورد الذي دُفع له من درج الكاشير يُحتسب مرة واحدة، كدفعة مورد.';
  @override
  String get financePayOuts => 'النقد الخارج من الأدراج';
  @override
  String get financeSupplierPayments => 'مدفوعات الموردين';
  @override
  String get financeNoExpenses => 'لم يُصرف شيء في هذه الفترة.';
  @override
  String get financeRecentExpenses => 'أحدث المصروفات';
  @override
  String get financeViewAll => 'عرض الكل';
  @override
  String get financeType => 'النوع';
  @override
  String get financeDetails => 'التفاصيل';
  @override
  String get financeKpiDrawers => 'النقد المتوقع في الأدراج المفتوحة';
  @override
  String financeOpenDrawerCount(int count) => 'الأدراج المفتوحة: $count';
  @override
  String get financeNoOpenDrawers => 'لا يوجد درج مفتوح في هذا الفرع.';
  @override
  String get financeOpenedBy => 'فتحه';
  @override
  String get financeOpenedAt => 'وقت الفتح';
  @override
  String get financeFloat => 'رصيد البداية';
  @override
  String get financeCashTaken => 'المحصَّل نقداً';
  @override
  String get financePaidIn => 'نقد داخل';
  @override
  String get financePaidOut => 'نقد خارج';
  @override
  String get financeExpected => 'المتوقع في الدرج';
  @override
  String get financeDrawersNote =>
      'المتوقع هو الرقم الذي يُطابَق عليه الدرج في تقرير Z: رصيد البداية، '
      'مضافاً إليه المحصَّل نقداً والنقد الداخل، مطروحاً منه النقد الخارج. '
      'أرصدة البنوك والمحافظ الإلكترونية لا تُحفظ هنا.';
  @override
  String get financeAsOf => 'حتى يوم العمل';
  @override
  String get financeBucketOverdue => 'متأخرة';
  @override
  String get financeBucketToday => 'مستحقة اليوم';
  @override
  String get financeBucketWeek => 'مستحقة خلال 7 أيام';
  @override
  String get financeBucketLater => 'مستحقة لاحقاً';
  @override
  String get financeTotalOwed => 'إجمالي المستحق';
  @override
  String get financeSupplier => 'المورد';
  @override
  String get financeDueDate => 'الاستحقاق';
  @override
  String get financePaid => 'المدفوع';
  @override
  String get financeOutstanding => 'المتبقي';
  @override
  String get financeNoBills => 'لا شيء مستحق للموردين.';
  @override
  String get financeBillsNote =>
      'كل فاتورة غير مسدَّدة في مجموعة واحدة فقط، حسب تاريخ استحقاقها '
      'مقارنةً بيوم العمل. المبالغ المدفوعة على الحساب تُنقص ما للمورد لكنها '
      'لا تسدِّد فاتورة بعينها، فلا تُخصم هنا.';
  @override
  String get financeRecentTransactions => 'أحدث الحركات';
  @override
  String get financeReference => 'المرجع';
  @override
  String get financeStatus => 'الحالة';
  @override
  String get financeKindSale => 'بيع';
  @override
  String get financeKindPayOut => 'إخراج نقد';
  @override
  String get financeKindSupplierInvoice => 'فاتورة مورد';
  @override
  String get financeKindSupplierPayment => 'دفعة مورد';
  @override
  String get financeStatusPaid => 'مدفوع';
  @override
  String get financeStatusPartlyPaid => 'مدفوع جزئياً';
  @override
  String get financeStatusUnpaid => 'غير مدفوع';
  @override
  String get financeStatusPartlyRefunded => 'مسترد جزئياً';
  @override
  String get financeStatusRefunded => 'مسترد';
  @override
  String get financeStatusOpen => 'مفتوح';
  @override
  String get financeStatusVoided => 'ملغى';
  @override
  String get financeStatusRecorded => 'مسجَّل';
  @override
  String get financeNoTransactions => 'لم تتحرك أموال في هذه الفترة.';
  @override
  String financeTransactionsTruncated(int count) =>
      'تُعرض أحدث $count حركة فقط. اختر فترة أقصر لرؤية الأقدم.';
  @override
  String get financeTransactionsNote =>
      'فاتورة المورد مطالبة وليست مالاً تحرّك، وسدادها سطر مستقل. المبيعات '
      'المعروضة هي التي يعرضها لك تبويب المبيعات.';
  @override
  String get settingsGeneral => 'عام';
  @override
  String get settingsAppearance => 'اللغة والمظهر';
  @override
  String get paneAppearanceBlurb => 'لغة هذا الجهاز ومظهره';
  @override
  String get appearanceThisTerminal =>
      'لهذا الجهاز فقط. يحتفظ كل جهاز آخر بلغته ومظهره، أيًّا كان من يسجّل '
      'الدخول.';
  @override
  String get appearanceLanguage => 'اللغة';
  @override
  String get appearanceTheme => 'المظهر';
  @override
  String get themeSystem => 'تلقائي';
  @override
  String get themeLight => 'فاتح';
  @override
  String get themeDark => 'داكن';
  @override
  String get themeSystemHint =>
      'التلقائي يتبع إعداد الفاتح أو الداكن في هذا الجهاز نفسه.';
  @override
  String get backupLastCopy => 'آخر نسخة';
  @override
  String get backupNowNeedsPermission =>
      'أخذ نسخة عند الطلب يحتاج صلاحية النسخ الاحتياطي.';
  @override
  String get manage => 'الإدارة';
  @override
  String get manageMenuTooltip => 'افتح أحد أقسام الإدارة';
  @override
  String get backToTill => 'رجوع إلى الكاشير';
  @override
  String get paneStaff => 'الموظفون';
  @override
  String get paneStaffBlurb => 'من يعمل هنا، وما المسموح له به';
  @override
  String get paneSalesBlurb => 'كل بيع سجّله هذا الفرع، بإيصاله ومرتجعاته';
  @override
  String get paneReportsBlurb =>
      'ما باعه هذا الفرع خلال فترة، ومقارنته بالفترة التي قبلها';
  @override
  String get reportPeriodToday => 'اليوم';
  @override
  String get reportPeriodWeek => 'هذا الأسبوع';
  @override
  String get reportPeriodMonth => 'هذا الشهر';
  @override
  String get reportPeriodCustom => 'فترة مخصصة';
  @override
  String get reportVsPrevious => 'مقارنة بالفترة السابقة بنفس الطول';
  @override
  String get reportNoComparison => 'لا شيء في الفترة السابقة للمقارنة';
  @override
  String get reportKpiRefunds => 'المرتجعات';
  @override
  String reportRefundCount(int count) => 'عدد المرتجعات: $count';
  @override
  String get reportTrend => 'المبيعات حسب يوم العمل';
  @override
  String get reportTopProducts => 'الأصناف الأكثر مبيعاً';
  @override
  String get reportTopProductsNote =>
      'الوحدات التي بقيت مباعة بعد المرتجعات والإلغاء، بسعر بيعها — قبل '
      'الخصومات';
  @override
  String get reportRankQuantity => 'حسب الكمية';
  @override
  String get reportRankAmount => 'حسب القيمة';
  @override
  String get reportColumnQuantity => 'الكمية';
  @override
  String get reportColumnAmount => 'القيمة';
  @override
  String get reportNoProducts => 'لم يُبع أي صنف في هذه الفترة.';
  @override
  String get reportPayments => 'طرق الدفع';
  @override
  String get reportOnAccount => 'على الحساب — مبلغ مستحق لم يُحصَّل';
  @override
  String get reportNoPayments => 'لم يُحصَّل أي مبلغ في هذه الفترة.';
  @override
  String get reportTerminals => 'حسب نقطة البيع';
  @override
  String get reportBranchTotal => 'إجمالي الفرع';
  @override
  String get reportUnregistered => 'غير مسجّلة في هذا الفرع';
  @override
  String get reportInsights => 'أبرز الملاحظات';
  @override
  String get reportInsightBestDay => 'أفضل يوم';
  @override
  String get reportInsightTopTerminal => 'نقطة البيع الأعلى مبيعاً';
  @override
  String get reportInsightGrowth => 'صافي المبيعات مقارنة بالفترة السابقة';
  @override
  String get reportInsightsNone =>
      'لا توجد مبيعات كافية في هذه الفترة لاستخلاص ملاحظات.';
  @override
  String get reportUnavailable => 'تعذّرت قراءة التقرير من قاعدة البيانات.';
  @override
  String get reportNoDatabase =>
      'تُقرأ التقارير من قاعدة بيانات الفرع، وهذا الجهاز غير متصل بها بعد.';
  @override
  String get exportExcel => 'تصدير إلى Excel';
  @override
  String get exportExcelDialogTitle => 'حفظ ملف Excel';
  @override
  String exportExcelSaved(String path) => 'حُفظ الملف في $path';
  @override
  String exportExcelFailed(String reason) => 'تعذّرت كتابة ملف Excel: $reason';
  @override
  String get exportSheetSummary => 'الملخص';
  @override
  String get exportPeriodFrom => 'من';
  @override
  String get exportPeriodTo => 'إلى';
  @override
  String get exportColumnFigure => 'البند';
  @override
  String get exportColumnValue => 'القيمة';
  @override
  String get exportColumnNote => 'ملاحظة';
  @override
  String get exportColumnDate => 'التاريخ';
  @override
  String get exportColumnOccurredAt => 'التاريخ والوقت';
  @override
  String get exportColumnShare => 'النسبة';
  @override
  String get exportColumnRank => 'الترتيب';
  @override
  String get exportColumnProduct => 'الصنف';
  @override
  String get paneMenu => 'المنيو';
  @override
  String get paneMenuBlurb => 'الأقسام والأصناف وأسعارها';
  @override
  String get panePurchasing => 'المشتريات';
  @override
  String get panePurchasingBlurb =>
      'من تشتري منهم، وما طلبته، وتسجيل ما يصل.';
  @override
  String get paneRoles => 'الأدوار';
  @override
  String get paneRolesBlurb => 'الصلاحيات وراء كل مسمى وظيفي';
  @override
  String get paneActivity => 'السجل';
  @override
  String get paneActivityBlurb => 'ما الذي تغيّر، وعلى يد من';
  // ── Backup and restore ────────────────────────────────────────────
  @override
  String get paneBackup => 'النسخ الاحتياطي';
  @override
  String get paneBackupBlurb => 'نسخ من قاعدة البيانات، واستعادة إحداها';
  @override
  String get backupSameDiskWarning =>
      'تُحفظ النسخ على قرص هذا الجهاز نفسه. هذا ينجّيك من تعديل خاطئ أو جدول '
      'محذوف، ولا ينجّيك من عطل القرص أو سرقة الجهاز أو حريق أو برنامج يشفّر كل '
      'ملف يستطيع هذا الحساب الكتابة فيه — وهذه هي الأمور التي تحدث فعلاً. '
      'انسخ أحدث نسخة إلى ذاكرة USB بانتظام — «انسخ إلى…» بجانب أي نسخة '
      'موثّقة — واحتفظ بها في مكان غير هذا الجهاز.';
  @override
  String get backupToolsMissing =>
      'أدوات PostgreSQL غير موجودة على هذا الجهاز، فلا يمكن أخذ نسخة احتياطية '
      'ولا استعادة واحدة.';
  @override
  String get backupToolsMissingHelp =>
      'ثبّت أدوات PostgreSQL — pg_dump و pg_restore — من postgresql.org ثم '
      'افتح هذه الشاشة من جديد.';
  @override
  String get backupSearchedIn => 'تم البحث في';
  @override
  String get backupDestination => 'مكان حفظ النسخ';
  @override
  String get backupDestinationHint =>
      'مجلد على هذا الجهاز. يُنشأ تلقائياً إن لم يكن موجوداً.';
  @override
  String get backupTakeNow => 'خذ نسخة الآن';
  @override
  String get backupTaking => 'جارٍ أخذ النسخة…';
  @override
  String get backupAutomatic => 'خذ نسخة عند إقفال يوم العمل';
  @override
  String get backupAutomaticHint =>
      'مفعّل افتراضياً. النسخة التي لا يتذكّر أحد أخذها ليست نسخة احتياطية.';
  @override
  String get backupHistory => 'النسخ المأخوذة';
  @override
  String get backupNoneYet => 'لم تُؤخذ أي نسخة من قاعدة البيانات حتى الآن.';
  @override
  String get backupNoVerifiedCopy =>
      'لا توجد نسخة تم التحقق منها. هذا المطعم بلا نسخة احتياطية.';
  @override
  String backupLastVerified(String when) => 'آخر نسخة موثّقة: $when';
  @override
  String backupStale(int days) => days == 1
      ? 'مضى على آخر نسخة موثّقة يوم واحد.'
      : 'مضى على آخر نسخة موثّقة $days يوماً.';
  @override
  String get backupOutcomeVerified => 'موثّقة';
  @override
  String get backupOutcomeUnverified => 'ليست نسخة احتياطية';
  @override
  String get backupOutcomeFailed => 'فشلت';
  @override
  String get backupTriggerManual => 'يدوي';
  @override
  String get backupTriggerDayClose => 'إقفال اليوم';
  @override
  String get backupFailureToolsMissing =>
      'أداة pg_dump غير مثبّتة على هذا الجهاز.';
  @override
  String get backupFailureDestinationUnwritable =>
      'تعذّرت الكتابة في المجلد.';
  @override
  String get backupFailureDumpRefused => 'رفضت PostgreSQL إنتاج النسخة.';
  @override
  String get backupFailureArchiveUnreadable =>
      'كُتب الملف ولم تنجح قراءته مرة أخرى.';
  @override
  String get backupFailureArchiveIncomplete =>
      'تنقص الملفَ جداولُ لا يستطيع المطعم العمل بدونها.';
  @override
  String backupTablesFound(int count) =>
      count == 1 ? 'جدول واحد' : '$count جدولاً';
  @override
  String get backupRestoreAction => 'استعادة…';
  @override
  String backupRestoreTitle(String when) =>
      'هل تستبدل قاعدة البيانات بالنسخة المأخوذة $when؟';
  @override
  String get backupRestoreBlocked => 'لا يمكن الاستعادة والكاشير ما زال يعمل.';
  @override
  String restoreBlockerOpenShifts(int count) => count == 1
      ? 'كاشير واحد ما زالت ورديته مفتوحة'
      : '$count كاشيرات ما زالت ورديّاتها مفتوحة';
  @override
  String restoreBlockerOpenDay(int count) => 'يوم العمل لم يُقفل بعد';
  @override
  String backupRestoreOrdersLost(int count, String value) => count == 1
      ? 'سيضيع طلب واحد سُجّل بعد ذلك الوقت، بقيمة $value.'
      : 'سيضيع $count طلباً سُجّلت بعد ذلك الوقت، بقيمة $value.';
  @override
  String get backupRestoreEverythingElseLost =>
      'ويضيع معها كل ما سُجّل بعد ذلك — الورديات وحركات النقدية وتغييرات '
      'الموظفين وسجل التدقيق.';
  @override
  String get backupRestoreNoWayBack =>
      'لا رجوع بعدها. لا شيء هنا يحتفظ بنسخة مما سيُستبدل.';
  @override
  String get backupRestoreConfirm => 'استبدل قاعدة البيانات';
  @override
  String get backupRestoreKeep => 'أبقِ قاعدة البيانات';
  @override
  String get backupRestoreDone =>
      'تم استبدال قاعدة البيانات. أغلق البرنامج ثم شغّله من جديد.';
  @override
  String backupRestoreFailed(String detail) =>
      'لم تكتمل الاستعادة ولم يتغيّر شيء. $detail';
  @override
  String get backupAccount => 'حساب النسخ الاحتياطي';
  @override
  String get backupAccountHint =>
      'يدخل النسخ الاحتياطي إلى PostgreSQL باسم pos_backup، وهو حساب للقراءة '
      'فقط أُنشئ عند تثبيت PostgreSQL. أدخل كلمة مروره مرة واحدة؛ تُحفظ على '
      'هذا الجهاز كي تعمل نسخة إقفال اليوم دون أن يكون أحد مسجّلاً هنا.';
  @override
  String get backupAccountStored => 'كلمة المرور محفوظة على هذا الجهاز.';
  @override
  String get backupAccountMissing => 'لم تُحفظ كلمة مرور على هذا الجهاز بعد.';
  @override
  String get backupAccountSaved => 'تم الحفظ. ستستخدمها النسخة القادمة.';
  @override
  String get backupCopyAction => 'انسخ إلى…';
  @override
  String backupCopyDone(String path) =>
      'نُسخت إلى $path وتمت مطابقتها مع الأصل.';
  @override
  String backupCopyFailed(String detail) => 'لم تتم النسخ. $detail';
  @override
  String get backupRestoreFromFile => 'استعادة من ملف…';
  @override
  String get backupFileGone =>
      'لم تعد على هذا الجهاز — يُحتفظ هنا بأحدث 14 نسخة فقط.';
  @override
  String get backupOpenPane => 'افتح النسخ الاحتياطي';
  @override
  String get backupDayCloseWorking => 'جارٍ إقفال اليوم وأخذ نسخة احتياطية…';
  @override
  String get backupDayCloseFailed =>
      'تم إقفال اليوم. لم تنجح النسخة الاحتياطية التلقائية — افتح الإدارة ثم '
      'النسخ الاحتياطي لمعرفة السبب.';
  @override
  String get actBackupTaken => 'أخذ نسخة احتياطية';
  @override
  String get actBackupRestored => 'استعاد قاعدة البيانات من نسخة احتياطية';
  @override
  String get actAdminEntered => 'فتح وضع المسؤول';
  @override
  String get actAdminExited => 'خرج من وضع المسؤول';
  @override
  String get actAdminTimedOut => 'أُقفل وضع المسؤول لعدم النشاط';
  @override
  String get actAdminLockedOut =>
      'أُغلق باب وضع المسؤول بعد أكواد خاطئة متكررة لاسم المستخدم هذا';
  @override
  String get actAdminRefused => 'رُفض دخوله وضع المسؤول';
  @override
  String adminTitle(String pane) => 'XOrder POS › المسؤول › $pane';
  @override
  String get exitAdminMode => 'الخروج من وضع المسؤول';
  @override
  String get adminSignInTitle => 'وضع المسؤول';
  @override
  String adminSignInHelp(int minutes) =>
      'اسم المستخدم والكود الخاص بك. يُقفل وضع المسؤول نفسه بعد $minutes '
      'دقيقة دون لمس أو ضغط مفتاح.';
  @override
  String get yourPin => 'الكود الخاص بك';
  @override
  String get openAdminMode => 'فتح وضع المسؤول';
  @override
  String get adminSignInRefused =>
      'اسم المستخدم والكود هذان لا يفتحان وضع المسؤول.';
  @override
  String adminSignInAttemptsLeft(int attempts) => attempts == 1
      ? '$adminSignInRefused بقيت محاولة واحدة.'
      : '$adminSignInRefused بقيت $attempts محاولات.';
  @override
  String adminSignInLockedOut(int seconds) => seconds < 60
      ? 'محاولات خاطئة كثيرة. يمكن تجربة وضع المسؤول مرة أخرى بعد $seconds '
            'ثانية.'
      : 'محاولات خاطئة كثيرة. يمكن تجربة وضع المسؤول مرة أخرى بعد '
            '${(seconds + 59) ~/ 60} دقيقة.';
  @override
  String get adminDatabasePasswordNeeded =>
      'في المرة الأولى على هذا الجهاز، يحتاج وضع المسؤول أيضاً إلى كلمة مرور '
      'قاعدة بيانات الإدارة — مرة واحدة فقط. وتُحفظ على هذا الجهاز بعد ذلك.';
  @override
  String get adminDatabasePasswordRefused =>
      'لم تقبل PostgreSQL كلمة مرور الإدارة هذه.';
  @override
  String adminLockedAfter(int minutes) =>
      'أقفل وضع المسؤول نفسه بعد $minutes دقيقة دون نشاط. سجّل الدخول مرة '
      'أخرى للمتابعة.';
  @override
  String get adminModeSettingsHint =>
      'كيف يسمح هذا الجهاز بالدخول إلى وضع المسؤول. الاختصار مجرد مدخل مخفي — '
      'اسم المستخدم والكود هما القفل.';
  @override
  String get adminLockAfter => 'الإقفال بعد';
  @override
  String adminMinutes(int minutes) => '$minutes دقيقة';
  @override
  String get adminShortcut => 'الاختصار';
  // ── end of the backup block ────────────────────────────────────
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
  String get backOfficeSignInHelp =>
      'سجّل الدخول باسم مستخدم المسؤول وكلمة مرور الإدارة — كلمة مرور المسؤول '
      'التي حُددت عند تثبيت XOrder POS.';
  @override
  String get backOfficeSignInRefused =>
      'اسم المستخدم وكلمة المرور هذان لا يفتحان الإدارة.';
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
  String get settingsOrders => 'الطلبات والفواتير';
  @override
  String get settingsPrinter => 'الطابعة ودرج النقدية…';
  @override
  String get settingsAbout => 'حول XOrder POS';
  @override
  String get printerSettingsTitle => 'الطابعة ودرج النقدية';
  @override
  String get printerNoneChosen =>
      'لم تُختر طابعة. ابحث عن الطابعات على هذه الشبكة ثم اختر واحدة.';
  @override
  String get aboutVersion => 'الإصدار';
  @override
  String get aboutMode => 'الوضع';
  @override
  String get aboutTerminalId => 'معرّف الجهاز';
  @override
  String get aboutDatabase => 'قاعدة البيانات';
  @override
  String get receiptPreviewAction => 'معاينة';
  @override
  String get receiptPreviewNote =>
      'معاينة فقط — لا شيء يُطبع ولا شيء يُسجَّل.';
  @override
  String get paneUnits => 'الوحدات';
  @override
  String get paneUnitsBlurb => 'الوحدات التي يُعدّ ويُشترى بها المخزون';
  @override
  String get purchasingComesFromPlatform =>
      'على هذا الجهاز تُدار المشتريات والموردون والوحدات والمخزون من لوحة '
      'تحكم XOrder على xorder.io. اطلب البضاعة واستلمها وادفع للموردين من '
      'هناك، ولا يصل شيء منها إلى هذا الجهاز.';
  @override
  String get purchasingOnPlatformEntry => 'المشتريات والمخزون — على xorder.io…';
  @override
  String get unitNew => 'إضافة وحدة';
  @override
  String get unitEdit => 'تعديل الوحدة';
  @override
  String get unitNameEn => 'الاسم';
  @override
  String get unitNameAr => 'الاسم بالعربية';
  @override
  String get unitCode => 'الرمز';
  @override
  String get unitCodeHelp =>
      'قصير، ولا يتغيّر بعد الحفظ — تحفظه سطور المشتريات. حروف إنجليزية صغيرة '
      'وأرقام: kg، tray، box6.';
  @override
  String get unitEtaCode => 'رمز الوحدة لدى مصلحة الضرائب';
  @override
  String get unitEtaCodeHelp =>
      'ما تذكره الإيصالات الإلكترونية كوحدة بيع: EA قطعة، KGM كيلوجرام، '
      'LTR لتر.';
  @override
  String get unitAllowsFraction => 'تقبل الكسور';
  @override
  String get unitAllowsFractionHelp =>
      '١٢٫٥ كيلوجرام كمية حقيقية؛ ١٢٫٥ علبة ليست كذلك.';
  @override
  String get unitFractionChip => 'كسور';
  @override
  String get unitActive => 'مستخدمة';
  @override
  String get unitRetired => 'غير مستخدمة';
  @override
  String get actUnitSaved => 'حفظ وحدة';
  @override
  String get paneItems => 'أصناف المخزون';
  @override
  String get paneItemsBlurb => 'ما تشتريه وتعدّه — على المنيو أو لا';
  @override
  String get itemNew => 'إضافة صنف';
  @override
  String get itemEdit => 'تعديل الصنف';
  @override
  String get itemName => 'الاسم';
  @override
  String get itemNameAr => 'الاسم بالعربية';
  @override
  String get itemUnit => 'يُعدّ بـ';
  @override
  String get itemOnMenu => 'على المنيو';
  @override
  String get itemOnMenuHint =>
      'اسمه وسعره يُحدَّدان في المنيو؛ هنا تُحدَّد وحدة عدّه فقط.';
  @override
  String get itemsEmpty =>
      'لا شيء يُعدّ في المخزون بعد. أضف ما تشتريه — فراخ، زيت، غاز.';
  @override
  String get fieldTrackStock => 'تتبّع المخزون';
  @override
  String get fieldTrackStockHint => 'يُعدّ عند الشراء وتعرف كم تبقّى منه.';
  @override
  String get actStockItemSaved => 'حفظ صنف مخزون';
  @override
  String get paneStock => 'المخزون المتاح';
  @override
  String get paneStockBlurb =>
      'كم يوجد في هذا الفرع من كل صنف يُعدّ، وكم قيمته';
  @override
  String get stockColumnItem => 'الصنف';
  @override
  String get stockColumnOnHand => 'المتاح';
  @override
  String get stockColumnAvgCost => 'متوسط التكلفة';
  @override
  String get stockColumnValue => 'القيمة';
  @override
  String stockTotalValue(String amount) => 'قيمة المخزون: $amount';
  @override
  String get stockEmpty =>
      'لا شيء يُعدّ بعد. أضف ما تشتريه في أصناف المخزون، ثم استلم توريدة.';
  @override
  String get purchaseUnit => 'الوحدة';
  @override
  String purchaseAddAsItem(String name) => 'إضافة «$name» كصنف جديد';
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
  String get usersKpiStaff => 'الموظفون';
  @override
  String get usersKpiActive => 'النشطون';
  @override
  String usersActiveShare(int percent) => '$percent% من كل الحسابات';
  @override
  String get usersKpiShifts => 'الورديات الحالية';
  @override
  String get usersKpiShiftsNote => 'أدراج مفتوحة على أجهزة هذا الفرع';
  @override
  String get usersKpiRoles => 'الأدوار';
  @override
  String get staffStatusAll => 'الكل';
  @override
  String get staffStatusActive => 'نشط';
  @override
  String get staffStatusDisabled => 'موقوف';
  @override
  String get usersAllRoles => 'كل الأدوار';
  @override
  String get usersSearchHint => 'الاسم أو اسم المستخدم';
  @override
  String get usersColumnStatus => 'الحالة';
  @override
  String get usersColumnLastShift => 'آخر وردية';
  @override
  String get usersOnShiftNow => 'في وردية الآن';
  @override
  String get usersNeverOnShift => 'لم يفتح وردية';
  @override
  String get usersNoneMatch =>
      'لا أحد يطابق هذه التصفية. امسح البحث أو اختر دوراً آخر.';
  @override
  String get manageRoles => 'إدارة الأدوار';
  @override
  String get roleMatrixTitle => 'ما يسمح به كل دور';
  @override
  String get roleMatrixNote =>
      'الصلاحيات التي يمنحها كل دور. استثناءات الشخص نفسه غير محسوبة هنا — '
      'افتح صلاحياته لتراها.';
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

  @override
  String get extrasTitle => 'مكتبة الإضافات';
  @override
  String get extrasSubtitle =>
      'مجموعات خيارات قابلة لإعادة الاستخدام يمكنك ربطها بأي صنف. تعديل أي '
      'مجموعة يحدّثها في كل مكان تُستخدم فيه.';
  @override
  String get extrasNew => 'إضافة';
  @override
  String get extrasEdit => 'تعديل الإضافة';
  @override
  String get extrasNone =>
      'لا توجد إضافات مشتركة بعد. أنشئ واحدة لإعادة استخدامها عبر الأصناف.';
  @override
  String extrasUsedBy(int n) => '$n صنف';
  @override
  String get extrasNotUsed => 'غير مستخدمة بعد';
  @override
  String extrasDeleteWarning(int n) =>
      'حذف هذه الإضافة؟ ستتم إزالتها من $n صنف يستخدمها حالياً.';
  @override
  String extrasOptionsSummary(int n) => '$n خيار';
  @override
  String get extrasApplyTo => 'تنطبق على';
  @override
  String get extrasScopeItems => 'أصناف محددة';
  @override
  String get extrasScopeItemsHint => 'اربطها بالأصناف من صفحة كل صنف.';
  @override
  String get extrasScopeCategories => 'تصنيفات';
  @override
  String get extrasScopeAll => 'كل الأصناف';
  @override
  String get extrasPickCategories => 'اختر التصنيفات';
  @override
  String extrasAppliesCategories(int n) => '$n تصنيف';
  @override
  String get extrasLibraryNameEn => 'الاسم في قائمتك (إنجليزي)';
  @override
  String get extrasLibraryNameAr => 'الاسم في قائمتك (عربي)';
  @override
  String get extrasLibraryNameHint =>
      'به تجد هذه المجموعة هنا. لا يراه إلا أنت.';
  @override
  String get extrasMenuNameEn => 'عنوان المنيو (إنجليزي)';
  @override
  String get extrasMenuNameAr => 'عنوان المنيو (عربي)';
  @override
  String get extrasMenuNamePlaceholder => 'مثال: اختر الحجم';
  @override
  String get extrasMenuNameHint =>
      'ما يقرأه العميل فوق الاختيارات. اتركه فارغاً لاستخدام الاسم بالأعلى.';
  @override
  String extrasShownAs(String name) => 'في المنيو: $name';
  @override
  String get itemOptions => 'الخيارات والإضافات';
  @override
  String get itemNoOptions =>
      'لا توجد مجموعات خيارات. أضف واحدة للأحجام أو الإضافات أو "بدون…".';
  @override
  String get itemAddGroup => 'إضافة مجموعة';
  @override
  String get itemGroupNameEn => 'اسم المجموعة (مثال: الحجم)';
  @override
  String get itemGroupNameAr => 'اسم المجموعة';
  @override
  String get itemRequired => 'مطلوب';
  @override
  String get itemVariant => 'الحجم / النوع';
  @override
  String get itemVariantHint =>
      'كل خيار يحدد سعر الصنف (صغير/وسط/كبير). الاختيار مطلوب، وأول حجم في '
      'القائمة هو الافتراضي الذي تفتح عليه القائمة.';
  @override
  String get itemPricedBySize =>
      'سعر هذا الصنف يأتي من الأحجام بالأسفل. السعر بالأعلى يعكس الحجم '
      'الافتراضي — أول حجم في القائمة — فعدّل ذلك الحجم لتغييره.';
  @override
  String get itemDefaultSize => 'افتراضي';
  @override
  String get itemOptionDiscount => 'عرض';
  @override
  String get itemOptionDiscountHint =>
      'سعر عرض اختياري لهذا الحجم. يظهر للعميل مع شطب السعر الأصلي. يجب أن '
      'يكون أقل من السعر.';
  @override
  String get itemMaxSelect => 'أقصى اختيار';
  @override
  String get itemOptionEn => 'الخيار (إنجليزي)';
  @override
  String get itemOptionAr => 'الخيار';
  @override
  String get itemAddOption => 'إضافة خيار';
  @override
  String get itemAddFromLibrary => 'إضافة من المكتبة';
  @override
  String get itemFromLibrary => 'من المكتبة';
  @override
  String get itemLibraryEmpty =>
      'لا توجد إضافات مشتركة بعد. أنشئها من صفحة الإضافات.';
  @override
  String get itemManageLibrary => 'إدارة الإضافات';
  @override
  String get deleteLabel => 'حذف';
  @override
  String get deleteConfirmGeneric => 'هل أنت متأكد من الحذف؟';
  @override
  String get savingLabel => 'جارٍ الحفظ…';

  @override
  String get refusalGroupNameMissing =>
      'مجموعة الخيارات تحتاج إلى اسم — به تجدها مرة أخرى.';
  @override
  String get refusalGroupScopeNeedsLibrary =>
      'مجموعات المكتبة وحدها يمكن أن تنطبق على تصنيفات كاملة أو على كل '
      'الأصناف.';
  @override
  String get refusalGroupCategoriesMissing =>
      'المجموعة المخصصة لتصنيفات محددة تحتاج إلى تصنيف واحد على الأقل.';
  @override
  String refusalGroupChoicesOutOfRange(int max) =>
      'تسمح المجموعة بعدد اختيارات من 1 إلى $max.';
  @override
  String get refusalGroupNegativeCounts =>
      'لا يمكن أن يقل الحد الأدنى للاختيارات أو عدد الخيارات المجانية عن '
      'صفر.';
  @override
  String get refusalGroupNeedsMoreThanAllows =>
      'لا يمكن أن تطلب المجموعة اختيارات أكثر مما تسمح به.';
  @override
  String refusalGroupTooManyOptions(int max) =>
      'تتسع المجموعة لـ $max خياراً على الأكثر.';
  @override
  String get refusalGroupRequiredButEmpty =>
      'المجموعة المطلوبة تحتاج إلى خيار واحد على الأقل، وإلا فلن يمكن بيع '
      'الصنف الذي هي عليه أبداً.';
  @override
  String get refusalOptionNameMissing => 'كل خيار يحتاج إلى اسم.';
  @override
  String get refusalOptionTwice => 'الخيار نفسه موجود في هذه المجموعة مرتين.';
  @override
  String get refusalOptionNegativePrice =>
      'لا يمكن أن يكون سعر الخيار أقل من صفر.';
  @override
  String get refusalOptionSaleNotBelowPrice =>
      'سعر العرض يجب أن يكون أقل من السعر العادي للحجم.';
  @override
  String get refusalGroupTwice => 'المجموعة نفسها موجودة على هذا الصنف مرتين.';
  @override
  String get refusalGroupTypedOnAnotherItem =>
      'هذه المجموعة أُنشئت على صنف آخر. أضفها إلى المكتبة لاستخدامها على أكثر '
      'من صنف.';
  @override
  String refusalGroupNotInLibrary(String name) =>
      '«$name» أُنشئت على صنف واحد. أضفها إلى المكتبة لاستخدامها على أكثر من '
      'صنف.';
  @override
  String refusalGroupAlreadyReaches(String name) =>
      '«$name» تصل إلى هذا الصنف تلقائياً بالفعل، فلا يمكن إضافتها إليه مرة '
      'أخرى.';
  @override
  String refusalGroupSecondSizes(int count, String names) =>
      'للصنف مجموعة أحجام واحدة، وهذا سيعطيه $count: $names. أبقِ واحدة.';
  @override
  String refusalGroupWouldGiveSecondSizes(String item) =>
      '«$item» لديه أحجام بالفعل. للصنف مجموعة أحجام واحدة، وهذه المجموعة '
      'ستعطيه مجموعة ثانية — أزل الأخرى منه أولاً.';
  @override
  String get refusalGroupBelongsToOneItem =>
      'هذه المجموعة تخص صنفاً واحداً. عدّلها من الصنف نفسه.';
  @override
  String get refusalGroupBelongsToLibrary =>
      'هذه المجموعة في المكتبة. عدّلها هناك، وسيتبعها كل صنف يستخدمها.';
  @override
  String get refusalGroupForeignOption => 'أحد هذه الخيارات يخص مجموعة أخرى.';
  @override
  String get refusalGroupForeignCategory =>
      'أحد هذه التصنيفات ليس في هذا المنيو.';

  @override
  String get refusalItemNameMissing => 'الصنف يحتاج إلى اسم.';
  @override
  String get refusalOfferAbovePrice => 'سعر العرض أعلى من السعر العادي.';
  @override
  String get refusalCategoryNameMissing => 'التصنيف يحتاج إلى اسم.';
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
