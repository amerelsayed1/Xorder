import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
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
    this.initialPane = ManagementPane.staff,
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
  final ManagementPane initialPane;

  /// Passed through to Purchasing — see [ManagementDestination].
  final PurchasingTab? purchasingTab;
  final bool create;
  final Object? request;

  @override
  ConsumerState<ManagementScreen> createState() => _ManagementScreenState();
}

/// The panes, public so a caller can name the one it means.
/// [receipt] is deliberately outside the authoring set: every terminal prints
/// a slip with the restaurant's name and address on it, cloud and offline
/// alike, and only the write side needs Management's credential.
/// Which panes this terminal and this person actually have.
///
/// **Public, and the only answer.** The rail asked this and so does the Manage
/// menu, and two lists that were meant to agree are two lists that will not —
/// a menu offering Purchasing to somebody the rail hides it from would take
/// them to a screen that refuses everything.
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
/// on Staff would read as the pane having broken; landing on Purchasing is not
/// possible, because it is not this terminal's to show. So the screen lands
/// on its first pane and says where the thing they wanted lives.
///
/// Over the area rather than the pane, so a buying or inventory pane added
/// later is covered without being remembered here. Menu and Floor answer null
/// on purpose: nothing links to them on a cloud till, and each already says
/// it comes from the platform inside its own pane.
String? platformAuthoredPointer(AppStrings s, ManagementPane pane) =>
    switch (areaOf(pane)) {
      ManagementArea.buying ||
      ManagementArea.inventory => s.purchasingComesFromPlatform,
      ManagementArea.people ||
      ManagementArea.menu ||
      ManagementArea.money ||
      ManagementArea.compliance ||
      ManagementArea.system => null,
    };

/// Whether [pane] is absent because this terminal does not author it — as
/// opposed to because this person may not open it, which is a different
/// sentence and one the screen already answers by falling back.
bool hiddenBecausePlatformAuthors(
  ManagementPane pane, {
  required bool authorsItsOwnCatalogue,
}) => !authorsItsOwnCatalogue && _authoringPanes.contains(pane);

/// The back office, in areas.
///
/// **Added because the rail ran out of room.** Nine flat items already reached
/// the bottom of a 900px window; the four editors Wave D still owes — taxes,
/// service charges, payment methods, order types — would have pushed it off the
/// screen, and a navigation you have to scroll to discover is a navigation that
/// hides half the product.
///
/// Areas rather than one long list for a second reason: they are how somebody
/// thinks about the job. "Where do I change the VAT rate" is answered by *Money*
/// long before it is answered by reading eleven pane names.
enum ManagementArea {
  /// Who works here and what they may do.
  people,

  /// What the restaurant sells.
  menu,

  /// What it charges, and how it takes it.
  money,

  /// What it buys, and who it owes.
  buying,

  /// What it keeps, and what it is counted in.
  inventory,

  /// What the tax authority sees.
  compliance,

  /// Everything about how this till behaves.
  system,
}

/// Which area a pane belongs to.
///
/// A total function over the enum, so a pane added without an area fails to
/// compile rather than quietly vanishing from the rail.
ManagementArea areaOf(ManagementPane pane) => switch (pane) {
  ManagementPane.staff || ManagementPane.roles => ManagementArea.people,
  ManagementPane.menu ||
  ManagementPane.extras ||
  ManagementPane.floor => ManagementArea.menu,
  ManagementPane.taxes ||
  ManagementPane.charges ||
  ManagementPane.tenders ||
  ManagementPane.orderTypes => ManagementArea.money,
  ManagementPane.purchasing => ManagementArea.buying,
  ManagementPane.receipt || ManagementPane.eta => ManagementArea.compliance,
  ManagementPane.activity ||
  ManagementPane.backup ||
  ManagementPane.terminal => ManagementArea.system,
  ManagementPane.items ||
  ManagementPane.stock ||
  ManagementPane.units => ManagementArea.inventory,
};

String managementAreaName(AppStrings s, ManagementArea area) => switch (area) {
  ManagementArea.people => s.areaPeople,
  ManagementArea.menu => s.areaMenu,
  ManagementArea.money => s.areaMoney,
  ManagementArea.buying => s.areaBuying,
  ManagementArea.inventory => s.areaInventory,
  ManagementArea.compliance => s.areaCompliance,
  ManagementArea.system => s.areaSystem,
};

