import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../data/cloud/cloud_provisioning_repository.dart'
    show posAppVersion;
import '../../../domain/models/permissions.dart';
import '../../../domain/models/shift.dart';
import '../../../domain/services/eta_filing.dart' show etaFilingEnabled;
import '../application/admin_session.dart';
import 'admin_activity_watch.dart';
import 'admin_pane_bits.dart';
import 'admin_sign_in.dart';
import 'management_activity_pane.dart';
import 'management_backup_pane.dart';
import 'management_items_pane.dart';
import 'management_stock_pane.dart';
import 'management_units_pane.dart';
import 'management_floor_pane.dart';
import 'management_menu_pane.dart';
import 'management_eta_pane.dart';
import 'management_extras_pane.dart';
import 'management_charges_pane.dart';
import 'management_order_types_pane.dart';
import 'management_taxes_pane.dart';
import 'management_tenders_pane.dart';
import 'management_purchasing_pane.dart';
import 'management_receipt_pane.dart';
import 'management_roles_pane.dart';
import 'management_staff_pane.dart';
import 'management_terminal_pane.dart';

/// The back office, inside the till.
///
/// **Reached by PIN, not by being on the right screen.** Everything else in the
/// app assumes whoever is standing there may do it — a till is a shared machine
/// and asking a cashier to sign in before every sale is how a queue forms. This
/// section is the exception: it changes what the restaurant sells, who works
/// there and what they may do, so it asks who is asking and checks before it
/// opens.
///
/// The check is repeated at every write. This gate is a door, not a guarantee:
/// the person who signs in here could hand the machine to somebody else, and
/// the repositories are what make that not matter.
class ManagementScreen extends ConsumerStatefulWidget {
  const ManagementScreen({
    required this.onClose,
    required this.onReconfigure,
    this.initialPane,
    this.purchasingTab,
    this.create = false,
    this.request,
    super.key,
  });

  final VoidCallback onClose;

  /// Off to the setup wizard, after the Terminal pane has cleared this till's
  /// configuration. Required rather than defaulted: a back office that wiped
  /// the setup and then stayed open would be standing on a till with no
  /// database. See [ManagementTerminalPane].
  final VoidCallback onReconfigure;

  /// Which pane to land on.
  ///
  /// Exists so a menu item can say what it opens. "Management" is a place;
  /// "Staff & accounts" is an answer to the question somebody actually has, and
  /// they should not have to learn that accounts live behind the first word to
  /// find them.
  ///
  /// Null is the door's own landing: the first tab that holds a pane (see
  /// [backOfficeLanding]). Staff used to be the default, which was right while
  /// the back office was a list with Staff at the top; with tabs, landing three
  /// tabs in from the start would be the one screen that opens in the middle.
  final ManagementPane? initialPane;

  /// Passed through to Purchasing — see [ManagementDestination].
  final PurchasingTab? purchasingTab;
  final bool create;
  final Object? request;

  @override
  ConsumerState<ManagementScreen> createState() => _ManagementScreenState();
}

/// Which panes this terminal and this person actually have.
///
/// **Public, and the only answer.** The tab strip asks this, and so do the
/// window's bar and — once BO-4 lands — Home's quick actions. Two lists that
/// were meant to agree are two lists that will not: a menu offering Purchasing
/// to somebody the strip hides it from would take them to a screen that
/// refuses everything.
///
/// [ManagementPane.receipt] is deliberately outside the authoring set: every
/// terminal prints a slip with the restaurant's name and address on it, cloud
/// and offline alike, and only the write side needs Management's credential.
List<ManagementPane> managementPanesFor({
  required PosStaff admin,
  required bool authorsItsOwnCatalogue,
}) => [
  for (final pane in ManagementPane.values)
    if ((!_authoringPanes.contains(pane) || authorsItsOwnCatalogue) &&
        (pane != ManagementPane.eta || etaFilingEnabled) &&
        _permits(admin, pane))
      pane,
];

/// Menu authoring exists only where this terminal is the author of its own
/// catalogue — offline. On a cloud till the platform authors it and the
/// bootstrap seeder overwrites whatever is here, so the pane would be an
/// invitation to lose work.
///
/// **Money is not here.** Its tax rates are the platform's on a cloud till, but
/// the payment methods and service charges Wave D put in the same pane are local
/// on both deployments — so the pane gates its own top half rather than
/// disappearing, and a cloud restaurant can still say how it takes money.
///
/// **Buying and inventory are here, whatever the person holds** (CB-09, owner
/// decision 2026-09-12, POS-BE-030). On cloud the platform is the only author
/// of suppliers, purchase orders, receiving, supplier invoices and payments,
/// units and stock items, and none of it comes down to the till — so a
/// Purchasing pane here would write rows nobody on the platform ever sees, a
/// second author of the same business. Hidden by deployment rather than left
/// to `_paneRequires`: the platform withholds `purchase.manage` from every
/// bundle, but roles are the till's own even on cloud (doc 16 §1), so a local
/// Owner or Manager role still grants it, and a capability gate alone would
/// leak exactly the panes this is meant to close.
///
/// **What a cloud till already holds is left where it is.** Purchasing rows
/// typed into one before this — orders, suppliers, units, stock — are not
/// imported (one author means no merge path) and not deleted (they would be
/// the only copy). They simply stop being reachable from here, and stay in the
/// till's backups. The seeder touches none of the supplier, order, invoice,
/// payment, unit or movement tables, so hiding the panes is the whole change —
/// bought-only items aside, which are product rows and were already the
/// seeder's to rewrite before any of this (the note below).
// Stock items too: a bought-only item is a product row, and on a cloud till
// the bootstrap seeder deletes every product and rewrites the platform's.
const _authoringPanes = {
  ManagementPane.menu,
  // The library is the menu's too: a group made here would be erased by the
  // next sync on a cloud till, where the platform's Extras page is the author.
  ManagementPane.extras,
  ManagementPane.floor,
  ManagementPane.purchasing,
  ManagementPane.items,
  ManagementPane.stock,
  ManagementPane.units,
};

