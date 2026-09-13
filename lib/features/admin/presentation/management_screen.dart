import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../data/postgres/pos_database.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/permissions.dart';
import '../../../domain/models/shift.dart';
import '../../../domain/services/authorization.dart';
import 'admin_pane_bits.dart';
import 'management_activity_pane.dart';
import 'management_backup_pane.dart';
import 'management_items_pane.dart';
import 'management_stock_pane.dart';
import 'management_units_pane.dart';
import 'management_floor_pane.dart';
import 'management_menu_pane.dart';
import 'management_eta_pane.dart';
import 'management_charges_pane.dart';
import 'management_order_types_pane.dart';
import 'management_taxes_pane.dart';
import 'management_tenders_pane.dart';
import 'management_purchasing_pane.dart';
import 'management_receipt_pane.dart';
import 'management_roles_pane.dart';
import 'management_staff_pane.dart';

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
    this.initialPane = ManagementPane.staff,
    this.purchasingTab,
    this.create = false,
    this.request,
    super.key,
  });

  final VoidCallback onClose;

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
  ManagementPane.menu || ManagementPane.floor => ManagementArea.menu,
  ManagementPane.taxes ||
  ManagementPane.charges ||
  ManagementPane.tenders ||
  ManagementPane.orderTypes => ManagementArea.money,
  ManagementPane.purchasing => ManagementArea.buying,
  ManagementPane.receipt || ManagementPane.eta => ManagementArea.compliance,
  ManagementPane.activity || ManagementPane.backup => ManagementArea.system,
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
/// shows under Buying. [first] is the pane's own first line, which is where
/// the bar prints F8 for Staff; [divider] is drawn above this line.
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
  // deliberately outside supervisor override. `reports.view` and
  // `terminal.manage` still have none.
  //
  // Unlike Purchasing, this pane's gate is not backed by a repository that
  // refuses — `pos_backups` is granted INSERT to the till so the automatic copy
  // at day close can be recorded without anybody being in the back office. What
  // the gate protects is the two buttons: taking one on demand, and restoring.
  // Both go through `BackupService`, which is only ever reached from here.
  ManagementPane.backup => PosCapability.backupManage,
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
}

class _ManagementScreenState extends ConsumerState<ManagementScreen> {
  late ManagementPane _pane = widget.initialPane;

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
    final admin = ref.watch(signedInStaffProvider);

    // One door: the administrator's username and the back-office password.
    //
    // **The password is the database's, not a person's.** The till credential
    // holds SELECT and nothing more, deliberately, so nothing here can save
    // until the back office's own password is supplied — and it is held for
    // the session and never written to disk: on the same machine as the till's
    // password it would hand back everything the split protects.
    //
    // Watched rather than read once: a manager whose role is changed from
    // another till mid-session loses the screen on the next frame, which is
    // the same answer the database would give the next time they saved.
    if (admin == null ||
        !admin.can(PosCapability.staffManage) ||
        ref.watch(adminDbCredentialProvider) == null) {
      return _BackOfficeSignIn(
        onClose: widget.onClose,
        username: admin?.username,
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
    // arrival: picking a tab moves `_pane` and the sentence goes with it.
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

    // The panes of the area you are in — the tabs across the top.
    final areaPanes = [
      for (final (area, own) in areas)
        if (area == areaOf(showing)) ...own,
    ];

    return Scaffold(
      backgroundColor: context.pos.page,
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              admin: admin,
              onClose: widget.onClose,
              area: areaOf(showing),
            ),
            // Tabs only where there is more than one pane. A single tab over a
            // single pane is a heading dressed as a control, and the header
            // already says where you are.
            if (areaPanes.length > 1)
              _AreaTabs(
                panes: areaPanes,
                current: showing,
                onPick: (pane) => setState(() => _pane = pane),
              ),
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
                ManagementPane.menu => ManagementMenuPane(admin: admin),
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
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.admin,
    required this.onClose,
    required this.area,
  });

  final PosStaff admin;
  final VoidCallback onClose;

  /// Where you are. The rail used to say so by highlighting a row; with the
  /// rail gone the header has to, or the bar's area and the pane's tabs are
  /// two answers to a question nobody asked out loud.
  final ManagementArea area;

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
            '${strings.management} › ${managementAreaName(strings, area)}',
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
            label: strings.backToTill,
            border: Border.fromBorderSide(context.pos.resting),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

/// The panes of one area, as tabs across the top of the screen.
///
/// **Replaces a rail that listed all thirteen.** The window's bar now names
/// every area and every pane, so a second full index down the side of the
/// screen was the same navigation twice, spending a quarter of the width on it.
/// What is left to show here is only the neighbours of where you are — the
/// other panes of the same area, which is what somebody switching between the
/// VAT rate and the service charge actually wants one tap away.
class _AreaTabs extends StatelessWidget {
  const _AreaTabs({
    required this.panes,
    required this.current,
    required this.onPick,
  });

