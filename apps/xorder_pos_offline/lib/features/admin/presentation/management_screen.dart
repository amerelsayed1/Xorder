import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:shared_module/app/providers.dart';
import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/core/ui/tokens.dart';
import 'package:shared_module/core/ui/widgets/pos_widgets.dart';
import 'package:shared_module/domain/models/permissions.dart';
import 'package:shared_module/domain/models/shift.dart';
import 'package:shared_module/domain/services/authorization.dart';
import 'package:shared_module/domain/services/eta_filing.dart' show etaFilingEnabled;
import 'package:shared_module/features/history/presentation/history_widgets.dart' show HistoryFilterChip;
import 'package:shared_module/features/history/presentation/order_history_screen.dart';
import 'package:shared_module/features/history/presentation/refunds_screen.dart';
import 'package:shared_module/features/admin_mode/admin_session.dart';
import 'package:shared_module/features/admin_mode/back_office_contract.dart';

export 'package:shared_module/features/admin_mode/back_office_contract.dart';
import 'admin_activity_watch.dart';
import 'admin_pane_bits.dart';
import 'admin_sign_in.dart';
import 'management_about_pane.dart';
import 'management_activity_pane.dart';
import 'management_appearance_pane.dart';
import 'management_backup_pane.dart';
import 'management_items_pane.dart';
import 'management_stock_pane.dart';
import 'management_units_pane.dart';
import 'management_floor_pane.dart';
import 'management_menu_pane.dart';
import 'management_eta_pane.dart';
import 'management_combos_pane.dart';
import 'management_customers_pane.dart';
import 'management_extras_pane.dart';
import 'management_finance_panes.dart';
import 'management_home_pane.dart';
import 'management_charges_pane.dart';
import 'management_order_types_pane.dart';
import 'management_printer_pane.dart';
import 'management_taxes_pane.dart';
import 'management_tenders_pane.dart';
import 'management_purchasing_pane.dart';
import 'business_logo_card.dart';
import 'management_receipt_pane.dart';
import 'management_reports_pane.dart';
import 'management_roles_pane.dart';
import 'management_accounts_pane.dart';
import 'management_settlements_pane.dart';
import 'management_shifts_pane.dart';
import 'management_staff_pane.dart';
import 'management_sync_pane.dart';
import 'management_terminal_pane.dart';
import 'management_user_pane.dart';
import 'report_breakdown_panes.dart';

/// The back office, inside the till.
///
/// **Reached by PIN, not by being on the right screen.** Everything else in the
/// app assumes whoever is standing there may do it — a till is a shared machine
/// and asking a cashier to sign in before every sale is how a queue forms. This
/// section is the exception: it changes what the business sells, who works
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
  /// Staff at the top; under the owner's map it sits in People, eight menus
  /// along, and landing there would be the one entry that opens in the middle.
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
/// **Public, and the only answer.** The window's bar asks this — the only way
/// round the back office since the owner took the on-screen strip away (15 Sep
/// 2026) — and so does the screen, when it decides what a deep link may show.
/// Two lists that were meant to agree are two lists that will not: a line
/// offering Purchasing to somebody the screen hides it from would take them to
/// a screen that refuses everything. Home's shortcuts asked it too, until the
/// owner took them away as the bar's lines said twice (15 Sep 2026).
///
/// [ManagementPane.receipt] is deliberately outside the authoring set: every
/// terminal prints a slip with the business's name and address on it, cloud
/// and offline alike, and only the write side needs Management's credential.
/// Since CB-08 there is no write side at all on a cloud till — the platform
/// authors the profile and the bundle carries it — and the pane still stays,
/// read-only. It is the one screen that answers "what does our receipt say",
/// with the slip drawn beside it; hiding it would leave a manager checking a
/// registration number before an audit with nowhere at the till to read it.
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
/// disappearing, and a cloud business can still say how it takes money.
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
  // Combos are menu items too, and the seeder deletes `pos_products` they
  // point at on a cloud till.
  ManagementPane.combos,
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
/// screen names the tab and says where the thing they wanted lives.
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
/// office last month searching every menu for it — and a cloud till with no
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
  BackOfficeTab.settings ||
  BackOfficeTab.account => false,
};

