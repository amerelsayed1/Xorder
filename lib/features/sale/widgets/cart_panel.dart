import 'package:flutter/material.dart';

import '../../../app/labels.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/item_name.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/discount.dart';
import '../../../domain/models/ticket.dart';

/// How tightly the cart draws its lines.
///
/// **Compact drops one thing and one thing only: the sent timestamp.** Notes,
/// discounts, void reasons and struck-through prices all survive at both
/// densities — everything a cashier or a customer needs in order to *dispute*
/// the ticket is present either way. A density that hid a reason would make the
/// screen and the ledger disagree exactly when somebody was arguing about them.
///
/// (The timestamp itself is not built yet; there is nowhere on a `TicketLine`
/// that records when a round went out. The rule is written down here so that
/// whoever adds it knows which mode it belongs in.)
enum CartDensity {
  /// 44px plain rows. Seven lines fit the 420 list height.
  comfortable,

  /// 32px plain rows. Eleven fit — which is what a mid-sized full-service
  /// check of 9 to 14 lines needs.
  compact;

  /// Vertical padding inside a line row.
  double get linePadding => this == CartDensity.compact ? 7 : PosSpace.md;

  /// The gap between a line's name and its meta rows.
  double get metaGap => this == CartDensity.compact ? 0 : 1;

  double get nameSize => this == CartDensity.compact ? 13.5 : 14.5;
  double get amountSize => this == CartDensity.compact ? 14 : 15;
  double get metaSize => this == CartDensity.compact ? 11 : 12;

  /// A section bar's vertical padding.
  double get sectionPadding => this == CartDensity.compact ? 5 : 9;

  /// The number of lines past which a ticket is dense enough to want the
  /// compact treatment.
  ///
  /// Seven, because that is what fits comfortably — the switch happens exactly
  /// when the eighth line would otherwise fall off the bottom.
  static const switchAbove = 7;
}

/// What the cart's secondary button and F4 do, for one ticket state.
///
/// **One resolver, because there used to be two and they disagreed.** The
/// button's label switched on `isSeated` while its `onPressed` was always
/// "send round", so the control reading *Park* sent a round to the kitchen and
/// a takeaway ticket could never be put down at all. F4 was wired straight to
/// the same handler and drifted the same way.
///
/// An enum rather than a bool because the switches over it are exhaustive: if
/// this control ever means a third thing — "send and park", which is what a
/// handheld taken to a table actually wants — the label, the enablement and the
/// handler all stop compiling until somebody has answered for each of them. A
/// bool would simply have taken the false branch.
enum TicketHoldAction {
  /// Fire the draft lines at the kitchen. The ticket stays on screen — the
  /// table is still eating.
  sendRound,

  /// Put the whole ticket down and clear the screen for the next customer.
  park;

  /// A seated ticket sends; anything else parks.
  ///
  /// Seated is the discriminator rather than the order type, because a dine-in
  /// ticket with nobody seated yet is a ticket with no kitchen destination —
  /// there is no table for the runner to bring the food to.
  /// Which of the two this ticket's secondary button means.
  ///
  /// **[seated] is the restaurant's answer, not `Ticket.isSeated`.** That getter
  /// reads `orderType == OrderType.dineIn`, and deleting exactly that comparison
  /// is what §31 and `pos_order_types.requires_table` exist for: a caterer who
  /// seats people turns it on for takeaway, and their takeaway tickets have
  /// rounds to send like any other table. Passing the configured answer in keeps
  /// the button, the floor plan and the ticket engine agreeing about what
  /// "seated" means.
  ///
  /// A type that requires a table but has none assigned yet parks — there is no
  /// round to send to a table nobody has chosen.
  static TicketHoldAction forTicket(Ticket ticket, {required bool seated}) =>
      seated && ticket.tableId != null
      ? TicketHoldAction.sendRound
      : TicketHoldAction.park;

  String label(AppStrings s) => switch (this) {
    TicketHoldAction.sendRound => s.sendRoundKey,
    TicketHoldAction.park => s.parkKey,
  };