  final List<ManagementPane> panes;
  final ManagementPane current;
  final ValueChanged<ManagementPane> onPick;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: PosSpace.xl,
        vertical: PosSpace.md,
      ),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(bottom: palette.hairline),
      ),
      // Scrollable rather than wrapping: a row of tabs that breaks onto a
      // second line stops reading as one choice.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final pane in panes) ...[
              // The sentence the rail used to carry, where it still helps: on
              // a pointer that lingers.
              Tooltip(
                message: managementPaneLabel(strings, pane).$2,
                waitDuration: const Duration(milliseconds: 600),
                child: PosButton(
                  key: Key('management-tab-${pane.name}'),
                  label: managementPaneLabel(strings, pane).$1,
                  background:
                      pane == current ? palette.ink : Colors.transparent,
                  foreground: pane == current ? palette.onInk : null,
                  border: Border.fromBorderSide(palette.resting),
                  onPressed: () => onPick(pane),
                ),
              ),
              const SizedBox(width: PosSpace.sm),
            ],
          ],
        ),
      ),
    );
  }
}

/// The back office's one door: the administrator's username and the
/// back-office password — the database administrator password set when this
/// install was made. No PIN: PINs are for the till.
///
/// **Checked against the database the first time in a session**, then against
/// the password already held — so a second manager signing in after the first
/// is not another round trip, and a wrong one is refused all the same.
///
/// One refusal for every way in being wrong: an unknown username, a cashier's,
/// and a wrong password all read the same, so the form is no way of finding
/// out who the managers are.
class _BackOfficeSignIn extends ConsumerStatefulWidget {
  const _BackOfficeSignIn({required this.onClose, this.username});

  final VoidCallback onClose;

  /// Whoever is signed in at the till, offered as the name to sign in under.
  final String? username;

  @override
  ConsumerState<_BackOfficeSignIn> createState() => _BackOfficeSignInState();
}

class _BackOfficeSignInState extends ConsumerState<_BackOfficeSignIn> {
  late final _username = TextEditingController(text: widget.username ?? '');
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  /// The active staff member [username] names, if they may manage staff.
  Future<PosStaff?> _manager(String username) async {
    try {
      final everyone = await ref
          .read(staffDirectoryRepositoryProvider)
          .all(includeInactive: false);
      for (final person in everyone) {
        if (person.username?.toLowerCase() == username.toLowerCase() &&
            Authorization.check(person, PosCapability.staffManage).isAllowed) {
          return person;
        }
      }
    } on Object {
      // Unreadable is refused like unknown. The password check below says
      // whether the database is reachable at all.
    }
    return null;
  }

  Future<void> _submit() async {
    final username = _username.text.trim();
    final password = _password.text;
    if (username.isEmpty || password.isEmpty || _busy) return;

    final strings = context.strings;
    setState(() {
      _busy = true;
      _error = null;
    });

    final held = ref.read(adminDbCredentialProvider);
    PosDbFailure? failure;
    if (held != null) {
      failure = held == password ? null : PosDbFailure.auth;
    } else {
      // Tried before it is accepted: a password that was merely stored would
      // fail later, on the first save, after somebody had typed a whole staff
      // record.
      ref.read(adminDbCredentialProvider.notifier).set(password);
      failure = await ref
          .read(adminPosDatabaseProvider)
          .probe(ref.read(adminDeploymentProvider));
    }
    final staff = failure == null ? await _manager(username) : null;
    if (!mounted) return;

    if (staff != null) {
      // The screen rebuilds on the far side of the door.
      ref.read(signedInStaffProvider.notifier).signIn(staff);
      return;
    }

    if (held == null) ref.read(adminDbCredentialProvider.notifier).forget();
    _password.clear();
    setState(() {
      _busy = false;
      _error = switch (failure) {
        PosDbFailure.dns || PosDbFailure.tcp => strings.backOfficeUnreachable,
        null || PosDbFailure.auth => strings.backOfficeSignInRefused,
        _ => strings.backOfficeRefused,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final pos = context.pos;

    return Scaffold(
      backgroundColor: pos.shell,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(PosSpace.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  strings.management,
                  style: PosText.screenTitle(color: pos.shellText),
                ),
                const SizedBox(height: PosSpace.sm),
                Text(
                  strings.backOfficeSignInHelp,
                  style: PosText.ui(
                    size: 13,
                    color: pos.shellMuted,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: PosSpace.xl),
                UsernameField(
                  key: const Key('back-office-username'),
                  controller: _username,
                  onSubmitted: _passwordFocus.requestFocus,
                ),
                const SizedBox(height: PosSpace.lg),
                MicroLabel(strings.backOfficePassword),
                const SizedBox(height: PosSpace.sm),
                TextField(
                  key: const Key('back-office-password'),
                  controller: _password,
                  focusNode: _passwordFocus,
                  obscureText: true,
                  enabled: !_busy,
                  onSubmitted: (_) => _submit(),
                  textAlign: TextAlign.center,
                  style: PosText.mono(size: 16, color: pos.shellText),
                  cursorColor: pos.accent,
                  decoration: shellInputDecoration(pos),
                ),
                // Reserved, not conditional, so the button does not jump
                // under a finger already on its way to it.
                const SizedBox(height: PosSpace.md),
                SizedBox(
                  height: 36,
                  child: _error == null
                      ? null
                      : Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: PosText.ui(size: 12.5, color: pos.danger),
                        ),
                ),
                const SizedBox(height: PosSpace.sm),
                PosButton(
                  key: const Key('back-office-open'),
                  label: _busy ? strings.checking : strings.openManagement,
                  background: pos.accent,
                  foreground: pos.onAccent,
                  onPressed: _busy ? null : _submit,
                ),
                const SizedBox(height: PosSpace.md),
                PosButton(
                  label: strings.backToTill,
                  foreground: pos.shellText,
                  border: Border.fromBorderSide(pos.shellBorder),
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The back office's backup warning: what is wrong, and the way to it.
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