/// What to tell somebody who asked for a pane this terminal does not author.
///
/// **A deep link is a promise somebody else made.** A bar entry, a habit from
/// an offline till, a destination held across a sync that changed nothing on
/// screen — any of them can name Purchasing on a cloud till. Landing silently
/// somewhere else would read as the pane having broken; landing on Purchasing
/// itself is not possible, because it is not this terminal's to show. So the
/// screen shows the tab and says where the thing they wanted lives.
///
/// Over the tab rather than the pane, so a buying or inventory pane added
/// later is covered without being remembered here. Menu answers null on
/// purpose: nothing links to it on a cloud till, and each of its panes already
/// says it comes from the platform inside itself.
String? platformAuthoredPointer(AppStrings s, ManagementPane pane) =>
    _pointsToPlatform(tabOf(pane)) ? s.purchasingComesFromPlatform : null;

/// The tabs a cloud till keeps as a word and a sentence, rather than dropping.
///
/// **Inventory and Purchasing stay on a cloud till**, each saying where it
/// went. Dropping them would leave a manager who bought through this back
/// office last month searching every tab for it — and a cloud till with no
/// word for buying tells them nothing about where it went. Menu is not kept:
/// its absence on cloud is as old as the cloud till, and the platform's menu
/// is the first thing its owner learns.
bool _pointsToPlatform(BackOfficeTab tab) => switch (tab) {
  BackOfficeTab.inventory || BackOfficeTab.purchasing => true,
  BackOfficeTab.home ||
  BackOfficeTab.sales ||
  BackOfficeTab.reports ||
  BackOfficeTab.menu ||
  BackOfficeTab.finance ||
  BackOfficeTab.system ||
  BackOfficeTab.settings => false,
};

/// Whether [pane] is absent because this terminal does not author it — as
/// opposed to because this person may not open it, which is a different
/// sentence and one the screen already answers by falling back.
bool hiddenBecausePlatformAuthors(
  ManagementPane pane, {
  required bool authorsItsOwnCatalogue,
}) => !authorsItsOwnCatalogue && _authoringPanes.contains(pane);

/// The back office, in tabs — the mockup's nine (plan 19 §1.1), with People
/// under Settings as it is on the cloud.
///
/// **Home, Sales, Reports and Finance hold no pane yet**, so no fixture ever
/// sees them: a tab with no visible pane is absent, and these four have none
/// until their slices land (Home BO-4, Sales BO-2, Reports BO-6, Finance BO-9).
/// They are members now rather than added then so that the order is decided
/// once, here, and so that [backOfficeTabName] and the strip's width test
/// already carry all nine — a tenth word arriving with a slice is how a strip
/// that fitted at 1100 px stops fitting without anybody measuring it.
///
/// Replaces the seven areas of the flat bar. Money went to Settings (rules
/// about money are configuration; *Finance* is money that moved), Compliance
/// dissolved into Settings › General and System, and People became Settings ›
/// Users and › Roles.
enum BackOfficeTab {
  /// The landing page, once BO-4 builds it.
  home,

  /// The order history, re-hosted by BO-2.
  sales,

  /// BO-5's read model drawn by BO-6.
  reports,

  /// What the restaurant sells.
  menu,

  /// What it keeps, and what it is counted in.
  inventory,

  /// What it buys, and who it owes.
  purchasing,

  /// Money that moved, read-only (BO-9, BO-10).
  finance,

  /// How this till behaves, what it keeps, and what happened on it.
  system,

  /// The restaurant's configuration, and the people who work there.
  settings,
}

/// Which tab a pane belongs to.
///
/// A total function over the enum, so a pane added without a tab fails to
/// compile rather than quietly vanishing from the strip.
BackOfficeTab tabOf(ManagementPane pane) => switch (pane) {
  ManagementPane.menu ||
  ManagementPane.extras ||
  ManagementPane.floor => BackOfficeTab.menu,
  ManagementPane.items ||
  ManagementPane.stock ||
  ManagementPane.units => BackOfficeTab.inventory,
  ManagementPane.purchasing => BackOfficeTab.purchasing,
  // Terminal beside Backup and the log rather than in Settings: it wipes the
  // machine, and Settings is where somebody goes to change a tax rate.
  // ETA here too, still hidden while `etaFilingEnabled` is false.
  ManagementPane.activity ||
  ManagementPane.backup ||
  ManagementPane.terminal ||
  ManagementPane.eta => BackOfficeTab.system,
  ManagementPane.receipt ||
  ManagementPane.staff ||
  ManagementPane.roles ||
  ManagementPane.taxes ||
  ManagementPane.charges ||
  ManagementPane.tenders ||
  ManagementPane.orderTypes => BackOfficeTab.settings,
};

String backOfficeTabName(AppStrings s, BackOfficeTab tab) => switch (tab) {
  BackOfficeTab.home => s.tabHome,
  BackOfficeTab.sales => s.tabSales,
  BackOfficeTab.reports => s.tabReports,
  BackOfficeTab.menu => s.tabMenu,
  BackOfficeTab.inventory => s.tabInventory,
  BackOfficeTab.purchasing => s.tabPurchasing,
  BackOfficeTab.finance => s.tabFinance,
  BackOfficeTab.system => s.tabSystem,
  BackOfficeTab.settings => s.tabSettings,
};

IconData backOfficeTabIcon(BackOfficeTab tab) => switch (tab) {
  BackOfficeTab.home => Icons.home_outlined,
  BackOfficeTab.sales => Icons.receipt_long_outlined,
  BackOfficeTab.reports => Icons.bar_chart_outlined,
  BackOfficeTab.menu => Icons.restaurant_menu_outlined,
  BackOfficeTab.inventory => Icons.inventory_2_outlined,
  BackOfficeTab.purchasing => Icons.shopping_cart_outlined,
  BackOfficeTab.finance => Icons.account_balance_wallet_outlined,
  BackOfficeTab.system => Icons.dns_outlined,
  BackOfficeTab.settings => Icons.settings_outlined,
};

/// The groups of Settings' side nav, as the cloud groups its own settings
/// (`settings.config.js`: *account*, *pos*).
///
/// The plan's third group, *This terminal* — language and appearance — is not
/// here: it has no pane until BO-8 builds one, and a heading over nothing
/// reads as a section that failed to load. Language and theme stay in the
/// bar's Settings menu meanwhile, where they already are.
enum SettingsSection { account, pointOfSale }