  /// Whether this ticket is in a state the action can act on.
  ///
  /// Sending needs something unsent. **Parking needs only something on the
  /// ticket** — a ticket whose lines have all gone to the kitchen still has to
  /// be puttable-down, or a cashier who sent a round and then had to serve
  /// somebody else would be stuck holding it until it was paid.
  bool isAvailableFor(Ticket ticket) => switch (this) {
    TicketHoldAction.sendRound => ticket.hasDraft,
    TicketHoldAction.park => !ticket.isEmpty,
  };
}

/// 378px cart panel on shell ground with a 2px ink left border.
class CartPanel extends StatelessWidget {
  const CartPanel({
    super.key,
    required this.ticket,
    required this.cashierName,
    required this.online,
    required this.onQuantityChanged,
    required this.onHold,
    required this.onVoid,
    required this.onCharge,
    this.onChangeTable,
    this.onChooseCustomer,
    this.heldCount = 0,
    this.onShowHeld,
    this.selectedLineKey,
    this.onSelectLine,
    this.onEditNote,
    this.density = CartDensity.comfortable,
    this.seatedOrder = false,
  });

  final Ticket ticket;

  /// Whether this kind of order has tables, from the restaurant's own
  /// configuration (§31). Passed in rather than derived from
  /// `ticket.orderType == OrderType.dineIn`, which was never the question: a
  /// restaurant that seats catering orders has one that is seated and is not
  /// dine-in.
  ///
  /// Defaults to false so a caller that has not been updated shows no table
  /// prompt rather than a wrong one.
  final bool seatedOrder;

  final String cashierName;
  final bool online;
  final void Function(String lineKey, int delta) onQuantityChanged;

  /// Do whatever [TicketHoldAction.forTicket] says this ticket's secondary
  /// button means. One callback rather than one per action, so the label the
  /// cashier reads and the work that happens cannot come from two decisions.
  final VoidCallback onHold;
  final VoidCallback onVoid;
  final VoidCallback onCharge;
  final VoidCallback? onChangeTable;

  /// Open the customer picker (XORD-001). Null hides the row: the person at the
  /// till may not choose who an order is for, and a control that does nothing
  /// is not drawn.
  final VoidCallback? onChooseCustomer;

  /// How many parked tickets with no table are waiting, excluding this one.
  final int heldCount;

  /// Open the list of those. Null hides the affordance.
  final VoidCallback? onShowHeld;

  /// The line the cashier is working on, if any.
  ///
  /// Selection exists so a line-level act — discount today, void and price
  /// override next — has something to aim at. It is deliberately **not**
  /// persisted with the ticket: it is where a person's attention is, not a
  /// property of the sale, and a resumed table should not come back with
  /// somebody's cursor on it.
  final String? selectedLineKey;
  final ValueChanged<String>? onSelectLine;

  /// Add or change a line's note. Null hides the affordance entirely.
  final ValueChanged<String>? onEditNote;

  /// Taken as a parameter, never read from a provider in here.
  ///
  /// It is per-terminal settings state, and the rule that makes it safe — the
  /// switch is automatic above seven lines and then **sticky for the rest of
  /// that order** — lives where the order does. Rows that resize under a finger
  /// mid-sale are how a cashier taps the wrong line.
  final CartDensity density;