/// Whether [pane] is absent because this terminal does not author it — as
/// opposed to because this person may not open it, which is a different
/// sentence and one the screen already answers by falling back.
bool hiddenBecausePlatformAuthors(
  ManagementPane pane, {
  required bool authorsItsOwnCatalogue,
}) => !authorsItsOwnCatalogue && _authoringPanes.contains(pane);


/// Which tab a pane belongs to.
///
/// A total function over the enum, so a pane added without a tab fails to
/// compile rather than quietly vanishing from the bar.
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
  ManagementPane.combos => BackOfficeTab.menu,
  ManagementPane.items ||
  ManagementPane.stock ||
  ManagementPane.units => BackOfficeTab.inventory,
  ManagementPane.purchasing => BackOfficeTab.purchasing,
  ManagementPane.financeOverview ||
  ManagementPane.financeRevenue ||
  ManagementPane.financeTaxes ||
  ManagementPane.financeExpenses ||
  ManagementPane.financeDrawers ||
  ManagementPane.financeBills ||
  ManagementPane.financeTransactions ||
  ManagementPane.financeProfitLoss ||
  ManagementPane.financeAccounts ||
  ManagementPane.settlements => BackOfficeTab.finance,
  // Terminal beside Backup and the log rather than in Settings: it wipes the
  // machine, and Settings is where somebody goes to change a tax rate.
  // ETA here too, still hidden while `etaFilingEnabled` is false.
  // Dining areas & tables came here from Menu (XORD-022-B): where the tables
  // are is the till's own layout, not what the business sells.
  ManagementPane.floor ||
  ManagementPane.activity ||
  ManagementPane.backup ||
  ManagementPane.terminal ||
  ManagementPane.sync ||
  ManagementPane.eta => BackOfficeTab.system,
  ManagementPane.staff ||
  ManagementPane.roles ||
  ManagementPane.shifts => BackOfficeTab.people,
  ManagementPane.customers => BackOfficeTab.people,
  ManagementPane.receipt ||
  ManagementPane.taxes ||
  ManagementPane.charges ||
  ManagementPane.tenders ||
  ManagementPane.orderTypes ||
  ManagementPane.language ||
  ManagementPane.appearance ||
  ManagementPane.printer => BackOfficeTab.settings,
  // Who is signed in, and the version: the account menu's, not Settings'
  // (XORD-022-D).
  ManagementPane.user || ManagementPane.about => BackOfficeTab.account,
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
  BackOfficeTab.account => s.tabAccount,
};

/// Settings' own items, in the owner's map's order: each is a line in the
/// bar's Settings menu.
///
/// **Orders & invoices settings holds five panes behind a side nav**: the
/// business's General profile — the name on every slip — and the rules an
/// order and its invoice follow: order types, tax, service charges, payment
/// methods. One line for them in the bar rather than five, because the map
/// names one place; the side nav on the page is where the five are told apart.
///
/// **Language and Appearance are this terminal's**, not the business's: what
/// they hold is written to this machine's config file, not the branch
/// database. They are one card split in two (`ManagementAppearancePane`), and
/// the till's own Settings menu keeps its two quick toggles over the same
/// providers, because it is reachable without Admin Mode.
///
/// **Printer & cash drawer, User and About XOrder are panes too**, each the
/// till's own dialog content (or, for User, the session) hosted in the back
/// office. In the bar they take the place of the till's Printer and About
/// lines rather than sitting beneath them: one word per place in one menu.
/// Outside Admin Mode the till's two lines are back, opening their dialogs,
/// because none of this is reachable there (`app.dart`).
/// In the owner's map's order, which the bar reads.
enum SettingsSection { ordersAndInvoices, printer, language, appearance }