String settingsSectionName(AppStrings s, SettingsSection section) =>
    switch (section) {
      SettingsSection.account => s.settingsSectionAccount,
      SettingsSection.pointOfSale => s.settingsSectionPointOfSale,
    };

/// Where a Settings pane sits in the side nav: its group, and its place in it.
///
/// Total over the panes, so a pane given the Settings tab without a place here
/// is caught by `back_office_shell_test.dart` rather than rendering nowhere —
/// and a pane taken OUT of Settings has to be taken out here too, or the same
/// test says so. Null for every pane in another tab.
(SettingsSection, int)? settingsPlaceOf(ManagementPane pane) => switch (pane) {
  // General first: it is the company — the name on every slip.
  ManagementPane.receipt => (SettingsSection.account, 0),
  ManagementPane.staff => (SettingsSection.account, 1),
  ManagementPane.roles => (SettingsSection.account, 2),
  ManagementPane.taxes => (SettingsSection.pointOfSale, 0),
  ManagementPane.charges => (SettingsSection.pointOfSale, 1),
  ManagementPane.tenders => (SettingsSection.pointOfSale, 2),
  ManagementPane.orderTypes => (SettingsSection.pointOfSale, 3),
  ManagementPane.menu ||
  ManagementPane.extras ||
  ManagementPane.floor ||
  ManagementPane.purchasing ||
  ManagementPane.eta ||
  ManagementPane.activity ||
  ManagementPane.backup ||
  ManagementPane.items ||
  ManagementPane.stock ||
  ManagementPane.units ||
  ManagementPane.terminal => null,
};

/// Order within a tab: Settings by its side nav, every other tab by the enum.
///
/// Only ever compared between panes of the same tab, so the two scales never
/// meet — a Settings place is never weighed against an enum index.
int _rankInTab(ManagementPane pane) => switch (settingsPlaceOf(pane)) {
  (final section, final place)? =>
    section.index * ManagementPane.values.length + place,
  null => pane.index,
};

/// The visible tabs, each with its visible panes in the order it shows them.
///
/// **A tab with no visible pane is absent**, as an empty area was before it:
/// a word over a gap reads as a tab that failed to load. The one exception is
/// a tab [_pointsToPlatform] keeps on a cloud till, which comes back with no
/// panes at all and shows the sentence saying where they went.
///
/// Built from [managementPanesFor] and nothing else, so what a tab can reach
/// is exactly what that function allows — `back_office_shell_test.dart` holds
/// the two equal for every fixture on both deployments.
List<(BackOfficeTab, List<ManagementPane>)> backOfficeTabsFor({
  required PosStaff admin,
  required bool authorsItsOwnCatalogue,
}) {
  final panes = managementPanesFor(
    admin: admin,
    authorsItsOwnCatalogue: authorsItsOwnCatalogue,
  );
  return [
    for (final tab in BackOfficeTab.values)
      if ([for (final p in panes) if (tabOf(p) == tab) p]
            ..sort((a, b) => _rankInTab(a) - _rankInTab(b))
          case final own
          when own.isNotEmpty ||
              (!authorsItsOwnCatalogue && _pointsToPlatform(tab)))
        (tab, own),
  ];
}

/// Where the door lands: the first pane of the first tab that holds one.
///
/// Home is where it lands once BO-4 exists; until then this is the first
/// visible tab. **A tab that only points at the platform is passed over** — on
/// a cloud till that is Inventory, and greeting the owner on every entry with
/// "this is not here" would make the sentence a welcome rather than an answer.
///
/// Never empty: Staff has no gate beyond the door, so everybody past it holds
/// at least that pane.
ManagementPane backOfficeLanding(
  List<(BackOfficeTab, List<ManagementPane>)> tabs,
) => tabs.expand((tab) => tab.$2).first;

/// Where the caller was, and which pane they asked for.
///
/// **Both, because the way out matters as much as the way in.** The route used
/// to send every close to the start screen, which was right while the only door
/// was on the start screen. A manager who opens Purchasing from the till and
/// closes it should be back at the till with their ticket still on it, not
/// standing on a start screen wondering where the shift went.
class ManagementDestination {
  const ManagementDestination({
    this.pane,
    this.returnTo,
    this.purchasingTab,
    this.create = false,
    this.request,
  });

  /// Null for the door's own landing — see [ManagementScreen.initialPane].
  final ManagementPane? pane;

  /// The route to go back to. Null means the start screen, which is what the
  /// only previous caller wanted.
  final String? returnTo;

  /// For [ManagementPane.purchasing]: which half of buying to open on.
  final PurchasingTab? purchasingTab;

  /// Start a new one straight away, rather than showing the list it joins.
  final bool create;

  /// A fresh `Object()` per menu tap. Without it the same request twice is the
  /// same value twice, and a screen already showing it has nothing to notice.
  final Object? request;
}

/// The lines a pane adds to the window's bar, in place of its tab's own line.
///
/// Only Purchasing has any. It is really four things — orders, the invoices
/// that arrive against them, the payments that settle those, and the
/// suppliers behind all three — and "where do I enter this invoice" is
/// answered by an invoice, not by a tab that holds a list of them. So it lists
/// each, with the "new" that starts one beside the list it belongs to. The
/// strip and the pane's own tabs can take somebody to the list; only the bar
/// takes them straight to an empty invoice.
///
/// A FACTORY per entry rather than a destination: each tap has to be a fresh
/// request, or asking for "New order" twice would be answered once. The bool
/// marks the first entry of a group, where the bar draws a divider.
List<(String, ManagementDestination Function(), bool)> managementMenuEntries(
  AppStrings s,
  ManagementPane pane,
) => switch (pane) {
  ManagementPane.purchasing => [
    (s.purchaseOrders, () => _purchasing(PurchasingTab.orders), true),
    (
      s.purchaseOrderNew,
      () => _purchasing(PurchasingTab.orders, create: true),
      false,
    ),
    (s.supplierInvoices, () => _purchasing(PurchasingTab.invoices), true),
    (
      s.invoiceNew,
      () => _purchasing(PurchasingTab.invoices, create: true),
      false,
    ),
    (s.paymentsList, () => _purchasing(PurchasingTab.payments), false),
    (s.suppliers, () => _purchasing(PurchasingTab.suppliers), true),
    (
      s.supplierNew,
      () => _purchasing(PurchasingTab.suppliers, create: true),
      false,
    ),
  ],
  _ => const [],
};

