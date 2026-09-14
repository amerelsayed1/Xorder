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
import '../../../domain/services/authorization.dart';
import '../../../domain/services/eta_filing.dart' show etaFilingEnabled;
import '../../history/presentation/order_history_screen.dart';
import '../application/admin_session.dart';
import 'admin_activity_watch.dart';
import 'admin_pane_bits.dart';
import 'admin_sign_in.dart';
import 'management_activity_pane.dart';
import 'management_appearance_pane.dart';
import 'management_backup_pane.dart';
import 'management_items_pane.dart';
import 'management_stock_pane.dart';
import 'management_units_pane.dart';
import 'management_floor_pane.dart';
import 'management_menu_pane.dart';
import 'management_eta_pane.dart';
import 'management_extras_pane.dart';
import 'management_finance_panes.dart';
import 'management_home_pane.dart';
import 'management_charges_pane.dart';
import 'management_order_types_pane.dart';
import 'management_taxes_pane.dart';
import 'management_tenders_pane.dart';
import 'management_purchasing_pane.dart';
import 'management_receipt_pane.dart';
import 'management_reports_pane.dart';
import 'management_roles_pane.dart';
import 'management_staff_pane.dart';
import 'management_terminal_pane.dart';
import 'report_breakdown_panes.dart';

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
  /// Null is the door's own landing: Home (see [backOfficeLanding]). Staff used
  /// to be the default, which was right while the back office was a list with
  /// Staff at the top; with tabs, landing three tabs in from the start would be
  /// the one screen that opens in the middle.
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
/// window's bar and Home's quick actions ([homeQuickActionsFor]). Two lists that
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
  // The menu pane again, reached from its Categories line.
  ManagementPane.categories,
  // The library is the menu's too: a group made here would be erased by the
  // next sync on a cloud till, where the platform's Extras page is the author.
  ManagementPane.extras,
  ManagementPane.floor,
  ManagementPane.purchasing,
  ManagementPane.items,
  ManagementPane.stock,
  ManagementPane.units,
  // Not an authoring pane — Bills due only reads — but it reads the supplier
  // ledger, which on a cloud till is the platform's and never comes down
  // (BO-10). Hidden by the same rule as Purchasing for the same reason: a
  // local Owner role still holds `purchase.manage` there, so the capability
  // alone would show a card of whatever rows this till kept from before.
  ManagementPane.financeBills,
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
  BackOfficeTab.people ||
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

/// The back office, in tabs — the owner's map of 14 Sep 2026: ten words, in
/// this order, in the strip and the window's bar alike.
///
/// **Every tab holds a pane.** Home has had its pane since BO-4 and Sales the
/// order history since BO-2, both for everybody past the door; Reports has had
/// its one pane since BO-6 and Finance its panes since BO-9, both for whoever
/// holds `reports.view`. They were members before their slices, rather than
/// added with them, so that the order is decided once, here, and so that
/// [backOfficeTabName] and the strip's width test carry every word — a word
/// arriving with a slice is how a strip that fitted at 1100 px stops fitting
/// without anybody measuring it.
///
/// Replaces the seven areas of the flat bar. Money went to Settings (rules
/// about money are configuration; *Finance* is money that moved) and
/// Compliance dissolved into Settings and System. **People is a tab again**:
/// BO-1 filed Users and Roles under Settings, as the cloud does; the owner's
/// map gives them a tab of their own, which Shifts joins when it is built.
enum BackOfficeTab {
  /// The landing page (BO-4): this till, today's takings, the way onward.
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

  /// Who works here, and what each of them may do.
  people,

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
  ManagementPane.home => BackOfficeTab.home,
  ManagementPane.sales => BackOfficeTab.sales,
  ManagementPane.reports ||
  ManagementPane.reportsSales ||
  ManagementPane.reportsItems ||
  ManagementPane.reportsPayments ||
  ManagementPane.reportsBranches ||
  ManagementPane.reportsEmployees => BackOfficeTab.reports,
  ManagementPane.menu ||
  ManagementPane.categories ||
  ManagementPane.extras ||
  ManagementPane.floor => BackOfficeTab.menu,
  ManagementPane.items ||
  ManagementPane.stock ||
  ManagementPane.units => BackOfficeTab.inventory,
  ManagementPane.purchasing => BackOfficeTab.purchasing,
  ManagementPane.financeOverview ||
  ManagementPane.financeRevenue ||
  ManagementPane.financePayments ||
  ManagementPane.financeTaxes ||
  ManagementPane.financeExpenses ||
  ManagementPane.financeDrawers ||
  ManagementPane.financeBills ||
  ManagementPane.financeTransactions => BackOfficeTab.finance,
  // Terminal beside Backup and the log rather than in Settings: it wipes the
  // machine, and Settings is where somebody goes to change a tax rate.
  // ETA here too, still hidden while `etaFilingEnabled` is false.
  ManagementPane.activity ||
  ManagementPane.backup ||
  ManagementPane.terminal ||
  ManagementPane.eta => BackOfficeTab.system,
  ManagementPane.staff || ManagementPane.roles => BackOfficeTab.people,
  ManagementPane.receipt ||
  ManagementPane.taxes ||
  ManagementPane.charges ||
  ManagementPane.tenders ||
  ManagementPane.orderTypes ||
  ManagementPane.language ||
  ManagementPane.appearance => BackOfficeTab.settings,
};

