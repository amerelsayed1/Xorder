import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/tokens.dart';
import '../../core/ui/widgets/pos_widgets.dart';
import '../../domain/models/catalog.dart';
import '../../domain/models/ticket.dart';
import '../../domain/repositories/repositories.dart';
import '../payment/payment_screen.dart';
import '../../domain/models/permissions.dart';
import '../../domain/services/authorization.dart';
import '../payment/customer_dialog.dart';
import '../../domain/services/ticket_engine.dart';
import '../admin/presentation/supervisor_override.dart';
import '../receipt/receipt_dialog.dart';
import 'widgets/cart_panel.dart';
import 'widgets/discount_sheet.dart';
import 'widgets/held_tickets_dialog.dart';
import 'widgets/line_void_dialog.dart';
import '../../domain/models/business_day.dart';
import '../cash/presentation/cash_dialogs.dart';
import '../../domain/models/combo.dart';
import 'widgets/combo_sheet.dart';
import 'widgets/line_note_dialog.dart';
import 'widgets/open_item_dialog.dart';
import 'widgets/price_override_dialog.dart';
import 'widgets/category_rail.dart';
import 'widgets/modifier_sheet.dart';
import 'widgets/pos_top_bar.dart';
import 'widgets/product_grid.dart';

/// The primary selling screen.
///
/// Three shells, one feature set, chosen by width (design sheet §2):
/// ≥1100 rail + grid + persistent cart · 700–1099 tabs + grid + cart ·
/// <700 pushed routes. Desktop is the design driver; the narrow shell exists
/// for Android POS handhelds.
/// What the sale screen was in the middle of when it left for another
/// screen, carried as the route's `extra` so the other screen can hand it
/// back and the sale screen can pick up where it was.
enum SaleIntent {
  /// Collecting: the cashier pressed F9 on a dine-in ticket with no table,
  /// went to the floor to seat it (or to say there is no table), and wants
  /// payment next — not the sale screen again and F9 a second time.
  collect,

  /// Changing table: the ticket on screen goes to the floor WITH the cashier,
  /// and the table they pick is where it moves to — not where a new ticket
  /// starts.
  moveTable,
}

class SaleScreen extends ConsumerStatefulWidget {
  const SaleScreen({
    super.key,
    required this.onLock,
    required this.onTables,
    required this.onOrders,
    this.onTablesToCollect,
    this.onChangeTable,
    this.onBack,
    this.collectOnOpen = false,
  });

  final VoidCallback onLock;
  final VoidCallback onTables;

  /// Escape, with nothing to clear: one step back — the floor for a seated
  /// order, otherwise the home screen. Null or a no-op where there is nowhere
  /// to go back to (pos-home-screen).
  final VoidCallback? onBack;

  /// To the floor because a collect needs a table first — carrying
  /// [SaleIntent.collect], so the floor sends the cashier back here into
  /// payment. Falls back to [onTables] when not given.
  final VoidCallback? onTablesToCollect;

  /// "Change table" on the cart: to the floor carrying
  /// [SaleIntent.moveTable], without parking the ticket first. Falls back to
  /// [onTables] when not given — which parks it, and is the bug this exists
  /// to fix.
  final VoidCallback? onChangeTable;

  /// Opened with [SaleIntent.collect] in hand: go straight to payment.
  final bool collectOnOpen;

  /// Order history. A destination, so leaving the till does not disturb the
  /// live ticket — it is parked in memory and still here on return.
  final VoidCallback onOrders;

  @override
  ConsumerState<SaleScreen> createState() => _SaleScreenState();
}