/// One line of the Back office menu in the window's bar.
///
/// [pane] is what the line opens, null for a line that is not a pane — the
/// pointer a cloud till shows in place of Inventory and Purchasing. [divider]
/// is drawn above this line.
typedef ManagementBarEntry = ({
  BackOfficeTab tab,
  ManagementPane? pane,
  String label,
  ManagementDestination Function() open,
  bool divider,
});

/// The back office as the window's bar offers it: one menu, one line per tab.
///
/// **One menu now, not one per area (BO-1).** The tabs are back on screen, and
/// seven words in the bar above a strip of the same tabs would be the same
/// navigation twice — the exact reason the tabs were once taken away. What the
/// bar still does that the strip cannot is the shortcut: Purchasing keeps its
/// "new order / new invoice / new supplier" lines.
///
/// **Here rather than in the bar, so the two cannot drift.** The rule and its
/// test sit beside each other in this file, and `app.dart` only draws.
///
/// **On a cloud till Inventory and Purchasing share one line**, the pointer
/// that names both ("Purchasing & stock — on xorder.io…"). It opens the
/// Purchasing tab, which says the same thing at length. Two lines leading to
/// one sentence would be a menu padded with the same answer.
List<ManagementBarEntry> managementBarFor(
  AppStrings s, {
  required PosStaff admin,
  required bool authorsItsOwnCatalogue,
}) {
  final lines = <ManagementBarEntry>[];
  var pointed = false;
  var previousWasGroup = false;
  for (final (tab, panes) in backOfficeTabsFor(
    admin: admin,
    authorsItsOwnCatalogue: authorsItsOwnCatalogue,
  )) {
    final block = <ManagementBarEntry>[
      if (panes.isEmpty && !pointed)
        (
          tab: BackOfficeTab.purchasing,
          pane: null,
          label: s.purchasingOnPlatformEntry,
          open: () => ManagementDestination(
            pane: ManagementPane.purchasing,
            request: Object(),
          ),
          divider: false,
        )
      else
        for (final pane in panes)
          for (final (i, (label, open, groups))
              in managementMenuEntries(s, pane).indexed)
            (
              tab: tab,
              pane: pane,
              label: label,
              open: open,
              divider: groups && i > 0,
            ),
    ];
    if (panes.isEmpty) {
      if (pointed) continue;
      pointed = true;
    }
    if (block.isEmpty) {
      block.add((
        tab: tab,
        pane: panes.first,
        label: backOfficeTabName(s, tab),
        open: () => ManagementDestination(pane: panes.first, request: Object()),
        divider: false,
      ));
    }
    // A run of Purchasing's lines is set off from its single-line neighbours
    // on both sides; single lines sit together, as the strip's words do.
    final group = block.length > 1;
    if (lines.isNotEmpty && (group || previousWasGroup)) {
      final first = block.first;
      block[0] = (
        tab: first.tab,
        pane: first.pane,
        label: first.label,
        open: first.open,
        divider: true,
      );
    }
    previousWasGroup = group;
    lines.addAll(block);
  }
  return lines;
}

ManagementDestination _purchasing(PurchasingTab tab, {bool create = false}) =>
    ManagementDestination(
      pane: ManagementPane.purchasing,
      purchasingTab: tab,
      create: create,
      request: Object(),
    );

/// What a pane is called, and what it is for.
///
/// A function of the language rather than a const map: this is the one place
/// that names every pane, so it is the one place a pane added without an Arabic
/// label has to fail to compile.
///
/// Staff and Receipt answer with their Settings names, Users and General, so
/// the side nav, the header and the bar say one word for one place. The plan
/// names them that way (§1.1, §2.6) and the cloud does too; the panes' own
/// headings inside still say what they list.
(String, String) managementPaneLabel(AppStrings s, ManagementPane pane) =>
    switch (pane) {
      ManagementPane.staff => (s.settingsUsers, s.paneStaffBlurb),
      ManagementPane.menu => (s.paneMenu, s.paneMenuBlurb),
      ManagementPane.extras => (s.extrasTitle, s.extrasSubtitle),
      ManagementPane.floor => (s.floorPlan, s.floorPlanHint),
      ManagementPane.taxes => (s.paneTaxes, s.paneTaxesHint),
      ManagementPane.charges => (s.serviceCharges, s.serviceChargesHint),
      ManagementPane.tenders => (s.tenderTypes, s.tenderTypesHint),
      ManagementPane.orderTypes => (s.orderTypes, s.orderTypesHint),
      ManagementPane.purchasing => (s.panePurchasing, s.panePurchasingBlurb),
      ManagementPane.receipt => (s.settingsGeneral, s.paneReceiptBlurb),
      ManagementPane.eta => (s.paneEta, s.paneEtaBlurb),
      ManagementPane.roles => (s.paneRoles, s.paneRolesBlurb),
      ManagementPane.activity => (s.paneActivity, s.paneActivityBlurb),
      ManagementPane.backup => (s.paneBackup, s.paneBackupBlurb),
      ManagementPane.items => (s.paneItems, s.paneItemsBlurb),
      ManagementPane.stock => (s.paneStock, s.paneStockBlurb),
      ManagementPane.units => (s.paneUnits, s.paneUnitsBlurb),
      ManagementPane.terminal => (s.paneTerminal, s.paneTerminalBlurb),
    };