/// The visible panes, grouped, in area order and pane order within each.
///
/// Empty areas are absent rather than shown with nothing under them — a heading
/// over a gap reads as a pane that failed to load.
List<(ManagementArea, List<ManagementPane>)> managementAreasFor({
  required PosStaff admin,
  required bool authorsItsOwnCatalogue,
}) {
  final panes = managementPanesFor(
    admin: admin,
    authorsItsOwnCatalogue: authorsItsOwnCatalogue,
  );
  return [
    for (final area in ManagementArea.values)
      if ([for (final p in panes) if (areaOf(p) == area) p] case final own
          when own.isNotEmpty)
        (area, own),
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
    required this.pane,
    this.returnTo,
    this.purchasingTab,
    this.create = false,
    this.request,
  });

  final ManagementPane pane;

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

/// What the menu bar offers under one pane.
///
/// Usually the pane itself. Purchasing is really four things — orders, the
/// invoices that arrive against them, the payments that settle those, and the
/// suppliers behind all three — and "where do I enter this invoice" is answered
/// by an invoice, not by a pane that holds a tab of them. So it lists each,
/// with the "new" that starts one beside the list it belongs to.
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
  _ => [
    (
      managementPaneLabel(s, pane).$1,
      () => ManagementDestination(pane: pane, request: Object()),
      true,
    ),
  ],
};

/// One line under an area in the window's bar.
///
/// [pane] is null for a line that is not a pane — the pointer a cloud till
/// shows under Buying. [first] is the pane's own first line; [divider] is
/// drawn above this line.
typedef ManagementBarEntry = ({
  ManagementPane? pane,
  bool first,
  String label,
  ManagementDestination Function() open,
  bool divider,
});