String backOfficeTabName(AppStrings s, BackOfficeTab tab) => switch (tab) {
  BackOfficeTab.home => s.tabHome,
  BackOfficeTab.sales => s.tabSales,
  BackOfficeTab.reports => s.tabReports,
  BackOfficeTab.menu => s.tabMenu,
  BackOfficeTab.inventory => s.tabInventory,
  BackOfficeTab.purchasing => s.tabPurchasing,
  BackOfficeTab.finance => s.tabFinance,
  BackOfficeTab.people => s.tabPeople,
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
  BackOfficeTab.people => Icons.people_outline,
  BackOfficeTab.system => Icons.dns_outlined,
  BackOfficeTab.settings => Icons.settings_outlined,
};

/// Settings' own items, in the owner's map's order: each is an entry in the
/// tab's sub-nav and a line in the bar's Settings menu.
///
/// **Orders & invoices settings holds five panes behind a side nav**: the
/// restaurant's General profile — the name on every slip — and the rules an
/// order and its invoice follow: order types, tax, service charges, payment
/// methods. One word for them in the sub-nav rather than five, because the
/// map names one place; the side nav inside is where the five are told apart.
///
/// **Language and Appearance are this terminal's**, not the restaurant's: what
/// they hold is written to this machine's config file, not the branch
/// database. They are one card split in two (`ManagementAppearancePane`), and
/// the till's own Settings menu keeps its two quick toggles over the same
/// providers, because it is reachable without Admin Mode.
///
/// The map's other Settings items — printer & cash drawer, user, about — are
/// the till's own lines in the same bar menu, and have no pane here.
enum SettingsSection { ordersAndInvoices, language, appearance }

String settingsSectionName(AppStrings s, SettingsSection section) =>
    switch (section) {
      SettingsSection.ordersAndInvoices => s.settingsOrdersInvoices,
      SettingsSection.language => s.settingsLanguage,
      SettingsSection.appearance => s.settingsLook,
    };

/// Which of Settings' items a Settings pane sits under.
///
/// Total over the panes, so a pane given the Settings tab without an item here
/// is caught by `back_office_shell_test.dart` rather than rendering nowhere —
/// and a pane taken OUT of Settings has to be taken out here too, or the same
/// test says so. Null for every pane in another tab.
SettingsSection? settingsSectionOf(ManagementPane pane) => switch (pane) {
  ManagementPane.receipt ||
  ManagementPane.orderTypes ||
  ManagementPane.taxes ||
  ManagementPane.charges ||
  ManagementPane.tenders => SettingsSection.ordersAndInvoices,
  ManagementPane.language => SettingsSection.language,
  ManagementPane.appearance => SettingsSection.appearance,
  ManagementPane.home ||
  ManagementPane.sales ||
  ManagementPane.reports ||
  ManagementPane.reportsSales ||
  ManagementPane.reportsItems ||
  ManagementPane.reportsPayments ||
  ManagementPane.reportsBranches ||
  ManagementPane.reportsEmployees ||
  ManagementPane.menu ||
  ManagementPane.categories ||
  ManagementPane.extras ||
  ManagementPane.floor ||
  ManagementPane.purchasing ||
  ManagementPane.eta ||
  ManagementPane.staff ||
  ManagementPane.roles ||
  ManagementPane.activity ||
  ManagementPane.backup ||
  ManagementPane.items ||
  ManagementPane.stock ||
  ManagementPane.units ||
  ManagementPane.terminal ||
  ManagementPane.financeOverview ||
  ManagementPane.financeRevenue ||
  ManagementPane.financePayments ||
  ManagementPane.financeTaxes ||
  ManagementPane.financeExpenses ||
  ManagementPane.financeDrawers ||
  ManagementPane.financeBills ||
  ManagementPane.financeTransactions => null,
};

/// A pane's place in its tab: the order the owner's map lists them in, which
/// the sub-nav, Settings' side nav and the bar's menus all follow.
///
/// **A total switch rather than a list**, so a pane added without a place
/// fails to compile rather than sorting to wherever an absent index lands.
/// Only ever compared between panes of the same tab.
int _placeInTab(ManagementPane pane) => switch (pane) {
  ManagementPane.home => 0,
  ManagementPane.sales => 0,
  // ملخص الأعمال، المبيعات، الأصناف، طرق الدفع، الفروع والأجهزة، الموظفين
  ManagementPane.reports => 0,
  ManagementPane.reportsSales => 1,
  ManagementPane.reportsItems => 2,
  ManagementPane.reportsPayments => 3,
  ManagementPane.reportsBranches => 4,
  ManagementPane.reportsEmployees => 5,
  // المنيو، الأقسام، مكتبة الإضافات، الصالة
  ManagementPane.menu => 0,
  ManagementPane.categories => 1,
  ManagementPane.extras => 2,
  ManagementPane.floor => 3,
  // أصناف المخزون، المخزون المتاح، الوحدات
  ManagementPane.items => 0,
  ManagementPane.stock => 1,
  ManagementPane.units => 2,
  ManagementPane.purchasing => 0,
  // Overview and Revenue lead, ahead of the map's الخزينة، المصروفات، طرق
  // الدفع، الضرائب. The map has no word for either; they are this tab's own
  // summary, first as the mockup's sub-tabs had them. Folding them into
  // Reports' Business summary was the alternative, and would have made one
  // page of two reads (BO-6's and BO-9's) that disagree about what a period
  // is. Bills due and Transactions follow the map's words, kept reachable
  // until the map places them.
  ManagementPane.financeOverview => 0,
  ManagementPane.financeRevenue => 1,
  ManagementPane.financeDrawers => 2,
  ManagementPane.financeExpenses => 3,
  ManagementPane.financePayments => 4,
  ManagementPane.financeTaxes => 5,
  ManagementPane.financeBills => 6,
  ManagementPane.financeTransactions => 7,
  // الموظفون، الأدوار والصلاحيات
  ManagementPane.staff => 0,
  ManagementPane.roles => 1,
  // السجل، النسخ الاحتياطي، الأجهزة — and ETA, hidden while filing is off.
  ManagementPane.activity => 0,
  ManagementPane.backup => 1,
  ManagementPane.terminal => 2,
  ManagementPane.eta => 3,
  // General first: it is the company — the name on every slip. Then the
  // rules in the order an order meets them.
  ManagementPane.receipt => 0,
  ManagementPane.orderTypes => 1,
  ManagementPane.taxes => 2,
  ManagementPane.charges => 3,
  ManagementPane.tenders => 4,
  ManagementPane.language => 5,
  ManagementPane.appearance => 6,
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
            ..sort((a, b) => _placeInTab(a) - _placeInTab(b))
          case final own
          when own.isNotEmpty ||
              (!authorsItsOwnCatalogue &&
                  _pointsToPlatform(tab) &&
                  _wouldPermitTab(admin, tab)))
        (tab, own),
  ];
}

