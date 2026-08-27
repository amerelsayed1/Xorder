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
  String get enterOpeningFloat;
  String get openShift;
  String get openingFloat;
  String get emptyDrawer;
  String get openingFloatHelp;
  String closeShiftTitle(String reference);
  String closeShiftHelp(String openedBy);
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
  String get renewalOnlineHelp;
  String get renewalOfflineHelp;
  String get licenceUpdated;
  String get noRouteToPlatform;
  String get licenceFileHint;
  String get pasteLicenceFile;
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

  // ── Setup wizard chrome ───────────────────────────────────────────────────
  String get productWordmark;
  String get terminalSetup;
  String stepOf(int step, int total);
  String get openTheTill;

  String get stepLanguage;
  String get stepLanguageBlurb;
  String get stepConnection;
  String get stepConnectionBlurb;
  String get stepAccount;
  String get stepAccountBlurb;
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
  String get modeBranchServer;
  String get modeBranchServerBlurb;
  String get modeStandalone;
  String get modeStandaloneBlurb;
  String get syncAutomatic;
  String get syncAutomaticBlurb;
  String get syncManual;
  String get syncManualBlurb;
  String get serverAddress;
  String get branchServerHelp;
  String get upstream;
  String get upstreamHelp;
  String get trustWithoutCertificate;
  String get trustWithoutCertificateBlurb;
  String get branchDatabase;
  String get branchDatabaseHelp;
  String get databaseName;
  String get databasePort;
  String get databaseUser;
  String get databaseUserHelp;
  String get databasePassword;
  String get databasePasswordHelp;
  String get testConnection;
  String get standaloneHelp;
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

  // ── Setup: licence ────────────────────────────────────────────────────────
  String get licenceKey;
  String get activateOnline;
  String get activateFromFile;
  String get licenceOnlineHelp;
  String get licenceOfflineHelp;
  String get cashUpNeverGated;

  // ── Setup: account ────────────────────────────────────────────────────────
  String get restaurant;
  String get restaurantHelp;
  String get methodPairingCode;
  String get methodPairingCodeBlurb;
  String get methodManual;
  String get methodManualBlurb;
  String claimedAs(String terminal, String branch);
  String get claimedHelp;
  String get setupCode;
  String get setupCodeHelp;
  String get claimThisTerminal;
  String get username;
  String get password;
  String get manualCredentialsWarning;

  // ── Setup: branch, terminal, hardware ─────────────────────────────────────
  String get noOrderTypesConfigured;
  String get branchPaneHelp;
  String get terminalName;
  String get terminalNameProvisionedHelp;
  String get terminalNameManualHelp;
  String get registered;
  String get registerThisTerminal;
  String get registerHelp;
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
  String get fromDeviceConfiguration;
  String get deviceTaxHelp;
  String get downloadMenu;
  String get downloadAgain;
  String itemsCached(int items);
  String get cataloguePaneHelp;
  String catalogueDownloadFailed(Object error);
  String get summaryLanguage;
  String get summaryConnection;
  String get summaryServer;
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
  String get pasteLicenceFile => 'Paste licence file';
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
  String get productWordmark => 'XORDER POS';
  @override
  String get terminalSetup => 'TERMINAL SETUP';
  @override
  String stepOf(int step, int total) => 'Step $step of $total';
  @override
  String get openTheTill => 'Open the till';

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
  String get modeCloudBlurb => 'Terminals connect to the XOrder platform.';
  @override
  String get modeBranchServer => 'Branch server';
  @override
  String get modeBranchServerBlurb =>
      'A server in this branch is the source of truth.';
  @override
  String get modeStandalone => 'Islanded';
  @override
  String get modeStandaloneBlurb =>
      'This terminal only, checking in periodically.';
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
  String get serverAddress => 'Server address';
  @override
  String get branchServerHelp =>
      'The box in this branch running XOrder. Every till on this network sends '
      'its sales here.';
  @override
  String get upstream => 'Upstream';
  @override
  String get upstreamHelp =>
      'Where the branch server forwards to when the internet is up. Required: a '
      'branch that forwards nowhere is a restaurant the platform cannot see, '
      'and every till has to be visible to Super Admin.';
  @override
  String get trustWithoutCertificate =>
      'Trust this server without a certificate';
  @override
  String get trustWithoutCertificateBlurb =>
      'Only for a box on this local network. Never for a public address.';
  @override
  String get branchDatabase => 'Branch database';
  @override
  String get branchDatabaseHelp =>
      'This till writes its sales straight into the branch server’s PostgreSQL, '
      'so it needs an account there.';
  @override
  String get databaseName => 'Database';
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
  String get testConnection => 'Test connection';
  @override
  String get standaloneHelp =>
      'No server to configure — this till keeps everything on this machine. It '
      'still checks in with the platform from time to time, and its licence '
      'sets how long it may go without doing so. Back it up: there is no second '
      'copy.';
  @override
  String get sendingSales => 'Sending sales';
  @override
  String get sendingSalesHelp =>
      'Every till sells offline either way — this only decides when the queue '
      'drains. The terminal reports in to the dashboard on its own schedule '
      'regardless.';

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
  String get licenceKey => 'Licence key';
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
      'Registering is what puts this till on the dashboard. If it fails you can '
      'still finish setup — the terminal registers at first sync instead.';
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
  String get cataloguePaneHelp =>
      'The menu is cached so the till can sell before it has ever been online '
      'again. It refreshes in the background while trading.';
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
  String get pasteLicenceFile => 'الصق ملف الترخيص';
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
  String get productWordmark => 'XORDER POS';
  @override
  String get terminalSetup => 'إعداد الجهاز';
  @override
  String stepOf(int step, int total) => 'خطوة $step من $total';
  @override
  String get openTheTill => 'افتح الكاشير';

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
  String get modeCloudBlurb => 'الأجهزة تتصل بمنصّة XOrder.';
  @override
  String get modeBranchServer => 'خادم في الفرع';
  @override
  String get modeBranchServerBlurb => 'خادم داخل هذا الفرع هو المرجع.';
  @override
  String get modeStandalone => 'منفصل';
  @override
  String get modeStandaloneBlurb => 'هذا الجهاز وحده، مع تسجيل دوري.';
  @override
  String get syncAutomatic => 'تلقائي';
  @override
  String get syncAutomaticBlurb => 'أرسل المبيعات فور توفر الاتصال.';
  @override
  String get syncManual => 'يدوي';
  @override
  String get syncManualBlurb => 'أرسل المبيعات عندما يختار الموظفون.';
  @override
  String get serverAddress => 'عنوان الخادم';
  @override
  String get branchServerHelp =>
      'الجهاز الذي يشغّل XOrder في هذا الفرع. كل كاشير على هذه الشبكة يرسل '
      'مبيعاته إليه.';
  @override
  String get upstream => 'الخادم الأعلى';
  @override
  String get upstreamHelp =>
      'الوجهة التي يحوّل إليها خادم الفرع عند توفر الإنترنت. مطلوب: فرع لا '
      'يحوّل إلى أي جهة هو مطعم لا تراه المنصّة، وكل جهاز يجب أن يكون ظاهراً '
      'لإدارة النظام.';
  @override
  String get trustWithoutCertificate => 'الوثوق بهذا الخادم بدون شهادة';
  @override
  String get trustWithoutCertificateBlurb =>
      'فقط لجهاز على هذه الشبكة المحلية. لا تفعل ذلك أبداً لعنوان عام.';
  @override
  String get branchDatabase => 'قاعدة بيانات الفرع';
  @override
  String get branchDatabaseHelp =>
      'هذا الكاشير يكتب مبيعاته مباشرة في PostgreSQL على خادم الفرع، فهو يحتاج '
      'حساباً هناك.';
  @override
  String get databaseName => 'قاعدة البيانات';
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
  String get testConnection => 'اختبار الاتصال';
  @override
  String get standaloneHelp =>
      'لا يوجد خادم لإعداده — هذا الكاشير يحتفظ بكل شيء على هذا الجهاز. ومع ذلك '
      'يسجّل حضوره لدى المنصّة من حين لآخر، وترخيصه يحدد المدة المسموح بها بدون '
      'ذلك. خُذ نسخة احتياطية: لا توجد نسخة ثانية.';
  @override
  String get sendingSales => 'إرسال المبيعات';
  @override
  String get sendingSalesHelp =>
      'كل كاشير يبيع بدون إنترنت في الحالتين — هذا يحدد فقط متى تُفرَّغ قائمة '
      'الانتظار. الجهاز يبلّغ لوحة التحكم بحالته وفق جدوله الخاص على أي حال.';

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
  String get licenceKey => 'مفتاح الترخيص';
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
      'التسجيل هو ما يُظهر هذا الكاشير في لوحة التحكم. إذا فشل يمكنك إكمال '
      'الإعداد — سيسجّل الجهاز نفسه عند أول مزامنة.';
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
  String get cataloguePaneHelp =>
      'يُحفظ المنيو حتى يستطيع الكاشير البيع قبل أن يتصل بالإنترنت مرة أخرى. '
      'ويُحدَّث في الخلفية أثناء العمل.';
  @override
  String catalogueDownloadFailed(Object error) => 'فشل تحميل المنيو: $error';
  @override
  String get summaryLanguage => 'اللغة';
  @override
  String get summaryConnection => 'الاتصال';
  @override
  String get summaryServer => 'الخادم';
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
