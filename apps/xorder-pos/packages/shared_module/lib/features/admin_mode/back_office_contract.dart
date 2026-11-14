/// The back office as the shared shell knows it (pos-split-apps, stage 3).
///
/// The router opens it behind `PosRoutes.management`, the window bar draws
/// its menus, the start screen deep-links to one of its panes, and the Admin
/// Mode door guards it — all of that is shared code. The panes themselves are
/// not: they are the offline app's (`apps/xorder_pos_offline`), and the cloud
/// app has none (CB-07), only a signpost to the dashboard. So the shell holds
/// the **names** here — which panes exist, which tab each sits under, and
/// what a destination is — and asks `backOfficeProvider` for the rest.
///
/// The enums were lifted out of `management_screen.dart` unchanged; the rules
/// that read them (`tabOf`, `managementPanesFor`, `managementBarFor`) stayed
/// there, in the one app that has panes to show.
library;

import 'package:flutter/widgets.dart';

import '../../core/l10n/app_strings.dart';
import '../../domain/models/shift.dart' show PosStaff;

/// What the shell asks of a back office. Bound per app by `backOfficeProvider`.
abstract interface class BackOffice {
  /// The screen behind `PosRoutes.management`.
  Widget screen(
    BuildContext context, {
    required ManagementDestination destination,
    required VoidCallback onClose,
    required VoidCallback onReconfigure,
  });

  /// The window bar's back-office menus for [admin], who is in Admin Mode.
  /// Empty when there is no back office to offer.
  List<ManagementBarMenu> barMenus(
    AppStrings s, {
    required PosStaff admin,
    required bool authorsItsOwnCatalogue,
  });
}

/// No back office at all: the shared package on its own. Each app binds a
/// real one in its `main`; a test harness that never opens Management can
/// live with this.
final class NoBackOffice implements BackOffice {
  const NoBackOffice();

  @override
  Widget screen(
    BuildContext context, {
    required ManagementDestination destination,
    required VoidCallback onClose,
    required VoidCallback onReconfigure,
  }) => const SizedBox.shrink();

  @override
  List<ManagementBarMenu> barMenus(
    AppStrings s, {
    required PosStaff admin,
    required bool authorsItsOwnCatalogue,
  }) => const [];
}

/// The back office, in tabs — the owner's map of 14 Sep 2026: ten words, in
/// this order, each a menu of the window's bar.
///
/// **A model, no longer drawn on screen.** A strip of these words ran across
/// the top of the back office, with a row of the chosen tab's items under it,
/// until the owner took both away on 15 Sep 2026 ("no need for this, use same
/// design only on the top menu"): the bar already said the same list one
/// level deeper, and two navigations saying one thing are two to keep in step.
/// Keeping the strip because it is always on screen, which a closed menu is
/// not, was the argument for it; the header's page name is what answers
/// "where am I" now. The tabs remain what the bar is built from, what a deep
/// link is checked against, and the header's word for a pointer tab.
///
/// **Every tab holds a pane.** Home has had its pane since BO-4 and Sales the
/// order history since BO-2, both for everybody past the door; Reports has had
/// its one pane since BO-6 and Finance its panes since BO-9, both for whoever
/// holds `reports.view`. They were members before their slices, rather than
/// added with them, so that the order is decided once, here, and so that
/// [backOfficeTabName] and the bar's width test carry every word — a word
/// arriving with a slice is how a bar that fitted at 1100 px stops fitting
/// without anybody measuring it.
///
/// Replaces the seven areas of the flat bar. Money went to Settings (rules
/// about money are configuration; *Finance* is money that moved) and
/// Compliance dissolved into Settings and System. **People is a tab again**:
/// BO-1 filed Users and Roles under Settings, as the cloud does; the owner's
/// map gives them a tab of their own, with Shifts beside them.
enum BackOfficeTab {
  /// The landing page (BO-4): a greeting, and today's takings.
  home,

  /// The order history, re-hosted by BO-2.
  sales,

  /// BO-5's read model drawn by BO-6.
  reports,