/// One item of a tab: a word in its sub-nav, and a line in its bar menu.
///
/// [opens] is the pane it lands on; [holds] every pane that counts as being
/// on it — more than one only for Settings' Orders & invoices settings, whose
/// five panes sit behind a side nav of their own.
typedef BackOfficeItem = ({
  String label,
  ManagementPane opens,
  List<ManagementPane> holds,
});

/// A tab's items, in its order: a pane each, bar Settings, whose items are its
/// [SettingsSection]s.
///
/// **One function for the sub-nav and the bar**, so the two say the same
/// words in the same order — and read off [panes], which is what
/// [backOfficeTabsFor] allowed, so nobody is offered an item they may not
/// open.
///
/// **An item of the owner's map with no screen yet is not here** — not as a
/// placeholder, not as a greyed word: Sales' invoices, returns and cancelled
/// orders; Finance's settlements; People's shifts; System's sync. Each arrives
/// as a pane with the slice that builds it. Reports' five breakdowns arrived
/// as panes of their own once the period moved out of Business summary into
/// `reportPeriodProvider`: entries into sections of that page would each have
/// opened it back on Today.
List<BackOfficeItem> backOfficeItemsFor(
  AppStrings s,
  BackOfficeTab tab,
  List<ManagementPane> panes,
) => tab == BackOfficeTab.settings
    ? [
        for (final section in SettingsSection.values)
          if ([
                for (final p in panes)
                  if (settingsSectionOf(p) == section) p,
              ]
              case final own when own.isNotEmpty)
            (
              label: settingsSectionName(s, section),
              opens: own.first,
              holds: own,
            ),
      ]
    : [
        for (final pane in panes)
          (
            label: managementPaneLabel(s, pane).$1,
            opens: pane,
            holds: [pane],
          ),
      ];

/// Where the door lands: the first pane of the first tab that holds one —
/// which, since BO-4, is Home for everybody.
///
/// Home is first in the strip and has no gate beyond the door, so this rule
/// needed no change to land there; it is kept as the rule rather than written
/// as "Home" so that a Home ever gated or hidden hands the landing to the next
/// tab instead of to a pane that is not there. **A tab that only points at the
/// platform is passed over** — on a cloud till that is Inventory, and greeting
/// the owner on every entry with "this is not here" would make the sentence a
/// welcome rather than an answer.
///
/// Never empty: Home, Sales and Staff have no gate beyond the door, so
/// everybody past it holds at least those panes.
ManagementPane backOfficeLanding(
  List<(BackOfficeTab, List<ManagementPane>)> tabs,
) => tabs.expand((tab) => tab.$2).first;

/// Home's shortcuts, each to the first pane it names — and absent when that
/// pane is.
///
/// **Read off the same tabs as the strip and the bar**, so a shortcut can
/// never lead where the strip would not: no Product management on a cloud
/// till, where Menu is the platform's; no Sales reports for whoever lacks
/// `reports.view`, which is the gate on the one pane Reports holds.
List<(HomeQuickAction, ManagementPane)> homeQuickActionsFor(
  List<(BackOfficeTab, List<ManagementPane>)> tabs,
) {
  ManagementPane? firstOf(BackOfficeTab tab) {
    for (final (t, panes) in tabs) {
      if (t == tab && panes.isNotEmpty) return panes.first;
    }
    return null;
  }

  final reachable = [for (final (_, panes) in tabs) ...panes];
  return [
    for (final action in HomeQuickAction.values)
      if (switch (action) {
            HomeQuickAction.salesReports => firstOf(BackOfficeTab.reports),
            HomeQuickAction.products => firstOf(BackOfficeTab.menu),
            // Staff, under People.
            HomeQuickAction.employees =>
              reachable.contains(ManagementPane.staff)
                  ? ManagementPane.staff
                  : null,
          }
          case final pane?)
        (action, pane),
  ];
}

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