String settingsSectionName(AppStrings s, SettingsSection section) =>
    switch (section) {
      SettingsSection.ordersAndInvoices => s.settingsOrdersInvoices,
      SettingsSection.language => s.settingsLanguage,
      SettingsSection.appearance => s.settingsLook,
      SettingsSection.printer => s.printerSettingsTitle,
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
  ManagementPane.printer => SettingsSection.printer,
  ManagementPane.user ||
  ManagementPane.about ||
  ManagementPane.home ||
  ManagementPane.sales ||
  ManagementPane.shifts ||
  ManagementPane.customers ||
  ManagementPane.settlements ||
  ManagementPane.financeAccounts ||
  ManagementPane.sync ||
  ManagementPane.reports ||
  ManagementPane.reportsSales ||
  ManagementPane.reportsItems ||
  ManagementPane.reportsPayments ||
  ManagementPane.reportsBranches ||
  ManagementPane.reportsEmployees ||
  ManagementPane.menu ||
  ManagementPane.categories ||
  ManagementPane.extras ||
  ManagementPane.combos ||
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
  ManagementPane.financeTaxes ||
  ManagementPane.financeExpenses ||
  ManagementPane.financeDrawers ||
  ManagementPane.financeBills ||
  ManagementPane.financeProfitLoss ||
  ManagementPane.financeTransactions => null,
};

/// A pane's place in its tab: the order the owner's map lists them in, which
/// the bar's menus and Settings' side nav follow.
///
/// **A total switch rather than a list**, so a pane added without a place
/// fails to compile rather than sorting to wherever an absent index lands.
/// Only ever compared between panes of the same tab.
int _placeInTab(ManagementPane pane) => switch (pane) {
  ManagementPane.home => 0,
  // المبيعات: one page, with its filters and a Sales/Returns switch inside.
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
  // After the owner's: Combos has no word in the map, so it goes last rather
  // than between pages whose order was dictated.
  ManagementPane.combos => 3,
  // أصناف المخزون، المخزون المتاح، الوحدات
  ManagementPane.items => 0,
  ManagementPane.stock => 1,
  ManagementPane.units => 2,
  ManagementPane.purchasing => 0,
  // Overview and Revenue lead, ahead of the map's الخزينة، المصروفات،
  // التسويات، طرق الدفع، الضرائب, in the map's order. The map has no word for
  // either; they are this tab's own summary, first as the mockup's sub-tabs
  // had them. Folding them into Reports' Business summary was the
  // alternative, and would have made one page of two reads (BO-6's and
  // BO-9's) that disagree about what a period is. Bills due and Transactions
  // follow the map's words, kept reachable until the map places them.
  ManagementPane.financeOverview => 0,
  ManagementPane.financeRevenue => 1,
  ManagementPane.financeDrawers => 2,
  ManagementPane.financeExpenses => 3,
  ManagementPane.settlements => 4,
  ManagementPane.financeTaxes => 5,
  ManagementPane.financeBills => 6,
  ManagementPane.financeTransactions => 7,
  // After the owner's: the map has no word for it, so it goes last rather than
  // between pages whose order was dictated.
  ManagementPane.financeProfitLoss => 8,
  // Last in Finance (XORD-015): no existing page moves. The owner's map puts
  // Financial Accounts first; that is a rename-and-reorder for the owner to
  // ask for, not something to do to ten pages' positions in the same change.
  ManagementPane.financeAccounts => 9,
  // الموظفون، الأدوار والصلاحيات، الورديات
  ManagementPane.staff => 0,
  ManagementPane.roles => 1,
  ManagementPane.shifts => 2,
  // After the owner's three: the map has no word for Customers, so it goes
  // last rather than between pages whose order was dictated.
  ManagementPane.customers => 3,
  // السجل، النسخ الاحتياطي، الأجهزة، المزامنة — and ETA, hidden while filing
  // is off.
  // XORD-022: Dining areas & tables, Devices, Synchronization, Backups,
  // System logs — then ETA, hidden while filing is off.
  ManagementPane.floor => 0,
  ManagementPane.terminal => 1,
  ManagementPane.sync => 2,
  ManagementPane.backup => 3,
  ManagementPane.activity => 4,
  ManagementPane.eta => 5,
  // General first: it is the company — the name on every slip. Then the
  // rules in the order an order meets them.
  ManagementPane.receipt => 0,
  ManagementPane.orderTypes => 1,
  ManagementPane.taxes => 2,
  ManagementPane.charges => 3,
  ManagementPane.tenders => 4,
  // Then the owner's map: this machine's printer and drawer, its language and
  // look, the person in Admin Mode, and the version.
  ManagementPane.printer => 5,
  ManagementPane.language => 6,
  ManagementPane.appearance => 7,
  // The account menu's: the person, then the version.
  ManagementPane.user => 0,
  ManagementPane.about => 1,
};