/// The capability a pane needs beyond the `staffManage` that opened the screen.
///
/// **Only the panes whose repositories actually enforce one appear here.**
/// Hiding a pane on a capability nothing checks would be a claim the database
/// does not back — the strip would say no while a direct write said yes. So
/// Purchasing is gated (its three repositories all demand `purchase.manage`)
/// and the others are not, until each one's writes are gated too.
String? _paneRequires(ManagementPane pane) => switch (pane) {
  ManagementPane.purchasing => PosCapability.purchaseManage,
  // The third capability that had no screen, and the one with the worst
  // consequences: `backup.manage` is critical-risk, held only by Owner, and
  // deliberately outside supervisor override. `reports.view` still has none.
  //
  // Unlike Purchasing, this pane's gate is not backed by a repository that
  // refuses — `pos_backups` is granted INSERT to the till so the automatic copy
  // at day close can be recorded without anybody being in the back office. What
  // the gate protects is the two buttons: taking one on demand, and restoring.
  // Both go through `BackupService`, which is only ever reached from here.
  ManagementPane.backup => PosCapability.backupManage,
  // Wiping this till's setup. Like Backup, nothing in the database refuses it
  // — the configuration is a file on this machine — so what the gate protects
  // is the one button, and the pane is the only place it is reached from.
  ManagementPane.terminal => PosCapability.terminalManage,
  // Units exist for buying and counting stock: the buyer's.
  ManagementPane.items ||
  ManagementPane.stock ||
  ManagementPane.units => PosCapability.purchaseManage,
  _ => null,
};

bool _permits(PosStaff admin, ManagementPane pane) {
  final needed = _paneRequires(pane);
  // `can` and not `capabilities`: the latter is the direct-grant set alone,
  // and an owner holds almost everything through their role.
  return needed == null || admin.can(needed);
}

enum ManagementPane {
  staff,
  menu,
  extras,
  floor,
  taxes,
  charges,
  tenders,
  orderTypes,
  purchasing,
  receipt,
  eta,
  roles,
  activity,
  backup,
  items,
  stock,
  units,
  terminal,
}

class _ManagementScreenState extends ConsumerState<ManagementScreen> {
  /// The pane ASKED for — by the caller, the strip, the sub-nav or a notice.
  /// Null until something asks, which is the door's own landing. What is
  /// actually shown is worked out from this at every build, because a request
  /// can outlive the permission or the deployment that justified it.
  late ManagementPane? _pane = widget.initialPane;

  /// Where Esc is heard. Held rather than anonymous so a text field that took
  /// the first Esc can hand focus back here, and the second one still arrives.
  final _escapeFocus = FocusNode(debugLabel: 'management-escape');

  late final AdminSessionController _admin;

  /// Set when the inactivity timer ended the session, so the door can say why
  /// it is showing again.
  int? _lockedAfter;

  @override
  void initState() {
    super.initState();
    _admin = ref.read(adminSessionProvider.notifier);
  }

  /// Leaving Admin Mode by any route — the till locked, another screen chosen
  /// from the bar — ends it, exactly as Exit does. A session that outlived its
  /// screen is how a locked till came to open the staff pane.
  ///
  /// After this frame rather than now: the tree is being torn down, and a
  /// provider changed in the middle of that is one its other listeners hear
  /// about mid-teardown.
  @override
  void dispose() {
    final admin = _admin;
    Future.microtask(() => admin.end(AdminSessionEnd.left));
    _escapeFocus.dispose();
    super.dispose();
  }

  void _exit() {
    _admin.end(AdminSessionEnd.exited);
    widget.onClose();
  }

  void _lock() {
    setState(
      () => _lockedAfter = ref.read(adminModeSettingsProvider).timeoutMinutes,
    );
    _admin.end(AdminSessionEnd.timedOut);
  }

  /// Esc is "Back to the till", with one step in front of it.
  ///
  /// The panes keep no draft: leaving throws away whatever is half typed, and
  /// the button already does exactly that. But a button is aimed at and Esc is
  /// a reflex — a manager backing out of a dropdown or a mistyped name reaches
  /// for it mid-form. So inside a field the first Esc only leaves the field,
  /// and the second leaves the back office.
  ///
  /// Not at the door: a username and a PIN are nothing to lose, and
  /// somebody who opened the wrong screen wants out in one key.
  void _escape({required bool signingIn}) {
    final typing =
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorStateOfType<EditableTextState>() !=
        null;
    if (typing && !signingIn) {
      _escapeFocus.requestFocus();
      return;
    }
    widget.onClose();
  }

  /// Follow the caller when it names a DIFFERENT pane.
  ///
  /// Without this, asking for a pane while already inside the back office did
  /// nothing at all: `go('/management', extra: pane)` rebuilds this widget with
  /// a new `initialPane`, and a `late` field initialised once kept showing
  /// whatever was already open. From the start screen it worked, because that
  /// built a fresh screen — which is why the menu bar appeared to work until
  /// somebody used it twice.
  ///
  /// Guarded on the OLD value rather than on `_pane`, so a manager who picked a
  /// pane from the strip and is then rebuilt for any other reason stays where
  /// they put themselves. Only a caller changing its mind moves them.
  @override
  void didUpdateWidget(ManagementScreen old) {
    super.didUpdateWidget(old);
    // A new REQUEST counts even for the same pane: "Invoices" from the bar
    // while already on Purchasing names the pane it is already showing, and
    // still has to be followed.
    if (widget.initialPane != old.initialPane ||
        !identical(widget.request, old.request)) {
      setState(() => _pane = widget.initialPane);
    }
  }

  /// A tab from the strip: its first pane, or — for a tab that only points at
  /// the platform — any pane of it, which the build answers with the pointer.
  void _openTab(BackOfficeTab tab, List<ManagementPane> panes) => setState(
    () => _pane = panes.isNotEmpty
        ? panes.first
        : ManagementPane.values.firstWhere((p) => tabOf(p) == tab),
  );

  void _open(ManagementPane pane) => setState(() => _pane = pane);