/// The lines a pane shows in the window's bar, in place of its own one line.
///
/// Only Purchasing has any. It is really four things — orders, the suppliers
/// they go to, the invoices that arrive against them and the payments that
/// settle those, in the owner's map's order — and "where do I enter this
/// invoice" is answered by an invoice, not by a tab that holds a list of them.
/// So it lists each, with the "new" that starts one beside the list it belongs
/// to. The pane's own tabs can take somebody to the list; only the bar takes
/// them straight to an empty invoice.
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
    (s.suppliers, () => _purchasing(PurchasingTab.suppliers), true),
    (
      s.supplierNew,
      () => _purchasing(PurchasingTab.suppliers, create: true),
      false,
    ),
    (s.supplierInvoices, () => _purchasing(PurchasingTab.invoices), true),
    (
      s.invoiceNew,
      () => _purchasing(PurchasingTab.invoices, create: true),
      false,
    ),
    (s.paymentsList, () => _purchasing(PurchasingTab.payments), false),
  ],
  _ => const [],
};

/// One line of a back-office menu in the window's bar.
///
/// [pane] is what the line opens, null for a line that is not a pane — the
/// pointer a cloud till shows under Inventory and Purchasing. [divider] is
/// drawn above this line.
typedef ManagementBarEntry = ({
  BackOfficeTab tab,
  ManagementPane? pane,
  String label,
  ManagementDestination Function() open,
  bool divider,
});

/// One menu of the window's bar: a tab's word, and its lines.
typedef ManagementBarMenu = ({
  BackOfficeTab tab,
  String label,
  List<ManagementBarEntry> lines,
});

/// The back office as the window's bar offers it: a menu per visible tab, in
/// the strip's order and under the strip's word, listing that tab's items.
///
/// **The owner's map, 14 Sep 2026.** BO-1 folded the bar into one Back office
/// menu with a line per tab, arguing that seven words in the bar above a strip
/// of the same tabs was the same navigation twice. The owner reversed that,
/// then drew the whole back office as one map — ten words, each with its
/// items — for the strip and the bar alike. So the two are the same list read
/// at two depths: the strip and its sub-nav on screen, the bar one gesture
/// away from anywhere, both from [backOfficeTabsFor] and [backOfficeItemsFor].
///
/// **The first menu is Home**, named as the strip names it, so the ten words
/// are the same ten in both places. It holds the Home line, and the bar adds
/// Exit Admin Mode under it: that is an act on the session, not a destination,
/// so it is not a line here. "Back office" was the other candidate for the
/// word, and would have made the bar the one place the first word differs.
///
/// **Settings is returned like any other tab, and the bar does not draw it as
/// a menu of its own.** The till already has a Settings menu, and two menus
/// both called الإعدادات side by side would leave somebody to learn which is
/// which by opening both. `app.dart` folds these lines into the till's own,
/// beneath everything it already held.
///
/// **On a cloud till Inventory and Purchasing are each a menu of one line**,
/// the pointer that names both ("Purchasing & stock — on xorder.io…"), opening
/// the tab that says the same thing at length. Only for whoever would have
/// those tabs offline: [backOfficeTabsFor] keeps a pointer tab for nobody
/// else.
///
/// **Here rather than in the bar, so the two cannot drift.** The rule and its
/// test sit beside each other, and `app.dart` only draws.
List<ManagementBarMenu> managementBarFor(
  AppStrings s, {
  required PosStaff admin,
  required bool authorsItsOwnCatalogue,
}) => [
  for (final (tab, panes) in backOfficeTabsFor(
    admin: admin,
    authorsItsOwnCatalogue: authorsItsOwnCatalogue,
  ))
    (
      tab: tab,
      label: backOfficeTabName(s, tab),
      lines: panes.isEmpty
          ? [_platformPointerLine(s, tab)]
          : _tabLines(s, tab, panes),
    ),
];

/// A tab's lines: one per item, in the tab's order — Purchasing's own lines
/// in place of its one, set off in groups by the dividers they carry.
List<ManagementBarEntry> _tabLines(
  AppStrings s,
  BackOfficeTab tab,
  List<ManagementPane> panes,
) => [
  for (final item in backOfficeItemsFor(s, tab, panes))
    ...switch (managementMenuEntries(s, item.opens)) {
      final own when own.isNotEmpty => <ManagementBarEntry>[
        for (final (i, (label, open, groups)) in own.indexed)
          (
            tab: tab,
            pane: item.opens,
            label: label,
            open: open,
            divider: groups && i > 0,
          ),
      ],
      _ => <ManagementBarEntry>[
        (
          tab: tab,
          pane: item.opens,
          label: item.label,
          open: () => ManagementDestination(pane: item.opens, request: Object()),
          divider: false,
        ),
      ],
    },
];