class _SaleScreenState extends ConsumerState<SaleScreen> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    if (widget.collectOnOpen) {
      // Back from the floor with a table chosen, or with "no table" said:
      // the cashier pressed collect before leaving and has not changed their
      // mind. Before this they landed here and pressed it again (16 Oct 2026).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _charge(ref.read(ticketProvider));
      });
    }
  }

  /// The line a line-level act aims at.
  ///
  /// Screen state, not ticket state: it is where a person's attention is, not
  /// a property of the sale. A resumed table must not come back with somebody
  /// else's cursor on it, and a settled sale must not carry one to the ledger.
  String? _selectedLineKey;

  /// Whether the cart has switched to compact rows for this order.
  ///
  /// **One way, and sticky until the ticket clears.** It turns on when the
  /// ticket passes [CartDensity.switchAbove] lines and does not turn off again
  /// when a line is removed — rows that resize under a finger mid-sale are how
  /// a cashier taps the wrong one, and a ticket that oscillates around the
  /// boundary would do exactly that.
  ///
  /// Screen state rather than ticket state, for the same reason the selection
  /// is: a resumed table must not come back carrying somebody else's display
  /// preference. The per-terminal *default* is Settings › POS behaviour when
  /// Wave D lands, and there is deliberately no manual toggle on this screen.
  bool _compactCart = false;

  /// Called on every build with the current ticket.
  CartDensity _densityFor(Ticket ticket) {
    if (!_compactCart && ticket.lines.length > CartDensity.switchAbove) {
      // Deferred, because this is read during build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_compactCart) setState(() => _compactCart = true);
      });
      return CartDensity.compact;
    }
    return _compactCart ? CartDensity.compact : CartDensity.comfortable;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _addProduct(Product product, Catalog catalog) async {
    if (!product.isAvailable) {
      posToast(context, context.strings.outOfStock(product.nameEn));
      return;
    }

    final groups = catalog.groupsFor(product);
    final controller = ref.read(ticketProvider.notifier);

    // A product with no modifier groups goes straight onto the ticket — an
    // extra confirmation on every drink would cost the cashier real seconds.
    if (groups.isEmpty) {
      controller.addProduct(product);
      return;
    }

    final selection = await ModifierSheet.show(
      context,
      product: product,
      groups: groups,
    );
    if (selection == null || !mounted) return;

    controller.addProduct(
      product,
      modifiers: selection.modifiers,
      groups: groups,
      quantity: selection.quantity,
    );
  }

  Future<void> _charge(Ticket ticket) async {
    if (ticket.isEmpty) {
      posToast(context, context.strings.nothingToCharge);
      return;
    }
    // An order type served at a table is not charged until it has one. A
    // dine-in bill with no table on it is one the floor cannot show and the
    // receipt cannot place, so the button and F9 both go to the floor instead,
    // where choosing the table seats this ticket.
    if (ticket.tableId == null &&
        ref.read(orderTypeRulesProvider).requiresTable(ticket.orderType)) {
      posToast(context, context.strings.chooseTableFirst);
      (widget.onTablesToCollect ?? widget.onTables)();
      return;
    }
    final settled = await PaymentScreen.show(context);
    if (settled == null || !mounted) return;

    await ReceiptDialog.show(
      context,
      ticket: settled.ticket,
      result: settled.result,
    );
    if (!mounted) return;

    // A settled table walks the cashier back to the floor — the next thing
    // they do is seat or resume another table, not stare at an empty ticket.
    // Takeaway and delivery stay here, where the next order starts.
    if (settled.ticket.tableId != null) widget.onTables();
  }

  /// Void or clear the whole ticket.
  ///
  /// Which of those it is depends on whether the kitchen has seen any of it —
  /// [OrderVoidFlow] decides, because that boundary is a business rule and not
  /// something a button should be guessing at.
  Future<void> _void(Ticket ticket) async {
    final outcome = await OrderVoidFlow.run(context, ref, ticket: ticket);
    if (outcome == null || !mounted) return;

    if (outcome.changedElsewhere) {
      // Another till saved over this check: voiding this copy would leave its
      // newer lines out of the waste. Catch the floor up and say so.
      unawaited(ref.read(openTicketsProvider.notifier).refresh());
      posToast(
        context,
        context.strings.tableChangedElsewhere(ticket.tableLabel),
      );
      return;
    }
    if (!outcome.shouldDiscard) {
      // The write failed and the ticket is still here on purpose. Clearing it
      // anyway would lose the food and the record of it together.
      posToast(context, context.strings.voidCouldNotBeRecorded);
      return;
    }

    // The table's money never moved, so nothing else will remove the parked
    // row — a voided table that stayed parked would come back on the floor
    // holding a bill nobody owes.
    // `settle` rather than a separate "release": the table is free either way,
    // and the disk row must go for the same reason it does after payment — a
    // voided table that stayed parked would come back on the floor holding a
    // bill nobody owes.
    await ref.read(openTicketsProvider.notifier).settle(ticket);

    if (!mounted) return;

    setState(() => _selectedLineKey = null);
    ref.read(ticketProvider.notifier).reset();
    posToast(
      context,
      outcome.invoiceNumber == null
          ? context.strings.ticketVoided
          : context.strings.voidOrderRecorded(outcome.invoiceNumber!),
    );
    if (ticket.tableId != null) widget.onTables();
  }

  /// Take money off the bill.
  ///
  /// **Two gates, and only ever one prompt.** Whether a person may discount at
  /// all is `discount.apply`; how much they may take off without asking is a
  /// limit the engine enforces. Somebody who lacks the capability entirely is
  /// asked once here and then works inside the sheet with no ceiling — because
  /// Open the drawer with no sale behind it (§23).
  Future<void> _openDrawer() async {
    final opened = await DrawerOpenFlow.run(context, ref);
    if (!opened || !mounted) return;
    posToast(context, context.strings.drawerOpened);
  }

  /// Money into or out of the drawer that is not a sale (§22).
  Future<void> _moveCash(CashMovementKind kind) async {
    final decision = await requestPermission(
      context,
      ref,
      PosCapability.cashMovement,
      action: kind == CashMovementKind.payOut
          ? context.strings.payOutTitle
          : context.strings.payInTitle,
      auditAction: kind == CashMovementKind.payOut
          ? 'cash.paid_out'
          : 'cash.paid_in',
      entityType: 'drawer',
      approveLabel: kind == CashMovementKind.payOut
          ? context.strings.payOutAction
          : context.strings.payInAction,
    );
    if (!mounted || decision is! Allowed) return;

    final amount = await CashMovementDialog.show(
      context,
      kind: kind,
      // The supervisor's approval, when one lent this: the repository asks.
      approval: decision.approval,
    );
    if (amount == null || !mounted) return;
    posToast(context, context.strings.cashRecorded);
  }

  /// Ring up a meal (§17).
  ///
  /// A fixed combo — every group offering one option and demanding it — goes
  /// straight on. Putting a picker in front of a cashier for a meal with
  /// nothing to choose is three taps to say the only thing that could be said.
  Future<void> _addCombo(Combo combo) async {
    var chosen = combo.fixedSelection;

    if (!combo.isFixed) {
      final picked = await ComboSheet.show(context, combo: combo);
      if (picked == null || !mounted) return;
      chosen = picked;
    }

    final result = TicketEngine.addComboLine(
      ref.read(ticketProvider),
      combo,
      chosen: chosen,
    );
    if (result.refusal != null || !mounted) return;

    ref.read(ticketProvider.notifier).applyEdit(result.ticket!);
  }

  /// Charge for something that is not on the menu (§17).
  ///
  /// No F-key: the map is full, and this is a control on the search row where
  /// somebody is already looking when the thing they want is not on the grid.
  Future<void> _addOpenItem() async {
    final updated = await OpenItemFlow.run(
      context,
      ref,
      ticket: ref.read(ticketProvider),
    );
    if (updated == null || !mounted) return;

    ref.read(ticketProvider.notifier).applyEdit(updated);
    posToast(
      context,
      context.strings.openItemAdded(updated.lines.last.product.nameEn),
    );
  }

  /// Add or change what the kitchen is being told about one line.
  ///
  /// No F-key and no permission gate. A note is an instruction, not a
  /// concession — it changes nothing about what anybody is charged, so gating
  /// it would put a supervisor between a cashier and the words "no onions".
  Future<void> _editNote(Ticket ticket, String lineKey) async {
    final line = ticket.lines.where((l) => l.key == lineKey).firstOrNull;
    if (line == null) return;

    final note = await LineNoteDialog.show(
      context,
      line: line,
      strings: context.strings,
    );
    if (note == null || !mounted) return;

    ref.read(ticketProvider.notifier).setLineNote(lineKey, note);
  }

  /// Sell the selected line at a price somebody set by hand.
  ///
  /// Aimed at the selected line and nothing else. There is no sensible
  /// "override the price" of a whole ticket — a bill is not an item — so unlike
  /// `F6`, this refuses rather than falling back to the order.
  Future<void> _overridePrice(Ticket ticket) async {
    final line = ticket.lines
        .where((l) => l.key == _selectedLineKey)
        .firstOrNull;
    if (line == null) {
      posToast(context, context.strings.priceOverrideNothingSelected);
      return;
    }

    final updated = await PriceOverrideFlow.run(
      context,
      ref,
      ticket: ticket,
      line: line,
    );
    if (updated == null || !mounted) return;

    ref.read(ticketProvider.notifier).applyEdit(updated);

    final repriced = updated.lines
        .where((l) => l.key == line.key)
        .firstOrNull;
    posToast(
      context,
      context.strings.priceOverrideApplied(
        (repriced?.unitPrice ?? line.unitPrice).format(withCurrency: true),
      ),
    );
  }

  /// Order history.
  ///
  /// Gated here as well as on the rail button. The rail hides the control for
  /// somebody who may not look, but `F7` is a key on a keyboard and reaches
  /// this method whether or not a button was drawn — a gate that lives only in
  /// the widget tree is one a shortcut walks straight past.
  ///
  /// Not overridable: this is not an act somebody supervises for one moment,
  /// it is a body of records they either may read or may not.
  void _openOrders() {
    // `operate`, not `order.view_all`. History used to be all-or-nothing — a
    // cashier saw everybody's sales or nobody's — so the door was the gate. It
    // is scoped per person now (`history_scope.dart`: without `order.view_all`
    // the list is the viewer's own), so the door opens for anyone who may work
    // the till, and what they see behind it is decided there.
    if (ref.read(canProvider(PosCapability.operate)) is! Allowed) {
      posToast(context, context.strings.orderHistoryNotPermitted);
      return;
    }
    widget.onOrders();
  }

  /// a manager who has just approved the act should not be called back to
  /// approve the amount as well, with a customer standing there.
  ///
  /// An empty ticket is refused before any of that, so a stray `F6` between
  /// sales does not open a dialog about nothing.
  Future<void> _discount(Ticket ticket) async {
    if (ticket.isEmpty) {
      posToast(context, context.strings.discountNothingToDiscount);
      return;
    }

    // Aimed at the selected line, or at the whole bill when there is none.
    // The line has to still be on the ticket: a cashier who selected something
    // and then removed it must not discount a line that is gone.
    final line = ticket.lines
        .where((l) => l.key == _selectedLineKey)
        .firstOrNull;

    final decision = Authorization.check(
      ref.read(signedInStaffProvider),
      PosCapability.discountApply,
    );

    PosStaff? approver;
    if (decision is! Allowed) {
      final lent = await requestPermission(
        context,
        ref,
        PosCapability.discountApply,
        action: context.strings.discountTitle,
        auditAction: 'discount.apply',
        entityId: ticket.id,
      );
      if (lent is! Allowed || lent.approvedBy == null) return;
      approver = lent.approvedBy;
    }

    if (!mounted) return;
    final updated = await DiscountSheet.show(
      context,
      ticket: ticket,
      lineKey: line?.key,
      lineLabel: line == null
          ? null
          : '${line.quantity} × '
                '${line.product.displayName(context.strings.languageCode)} · '
                '${line.lineTotal.format(withCurrency: true)}',
      preApprovedBy: approver,
    );
    if (updated == null || !mounted) return;
    ref.read(ticketProvider.notifier).applyEdit(updated);
  }

  /// Take the selected line off — cancelling it or voiding it, whichever this
  /// line actually is.
  ///
  /// The screen does not decide which: [LineVoidFlow] reads the line's stage,
  /// because a control that guessed would eventually record waste as
  /// housekeeping.
  Future<void> _removeSelectedLine(Ticket ticket) async {
    final key = _selectedLineKey;
    if (key == null) return;

    final updated = await LineVoidFlow.run(
      context,
      ref,
      ticket: ticket,
      lineKey: key,
    );
    if (updated == null || !mounted) return;

    ref.read(ticketProvider.notifier).applyEdit(updated);
    // A cancelled line is gone, so the selection has to go with it. A voided
    // one is still there and stays selected — the cashier may want to show it
    // to somebody.
    if (updated.lines.every((l) => l.key != key)) {
      setState(() => _selectedLineKey = null);
    }
  }

  /// The secondary cart action, whatever it means for this ticket.
  ///
  /// **The single decision point for the button and for F4.** They used to be
  /// wired separately — the button read its label off `isSeated` and then always
  /// sent a round, and F4 called the round handler unconditionally — so a
  /// takeaway ticket could not be put down at all, and the control that said
  /// *Park* sent food to the kitchen instead.
  Future<void> _hold(Ticket ticket) async {
    // The same configured answer the cart panel is given, from the same place,
    // so F4 and the button cannot disagree about what this ticket is.
    final action = TicketHoldAction.forTicket(
      ticket,
      seated: ref.read(orderTypeRulesProvider).requiresTable(ticket.orderType),
    );
    if (!action.isAvailableFor(ticket)) return;

    switch (action) {
      case TicketHoldAction.sendRound:
        _sendRound();
      case TicketHoldAction.park:
        await _park(ticket);
    }
  }

  void _sendRound() {
    ref.read(ticketProvider.notifier).sendRound();
    posToast(context, context.strings.roundSentToKitchen);
  }

  /// Put the ticket down and clear the till for the next customer.
  ///
  /// The live ticket is reset rather than left on screen, because a Park that
  /// left the ticket where it was would give the cashier two copies of one sale
  /// — the parked one and the one in front of them — and whichever they then
  /// charged, the other would still be there at the day close.
  Future<void> _park(Ticket ticket) async {
    final outcome = await ref.read(openTicketsProvider.notifier).park(ticket);
    if (!mounted) return;
    if (outcome != ParkOutcome.parked) {
      _parkRefused(outcome, ticket);
      return;
    }
    ref.read(ticketProvider.notifier).reset();
    setState(() {
      _selectedLineKey = null;
      // The next ticket gets its own answer to the density question.
      _compactCart = false;
    });
    posToast(context, context.strings.ticketParked);
  }

  /// Why [ticket] is still on screen: the database could not take it, or its
  /// table was changed on another till (XORD-044).
  void _parkRefused(ParkOutcome outcome, Ticket ticket) => posToast(
    context,
    outcome == ParkOutcome.changedElsewhere
        ? context.strings.tableChangedElsewhere(ticket.tableLabel)
        : context.strings.cashCouldNotBeRecorded,
  );

  /// Pick a held ticket back up.
  ///
  /// Whatever is on screen is parked first, so a resume never destroys a sale —
  /// the alternative, refusing to resume while the till is busy, would leave a
  /// cashier with a customer in front of them and no way to reach the order they
  /// are asking about.
  Future<void> _showHeld(Ticket live) async {
    final held = ref.read(openTicketsProvider).heldOtherThan(live.id);
    final chosen = await HeldTicketsDialog.show(context, tickets: held);
    if (chosen == null || !mounted) return;

    final outcome = await ref.read(openTicketsProvider.notifier).park(live);
    if (!mounted) return;
    if (outcome != ParkOutcome.parked) {
      _parkRefused(outcome, live);
      return;
    }
    ref.read(ticketProvider.notifier).adopt(chosen);
    setState(() {
      _selectedLineKey = null;
      _compactCart = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final catalog = ref.watch(catalogProvider);
    final ticket = ref.watch(ticketProvider);
    final ui = ref.watch(posUiProvider);

    if (session.isLoading || catalog.isLoading) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: context.pos.accent),
        ),
      );
    }

    final sessionData = session.requireValue;
    final catalogData = catalog.requireValue;

    return _shortcuts(
      ticket: ticket,
      child: Scaffold(
        backgroundColor: context.pos.page,
        body: Column(
          // Stretch, not the default centre: without it the 56px shell top bar
          // shrink-wraps to its content and floats in the middle of the window.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PosTopBar(
              session: sessionData,
              supportedOrderTypes: ref.watch(branchOrderTypesProvider),
              onLock: widget.onLock,
            ),
            // The platform stopped recognising this till. A cashier mid-shift
            // never sees the start screen, so the warning has to live where
            // they actually are — one strip, under the bar, not a dialog that
            // interrupts a sale. Selling is untouched: this is information
            // about sync, and nothing about sync may block taking money.
            if (ref.watch(terminalRejectedProvider))
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: PosSpace.s14,
                  vertical: PosSpace.sm,
                ),
                color: context.pos.danger,
                child: Text(
                  context.strings.terminalRejectedTitle,
                  textAlign: TextAlign.center,
                  style: PosText.ui(
                    size: 12.5,
                    weight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => _shell(
                  constraints.maxWidth,
                  sessionData,
                  catalogData,
                  ticket,
                  ui,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Shell-level shortcuts. Registered once here, never per-widget, so a key
  /// means the same thing on every screen the shell hosts.
  Widget _shortcuts({required Ticket ticket, required Widget child}) =>
      CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.f2):
              _searchFocus.requestFocus,
          // Whatever the cart's secondary button does for this ticket. The key
          // and the button go through one resolver on purpose: they were two
          // paths once, and the one nobody was looking at sent a round from a
          // control labelled Park.
          const SingleActivator(LogicalKeyboardKey.f4): () => _hold(ticket),
          const SingleActivator(LogicalKeyboardKey.f5): () =>
              _overridePrice(ticket),
          const SingleActivator(LogicalKeyboardKey.f6): () => _discount(ticket),
          const SingleActivator(LogicalKeyboardKey.f7): _openOrders,
          const SingleActivator(LogicalKeyboardKey.delete): () =>
              _removeSelectedLine(ticket),
          const SingleActivator(LogicalKeyboardKey.f9): () => _charge(ticket),
          // F10 used to toast "drawer opened" and open nothing. §23 makes it
          // a permission, a confirmation and an audit row — an unexplained
          // drawer opening is the one thing a till can actually notice.
          const SingleActivator(LogicalKeyboardKey.f10): _openDrawer,
          const SingleActivator(LogicalKeyboardKey.f11): () =>
              _moveCash(CashMovementKind.payIn),
          const SingleActivator(LogicalKeyboardKey.f12): () =>
              _moveCash(CashMovementKind.payOut),
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (_searchController.text.isNotEmpty) {
              _searchController.clear();
              ref.read(posUiProvider.notifier).setQuery('');
              return;
            }
            // Nothing to clear: back one step. Not while somebody is typing in
            // some other box — Escape there means "stop editing", and leaving
            // the screen under their cursor would lose what they were doing.
            final focus = FocusManager.instance.primaryFocus;
            final typingElsewhere =
                focus != null &&
                focus != _searchFocus &&
                focus.context?.findAncestorWidgetOfExactType<EditableText>() !=
                    null;
            if (!typingElsewhere) widget.onBack?.call();
          },
        },
        child: Focus(autofocus: true, child: child),
      );

  Widget _shell(
    double width,
    PosSession session,
    Catalog catalog,
    Ticket ticket,
    PosUiState ui,
  ) {
    final products = _visibleProducts(catalog, ui);
    final productArea = _productArea(catalog, products, ticket, ui);

    if (width >= PosSize.wideShellMin) {
      return Row(
        children: [
          CategoryRail(
            catalog: catalog,
            selectedId: ui.selectedCategoryId,
            onSelect: ref.read(posUiProvider.notifier).selectCategory,
            onTables: widget.onTables,
            // Hidden rather than disabled when the person may not look. See
            // `CategoryRail.onOrders`.
            onOrders:
                ref.watch(canProvider(PosCapability.operate)) is Allowed
                ? _openOrders
                : null,
          ),
          Expanded(child: productArea),
          _cart(session, ticket, ui),
        ],
      );
    }

    if (width >= PosSize.mediumShellMin) {
      return Row(
        children: [
          Expanded(child: productArea),
          _cart(session, ticket, ui),
        ],
      );
    }

    // Narrow: the cart is a route, not a pane.
    return productArea;
  }

  Widget _cart(PosSession session, Ticket ticket, PosUiState ui) => CartPanel(
    seatedOrder: ref
        .watch(orderTypeRulesProvider)
        .requiresTable(ref.watch(ticketProvider).orderType),
    ticket: ticket,
    // The person who is selling, not the branch's first staff row — a receipt
    // carrying the wrong cashier is a receipt that misdirects every question
    // asked about the sale afterwards. See `operatorNameProvider`.
    cashierName: ref.watch(operatorNameProvider),
    online: ui.online,
    density: _densityFor(ticket),
    onEditNote: (key) => _editNote(ticket, key),
    selectedLineKey: _selectedLineKey,
    // Tapping the selected line again clears it, so a cashier can get back to
    // discounting the whole order without hunting for a "deselect" control.
    onSelectLine: (key) =>
        setState(() => _selectedLineKey = _selectedLineKey == key ? null : key),
    onQuantityChanged: (key, delta) =>
        ref.read(ticketProvider.notifier).changeQuantity(key, delta),
    onHold: () => _hold(ticket),
    onVoid: () => _void(ticket),
    onCharge: () => _charge(ticket),
    onChangeTable: widget.onChangeTable ?? widget.onTables,
    // Choosing who the order is for is part of ringing it up (XORD-001), so it
    // needs the same key the sale screen itself does.
    onChooseCustomer: ref.watch(canProvider(PosCapability.operate)) is Allowed
        ? () => chooseCustomerForTicket(context, ref)
        : null,
    heldCount: ref.watch(openTicketsProvider).heldOtherThan(ticket.id).length,
    onShowHeld: () => _showHeld(ticket),
  );

  List<Product> _visibleProducts(Catalog catalog, PosUiState ui) {
    if (ui.query.trim().isNotEmpty) return catalog.search(ui.query);
    return catalog.inCategory(ui.selectedCategoryId);
  }

  Widget _productArea(
    Catalog catalog,
    List<Product> products,
    Ticket ticket,
    PosUiState ui,
  ) {
    final slugs = {for (final c in catalog.categories) c.id: c.slug};
    final inCart = ticket.lines.map((l) => l.product.id).toSet();

    return Column(
      children: [
        _searchRow(),
        Expanded(
          child: ProductGrid(
            products: products,
            // Only when nobody is searching: a search is a hunt for a named
            // thing, and answering it with meals that merely sit in the same
            // category is answering a different question.
            combos: ui.query.trim().isEmpty
                ? catalog.combosIn(ui.selectedCategoryId)
                : const [],
            categorySlugs: slugs,
            inCartProductIds: inCart,
            onTap: (product) => _addProduct(product, catalog),
            onTapCombo: _addCombo,
          ),
        ),
        _footerStrip(catalog, products, ui),
      ],
    );
  }

  Widget _searchRow() => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: PosSpace.s14,
      vertical: PosSpace.md,
    ),
    decoration: BoxDecoration(
      color: context.pos.surface,
      border: Border(bottom: context.pos.hairline),
    ),
    child: Row(
      children: [
        Expanded(
          child: Container(
            height: PosSize.searchRow,
            padding: const EdgeInsets.symmetric(horizontal: PosSpace.md),
            decoration: BoxDecoration(
              color: context.pos.page,
              border: Border.fromBorderSide(context.pos.emphasis),
            ),
            child: Row(
              children: [
                Icon(Icons.search, size: 17, color: context.pos.inkWarm),
                const SizedBox(width: PosSpace.sm),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocus,
                    onChanged: ref.read(posUiProvider.notifier).setQuery,
                    style: PosText.ui(color: context.pos.inkWarm, size: 14.5),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      hintText: context.strings.searchHint,
                      hintStyle: PosText.ui(
                        size: 14.5,
                        color: context.pos.muted,
                      ),
                    ),
                  ),
                ),
                const KeyChip('F2'),
              ],
            ),
          ),
        ),
        const SizedBox(width: PosSpace.md),
        PosButton(
          label: context.strings.customAmount,
          height: PosSize.searchRow,
          border: Border.fromBorderSide(BorderSide(color: context.pos.inkWarm)),
          onPressed: _addOpenItem,
        ),
      ],
    ),
  );

  Widget _footerStrip(Catalog catalog, List<Product> visible, PosUiState ui) {
    final searching = ui.query.trim().isNotEmpty;
    final strings = context.strings;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: PosSpace.s14,
        vertical: PosSpace.s10,
      ),
      decoration: BoxDecoration(
        color: context.pos.surface,
        border: Border(top: context.pos.hairline),
      ),
      child: Row(
        children: [
          Text(
            strings.shortcutStrip,
            style: PosText.mono(size: 11, color: context.pos.muted),
          ),
          const Spacer(),
          Text(
            searching
                ? strings.matchCount(visible.length)
                : strings.catalogCached(catalog.products.length),
            style: PosText.mono(size: 11, color: context.pos.ink),
          ),
        ],
      ),
    );
  }
}