  @override
  Widget build(BuildContext context) {
    final totals = ticket.totals;
    final strings = context.strings;

    return Container(
      width: PosSize.cartPanel,
      decoration: BoxDecoration(
        color: context.pos.shell,
        border: Border(left: context.pos.emphasis),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(strings, pos: context.pos),
          if (onChooseCustomer != null) _customerRow(strings, pos: context.pos),
          Expanded(
            child: ticket.isEmpty
                ? _emptyState(strings, pos: context.pos)
                : _lines(strings, pos: context.pos),
          ),
          _totals(strings, totals, pos: context.pos),
          _actions(strings, totals, pos: context.pos),
        ],
      ),
    );
  }

  String _title(AppStrings s, {required bool seatedOrder}) {
    if (ticket.isSeated) {
      return s.seatedTable(ticket.tableLabel!, ticket.guestCount);
    }
    // Asked of the order type's own rule, not of its name (§31).
    if (seatedOrder) return s.noTableYet;
    return s.walkIn(ticket.orderType.label(s));
  }

  bool get showsHeld => heldCount > 0 && onShowHeld != null;

  /// Who the order is for, and the way to change it, without leaving the sale.
  ///
  /// Always one line: the name once somebody is chosen, "Who is this for?"
  /// until then — a walk-in is a valid order and nothing here asks for more.
  Widget _customerRow(AppStrings s, {required PosPalette pos}) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: PosSpace.lg,
      vertical: PosSpace.sm,
    ),
    decoration: BoxDecoration(border: Border(bottom: pos.shellBorder)),
    child: PosButton(
      key: const Key('cart-customer'),
      label: ticket.customer?.name ?? s.whoIsThisFor,
      height: 36,
      background: ticket.customer == null ? pos.shellCard : pos.accent,
      foreground: ticket.customer == null ? pos.shellText : Colors.white,
      fontSize: 12.5,
      onPressed: onChooseCustomer,
    ),
  );

  Widget _header(AppStrings s, {required PosPalette pos}) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: PosSpace.lg,
      vertical: PosSpace.s14,
    ),
    decoration: BoxDecoration(border: Border(bottom: pos.shellBorder)),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _title(s, seatedOrder: seatedOrder),
                overflow: TextOverflow.ellipsis,
                style: PosText.panelTitle(color: pos.shellText),
              ),
              const SizedBox(height: 2),
              Text(
                s.cartStatusLine(cashierName, online),
                overflow: TextOverflow.ellipsis,
                style: PosText.mono(size: 11.5, color: pos.shellMuted),
              ),
            ],
          ),
        ),
        // The way back to a parked takeaway, and the only one there is.
        //
        // Here rather than on the floor screen: the floor is a grid of tables
        // and a held ticket has none, so a tile for it would have to invent a
        // seat — a floor that lies about who is sitting where is worse than a
        // list somewhere else. The counter above the Park button is also where
        // the cashier just was when they put the thing down, and it is the only
        // control that exists in the medium shell, which has no rail and
        // therefore no way to reach the floor at all.
        //
        // Drawn only when something is actually held: a permanent "Held 0" is
        // clutter in a panel a cashier reads all day.
        if (showsHeld)
          PosButton(
            label: s.heldTicketsKey(heldCount),
            height: 38,
            background: pos.shellCard,
            foreground: pos.accent,
            fontSize: 12.5,
            onPressed: onShowHeld,
          ),
        if (ticket.isSeated && onChangeTable != null) ...[
          if (showsHeld) const SizedBox(width: PosSpace.sm),
          PosButton(
            label: s.changeTable,
            height: 38,
            background: pos.shellCard,
            foreground: pos.shellText,
            fontSize: 12.5,
            onPressed: onChangeTable,
          ),
        ],
      ],
    ),
  );

  Widget _emptyState(AppStrings s, {required PosPalette pos}) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: PosSpace.lg,
      vertical: PosSpace.xl,
    ),
    child: Text(
      s.cartEmptyHelp,
      style: PosText.ui(size: 13, color: pos.shellMuted, height: 1.6),
    ),
  );

  Widget _lines(AppStrings s, {required PosPalette pos}) {
    final sent = ticket.sentLines;
    final draft = ticket.draftLines;

    return ListView(
      children: [
        if (sent.isNotEmpty) ...[
          _sectionBar(s.alreadySent(sent.length), pos.shellMuted, pos: pos),
          for (final line in sent)
            _LineRow(
              line: line,
              dimmed: true,
              density: density,
              discount: ticket.discountOnLine(line.key),
              isSelected: line.key == selectedLineKey,
              onSelect: onSelectLine == null
                  ? null
                  : () => onSelectLine!(line.key),
              onEditNote: onEditNote == null
                  ? null
                  : () => onEditNote!(line.key),
            ),
          _sectionBar(s.newRound, pos.accent, pos: pos),
        ],
        for (final line in draft)
          _LineRow(
            line: line,
            density: density,
            discount: ticket.discountOnLine(line.key),
            isSelected: line.key == selectedLineKey,
            onSelect: onSelectLine == null
                ? null
                : () => onSelectLine!(line.key),
            onQuantityChanged: (delta) => onQuantityChanged(line.key, delta),
            onEditNote: onEditNote == null
                ? null
                : () => onEditNote!(line.key),
          ),
      ],
    );
  }

  Widget _sectionBar(String label, Color color, {required PosPalette pos}) =>
      Container(
        width: double.infinity,
        color: pos.shellRow,
        padding: EdgeInsets.symmetric(
          horizontal: PosSpace.lg,
          vertical: density.sectionPadding,
        ),
        child: MicroLabel(label, color: color),
      );

  Widget _totals(
    AppStrings s,
    TicketTotals totals, {
    required PosPalette pos,
  }) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: PosSpace.lg,
      vertical: PosSpace.s14,
    ),
    decoration: BoxDecoration(border: Border(top: pos.accentBorder)),
    child: Column(
      children: [
        _totalRow(s.subtotal, totals.subtotal.format(withCurrency: true), pos: pos),
        // **Order-level discounts live here, never inside a line.** A discount
        // that came off the whole bill has no line to belong to, and drawing it
        // under one would be a claim about what it discounted.
        for (final discount in ticket.orderDiscounts)
          _totalRow(
            discount.nameSnapshot,
            '-${discount.amount.format(withCurrency: true)}',
            pos: pos,
            emphasis: pos.accent,
          ),
        // Shown whenever service applies to this order type, even at a zero
        // AMOUNT: the design lists all three rows, and a row that appears
        // only once the ticket is non-empty makes the totals block jump as
        // items land. A zero RATE is different — "Service 0%" on every
        // takeaway, or "VAT 0%" on a branch that charges none, is a line the
        // cashier reads past a hundred times a day for nothing, and the rate
        // is configuration, so hiding on it never makes the block jump. The
        // amount still wins: a rate of nought with money against it (a tax
        // group on one product) is shown rather than hidden.
        if (ticket.taxConfig.appliesServiceTo(ticket.orderType) &&
            (ticket.taxConfig.serviceBp != 0 || !totals.service.isZero))
          _totalRow(
            s.servicePercent(
              (ticket.taxConfig.serviceBp / 100).toStringAsFixed(0),
            ),
            totals.service.format(withCurrency: true),
            pos: pos,
          ),
        if (ticket.taxConfig.vatBp != 0 || !totals.vat.isZero)
          _totalRow(
            s.vatPercent((ticket.taxConfig.vatBp / 100).toStringAsFixed(0)),
            totals.vat.format(withCurrency: true),
            pos: pos,
          ),
        Padding(
          padding: EdgeInsets.symmetric(vertical: PosSpace.sm),
          child: ColoredBox(
            color: pos.shellLine,
            child: SizedBox(height: 1, width: double.infinity),
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Flexible, because the word for "total" is longer in some
            // languages than in English and the figure beside it is the
            // largest type in the product. The label yields; the number never
            // does.
            Flexible(
              child: Text(
                s.totalCaps,
                overflow: TextOverflow.ellipsis,
                style: PosText.ui(
                  size: 17,
                  weight: FontWeight.w800,
                  color: pos.shellText,
                ),
              ),
            ),
            const Spacer(),
            Text(
              totals.total.format(),
              style: PosText.displayTotal(color: pos.accent),
            ),
            Padding(
              // Directional: the currency sits after the figure, which is the
              // right of it in English and the left of it in Arabic.
              padding: const EdgeInsetsDirectional.only(bottom: 3, start: 4),
              child: Text(
                ticket.currency,
                style: PosText.ui(size: 14, color: pos.shellMuted),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _totalRow(
    String label,
    String value, {
    required PosPalette pos,
    Color? emphasis,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: PosSpace.xs),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: PosText.ui(size: 13, color: emphasis ?? pos.shellText),
          ),
        ),
        const SizedBox(width: PosSpace.sm),
        // Directionality, not `MonoAmount`: the value arrives already
        // formatted — some of these rows are a rate, not an amount — and the
        // one guarantee that must hold either way is that it reads
        // left-to-right on an Arabic till.
        Directionality(
          textDirection: TextDirection.ltr,
          child: Text(
            value,
            style: PosText.mono(size: 13, color: emphasis ?? pos.shellText),
          ),
        ),
      ],
    ),
  );

  Widget _actions(
    AppStrings s,
    TicketTotals totals, {
    required PosPalette pos,
  }) {
    final hasAnything = !ticket.isEmpty;
    final ctaLabel = ticket.isSeated ? s.closeTableCta : s.chargeCta;
    final hold = TicketHoldAction.forTicket(ticket, seated: seatedOrder);

    return Column(
      children: [
        Container(
          color: pos.shellLine,
          child: Row(
            children: [
              Expanded(
                child: PosButton(
                  label: hold.label(s),
                  height: PosSize.secondaryAction,
                  background: pos.shell,
                  foreground: pos.shellText,
                  onPressed: hold.isAvailableFor(ticket) ? onHold : null,
                ),
              ),
              const SizedBox(width: 1),
              Expanded(
                child: PosButton(
                  label: s.voidTicket,
                  height: PosSize.secondaryAction,
                  background: pos.shell,
                  foreground: pos.offlinePillText,
                  onPressed: hasAnything ? onVoid : null,
                ),
              ),
            ],
          ),
        ),
        PosButton(
          label: '$ctaLabel  ${totals.total.format(withCurrency: true)}',
          height: PosSize.primaryCta,
          alignLeft: true,
          background: hasAnything ? pos.accent : pos.ctaDisabled,
          foreground: Colors.white,
          fontSize: 17,
          fontWeight: FontWeight.w800,
          padding: const EdgeInsets.symmetric(horizontal: PosSpace.lg),
          trailing: const KeyChip('F9', onShell: true),
          onPressed: hasAnything ? onCharge : null,
        ),
      ],
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.line,
    this.dimmed = false,
    this.discount,
    this.isSelected = false,
    this.onSelect,
    this.onQuantityChanged,
    this.onEditNote,
    this.density = CartDensity.comfortable,
  });

  final TicketLine line;
  final bool dimmed;
  final CartDensity density;
  final VoidCallback? onEditNote;

  /// What was taken off this line, if anything. Null for most lines.
  final AppliedDiscount? discount;

  final bool isSelected;
  final VoidCallback? onSelect;
  final ValueChanged<int>? onQuantityChanged;

  @override
  Widget build(BuildContext context) {
    final language = context.strings.languageCode;

    final row = Container(
      padding: EdgeInsets.symmetric(
        horizontal: PosSpace.lg,
        vertical: density.linePadding,
      ),
      decoration: BoxDecoration(
        color: isSelected ? context.pos.shellCard : null,
        border: BorderDirectional(
          bottom: context.pos.shellBorder,
          // Directional, so the selection mark sits on the leading edge in
          // both languages — and 2px, the one weight this system uses for
          // "this one", the same as a selected category or a selected reason.
          start: BorderSide(
            color: isSelected ? context.pos.accent : Colors.transparent,
            width: 2,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 30,
            child: Text(
              '${line.quantity}×',
              style: PosText.mono(
                size: 15,
                weight: FontWeight.w600,
                color: dimmed ? context.pos.shellMuted : context.pos.accent,
              ),
            ),
          ),
          const SizedBox(width: PosSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      // Two lines before the end ellipsis, and the ellipsis
                      // on the end the name is read from — see `ItemName`.
                      // The row grows by one line for a long name, which the
                      // list height absorbs; a name cut to half its letters
                      // is what gets the wrong dish rung up.
                      child: ItemName(
                        line.product.displayName(language),
                        maxLines: 2,
                        style:
                            PosText.ui(
                              size: density.nameSize,
                              weight: FontWeight.w600,
                              color: line.isVoided
                                  ? context.pos.shellMuted
                                  : context.pos.shellText,
                            ).copyWith(
                              decoration: line.isVoided
                                  ? TextDecoration.lineThrough
                                  : null,
                              decorationColor: context.pos.shellMuted,
                            ),
                      ),
                    ),
                    if (line.isVoided) ...[
                      const SizedBox(width: PosSpace.sm),
                      _VoidChip(),
                    ] else if (line.isCombo) ...[
                      const SizedBox(width: PosSpace.sm),
                      const _MealChip(),
                    ] else if (line.isRepriced) ...[
                      const SizedBox(width: PosSpace.sm),
                      const _RepricedChip(),
                    ],
                  ],
                ),
                // What the meal is made of, on the meta row. The kitchen reads
                // it off the docket and the customer reads it off the screen;
                // a line saying only "Lunch meal" leaves both guessing.
                if (line.combo != null)
                  Text(
                    line.combo!.summary(language),
                    style: PosText.ui(
                      size: density.metaSize,
                      color: context.pos.shellLineMeta,
                      height: 1.4,
                    ),
                  ),
                if (line.modifiers.isNotEmpty)
                  Text(
                    line.modifierSummary(language),
                    style: PosText.ui(
                      size: density.metaSize,
                      color: context.pos.shellLineMeta,
                      height: 1.4,
                    ),
                  ),
                // The kitchen's instruction, behind a 6px accent square so it
                // reads as an instruction rather than as part of the dish name.
                // Present at both densities: a note is what somebody in the
                // kitchen acts on, and hiding it to save eight pixels is how a
                // customer gets the onions they asked not to have.
                if (line.note != null && line.note!.trim().isNotEmpty)
                  _NoteRow(note: line.note!, density: density),
                // Why it went. On the meta row rather than in a chip, because
                // it is a sentence a cashier reads aloud to a customer, not a
                // status somebody scans for.
                if (line.voided?.note != null)
                  Text(
                    line.voided!.note!,
                    style: PosText.ui(
                      size: density.metaSize,
                      color: context.pos.danger,
                      height: 1.4,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: PosSpace.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // The menu price, struck through, above what is actually being
              // charged. It is the sentence a cashier reads to a customer —
              // "that was 50, it's 40" — and without it a repriced line is
              // just a line at an odd price that nobody can explain later.
              if (line.isRepriced && !line.isVoided)
                Text(
                  (line.menuUnitPrice * line.quantity).format(withCurrency: true),
                  style:
                      PosText.mono(
                        size: 11.5,
                        color: context.pos.shellMuted,
                      ).copyWith(
                        decoration: TextDecoration.lineThrough,
                        decorationColor: context.pos.shellMuted,
                      ),
                ),
              Text(
                line.lineTotal.format(withCurrency: true),
                style:
                    PosText.mono(
                      size: density.amountSize,
                      weight: FontWeight.w600,
                      color: line.isVoided
                          ? context.pos.shellMuted
                          : line.isRepriced
                          ? context.pos.accent
                          : context.pos.shellText,
                    ).copyWith(
                      // Struck through, not removed. The price is what the customer
                      // is being shown they are NOT paying.
                      decoration: line.isVoided
                          ? TextDecoration.lineThrough
                          : null,
                      decorationColor: context.pos.shellMuted,
                    ),
              ),
              if (onQuantityChanged != null && !line.isVoided) ...[
                SizedBox(height: density == CartDensity.compact ? 4 : PosSpace.sm),
                Row(
                  children: [
                    _stepper(
                      '−',
                      () => onQuantityChanged!(-1),
                      pos: context.pos,
                    ),
                    const SizedBox(width: 2),
                    _stepper(
                      '+',
                      () => onQuantityChanged!(1),
                      pos: context.pos,
                    ),
                    // No F-key: the map is full, which is an honest answer
                    // rather than a squeezed-in binding.
                    if (onEditNote != null) ...[
                      const SizedBox(width: 2),
                      _stepper('✎', onEditNote!, pos: context.pos),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );

    // A discount is a **child row of its line**, not a sibling. Drawing it as
    // its own line would make the ticket read as though something else was
    // sold; drawing it only in the totals would leave the cashier unable to
    // show a customer which item was reduced.
    final withDiscount = discount == null
        ? row
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [row, _discountRow(context, discount!)],
          );

    final selectable = onSelect == null
        ? withDiscount
        : Material(
            color: Colors.transparent,
            child: InkWell(onTap: onSelect, child: withDiscount),
          );

    return dimmed ? Opacity(opacity: 0.62, child: selectable) : selectable;
  }

  /// The discount, named, with **who approved it** when somebody did.
  ///
  /// The approver's name is the point. A line reading "Discount 30%" invites
  /// the question the cashier cannot answer at the till; one reading "approved
  /// by Hana M." has already answered it, in front of the customer.
  Widget _discountRow(BuildContext context, AppliedDiscount discount) {
    final pos = context.pos;
    final label = discount.approvedByName == null
        ? discount.nameSnapshot
        : '${discount.nameSnapshot} · ${context.strings.approvedByShort(discount.approvedByName!)}';

    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(
        PosSpace.s28,
        PosSpace.sm,
        PosSpace.lg,
        PosSpace.s10,
      ),
      decoration: BoxDecoration(
        border: BorderDirectional(
          bottom: pos.shellBorder,
          start: BorderSide(color: pos.accent, width: 2),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: PosText.mono(size: 11, color: pos.shellMuted),
            ),
          ),
          const SizedBox(width: PosSpace.sm),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              '-${discount.amount.format(withCurrency: true)}',
              style: PosText.mono(
                size: 13,
                weight: FontWeight.w600,
                color: pos.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepper(
    String glyph,
    VoidCallback onTap, {
    required PosPalette pos,
  }) => Material(
    color: pos.shellCard,
    child: InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 30,
        height: 30,
        child: Center(
          child: Text(glyph, style: PosText.ui(size: 16, color: pos.shellText)),
        ),
      ),
    ),
  );
}

/// The mark that says this line is not being charged for.
/// A line's note, on its meta row behind a 6px accent square.
///
/// The square rather than a chip or a label: a note is free text a cashier
/// typed, and wrapping it in a box would make a two-word instruction look like
/// a status. The mark says "somebody asked for this"; the words say what.
class _NoteRow extends StatelessWidget {
  const _NoteRow({required this.note, required this.density});

  final String note;
  final CartDensity density;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: density.metaGap),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsetsDirectional.only(end: 6, top: 5),
          color: context.pos.accent,
        ),
        Expanded(
          child: Text(
            note,
            style: PosText.ui(
              size: density.metaSize,
              color: context.pos.shellLineMeta,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Marks a line that is a meal rather than an item.
class _MealChip extends StatelessWidget {
  const _MealChip();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    decoration: BoxDecoration(
      border: Border.all(color: context.pos.accent.withValues(alpha: 0.6)),
    ),
    child: Text(
      context.strings.comboBadge,
      style: PosText.mono(
        size: 9.5,
        weight: FontWeight.w600,
        color: context.pos.accent,
      ),
    ),
  );
}

/// Marks a line that is not being sold at the menu price.
///
/// Accent rather than danger: repricing is a decision somebody made on purpose,
/// not a loss. The void chip beside it is danger, and the two must not read as
/// the same kind of event.
class _RepricedChip extends StatelessWidget {
  const _RepricedChip();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    decoration: BoxDecoration(
      border: Border.all(color: context.pos.accent.withValues(alpha: 0.6)),
    ),
    child: Text(
      context.strings.priceOverrideChip,
      style: PosText.mono(
        size: 9.5,
        weight: FontWeight.w600,
        color: context.pos.accent,
      ),
    ),
  );
}

class _VoidChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(border: Border.all(color: context.pos.danger)),
    child: Text(
      context.strings.lineVoidedChip,
      style: PosText.mono(
        size: 9.5,
        weight: FontWeight.w600,
        color: context.pos.danger,
        letterSpacing: 0.9,
      ),
    ),
  );
}