/// The visible tabs, each with its visible panes in the order it shows them.
///
/// **A tab with no visible pane is absent**, as an empty area was before it:
/// a menu with no lines reads as one that failed to load. The one exception is
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

/// One item of a tab: a line in its bar menu.
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
/// **Read by the bar, and by the screen** to find which item the page on show
/// belongs to — which is how it knows to draw Settings' side nav. Read off
/// [panes], which is what [backOfficeTabsFor] allowed, so nobody is offered an
/// item they may not open.
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
/// Home is the bar's first menu and has no gate beyond the door, so this rule
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

/// The back office as the window's bar offers it: a menu per visible tab, in
/// the map's order and under the map's word, listing that tab's items.
///
/// **The owner's map, 14 Sep 2026.** BO-1 folded the bar into one Back office
/// menu with a line per tab, arguing that seven words in the bar above a strip
/// of the same tabs was the same navigation twice. The owner reversed that,
/// then drew the whole back office as one map — ten words, each with its
/// items — for the strip and the bar alike.
///
/// **The only navigation there is (15 Sep 2026).** The owner then took the
/// strip and its sub-nav off the screen, keeping this. So every page a person
/// holds is a line here or a row of Settings' side nav, and a page that is
/// neither is a page nobody can reach — `back_office_shell_test.dart` follows
/// every line to prove the first, and `managementPanesFor` is what it is held
/// to.
///
/// **The first word is Home, and it is a button, not a menu** (owner, 15 Sep
/// 2026). It was a menu of two lines: Home, saying the menu's own word again,
/// and Exit Admin Mode, which the header's button already is on every page.
/// The owner called both duplication; with Exit gone the menu would have been
/// one line repeating its title, so the word opens Home itself — the one way
/// back to the landing, now that no strip starts with it. It keeps its one
/// line in [lines], marked [ManagementBarMenu.direct], so what it opens is
/// decided here like every other line and the bar only draws it. "Back
/// office" was the other candidate for the word, and would have made the bar
/// the one place the map's first word is not said.
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
      direct: _opensDirectly(tab),
    ),
];