/// The back office as the window's bar offers it: one menu per area.
///
/// **Here rather than in the bar, so the two cannot drift.** The rail and the
/// bar were already one answer through [managementAreasFor]; what the bar did
/// on top of it — expanding panes into [managementMenuEntries] — lived in
/// `app.dart`, where a test of the rule could not see it. Now the rule and its
/// test sit beside each other, and the bar only draws.
///
/// **Buying stays a word in the bar on a cloud till**, holding one line that
/// says where purchasing went. That is not a pane and opens none: it is a
/// deep link to Purchasing, which the screen answers with
/// [platformAuthoredPointer] above its first pane. Dropping the word instead
/// would leave a manager who bought through this bar last month searching
/// every menu for it — and a cloud till with no word for buying at all tells
/// them nothing about where it went.
List<(ManagementArea, List<ManagementBarEntry>)> managementBarFor(
  AppStrings s, {
  required PosStaff admin,
  required bool authorsItsOwnCatalogue,
}) {
  final areas = {
    for (final (area, panes) in managementAreasFor(
      admin: admin,
      authorsItsOwnCatalogue: authorsItsOwnCatalogue,
    ))
      area: panes,
  };
  return [
    for (final area in ManagementArea.values)
      if (<ManagementBarEntry>[
        for (final pane in areas[area] ?? const <ManagementPane>[])
          for (final (i, (label, open, groups))
              in managementMenuEntries(s, pane).indexed)
            (
              pane: pane,
              first: i == 0,
              label: label,
              open: open,
              divider: groups && i > 0,
            ),
        if (area == ManagementArea.buying &&
            hiddenBecausePlatformAuthors(
              ManagementPane.purchasing,
              authorsItsOwnCatalogue: authorsItsOwnCatalogue,
            ))
          (
            pane: null,
            first: true,
            label: s.purchasingOnPlatformEntry,
            open: () => ManagementDestination(
              pane: ManagementPane.purchasing,
              request: Object(),
            ),
            divider: false,
          ),
      ] case final entries when entries.isNotEmpty)
        (area, entries),
  ];
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
(String, String) managementPaneLabel(AppStrings s, ManagementPane pane) =>
    switch (pane) {
      ManagementPane.staff => (s.paneStaff, s.paneStaffBlurb),
      ManagementPane.menu => (s.paneMenu, s.paneMenuBlurb),
      ManagementPane.extras => (s.extrasTitle, s.extrasSubtitle),
      ManagementPane.floor => (s.floorPlan, s.floorPlanHint),
        ManagementPane.taxes => (s.paneTaxes, s.paneTaxesHint),
      ManagementPane.charges => (s.serviceCharges, s.serviceChargesHint),
      ManagementPane.tenders => (s.tenderTypes, s.tenderTypesHint),
      ManagementPane.orderTypes => (s.orderTypes, s.orderTypesHint),
      ManagementPane.purchasing => (s.panePurchasing, s.panePurchasingBlurb),
      ManagementPane.receipt => (s.paneReceipt, s.paneReceiptBlurb),
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
/// does not back — the rail would say no while a direct write said yes. So
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
  late ManagementPane _pane = widget.initialPane;

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
  /// pane from the rail and is then rebuilt for any other reason stays where
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
    // not a count, not the bar's areas. The shortcut that led here is a hidden
    // way in, not a lock; this is the lock.
    if (admin == null) {
      return AdminSignInView(
        onClose: widget.onClose,
        lockedAfterMinutes: _lockedAfter,
      );
    }

    final authors = ref.watch(catalogAdminRepositoryProvider) != null;
    final areas = managementAreasFor(
      admin: admin,
      authorsItsOwnCatalogue: authors,
    );
    final panes = [for (final area in areas) ...area.$2];

    // A pane this terminal or this person does not have is not a pane the body
    // may render: `initialPane` is a deep link and a deep link can outlive the
    // permission that justified it.
    final showing = panes.contains(_pane) ? _pane : panes.first;

    // …and when it is absent because the platform authors it, the fall-back
    // says so. Keyed on `_pane`, the pane ASKED for, so it is said once, on
    // arrival: the next request from the bar moves `_pane` (see
    // `didUpdateWidget`) and the sentence goes with it.
    final pointer =
        !panes.contains(_pane) &&
            hiddenBecausePlatformAuthors(
              _pane,
              authorsItsOwnCatalogue: authors,
            )
        ? platformAuthoredPointer(context.strings, _pane)
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
            context.strings,
            ref.watch(backupsProvider).valueOrNull,
            DateTime.now(),
          )
        : null;

    final screen = Scaffold(
      backgroundColor: context.pos.page,
      body: SafeArea(
        child: Column(
          children: [
            // No tabs: every pane is a page of its own. The window's bar names
            // every area and every pane, so a strip of the current area's
            // neighbours across the top was the same navigation twice.
            _Header(
              admin: admin,
              onClose: _exit,
              pane: showing,
            ),
            if (ref.watch(schemaUpgradeFailureProvider) case final failure?)
              _SchemaNotice(text: context.strings.schemaUpgradeFailed(failure)),
            if (backupNotice != null)
              _BackupNotice(
                text: backupNotice,
                onOpen: () => setState(() => _pane = ManagementPane.backup),
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
              child: switch (showing) {
                ManagementPane.staff => ManagementStaffPane(admin: admin),
                // The item editor's "Manage extras" link. Moved here rather
                // than through the router: this screen already owns which
                // pane is showing, as the backup notice's button does.
                ManagementPane.menu => ManagementMenuPane(
                  admin: admin,
                  onOpenExtras: () =>
                      setState(() => _pane = ManagementPane.extras),
                ),
                ManagementPane.extras => ManagementExtrasPane(admin: admin),
                ManagementPane.floor => ManagementFloorPane(admin: admin),
                ManagementPane.taxes => ManagementTaxesPane(
                  admin: admin,
                ),
                ManagementPane.charges => ManagementChargesPane(
                  admin: admin,
                ),
                ManagementPane.tenders => ManagementTendersPane(
                  admin: admin,
                ),
                ManagementPane.orderTypes => ManagementOrderTypesPane(
                  admin: admin,
                ),
                ManagementPane.purchasing => ManagementPurchasingPane(
                  admin: admin,
                  initialTab: widget.purchasingTab ?? PurchasingTab.orders,
                  create: widget.create,
                  request: widget.request,
                ),
                ManagementPane.receipt => ManagementReceiptPane(
                  admin: admin,
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
              },
            ),
          ],
        ),
      ),
    );

    return AdminActivityWatch(onIdle: _lock, child: screen);
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.admin,
    required this.onClose,
    required this.pane,
  });

  final PosStaff admin;
  final VoidCallback onClose;

  /// Which page this is. With no rail and no tabs, the header is the one thing
  /// on screen that says so — and the page, not its area, is what somebody
  /// arriving from the bar needs confirmed.
  final ManagementPane pane;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: PosSpace.xl),
      decoration: BoxDecoration(
        color: context.pos.surface,
        border: Border(bottom: context.pos.resting),
      ),
      child: Row(
        children: [
          Text(
            strings.adminTitle(managementPaneLabel(strings, pane).$1),
            style: PosText.screenTitle(color: context.pos.ink),
          ),
          const SizedBox(width: PosSpace.lg),
          Text(
            '${admin.name} · '
            '${admin.role?.displayName(strings.languageCode) ?? strings.noRole}',
            style: PosText.ui(size: 13, color: context.pos.muted),
          ),
          const Spacer(),
          PosButton(
            key: const Key('admin-exit'),
            label: strings.exitAdminMode,
            border: Border.fromBorderSide(context.pos.resting),
            onPressed: onClose,
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