  @override
  Widget build(BuildContext context) {
    final body = _body(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            _escape(signingIn: body is AdminSignInView),
      },
      child: Focus(focusNode: _escapeFocus, autofocus: true, child: body),
    );
  }

  Widget _body(BuildContext context) {
    // Whoever signed in to ADMIN MODE — not whoever is signed in at the till.
    // Entering used to replace the till's operator with the manager who came
    // through the door, and leaving never gave the till back.
    final admin = ref.watch(adminSessionProvider)?.staff;

    // Nothing of the back office renders before somebody is in: not a pane,
    // not a count, not a tab. The shortcut that led here is a hidden way in,
    // not a lock; this is the lock.
    if (admin == null) {
      return AdminSignInView(
        onClose: widget.onClose,
        lockedAfterMinutes: _lockedAfter,
      );
    }

    final strings = context.strings;
    final authors = ref.watch(catalogAdminRepositoryProvider) != null;
    final tabs = backOfficeTabsFor(
      admin: admin,
      authorsItsOwnCatalogue: authors,
    );
    final panes = [for (final (_, own) in tabs) ...own];
    final asked = _pane;

    // A pane this terminal or this person does not have is not a pane the body
    // may render: `initialPane` is a deep link and a deep link can outlive the
    // permission that justified it. Asked for a tab that only points at the
    // platform, the tab is shown with nothing in it but the pointer; asked for
    // anything else absent, the door's landing.
    final pointerTab = asked != null &&
        tabs.any((t) => t.$1 == tabOf(asked) && t.$2.isEmpty);
    final ManagementPane? showing = asked != null && panes.contains(asked)
        ? asked
        : pointerTab
        ? null
        : backOfficeLanding(tabs);
    final tab = showing != null ? tabOf(showing) : tabOf(asked!);
    final tabPanes = tabs.firstWhere((t) => t.$1 == tab).$2;

    // …and when it is absent because the platform authors it, the screen says
    // so. Keyed on `_pane`, the pane ASKED for, so it goes the moment anything
    // else is asked for (see `didUpdateWidget`).
    final pointer =
        asked != null &&
            !panes.contains(asked) &&
            hiddenBecausePlatformAuthors(
              asked,
              authorsItsOwnCatalogue: authors,
            )
        ? platformAuthoredPointer(strings, asked)
        : null;

    // Backups are the back office's business, said here rather than on the
    // screen a cashier opens the till from: only somebody who can open the
    // Backup pane can do anything about it, so only they are told. Not on the
    // Backup pane itself, which already says how old the last copy is.
    final backupNotice =
        panes.contains(ManagementPane.backup) &&
            showing != ManagementPane.backup &&
            ref.watch(backupsApplyProvider)
        ? backupWarning(
            strings,
            ref.watch(backupsProvider).valueOrNull,
            DateTime.now(),
          )
        : null;

    final content = showing == null
        ? const SizedBox.expand()
        : KeyedSubtree(
            key: ValueKey('back-office-pane-${showing.name}'),
            child: _paneBody(admin, showing),
          );

    final screen = Scaffold(
      backgroundColor: context.pos.page,
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              title: strings.adminTitle(
                showing != null
                    ? managementPaneLabel(strings, showing).$1
                    : backOfficeTabName(strings, tab),
              ),
              onClose: _exit,
            ),
            // Tabs again (BO-1, plan 19 §1.1). Until then there were none:
            // the window's bar named every area and every pane, and a strip of
            // the current area's neighbours was the same navigation twice. The
            // reversal kept that reasoning and moved the other half — the bar
            // shrank to one Back office menu, so the strip is now the one place
            // that names every tab, and it is always on screen, which a bar
            // menu closed by default is not.
            BackOfficeTabStrip(
              tabs: [for (final (t, _) in tabs) t],
              selected: tab,
              onSelect: (t) =>
                  _openTab(t, tabs.firstWhere((e) => e.$1 == t).$2),
            ),
            if (tab != BackOfficeTab.settings && tabPanes.length > 1)
              _SubNav(panes: tabPanes, selected: showing, onSelect: _open),
            if (ref.watch(schemaUpgradeFailureProvider) case final failure?)
              _SchemaNotice(text: strings.schemaUpgradeFailed(failure)),
            if (backupNotice != null)
              _BackupNotice(
                text: backupNotice,
                onOpen: () => _open(ManagementPane.backup),
              ),
            // The platform-owned notice every other cloud pane uses, full
            // width because it describes the screen rather than a section.
            if (pointer != null)
              SizedBox(
                width: double.infinity,
                child: PlatformOwnedNotice(
                  key: const Key('management-platform-pointer'),
                  text: pointer,
                ),
              ),
            Expanded(
              child: tab == BackOfficeTab.settings && showing != null
                  ? Row(
                      children: [
                        _SettingsNav(
                          panes: tabPanes,
                          selected: showing,
                          onSelect: _open,
                        ),
                        Expanded(child: content),
                      ],
                    )
                  : content,
            ),
            _StatusBar(admin: admin),
          ],
        ),
      ),
    );

    return AdminActivityWatch(onIdle: _lock, child: screen);
  }

  Widget _paneBody(PosStaff admin, ManagementPane pane) => switch (pane) {
    ManagementPane.staff => ManagementStaffPane(admin: admin),
    // The item editor's "Manage extras" link. Moved here rather than through
    // the router: this screen already owns which pane is showing, as the
    // backup notice's button does.
    ManagementPane.menu => ManagementMenuPane(
      admin: admin,
      onOpenExtras: () => _open(ManagementPane.extras),
    ),
    ManagementPane.extras => ManagementExtrasPane(admin: admin),
    ManagementPane.floor => ManagementFloorPane(admin: admin),
    ManagementPane.taxes => ManagementTaxesPane(admin: admin),
    ManagementPane.charges => ManagementChargesPane(admin: admin),
    ManagementPane.tenders => ManagementTendersPane(admin: admin),
    ManagementPane.orderTypes => ManagementOrderTypesPane(admin: admin),
    ManagementPane.purchasing => ManagementPurchasingPane(
      admin: admin,
      initialTab: widget.purchasingTab ?? PurchasingTab.orders,
      create: widget.create,
      request: widget.request,
    ),
    ManagementPane.receipt => ManagementReceiptPane(admin: admin),
    ManagementPane.eta => const ManagementEtaPane(),
    ManagementPane.roles => ManagementRolesPane(admin: admin),
    ManagementPane.activity => const ManagementActivityPane(),
    ManagementPane.backup => ManagementBackupPane(admin: admin),
    ManagementPane.items => ManagementItemsPane(admin: admin),
    ManagementPane.stock => const ManagementStockPane(),
    ManagementPane.units => ManagementUnitsPane(admin: admin),
    ManagementPane.terminal => ManagementTerminalPane(
      admin: admin,
      onReconfigure: widget.onReconfigure,
    ),
  };
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.onClose});

  /// Which page this is, by the pane's name — the strip says which tab, and
  /// somebody arriving from the bar needs the page confirmed, not the tab.
  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Container(
    height: PosSize.topBar,
    padding: const EdgeInsets.symmetric(horizontal: PosSpace.xl),
    decoration: BoxDecoration(
      color: context.pos.surface,
      border: Border(bottom: context.pos.hairline),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PosText.screenTitle(color: context.pos.ink),
          ),
        ),
        const SizedBox(width: PosSpace.lg),
        PosButton(
          key: const Key('admin-exit'),
          label: context.strings.exitAdminMode,
          border: Border.fromBorderSide(context.pos.resting),
          onPressed: onClose,
        ),
      ],
    ),
  );
}