/// The one line of a tab a cloud till keeps only as a pointer.
///
/// Opens the tab's first pane by the enum, as the strip's word does
/// (`_openTab`): the screen answers a pane the platform authors with the tab
/// and the sentence, not with the pane.
ManagementBarEntry _platformPointerLine(AppStrings s, BackOfficeTab tab) {
  final pane = ManagementPane.values.firstWhere((p) => tabOf(p) == tab);
  return (
    tab: tab,
    pane: null,
    label: s.purchasingOnPlatformEntry,
    open: () => ManagementDestination(pane: pane, request: Object()),
    divider: false,
  );
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
/// Every pane answers with the owner's map's word for it (14 Sep 2026) —
/// Orders, Business summary, Roles & permissions, Devices, Treasury — so the
/// sub-nav, the header and the bar say one word for one place. The panes' own
/// headings inside still say what they list. Receipt answers General, its
/// name in Settings' side nav.
(String, String) managementPaneLabel(AppStrings s, ManagementPane pane) =>
    switch (pane) {
      ManagementPane.home => (s.tabHome, s.paneHomeBlurb),
      ManagementPane.staff => (s.paneStaff, s.paneStaffBlurb),
      // Orders, as `/orders` calls the same list: the first of Sales' items,
      // the only one built.
      ManagementPane.sales => (s.orderHistoryTitle, s.paneSalesBlurb),
      ManagementPane.reports => (s.reportsSummary, s.paneReportsBlurb),
      ManagementPane.reportsSales => (s.reportsSales, s.reportsSalesBlurb),
      ManagementPane.reportsItems => (s.reportsItems, s.reportsItemsBlurb),
      ManagementPane.reportsPayments => (
        s.reportsPaymentMethods,
        s.reportsPaymentMethodsBlurb,
      ),
      ManagementPane.reportsBranches => (
        s.reportsBranches,
        s.reportsBranchesBlurb,
      ),
      ManagementPane.reportsEmployees => (
        s.reportsEmployees,
        s.reportsEmployeesBlurb,
      ),
      ManagementPane.menu => (s.paneMenu, s.paneMenuBlurb),
      ManagementPane.categories => (s.categories, s.paneMenuBlurb),
      ManagementPane.extras => (s.extrasTitle, s.extrasSubtitle),
      ManagementPane.floor => (s.floorPlan, s.floorPlanHint),
      ManagementPane.taxes => (s.paneTaxes, s.paneTaxesHint),
      ManagementPane.charges => (s.serviceCharges, s.serviceChargesHint),
      ManagementPane.tenders => (s.tenderTypes, s.tenderTypesHint),
      ManagementPane.orderTypes => (s.orderTypes, s.orderTypesHint),
      ManagementPane.purchasing => (s.panePurchasing, s.panePurchasingBlurb),
      ManagementPane.receipt => (s.settingsGeneral, s.paneReceiptBlurb),
      ManagementPane.eta => (s.paneEta, s.paneEtaBlurb),
      ManagementPane.roles => (s.rolesAndPermissions, s.paneRolesBlurb),
      ManagementPane.activity => (s.paneActivity, s.paneActivityBlurb),
      ManagementPane.backup => (s.paneBackup, s.paneBackupBlurb),
      ManagementPane.items => (s.paneItems, s.paneItemsBlurb),
      ManagementPane.stock => (s.paneStock, s.paneStockBlurb),
      ManagementPane.units => (s.paneUnits, s.paneUnitsBlurb),
      ManagementPane.terminal => (s.paneDevices, s.paneTerminalBlurb),
      ManagementPane.language => (s.settingsLanguage, s.paneAppearanceBlurb),
      ManagementPane.appearance => (s.settingsLook, s.paneAppearanceBlurb),
      ManagementPane.financeOverview => (
        s.financeOverview,
        s.financeOverviewBlurb,
      ),
      ManagementPane.financeRevenue => (s.financeRevenue, s.financeRevenueBlurb),
      ManagementPane.financePayments => (
        s.financePayments,
        s.financePaymentsBlurb,
      ),
      ManagementPane.financeTaxes => (s.financeTaxes, s.financeTaxesBlurb),
      ManagementPane.financeExpenses => (
        s.financeExpenses,
        s.financeExpensesBlurb,
      ),
      ManagementPane.financeDrawers => (s.financeDrawers, s.financeDrawersBlurb),
      ManagementPane.financeBills => (s.financeBills, s.financeBillsBlurb),
      ManagementPane.financeTransactions => (
        s.financeTransactions,
        s.financeTransactionsBlurb,
      ),
    };

/// The capabilities a pane needs beyond the door that opened the screen — all
/// of them. A set since BO-10, whose Bills due is a Finance figure and a
/// supplier-ledger read at once; a second function for "and also" would be a
/// gate `_wouldPermit` could be written without.
///
/// **Only the panes whose repositories actually enforce one appear here.**
/// Hiding a pane on a capability nothing checks would be a claim the database
/// does not back — the strip would say no while a direct write said yes. So
/// Purchasing is gated (its three repositories all demand `purchase.manage`)
/// and the others are not, until each one's writes are gated too.
Set<String> _paneRequires(ManagementPane pane) => switch (pane) {
  ManagementPane.purchasing => const {PosCapability.purchaseManage},
  // The third capability that had no screen, and the one with the worst
  // consequences: `backup.manage` is critical-risk, held only by Owner, and
  // deliberately outside supervisor override.
  //
  // Unlike Purchasing, this pane's gate is not backed by a repository that
  // refuses — `pos_backups` is granted INSERT to the till so the automatic copy
  // at day close can be recorded without anybody being in the back office. What
  // the gate protects is the two buttons: taking one on demand, and restoring.
  // Both go through `BackupService`, which is only ever reached from here.
  ManagementPane.backup => const {PosCapability.backupManage},
  // Wiping this till's setup. Like Backup, nothing in the database refuses it
  // — the configuration is a file on this machine — so what the gate protects
  // is the one button, and the pane is the only place it is reached from.
  ManagementPane.terminal => const {PosCapability.terminalManage},
  // Units exist for buying and counting stock: the buyer's.
  ManagementPane.items ||
  ManagementPane.stock ||
  ManagementPane.units => const {PosCapability.purchaseManage},
  // Anyone past the door (plan 19 §1.1). Whose sales they see is not a gate
  // on the pane but a scope on its rows — `HistoryScope`, in the provider,
  // exactly as `/orders` scopes them — so a cashier-grade administrator gets
  // the tab and their own sales in it, rather than no tab.
  ManagementPane.sales => const {},
  // The branch's takings (BO-6). Not the only guard: `salesReportProvider`
  // asks the same capability of the person acting before it reads a row, so
  // a screen built on the figures later without this gate still shows none.
  // Reports' five breakdowns, the same gate on the same figures: each reads
  // through `reportsAllowedProvider` too.
  ManagementPane.reports ||
  ManagementPane.reportsSales ||
  ManagementPane.reportsItems ||
  ManagementPane.reportsPayments ||
  ManagementPane.reportsBranches ||
  ManagementPane.reportsEmployees => const {PosCapability.reportsView},
  // Finance (BO-9, BO-10). Backed where it counts: every figure is read
  // through `reportsAllowedProvider`, which answers no without
  // `reports.view`, so a pane reached round the strip still draws nothing.
  ManagementPane.financeOverview ||
  ManagementPane.financeRevenue ||
  ManagementPane.financePayments ||
  ManagementPane.financeTaxes ||
  ManagementPane.financeExpenses ||
  ManagementPane.financeDrawers ||
  ManagementPane.financeTransactions => const {PosCapability.reportsView},
  // Both: a Finance figure, and made of the supplier ledger that is
  // Purchasing's. Backed by `billsDueProvider`, which asks both of the
  // person acting — and, through `_authoringPanes`, absent on a cloud till.
  ManagementPane.financeBills => const {
    PosCapability.reportsView,
    PosCapability.purchaseManage,
  },
  _ => const {},
};

bool _permits(PosStaff admin, ManagementPane pane) =>
    // `can` and not `capabilities`: the latter is the direct-grant set alone,
    // and an owner holds almost everything through their role.
    _paneRequires(pane).every(admin.can);

/// Whether [admin] would have [pane] on a till that authors it.
///
/// **Who is told where a platform-authored pane went.** The pointer stands in
/// for the pane, so it reaches the people the pane would have and nobody else:
/// a rota manager has no Purchasing offline, and xorder-new's sidebar hides the
/// Purchasing group from whoever lacks `purchase.manage` — sending them there
/// would be a door to a refusal.
bool _wouldPermit(PosStaff admin, ManagementPane pane) => _paneRequires(
  pane,
).every((needed) => Authorization.check(admin, needed).isAllowed);

/// Whether [admin] would have any pane of [tab] on a till that authors it —
/// the same rule as [_wouldPermit], for a tab kept only as a pointer.
bool _wouldPermitTab(PosStaff admin, BackOfficeTab tab) => ManagementPane
    .values
    .any((pane) => tabOf(pane) == tab && _wouldPermit(admin, pane));

enum ManagementPane {
  /// The landing page. A pane like the others rather than a special case in
  /// the shell, so it is in [managementPanesFor] — and so the strip, the bar
  /// and the table-driven test in `back_office_shell_test.dart` see it as they
  /// see every other page. No gate: it shows each person only what they hold.
  home,
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

  /// Settings › Appearance: the theme half of BO-8's Language & appearance,
  /// since the owner's map gave language an item of its own ([language]).
  /// Last when it was added, so every other pane kept the index it had;
  /// nothing stores one, but a deep link or a test naming panes by position
  /// is cheaper not to have to find.
  appearance,
  /// The order history, as the Sales tab (BO-2). Last, so no other pane's
  /// index moves; the strip orders tabs by [BackOfficeTab], not by this.
  sales,

  /// BO-5's figures, drawn as the Reports tab (BO-6). Last, for the same
  /// reason as [sales].
  reports,
  /// Finance (BO-9). The sub-nav orders these and BO-10's by `_financeOrder`,
  /// the mockup's order, not by their places here.
  financeOverview,
  financeRevenue,
  financePayments,
  financeTaxes,

  /// Finance (BO-10). Last, for the same reason as [sales].
  financeExpenses,
  financeDrawers,
  financeBills,
  financeTransactions,

  /// Menu › Categories (the owner's map): the menu pane again. It has no
  /// categories-only mode — its categories are the list down its start side,
  /// where they are added, renamed and archived — so this item opens the same
  /// pane, under the word somebody looking for a category reaches for. Last,
  /// for the same reason as [sales].
  categories,

  /// Settings › Language (the owner's map): the language half of the card
  /// [appearance] shows the other half of. Last, for the same reason.
  language,

  /// Reports' five breakdowns (the owner's map): Business summary's figures,
  /// each as a page of its own over the period all six share. Last, for the
  /// same reason as [sales]; `_placeInTab` puts them in the map's order.
  reportsSales,
  reportsItems,
  reportsPayments,
  reportsBranches,
  reportsEmployees,
}

class _ManagementScreenState extends ConsumerState<ManagementScreen> {
  /// The pane ASKED for — by the caller, the strip, the sub-nav or a notice.
  /// Null until something asks, which is the door's own landing. What is
  /// actually shown is worked out from this at every build, because a request
  /// can outlive the permission or the deployment that justified it.
  late ManagementPane? _pane = widget.initialPane;

  /// Which of Purchasing's tabs a Finance row asked for — its invoices for a
  /// supplier invoice, its payments for a payment. Null otherwise, and cleared
  /// by every other way of choosing a pane, so the Purchasing tab chosen from
  /// the strip later opens where it always has.
  PurchasingTab? _purchasingTab;

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
      setState(() {
        _pane = widget.initialPane;
        _purchasingTab = null;
      });
    }
  }

  /// A tab from the strip: its first pane, or — for a tab that only points at
  /// the platform — any pane of it, which the build answers with the pointer.
  void _openTab(BackOfficeTab tab, List<ManagementPane> panes) => setState(() {
    _pane = panes.isNotEmpty
        ? panes.first
        : ManagementPane.values.firstWhere((p) => tabOf(p) == tab);
    _purchasingTab = null;
  });

  void _open(ManagementPane pane) => setState(() {
    _pane = pane;
    _purchasingTab = null;
  });

  /// Where a Finance row or card leads, or null when that place is not one of
  /// [panes] — and the pane then draws no link, rather than one to a pane the
  /// strip hides, which would land on Home and read as a broken link.
  ///
  /// **The pane, not the row.** A sale opens the Sales tab and a supplier
  /// payment Purchasing's payments; neither lands on the one row. That would
  /// need the history and Purchasing to take a row to open from outside —
  /// the history has no such way in, and a search typed on somebody's behalf
  /// would be a filter they then have to find to clear.
  VoidCallback? _financeLink(
    FinanceTarget target,
    List<ManagementPane> panes,
  ) {
    final (pane, purchasingTab) = switch (target) {
      FinanceTarget.sales => (ManagementPane.sales, null),
      FinanceTarget.supplierInvoices => (
        ManagementPane.purchasing,
        PurchasingTab.invoices,
      ),
      FinanceTarget.supplierPayments => (
        ManagementPane.purchasing,
        PurchasingTab.payments,
      ),
      FinanceTarget.expenses => (ManagementPane.financeExpenses, null),
      FinanceTarget.drawers => (ManagementPane.financeDrawers, null),
      FinanceTarget.bills => (ManagementPane.financeBills, null),
      FinanceTarget.transactions => (ManagementPane.financeTransactions, null),
    };
    if (!panes.contains(pane)) return null;
    return () => setState(() {
      _pane = pane;
      _purchasingTab = purchasingTab;
    });
  }

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
    // The tab's items — the sub-nav's words, which the bar's menu lists too —
    // and the one the page on screen belongs to.
    final items = backOfficeItemsFor(strings, tab, tabPanes);
    final item = items.where((i) => i.holds.contains(showing)).firstOrNull;

    // …and when it is absent because the platform authors it, the screen says
    // so. Keyed on `_pane`, the pane ASKED for, so it goes the moment anything
    // else is asked for (see `didUpdateWidget`).
    final pointer =
        asked != null &&
            !panes.contains(asked) &&
            _wouldPermit(admin, asked) &&
            hiddenBecausePlatformAuthors(
              asked,
              authorsItsOwnCatalogue: authors,
            )
        ? platformAuthoredPointer(strings, asked)
        : null;

    // Backups are the back office's business, said here rather than on the
    // screen a cashier opens the till from: only somebody who can open the
    // Backup pane can do anything about it, so only they are told. Not on the
    // Backup pane itself, which already says how old the last copy is — nor on
    // General, whose backup card says the same sentence (BO-8). The same words
    // twice on one screen read as two problems.
    final backupNotice =
        panes.contains(ManagementPane.backup) &&
            showing != ManagementPane.backup &&
            showing != ManagementPane.receipt &&
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
            child: _paneBody(admin, showing, panes, tabs),
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
            // the current area's neighbours was the same navigation twice. BO-1
            // shrank the bar to one Back office menu to make room for this; the
            // owner put the bar's menu per area back on 14 Sep 2026 and kept
            // the strip too, because it is always on screen, which a bar menu
            // closed by default is not. Both read `backOfficeTabsFor`.
            BackOfficeTabStrip(
              tabs: [for (final (t, _) in tabs) t],
              selected: tab,
              onSelect: (t) =>
                  _openTab(t, tabs.firstWhere((e) => e.$1 == t).$2),
            ),
            if (items.length > 1)
              _SubNav(items: items, selected: item, onSelect: _open),
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
              // Settings' side nav, for the one item that holds more than a
              // page: Orders & invoices settings.
              child: showing != null && item != null && item.holds.length > 1
                  ? Row(
                      children: [
                        _SettingsNav(
                          panes: item.holds,
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

  Widget _paneBody(
    PosStaff admin,
    ManagementPane pane,
    List<ManagementPane> panes,
    List<(BackOfficeTab, List<ManagementPane>)> tabs,
  ) => switch (pane) {
    // Every way onward from Home is a pane this person already has — the
    // cards lead to Terminal and Backup only for whoever can open them.
    ManagementPane.home => ManagementHomePane(
      admin: admin,
      actions: [
        for (final (action, target) in homeQuickActionsFor(tabs))
          (action, () => _open(target)),
      ],
      onOpenTerminal: panes.contains(ManagementPane.terminal)
          ? () => _open(ManagementPane.terminal)
          : null,
      onOpenBackup: panes.contains(ManagementPane.backup)
          ? () => _open(ManagementPane.backup)
          : null,
    ),
    // `/orders`' own widget, not a second screen over the same rows (BO-2).
    // No way out of its own: the back office's Exit and Esc are the way out.
    // Whose sales it lists follows [admin] through `actingStaffProvider`, not
    // the cashier who may still be signed in at the till behind this.
    ManagementPane.sales => const OrderHistoryScreen(),
    // Whose figures follows [admin] through `actingStaffProvider`, as the
    // Sales list's rows do — see `reportsAllowedProvider`.
    ManagementPane.reports => const ManagementReportsPane(),
    ManagementPane.reportsSales => const ReportSalesPane(),
    ManagementPane.reportsItems => const ReportItemsPane(),
    ManagementPane.reportsPayments => const ReportPaymentsPane(),
    ManagementPane.reportsBranches => const ReportBranchesPane(),
    ManagementPane.reportsEmployees => const ReportEmployeesPane(),
    // "Manage roles" opens People › Roles & permissions, as the cloud's Users
    // page opens its roles.
    ManagementPane.staff => ManagementStaffPane(
      admin: admin,
      onManageRoles: () => _open(ManagementPane.roles),
    ),
    // The item editor's "Manage extras" link. Moved here rather than through
    // the router: this screen already owns which pane is showing, as the
    // backup notice's button does.
    ManagementPane.menu || ManagementPane.categories => ManagementMenuPane(
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
      initialTab: _purchasingTab ?? widget.purchasingTab ?? PurchasingTab.orders,
      create: widget.create,
      request: widget.request,
    ),
    // Settings › General (BO-8): the company form, and under it this
    // terminal's appearance and the backup summary. The card's way to System
    // › Backup is offered only to somebody who has that pane — a link to a
    // pane the strip hides would be a door to the landing.
    ManagementPane.receipt => ManagementReceiptPane(
      admin: admin,
      sections: [
        const TerminalAppearanceCard(),
        BackupSummaryCard(
          admin: admin,
          onOpenBackup: panes.contains(ManagementPane.backup)
              ? () => _open(ManagementPane.backup)
              : null,
        ),
      ],
    ),
    ManagementPane.language => const ManagementAppearancePane(
      part: AppearancePart.language,
    ),
    ManagementPane.appearance => const ManagementAppearancePane(
      part: AppearancePart.theme,
    ),
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
    ManagementPane.financeOverview => FinanceOverviewPane(
      links: (target) => _financeLink(target, panes),
    ),
    ManagementPane.financeRevenue => const FinanceRevenuePane(),
    ManagementPane.financePayments => const FinancePaymentsPane(),
    ManagementPane.financeTaxes => const FinanceTaxesPane(),
    ManagementPane.financeExpenses => FinanceExpensesPane(
      links: (target) => _financeLink(target, panes),
    ),
    ManagementPane.financeDrawers => const FinanceDrawersPane(),
    ManagementPane.financeBills => FinanceBillsPane(
      links: (target) => _financeLink(target, panes),
    ),
    ManagementPane.financeTransactions => FinanceTransactionsPane(
      links: (target) => _financeLink(target, panes),
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
/// only the six that have panes today — so the slice that adds the ninth
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

/// The second row, for a tab with two or more items: the owner's map's words
/// for that tab, which its bar menu lists too ([backOfficeItemsFor]).
///
/// Text only and quieter than the strip above it, with the same kind of
/// underline in ink rather than accent: two accent underlines stacked read as
/// two equal choices, and the upper one is the bigger decision.
///
/// Keyed by the pane an item opens, so a test or a tap names the page it
/// lands on — Settings' Orders & invoices settings is `receipt`, its first.
class _SubNav extends StatelessWidget {
  const _SubNav({
    required this.items,
    required this.selected,
    required this.onSelect,
  });

  final List<BackOfficeItem> items;
  final BackOfficeItem? selected;
  final ValueChanged<ManagementPane> onSelect;

  @override
  Widget build(BuildContext context) {
    final pos = context.pos;
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
          for (final item in items)
            GestureDetector(
              key: Key('back-office-subnav-${item.opens.name}'),
              behavior: HitTestBehavior.opaque,
              onTap: () => onSelect(item.opens),
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: PosSpace.md),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: item.opens == selected?.opens
                        ? pos.emphasis
                        : const BorderSide(
                            color: Colors.transparent,
                            width: 2,
                          ),
                  ),
                ),
                child: Text(
                  item.label,
                  maxLines: 1,
                  style: PosText.ui(
                    size: 13,
                    weight: item.opens == selected?.opens
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: item.opens == selected?.opens ? pos.ink : pos.body,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Settings' side nav, for Orders & invoices settings: its five panes, on the
/// start side.
///
/// A column rather than a third row: the sub-nav above already names
/// Settings' items, and a row of five forms under it would be three stacked
/// rows of words. At [PosSize.settingsNav] it leaves 868 px for a pane at the
/// 1100 breakpoint. No headings since the owner's map: the sub-nav names the
/// item, and five rows need no grouping.
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
          for (final pane in panes)
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
          // Shared with Home's connection card, so the two cannot disagree.
          const BackOfficeConnectionPill(),
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