  /// What the business sells.
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

  /// The business's configuration, and the people who work there.
  settings,

  /// Who is signed in, and what to do about it (XORD-022-D): their name, who
  /// is in Admin Mode, and About. **Not drawn as a menu of its own word**: the
  /// bar's account menu carries the person's name, and `app.dart` joins these
  /// lines to the till's own (Switch user, Lock, Log out).
  account,
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

  /// The same destination, going back to [route].
  ///
  /// For a bar line, which knows the pane it opens and not where the back
  /// office was entered from: without this, the first line chosen replaced
  /// the route's [returnTo] with null, and Exit went to the start screen from
  /// a back office opened at the till.
  ManagementDestination returningTo(String? route) => ManagementDestination(
    pane: pane,
    returnTo: route,
    purchasingTab: purchasingTab,
    create: create,
    request: request,
  );
}


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
///
/// [direct] when the bar draws the word as a button that opens the one line
/// itself, with no menu under it — see [managementBarFor]. The line is still
/// here, so every rule and walk that reads [lines] reads Home's too.
typedef ManagementBarMenu = ({
  BackOfficeTab tab,
  String label,
  List<ManagementBarEntry> lines,
  bool direct,
});

/// The four halves of buying. Public so a menu can open the one it means.
enum PurchasingTab { orders, suppliers, invoices, payments }

enum ManagementPane {
  /// The landing page. A pane like the others rather than a special case in
  /// the shell, so it is in [managementPanesFor] — and so the bar and the
  /// table-driven test in `back_office_shell_test.dart` see it as they
  /// see every other page. No gate: it shows each person only what they hold.
  home,
  staff,
  menu,
  extras,
  combos,
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
  /// index moves; the bar orders tabs by [BackOfficeTab], not by this.
  sales,

  /// BO-5's figures, drawn as the Reports tab (BO-6). Last, for the same
  /// reason as [sales].
  reports,
  /// Finance (BO-9). The bar orders these and BO-10's by `_placeInTab`, the
  /// map's order, not by their places here.
  financeOverview,
  financeRevenue,
  financeTaxes,

  /// Finance (BO-10). Last, for the same reason as [sales].
  financeExpenses,
  financeDrawers,
  financeBills,
  financeTransactions,

  /// Finance › Profit & loss: the period as one statement, behind
  /// `reports.view` like every Finance figure it is made of.
  financeProfitLoss,

  /// Menu › Categories (the owner's map): the menu pane again. It has no
  /// categories-only mode — its categories are the list down its start side,
  /// where they are added, renamed and archived — so this item opens the same
  /// pane, under the word somebody looking for a category reaches for. Last,
  /// for the same reason as [sales].
  categories,

  /// Settings › Language (the owner's map): the language half of the card
  /// [appearance] shows the other half of. Last, for the same reason.
  language,

  /// People › Customers: the directory with what each has bought, behind
  /// `reports.view` because it sets a name and a phone number beside spending.
  customers,

  /// People › Shifts and Finance › Settlements, both behind `reports.view`.
  shifts,
  settlements,

  /// System › Sync.
  sync,

  /// Settings › Printer & cash drawer, User and About XOrder.
  printer,
  user,
  about,

  /// Reports' five breakdowns (the owner's map): Business summary's figures,
  /// each as a page of its own over the period all six share. Last, for the
  /// same reason as [sales]; `_placeInTab` puts them in the map's order.
  reportsSales,
  reportsItems,
  reportsPayments,
  reportsBranches,
  reportsEmployees,

  /// Finance › Accounts (XORD-015): the business's cash, bank and wallet
  /// accounts and the account each payment method pays into. Last, for the same
  /// reason as [sales]: no other pane's index moves.
  financeAccounts,

  /// People › Waiter shifts: the XOrder Waiter handheld's shift clock, behind
  /// `reports.view` as People › Shifts is. Last, for the same reason as
  /// [sales]; `_placeInTab` puts it right after Shifts.
  waiterShifts,
}