/// Whether a tab's word in the bar is a button rather than a menu.
///
/// Home and Sales: each holds one item, itself, so a menu under it could only
/// say its name a second time. (Sales' Invoices, Cancelled orders and Returns
/// are filters and a switch inside its page, not lines of a menu.) Every other
/// tab either holds several items or, on a cloud till, a pointer whose words
/// are not the tab's. A total switch rather than a comparison of the menu's
/// word with its line's, so a tab added later is decided here rather than by
/// whatever two strings happen to match.
bool _opensDirectly(BackOfficeTab tab) => switch (tab) {
  BackOfficeTab.home || BackOfficeTab.sales => true,
  BackOfficeTab.reports ||
  BackOfficeTab.menu ||
  BackOfficeTab.inventory ||
  BackOfficeTab.purchasing ||
  BackOfficeTab.finance ||
  BackOfficeTab.people ||
  BackOfficeTab.system ||
  BackOfficeTab.settings ||
  BackOfficeTab.account => false,
};

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
/// Opens the tab's first pane by the enum: the screen answers a pane the
/// platform authors with the tab's name and the sentence, not with the pane.
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
/// header and the bar say one word for one place. The panes' own
/// headings inside still say what they list. Receipt answers General, its
/// name in Settings' side nav.
(String, String) managementPaneLabel(
  AppStrings s,
  ManagementPane pane,
) => switch (pane) {
  ManagementPane.home => (s.tabHome, s.paneHomeBlurb),
  ManagementPane.staff => (s.paneStaff, s.paneStaffBlurb),
  // The tab's own word, as the bar says it: Sales is one page now, and the
  // header and the bar name one place with one word.
  ManagementPane.sales => (s.tabSales, s.paneSalesBlurb),
  ManagementPane.shifts => (s.paneShifts, s.shiftsBlurb),
  ManagementPane.customers => (s.paneCustomers, s.paneCustomersBlurb),
  ManagementPane.settlements => (s.paneSettlements, s.settlementsBlurb),
  ManagementPane.financeAccounts => (
    s.paneFinanceAccounts,
    s.financeAccountsBlurb,
  ),
  ManagementPane.sync => (s.paneSync, s.paneSyncBlurb),
  // Without the till line's ellipsis: here it is a page, not a dialog.
  ManagementPane.printer => (s.printerSettingsTitle, s.panePrinterBlurb),
  ManagementPane.user => (s.paneUser, s.paneUserBlurb),
  ManagementPane.about => (s.paneAbout, s.paneAboutBlurb),
  ManagementPane.reports => (s.reportsSummary, s.paneReportsBlurb),
  ManagementPane.reportsSales => (s.reportsSales, s.reportsSalesBlurb),
  ManagementPane.reportsItems => (s.reportsItems, s.reportsItemsBlurb),
  ManagementPane.reportsPayments => (
    s.reportsPaymentMethods,
    s.reportsPaymentMethodsBlurb,
  ),
  ManagementPane.reportsBranches => (s.reportsBranches, s.reportsBranchesBlurb),
  ManagementPane.reportsEmployees => (
    s.reportsEmployees,
    s.reportsEmployeesBlurb,
  ),
  ManagementPane.menu => (s.paneMenu, s.paneMenuBlurb),
  ManagementPane.categories => (s.categories, s.paneSectionsBlurb),
  ManagementPane.extras => (s.extrasTitle, s.extrasSubtitle),
  ManagementPane.combos => (s.combosTitle, s.combosSubtitle),
  ManagementPane.floor => (s.paneDining, s.floorPlanHint),
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
  ManagementPane.financeOverview => (s.financeOverview, s.financeOverviewBlurb),
  ManagementPane.financeRevenue => (s.financeRevenue, s.financeRevenueBlurb),
  ManagementPane.financeTaxes => (s.financeTaxes, s.financeTaxesBlurb),
  ManagementPane.financeExpenses => (s.financeExpenses, s.financeExpensesBlurb),
  ManagementPane.financeDrawers => (s.financeDrawers, s.financeDrawersBlurb),
  ManagementPane.financeBills => (s.financeBills, s.financeBillsBlurb),
  ManagementPane.financeTransactions => (
    s.financeTransactions,
    s.financeTransactionsBlurb,
  ),
  ManagementPane.financeProfitLoss => (
    s.financeProfitLoss,
    s.financeProfitLossBlurb,
  ),
};