/// The back office's tabs, across the top.
///
/// **Every tab at its own width, and never a scroll.** A strip you have to
/// scroll hides half the product (plan 19 §1.2), so this is a plain [Row]: at
/// [PosSize.wideShellMin] all nine words fit in both languages, and
/// `back_office_shell_test.dart` measures that with all nine present — not
/// only the five that have panes today — so the slice that adds the ninth
/// cannot be the one that finds out.
///
/// Selection is the accent underline and nothing else: no tint, no radius, no
/// hover (`07-design-system.md` §1). Public so that test can draw the strip
/// with tabs no fixture reaches yet.
class BackOfficeTabStrip extends StatelessWidget {
  const BackOfficeTabStrip({
    required this.tabs,
    required this.selected,
    required this.onSelect,
    super.key,
  });

  final List<BackOfficeTab> tabs;
  final BackOfficeTab selected;
  final ValueChanged<BackOfficeTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final pos = context.pos;
    final strings = context.strings;
    return Container(
      key: const Key('back-office-tabs'),
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: PosSpace.sm),
      decoration: BoxDecoration(
        color: pos.surface,
        border: Border(bottom: pos.resting),
      ),
      child: Row(
        children: [
          for (final tab in tabs)
            GestureDetector(
              key: Key('back-office-tab-${tab.name}'),
              behavior: HitTestBehavior.opaque,
              onTap: () => onSelect(tab),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: PosSpace.md),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: tab == selected
                        ? pos.accentBorder
                        : const BorderSide(
                            color: Colors.transparent,
                            width: 2,
                          ),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      backOfficeTabIcon(tab),
                      size: 18,
                      color: tab == selected ? pos.ink : pos.muted,
                    ),
                    const SizedBox(width: PosSpace.sm),
                    Text(
                      backOfficeTabName(strings, tab),
                      maxLines: 1,
                      style: PosText.ui(
                        size: 14,
                        weight: tab == selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: tab == selected ? pos.ink : pos.body,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The second row, for a tab with two or more panes (Menu, Inventory, System).
///
/// Text only and quieter than the strip above it, with the same kind of
/// underline in ink rather than accent: two accent underlines stacked read as
/// two equal choices, and the upper one is the bigger decision.
class _SubNav extends StatelessWidget {
  const _SubNav({
    required this.panes,
    required this.selected,
    required this.onSelect,
  });

  final List<ManagementPane> panes;
  final ManagementPane? selected;
  final ValueChanged<ManagementPane> onSelect;

  @override
  Widget build(BuildContext context) {
    final pos = context.pos;
    final strings = context.strings;
    return Container(
      key: const Key('back-office-subnav'),
      height: PosSize.filterChip,
      padding: const EdgeInsets.symmetric(horizontal: PosSpace.sm),
      decoration: BoxDecoration(
        color: pos.surface,
        border: Border(bottom: pos.hairline),
      ),
      child: Row(
        children: [
          for (final pane in panes)
            GestureDetector(
              key: Key('back-office-subnav-${pane.name}'),
              behavior: HitTestBehavior.opaque,
              onTap: () => onSelect(pane),
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: PosSpace.md),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: pane == selected
                        ? pos.emphasis
                        : const BorderSide(
                            color: Colors.transparent,
                            width: 2,
                          ),
                  ),
                ),
                child: Text(
                  managementPaneLabel(strings, pane).$1,
                  maxLines: 1,
                  style: PosText.ui(
                    size: 13,
                    weight: pane == selected
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: pane == selected ? pos.ink : pos.body,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Settings' side nav: on the start side, grouped as the cloud groups it.
///
/// A column rather than a second row because Settings holds seven panes and
/// will hold more (BO-8's appearance, BO-7's Users grows a matrix); a row of
/// seven under a strip of nine is the scrolling strip by another name. At
/// [PosSize.settingsNav] it leaves 868 px for a pane at the 1100 breakpoint.
///
/// `BorderDirectional` and `EdgeInsetsDirectional` throughout, so Arabic puts
/// the nav on the right with its selection bar on the right edge — mirrored,
/// not merely re-labelled.
class _SettingsNav extends StatelessWidget {
  const _SettingsNav({
    required this.panes,
    required this.selected,
    required this.onSelect,
  });

  final List<ManagementPane> panes;
  final ManagementPane selected;
  final ValueChanged<ManagementPane> onSelect;

  @override
  Widget build(BuildContext context) {
    final pos = context.pos;
    final strings = context.strings;
    return Container(
      key: const Key('back-office-settings-nav'),
      width: PosSize.settingsNav,
      decoration: BoxDecoration(
        color: pos.surface,
        border: BorderDirectional(end: pos.resting),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: PosSpace.md),
        children: [
          for (final section in SettingsSection.values)
            if ([
                  for (final p in panes)
                    if (settingsPlaceOf(p)?.$1 == section) p,
                ]
                case final own when own.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  PosSpace.lg,
                  PosSpace.md,
                  PosSpace.lg,
                  PosSpace.xs,
                ),
                child: Text(
                  // Upper case is a Latin idea; Arabic has none, and
                  // `toUpperCase` leaves it as it is.
                  settingsSectionName(strings, section).toUpperCase(),
                  style: PosText.microLabel(color: pos.muted),
                ),
              ),
              for (final pane in own)
                GestureDetector(
                  key: Key('back-office-settings-${pane.name}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelect(pane),
                  child: Container(
                    height: PosSize.settingsNavRow,
                    alignment: AlignmentDirectional.centerStart,
                    padding: const EdgeInsetsDirectional.only(
                      start: PosSpace.lg - 2,
                      end: PosSpace.lg,
                    ),
                    decoration: BoxDecoration(
                      border: BorderDirectional(
                        start: pane == selected
                            ? pos.accentBorder
                            : const BorderSide(
                                color: Colors.transparent,
                                width: 2,
                              ),
                      ),
                    ),
                    child: Text(
                      managementPaneLabel(strings, pane).$1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PosText.ui(
                        size: 13.5,
                        weight: pane == selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: pane == selected ? pos.ink : pos.body,
                      ),
                    ),
                  ),
                ),
            ],
        ],
      ),
    );
  }
}

/// The bottom line of every tab: connection, branch, version, who is in.
///
/// **The till's own sources, not new ones** (plan 19 §1.3). The connection is
/// the same pill the till's top bar draws from the same providers — a sync
/// state on a cloud till, the branch server on an offline one — so the back
/// office can never call a till healthy that the till itself calls broken.
/// The branch is the name the terminal was set up under, as About prints it;
/// the version is `posAppVersion`, as About prints it. Support asks for both
/// over the phone, which is why they are here and not only in a dialog.
///
/// Who is in moved here from the header: it is the administrator, not the
/// till's operator, and it belongs with the other facts about this session.
class _StatusBar extends ConsumerWidget {
  const _StatusBar({required this.admin});

  final PosStaff admin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pos = context.pos;
    final strings = context.strings;
    final branch = ref.watch(terminalProfileProvider).branchName;
    final meta = PosText.ui(size: 13, color: pos.body);

    return Container(
      key: const Key('back-office-status-bar'),
      height: PosSize.minTouchTarget,
      padding: const EdgeInsets.symmetric(horizontal: PosSpace.xl),
      decoration: BoxDecoration(
        color: pos.surface,
        border: Border(top: pos.resting),
      ),
      child: Row(
        children: [
          // Which pill, and why, is the till's top bar's decision; see it.
          if (ref.watch(cloudSyncProvider) case final cloud?)
            Builder(
              builder: (context) {
                final sync = ref.watch(pendingSyncCountProvider);
                return SyncPill(
                  online: ref.watch(posUiProvider).online,
                  queued: sync.valueOrNull,
                  hasError: sync.hasError,
                  onTap: () {
                    cloud.kick();
                    posToast(context, strings.syncingWithPlatform);
                  },
                );
              },
            )
          else
            Builder(
              builder: (context) {
                final probe = ref.watch(branchDatabaseProvider);
                return BranchServerPill(
                  checking: probe.isLoading,
                  reachable: probe.hasValue && probe.value == null,
                  onTap: () => ref.invalidate(branchDatabaseProvider),
                );
              },
            ),
          if (branch != null && branch.isNotEmpty) ...[
            const SizedBox(width: PosSpace.lg),
            Icon(Icons.storefront_outlined, size: 16, color: pos.muted),
            const SizedBox(width: PosSpace.xs),
            Flexible(
              child: Text(
                branch,
                key: const Key('back-office-status-branch'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: meta,
              ),
            ),
          ],
          const SizedBox(width: PosSpace.lg),
          // A code, not a word: mono and left to right in both languages.
          Text(
            'v$posAppVersion',
            key: const Key('back-office-status-version'),
            textDirection: TextDirection.ltr,
            style: PosText.mono(size: 12, color: pos.muted),
          ),
          const Spacer(),
          Icon(Icons.person_outline, size: 16, color: pos.muted),
          const SizedBox(width: PosSpace.xs),
          Text(
            '${admin.name} · '
            '${admin.role?.displayName(strings.languageCode) ?? strings.noRole}',
            key: const Key('back-office-status-user'),
            maxLines: 1,
            style: meta,
          ),
        ],
      ),
    );
  }
}

/// The back office's backup warning: what is wrong, and the way to it.
/// The database is older than this build, and bringing it up to date failed.
///
/// Above every pane rather than inside whichever one reaches a missing table
/// first, because it explains all of them at once.
class _SchemaNotice extends StatelessWidget {
  const _SchemaNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final pos = context.pos;
    return Container(
      key: const Key('management-schema-notice'),
      padding: const EdgeInsets.symmetric(
        horizontal: PosSpace.xl,
        vertical: PosSpace.sm,
      ),
      decoration: BoxDecoration(
        color: pos.warnSoft,
        border: Border(bottom: BorderSide(color: pos.danger)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: pos.danger),
          const SizedBox(width: PosSpace.sm),
          Expanded(
            child: Text(
              text,
              style: PosText.ui(size: 13, color: pos.ink, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackupNotice extends StatelessWidget {
  const _BackupNotice({required this.text, required this.onOpen});

  final String text;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final pos = context.pos;
    return Container(
      key: const Key('management-backup-notice'),
      padding: const EdgeInsets.symmetric(
        horizontal: PosSpace.xl,
        vertical: PosSpace.sm,
      ),
      decoration: BoxDecoration(
        color: pos.warnSoft,
        border: Border(bottom: BorderSide(color: pos.warn)),
      ),
      child: Row(
        children: [
          Icon(Icons.backup_outlined, size: 18, color: pos.warn),
          const SizedBox(width: PosSpace.sm),
          Expanded(
            child: Text(
              text,
              style: PosText.ui(size: 13, color: pos.ink, height: 1.4),
            ),
          ),
          const SizedBox(width: PosSpace.md),
          PosButton(
            key: const Key('management-backup-open'),
            label: context.strings.backupOpenPane,
            height: 36,
            border: Border.fromBorderSide(BorderSide(color: pos.warn)),
            onPressed: onOpen,
          ),
        ],
      ),
    );
  }
}