/// The capabilities a pane needs beyond the door that opened the screen — all
/// of them. A set since BO-10, whose Bills due is a Finance figure and a
/// supplier-ledger read at once; a second function for "and also" would be a
/// gate `_wouldPermit` could be written without.
///
/// **Only the panes whose repositories actually enforce one appear here.**
/// Hiding a pane on a capability nothing checks would be a claim the database
/// does not back — the bar would say no while a direct write said yes. So
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
  // the tab and their own sales in it, rather than no tab. Invoices and
  // Cancelled orders are filters of that list, and the Returns view inside it
  // is scoped by the sale's seller the same way (`HistoryScope.scopeRefunds`).
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
  // Names and phone numbers beside what each person spends: the same gate as
  // the figures, asked again by `customerDirectoryProvider`.
  ManagementPane.customers => const {PosCapability.reportsView},
  // Finance (BO-9, BO-10). Backed where it counts: every figure is read
  // through `reportsAllowedProvider`, which answers no without
  // `reports.view`, so a pane reached round the bar still draws nothing.
  ManagementPane.financeOverview ||
  ManagementPane.financeRevenue ||
  ManagementPane.financeTaxes ||
  ManagementPane.financeExpenses ||
  ManagementPane.financeDrawers ||
  ManagementPane.financeProfitLoss ||
  ManagementPane.financeTransactions => const {PosCapability.reportsView},
  // Both: a Finance figure, and made of the supplier ledger that is
  // Purchasing's. Backed by `billsDueProvider`, which asks both of the
  // person acting — and, through `_authoringPanes`, absent on a cloud till.
  ManagementPane.financeBills => const {
    PosCapability.reportsView,
    PosCapability.purchaseManage,
  },
  // Read off the panes themselves, so the bar can never ask less than the
  // pane does. Backed by `shiftHistoryProvider`, which asks `reports.view` of
  // the person acting before it reads a shift.
  ManagementPane.shifts => ManagementShiftsPane.requires,
  ManagementPane.settlements => ManagementSettlementsPane.requires,
  ManagementPane.financeAccounts => ManagementAccountsPane.requires,
  // The gate the till's Settings menu puts on the printer dialog. Like
  // Terminal, nothing in the database refuses it — the printer is a file on
  // this machine — and the pane refuses without it too.
  ManagementPane.printer => const {PosCapability.terminalManage},
  // No gate beyond the door. Sync, User and About show what the till shows
  // anybody signed in. Listed rather than left to a `_`, so a pane added
  // later has to be given a gate or told it has none: a default is how a
  // gated pane ships open.
  ManagementPane.home ||
  ManagementPane.staff ||
  ManagementPane.menu ||
  ManagementPane.categories ||
  ManagementPane.extras ||
  ManagementPane.combos ||
  ManagementPane.floor ||
  ManagementPane.taxes ||
  ManagementPane.charges ||
  ManagementPane.tenders ||
  ManagementPane.orderTypes ||
  ManagementPane.receipt ||
  ManagementPane.eta ||
  ManagementPane.roles ||
  ManagementPane.activity ||
  ManagementPane.appearance ||
  ManagementPane.language ||
  ManagementPane.sync ||
  ManagementPane.user ||
  ManagementPane.about => const {},
};

bool _permits(PosStaff admin, ManagementPane pane) =>
    // `can` and not `capabilities`: the latter is the direct-grant set alone,
    // and an owner holds almost everything through their role.
    _paneRequires(pane).every(admin.can);

/// Whether [admin] would have [pane] on a till that authors it.
///
/// **Who is told where a platform-authored pane went.** The pointer stands in
/// for the pane, so it reaches the people the pane would have and nobody else:
/// a rota manager has no Purchasing offline, and xorder-cloud's sidebar hides the
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


class _ManagementScreenState extends ConsumerState<ManagementScreen> {
  /// The pane ASKED for — by the caller (the bar, through the route), a link
  /// inside a pane, or a notice. Null until something asks, which is the
  /// door's own landing. What is
  /// actually shown is worked out from this at every build, because a request
  /// can outlive the permission or the deployment that justified it.
  late ManagementPane? _pane = widget.initialPane;

  /// Which of Purchasing's tabs a Finance row asked for — its invoices for a
  /// supplier invoice, its payments for a payment. Null otherwise, and cleared
  /// by every other way of choosing a pane, so Purchasing asked for later
  /// opens where that request says, not where the row did.
  PurchasingTab? _purchasingTab;

  /// The sale Returns asked Orders to open on. Cleared by every other way of
  /// choosing a pane, as [_purchasingTab] is, so Orders picked from the bar
  /// afterwards is the plain list and not the last refund's sale.
  SaleToOpen? _openSale;

  /// Which half of the Sales page is showing: the list of sales (false) or the
  /// refunds (true). Cleared with [_openSale] by every other way of choosing a
  /// pane, so Sales picked from the bar afterwards is the plain list.
  bool _showReturns = false;

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
  /// Guarded on the OLD value rather than on `_pane`, so a manager who followed
  /// a link inside a pane — a Finance row, the backup notice — and is then
  /// rebuilt for any other reason stays where they put themselves. Only a
  /// caller changing its mind moves them.
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
        _openSale = null;
        _showReturns = false;
      });
    }
  }

  /// A pane, from inside the screen: a notice, a link one pane holds to
  /// another, Settings' side nav. Everything else arrives from
  /// the bar, through the route and [didUpdateWidget].
  void _open(ManagementPane pane) => setState(() {
    _pane = pane;
    _purchasingTab = null;
    _openSale = null;
    _showReturns = false;
  });

  /// Where a Finance row or card leads, or null when that place is not one of
  /// [panes] — and the pane then draws no link, rather than one to a pane the
  /// bar hides, which would land on Home and read as a broken link.
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
      _openSale = null;
      _showReturns = false;
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
    // The item of the tab's bar menu that the page on screen belongs to: an
    // item holding more than one page is what earns a side nav below.
    final item = backOfficeItemsFor(
      strings,
      tab,
      tabPanes,
    ).where((i) => i.holds.contains(showing)).firstOrNull;

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
            child: _paneBody(admin, showing, panes),
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
            ),
            // No tabs and no sub-nav under the header: the owner took both
            // away on 15 Sep 2026 ("no need for this, use same design only on
            // the top menu"). BO-1 had put the strip here and the owner's map
            // kept it beside the bar's menus, for being always on screen,
            // which a closed menu is not — but it was the bar's own list drawn
            // a second time, and the header's page name says where somebody
            // is. The window's bar is the way between pages now, and
            // `app.dart` keeps it up for as long as Admin Mode lasts.
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
              // page: Orders & invoices settings. The page's own navigation,
              // not the back office's, so it outlived the strip: the bar has
              // one line for the five, and without this four of them would be
              // reachable by nothing at all.
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
          ],
        ),
      ),
    );

    return AdminActivityWatch(onIdle: _lock, child: screen);
  }

  /// The Sales page: the list of sales, or the refunds, under one switch.
  ///
  /// The list is `/orders`' own widget, filtered by its status chips — Paid and
  /// Partly refunded are the invoices, Voided the cancelled orders — so there
  /// is one list to keep right rather than three. Returns stays a view of its
  /// own because a refund is a row of its own, not a status of a sale.
  ///
  /// Keyed by the sale when Returns asked for one: the history reads
  /// `openSale` once, when it is built, so a second sale needs a new state
  /// rather than a new argument. "Open the sale" moves to the list here rather
  /// than through the router, as Finance's links do.
  Widget _salesPane() {
    final Widget view = _showReturns
        ? RefundsScreen(
            onOpenSale: (sale) => setState(() {
              _showReturns = false;
              _openSale = sale;
            }),
          )
        : switch (_openSale) {
            final sale? => OrderHistoryScreen(
              key: ValueKey(sale),
              openSale: sale,
            ),
            null => const OrderHistoryScreen(),
          };
    return Column(
      children: [
        _SalesViewSwitch(
          returns: _showReturns,
          onChanged: (returns) => setState(() {
            _showReturns = returns;
            _openSale = null;
          }),
        ),
        Expanded(child: view),
      ],
    );
  }

  Widget _paneBody(
    PosStaff admin,
    ManagementPane pane,
    List<ManagementPane> panes,
  ) => switch (pane) {
    // No links out of Home: its cards and shortcuts were the status bar and
    // the window's bar said twice, and the owner took them away (15 Sep 2026).
    ManagementPane.home => ManagementHomePane(admin: admin),
    // `/orders`' own widget, not a second screen over the same rows (BO-2).
    // No way out of its own: the back office's Exit and Esc are the way out.
    // Whose sales it lists follows [admin] through `actingStaffProvider`, not
    // the cashier who may still be signed in at the till behind this.
    //
    // Invoices and Cancelled orders are its status filters, and Returns is the
    // other half of the switch above it — one page, not a menu of near-copies.
    ManagementPane.sales => _salesPane(),
    ManagementPane.shifts => ManagementShiftsPane(admin: admin),
    ManagementPane.customers => const ManagementCustomersPane(),
    ManagementPane.settlements => ManagementSettlementsPane(admin: admin),
    ManagementPane.financeAccounts => ManagementAccountsPane(admin: admin),
    ManagementPane.sync => ManagementSyncPane(admin: admin),
    ManagementPane.printer => ManagementPrinterPane(admin: admin),
    // The pane ends the session itself, so `_exit`'s own end is a no-op and
    // the audit row still says "exited". Its count of permissions leads to
    // Roles only for somebody who has that pane.
    ManagementPane.user => ManagementUserPane(
      admin: admin,
      onExit: _exit,
      onOpenRoles: panes.contains(ManagementPane.roles)
          ? () => _open(ManagementPane.roles)
          : null,
    ),
    ManagementPane.about => ManagementAboutPane(admin: admin),
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
    ManagementPane.menu => ManagementMenuPane(
      admin: admin,
      onOpenExtras: () => _open(ManagementPane.extras),
    ),
    // Its own page now: the sections alone, with how many items each holds.
    ManagementPane.categories => ManagementMenuPane(
      admin: admin,
      mode: MenuPaneMode.sections,
    ),
    ManagementPane.extras => ManagementExtrasPane(admin: admin),
    ManagementPane.combos => ManagementCombosPane(admin: admin),
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
    // pane the bar hides would be a door to the landing.
    ManagementPane.receipt => ManagementReceiptPane(
      admin: admin,
      leading: [BusinessLogoCard(admin: admin)],
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
    ManagementPane.language => ManagementAppearancePane(
      part: AppearancePart.language,
      admin: admin,
    ),
    ManagementPane.appearance => const ManagementAppearancePane(
      part: AppearancePart.theme,
    ),
    ManagementPane.eta => const ManagementEtaPane(),
    ManagementPane.roles => ManagementRolesPane(admin: admin),
    ManagementPane.activity => const ManagementActivityPane(),
    ManagementPane.backup => ManagementBackupPane(admin: admin),
    ManagementPane.items => ManagementItemsPane(admin: admin),
    ManagementPane.stock => ManagementStockPane(admin: admin),
    ManagementPane.units => ManagementUnitsPane(admin: admin),
    ManagementPane.terminal => ManagementTerminalPane(
      admin: admin,
      onReconfigure: widget.onReconfigure,
    ),
    ManagementPane.financeOverview => FinanceOverviewPane(
      links: (target) => _financeLink(target, panes),
    ),
    ManagementPane.financeRevenue => const FinanceRevenuePane(),
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
    ManagementPane.financeProfitLoss => const FinanceProfitLossPane(),
  };
}

/// Sales / Returns, above the Sales page: the two views of it, as the history's
/// own filter chips are drawn, so the switch reads as part of the page.
class _SalesViewSwitch extends StatelessWidget {
  const _SalesViewSwitch({required this.returns, required this.onChanged});

  final bool returns;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        PosSpace.s18,
        PosSpace.md,
        PosSpace.s18,
        0,
      ),
      child: Row(
        children: [
          HistoryFilterChip(
            key: const Key('sales-view-sales'),
            label: strings.tabSales,
            selected: !returns,
            onTap: () => onChanged(false),
          ),
          const SizedBox(width: PosSpace.sm),
          HistoryFilterChip(
            key: const Key('sales-view-returns'),
            label: strings.paneReturns,
            selected: returns,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title});

  /// Which page this is, by the pane's name. With no strip under it, this is
  /// the one thing on screen saying where somebody is — and somebody arriving
  /// from the bar needs the page confirmed, not the menu they chose it from.
  ///
  /// No button of its own: the way out of Admin Mode is Log out at the end of
  /// the window's bar (`app.dart`), Esc, and the User pane.
  final String title;

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
            // The page's bare name, so the same word also sits in the bar:
            // tests find the header by this.
            key: const Key('back-office-title'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PosText.screenTitle(color: context.pos.ink),
          ),
        ),
      ],
    ),
  );
}

/// Settings' side nav, for Orders & invoices settings: its five panes, on the
/// start side.
///
/// **The page's own navigation, not the back office's.** The bar gives the
/// group one line, for the one place the owner's map names, so this is where
/// its five are told apart — which is why it stayed when the strip and sub-nav
/// went (15 Sep 2026). Five lines in the bar instead was the alternative, and
/// would have made Settings' menu the one that no longer reads as the map.
///
/// A column, at [PosSize.settingsNav]: it leaves 868 px for a pane at the 1100
/// breakpoint. No headings: the header names the page, and five rows need no
/// grouping.
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
