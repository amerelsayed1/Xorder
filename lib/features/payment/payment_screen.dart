import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import 'customer_dialog.dart';
import '../../core/config/deployment.dart';
import '../../core/money/money.dart';
import '../../core/text/digits.dart';
import '../../app/labels.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/tokens.dart';
import '../../core/ui/widgets/fold_digits_formatter.dart';
import '../../core/ui/widgets/pos_widgets.dart';
import '../../domain/models/permissions.dart';
import '../../domain/models/tender_method.dart';
import '../../domain/models/ticket.dart';
import '../../domain/repositories/repositories.dart' show SubmitOrderResult;
import '../../domain/services/authorization.dart';
import '../admin/presentation/supervisor_override.dart';

/// A payment method offered at the till.
///
/// In production these come from `tender_types` via `GET /api/pos/config`
/// (POS-BE-013, still PROPOSED) — as data, so v1 can record a card taken on a
/// standalone bank terminal without pretending to be a processor.
/// The keypad's clear key, by identity rather than by caption.
const _clearKey = 'CLR';

/// The tender types this till offers — now read from the restaurant, not from
/// this file.
///
/// It was a constant here, then a constant in [TenderMethod], and since §40 it
/// is `pos_tender_types`. Money going back has to offer the same methods money
/// came in on, so settlement and refunds read the same provider: two lists of
/// tender types is how a till ends up refunding to a method it cannot take
/// payment on.

/// Take one or many tenders until the balance clears.
/// What a completed settlement hands back to the sale screen.
class SettledSale {
  const SettledSale({required this.ticket, required this.result});

  final Ticket ticket;
  final SubmitOrderResult result;
}

class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({super.key});

  static Future<SettledSale?> show(BuildContext context) =>
      showDialog<SettledSale?>(
        context: context,
        barrierColor: context.pos.scrim,
        builder: (_) => const PaymentScreen(),
      );

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  int _methodId = 1;
  String _entry = '';
  final _reference = TextEditingController();
  bool _busy = false;
  String? _message;

  /// Holds the idle lock off while money is part-way through this screen.
  /// Read once: [dispose] must release it without asking a [ref] that is
  /// going away.
  late final IdleLockGuard _idleGuard = ref.read(idleLockGuardProvider);

  @override
  void dispose() {
    _idleGuard.release(this);
    _reference.dispose();
    super.dispose();
  }

  Money? _parsedEntry(Ticket ticket) => _entry.isEmpty
      ? null // empty entry means "the whole remaining due"
      : Money.tryParse(
          _entry,
          currency: ticket.currency,
          exponent: ticket.exponent,
        );

  void _digit(String value) => setState(() {
    _entry += value;
    _message = null;
  });
  void _clear() => setState(() {
    _entry = '';
    _message = null;
  });

  void _quickCash(int major, Ticket ticket) => setState(() {
    _entry = Money(major * 100, currency: ticket.currency).format();
    _message = null;
  });

  /// Cloud tenders carry platform ids and cannot safely be guessed.  Offline
  /// tills retain their bootstrap fallback while the local query starts.
  List<TenderMethod> get _methods {
    final configured = ref.read(tenderTypesProvider).valueOrNull;
    final source = configured ??
        (ref.read(deploymentProvider).mode == DeploymentMode.cloud
            ? const <TenderMethod>[]
            : TenderMethod.seeded);
    // Customer receivables are not modelled yet. Recording this as an ordinary
    // tender closes the sale as paid and loses the debt, so fail closed.
    return source.where((method) => method.kind != TenderKind.account).toList();
  }

  bool get _cloudMethodsLoading =>
      ref.read(deploymentProvider).mode == DeploymentMode.cloud &&
      ref.read(tenderTypesProvider).isLoading;

  TenderMethod? get _method {
    final methods = _methods;
    for (final method in methods) {
      if (method.id == _methodId) return method;
    }
    return methods.firstOrNull;
  }

  Future<void> _take(Ticket ticket) async {
    if (_busy) return;
    final strings = context.strings;
    if (_cloudMethodsLoading) {
      setState(() => _message = strings.paymentMethodsLoading);
      return;
    }
    final controller = ref.read(ticketProvider.notifier);
    final method = _method;
    if (method == null) {
      setState(() => _message = strings.paymentMethodsLoading);
      return;
    }
    if (method.kind == TenderKind.account) {
      setState(() => _message = strings.paymentOnAccountUnavailable);
      return;
    }
    final reference = _reference.text.trim();
    if (method.requiresReference && reference.isEmpty) {
      setState(() => _message = strings.paymentReferenceRequired);
      return;
    }
    final ok = controller.addTender(
      typeId: method.id,
      label: method.wireLabel,
      // Snapshotted with the money, not resolved at cash-up. See
      // [Tender.countsAsCash].
      countsAsCash: method.countsAsCash,
      amount: _parsedEntry(ticket),
      reference: reference.isEmpty ? null : reference,
    );

    if (!ok) {
      posToast(context, strings.enterAmountAboveZero);
      return;
    }

    setState(() {
      _entry = '';
      _reference.clear();
      _message = null;
    });

    final updated = ref.read(ticketProvider);
    if (!updated.totals.isSettled) return;

    // Settled — record it, free the table, and hand the outcome back to the
    // sale screen, which owns what happens next (the receipt, and for a
    // seated ticket the walk back to the floor).
    setState(() => _busy = true);
    SubmitOrderResult result;
    try {
      result = await ref
          .read(ordersRepositoryProvider)
          // Read here rather than baked into the repository: the sale belongs to
          // whoever took the money, and on a seated table that is routinely not
          // the person who opened the ticket.
          .submit(updated, servedBy: ref.read(signedInStaffProvider));
    } on Object {
      // The database did not commit the order. Restore the exact pre-tender
      // ticket so the cashier can retry without a supervisor removing a payment
      // that never existed in the ledger.
      controller.applyEdit(ticket);
      if (mounted) {
        setState(() {
          _busy = false;
          _message = strings.paymentCouldNotBeRecorded;
        });
      }
      return;
    }
    if (!mounted) return;

    // Re-read the backlog rather than adding one to a running total. The count
    // is whatever the outbox says it is — a submit that replayed onto an
    // existing order enqueued nothing, and incrementing here would have
    // reported a sale as unsent twice.
    ref.invalidate(pendingSyncCountProvider);

    // The table's money is in the drawer — its seat is free again.
    await ref.read(openTicketsProvider.notifier).settle(updated);

    if (!mounted) return;
    Navigator.of(context).pop(SettledSale(ticket: updated, result: result));
  }

  /// The physical keyboard, which the screen ignored: the amount could only be
  /// built from the on-screen keypad, so a cashier with hands on the keys had to
  /// reach for the mouse (`docs/pos/12-design-brief.md`: keyboard-first, Enter
  /// confirms).
  ///
  /// 0-9 and the numpad add a digit, `.` and the numpad's decimal key add one
  /// point, Backspace takes the last character off, Delete clears (the keypad's
  /// CLR) and Enter collects exactly as the green button does — `_take` refuses
  /// while a settlement is in flight, so a second Enter is harmless.
  ///
  /// **Not while a text field has the keys.** The reference box takes printable
  /// keys through the text-input channel AND lets the key event bubble up to
  /// here, so without this check every digit of an authorisation code would also
  /// land in the amount.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    if (_busy) return KeyEventResult.ignored;
    final typing =
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<EditableText>() !=
        null;
    if (typing) return KeyEventResult.ignored;

    // Cmd/Ctrl/Alt chords are somebody's shortcut, not an amount.
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    // **The character, then the key.** With an Arabic layout on, the digit row
    // reports the Arabic digit's own logical key rather than `digit5`, so a map
    // of keys alone ignored exactly the cashier who types in Arabic. What the
    // key typed is folded to ASCII (as the reference box does) and the key map
    // stays as the fall-back for an event that carries no character.
    final typed = event.character == null ? null : foldDigits(event.character!);
    final digit = amountDigitFor(event.character, key);
    if (digit != null) {
      _digit(digit);
      return KeyEventResult.handled;
    }
    if (typed == '.' ||
        key == LogicalKeyboardKey.period ||
        key == LogicalKeyboardKey.numpadDecimal) {
      if (!_entry.contains('.')) _digit(_entry.isEmpty ? '0.' : '.');
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace) {
      if (_entry.isNotEmpty) {
        setState(() {
          _entry = _entry.substring(0, _entry.length - 1);
          _message = null;
        });
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete) {
      _clear();
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent &&
        (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter)) {
      _take(ref.read(ticketProvider));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild the dialog when configured tenders arrive; event handlers use
    // `read` so they never subscribe outside the build phase.
    ref.watch(tenderTypesProvider);
    final ticket = ref.watch(ticketProvider);
    final totals = ticket.totals;
    final strings = context.strings;

    // **No idle lock while money is in flight**: a settlement waiting on the
    // database, or a ticket part-paid with the balance still to take. Locking
    // closes every dialog, and closing this one mid-settlement leaves an order
    // committed with nobody to print it, free its table or clear the screen.
    // Merely open, with nothing taken, it is only a view of the bill — the
    // lock closes it as Back would, and the ticket is untouched. The cost is
    // that a cashier who walks off half-way through a split payment leaves the
    // till unlocked until they come back. Chosen over locking a part-paid bill
    // because the tenders already taken would then sit on a ticket behind a
    // lock screen, for whoever signs in next to find; whether that trade is
    // right is open (ADR-006), and this is the one line to change if not.
    if (_busy || ticket.tenders.isNotEmpty) {
      _idleGuard.hold(this);
    } else {
      _idleGuard.release(this);
    }

    final dialog = Dialog(
      backgroundColor: context.pos.surface,
      insetPadding: const EdgeInsets.all(PosSpace.s24),
      shape: RoundedRectangleBorder(
        side: context.pos.emphasis,
        borderRadius: PosBorders.radius,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 660),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(strings, ticket),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _left(strings, ticket, totals)),
                  SizedBox(width: 400, child: _right(strings, ticket, totals)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return Focus(autofocus: true, onKeyEvent: _onKey, child: dialog);
  }

  Widget _header(AppStrings strings, Ticket ticket) => Container(
    height: PosSize.secondaryAction,
    color: context.pos.ink,
    padding: const EdgeInsets.symmetric(horizontal: PosSpace.md),
    child: Row(
      children: [
        PosButton(
          label: strings.backToTicket,
          height: 36,
          background: context.pos.shellCard,
          foreground: context.pos.shellText,
          fontSize: 12.5,
          onPressed: () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: PosSpace.md),
        Text(
          strings.payment,
          style: PosText.ui(
            size: 15,
            weight: FontWeight.w800,
            color: context.pos.onInk,
          ),
        ),
        const Spacer(),
        // Who the food is for (POS-BE-014). On the payment header rather than
        // on the sale screen because this is where a phone number is given:
        // the cashier asks for it while they are taking the money, not while
        // they are ringing the food up.
        PosButton(
          label: ticket.customer?.name ?? strings.walkInCustomer,
          height: 36,
          background: context.pos.shellCard,
          foreground: context.pos.shellText,
          fontSize: 12.5,
          onPressed: _chooseCustomer,
        ),
        const SizedBox(width: PosSpace.md),
        Text(
          [
            ticket.orderType.label(strings),
            if (ticket.tableLabel != null) ticket.tableLabel!,
            strings.lineCount(ticket.lines.length),
          ].join(' · '),
          style: PosText.mono(size: 11.5, color: context.pos.shellMuted),
        ),
      ],
    ),
  );

  /// Attach, replace or remove the customer on this ticket.
  ///
  /// Nothing here touches the money: a customer is who, not what, and the
  /// totals are the same either way. So this never refuses and never has to
  /// be undone if the cashier picked the wrong person — they open it again.
  Future<void> _chooseCustomer() => chooseCustomerForTicket(context, ref);

  Widget _left(AppStrings strings, Ticket ticket, TicketTotals totals) =>
      Container(
        color: context.pos.page,
        padding: const EdgeInsets.all(PosSpace.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _dueCard(strings, ticket, totals),
            const SizedBox(height: PosSpace.s14),
            Expanded(child: _tendersCard(strings, ticket)),
          ],
        ),
      );

  Widget _dueCard(AppStrings strings, Ticket ticket, TicketTotals totals) =>
      PosSurface(
        border: Border.fromBorderSide(context.pos.emphasis),
        padding: const EdgeInsets.all(PosSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                MicroLabel(
                  ticket.tenders.isEmpty
                      ? strings.amountDue
                      : strings.remainingDue,
                ),
                const Spacer(),
                Text(
                  strings.totalIs(totals.total.format(withCurrency: true)),
                  style: PosText.mono(size: 12, color: context.pos.muted),
                ),
              ],
            ),
            const SizedBox(height: PosSpace.sm),
            Text(totals.due.format(withCurrency: true), style: PosText.bigNumeric(color: context.pos.ink)),
            if (_afterEntry(ticket, totals) case final after?) ...[
              const SizedBox(height: PosSpace.sm),
              _afterEntryLine(strings, after),
            ],
            const SizedBox(height: PosSpace.md),
            _progress(totals),
            const SizedBox(height: PosSpace.sm),
            Text(
              strings.paidOfTotal(
                totals.paid.format(withCurrency: true),
                totals.total.format(withCurrency: true),
                ticket.tenders.length,
              ),
              style: PosText.ui(size: 12, color: context.pos.muted),
            ),
          ],
        ),
      );

  /// What the typed amount leaves: positive is still owed, negative is
  /// change to hand back. Null while nothing (or nothing readable) is typed and
  /// when it is exactly the due, where there is nothing to say.
  ///
  /// Display only — the engine still takes the tender and works out `change`
  /// itself, and the receipt prints the same figure. This is the cashier seeing
  /// it BEFORE pressing Collect rather than on the receipt after the sale.
  Money? _afterEntry(Ticket ticket, TicketTotals totals) {
    final entered = _parsedEntry(ticket);
    if (entered == null || !entered.isPositive) return null;
    final after = totals.due - entered;
    return after.isZero ? null : after;
  }

  Widget _afterEntryLine(AppStrings strings, Money after) {
    final change = after.isNegative;
    return Row(
      key: const Key('payment-after-entry'),
      children: [
        MicroLabel(change ? strings.changeDue : strings.remainingDue),
        const Spacer(),
        Text(
          (change ? -after : after).format(withCurrency: true),
          key: const Key('payment-after-entry-amount'),
          style: PosText.mono(
            size: 20,
            weight: FontWeight.w700,
            color: change ? context.pos.ok : context.pos.ink,
          ),
        ),
      ],
    );
  }

  Widget _progress(TicketTotals totals) {
    final ratio = totals.total.isZero
        ? 0.0
        : (totals.paid.minor / totals.total.minor).clamp(0.0, 1.0);

    return SizedBox(
      height: 8,
      child: Row(
        children: [
          Expanded(
            flex: (ratio * 1000).round(),
            child: ColoredBox(color: context.pos.ok),
          ),
          Expanded(
            flex: 1000 - (ratio * 1000).round(),
            child: ColoredBox(color: context.pos.line),
          ),
        ],
      ),
    );
  }

  Widget _tendersCard(AppStrings strings, Ticket ticket) => PosSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(PosSpace.md),
          child: MicroLabel(strings.tendersHeading),
        ),
        if (ticket.tenders.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: PosSpace.lg),
            child: Text(
              strings.noTenderYet,
              style: PosText.ui(
                size: 12.5,
                color: context.pos.muted,
                height: 1.5,
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              itemCount: ticket.tenders.length,
              itemBuilder: (context, index) =>
                  _tenderRow(strings, ticket, index),
            ),
          ),
      ],
    ),
  );

  /// Take a payment back off, on the person's own permission or a
  /// supervisor's. It used to be a tap with no question behind it.
  Future<void> _removeTender(Ticket ticket, int index) async {
    final strings = context.strings;
    final tender = ticket.tenders[index];

    final decision = await requestPermission(
      context,
      ref,
      PosCapability.paymentRemove,
      action: strings.removePaymentTitle(
        '${tenderName(tender.typeId, tender.label, strings)} · '
        '${tender.amount.format(withCurrency: true)}',
      ),
      auditAction: 'payment.removed',
      entityId: ticket.id,
      approveLabel: strings.removePaymentAction,
    );
    if (!mounted || decision is! Allowed) return;

    final refused = ref
        .read(ticketProvider.notifier)
        .removeTenderAt(
          index,
          by: ref.read(signedInStaffProvider),
          approval: decision.approval,
        );
    if (refused != null && mounted) {
      posToast(context, strings.removePaymentRefused);
    }
  }

  Widget _tenderRow(AppStrings strings, Ticket ticket, int index) {
    final tender = ticket.tenders[index];

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: PosSpace.lg,
        vertical: PosSpace.md,
      ),
      decoration: BoxDecoration(border: Border(top: context.pos.hairline)),
      child: Row(
        children: [
          Expanded(
            child: Text(
              tenderName(tender.typeId, tender.label, strings),
              style: PosText.ui(color: context.pos.inkWarm, size: 13, weight: FontWeight.w600),
            ),
          ),
          Text(tender.amount.format(withCurrency: true), style: PosText.mono(color: context.pos.inkWarm, size: 15)),
          const SizedBox(width: PosSpace.md),
          InkWell(
            onTap: () => _removeTender(ticket, index),
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.fromBorderSide(context.pos.hairline),
              ),
              child: Text(
                '×',
                style: PosText.ui(size: 16, color: context.pos.danger),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _right(AppStrings strings, Ticket ticket, TicketTotals totals) =>
      Container(
        decoration: BoxDecoration(
          color: context.pos.surface,
          // Directional, so the rule stays between the two panels rather than
          // running down the outside edge of the window in Arabic.
          border: BorderDirectional(start: context.pos.emphasis),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _methodGrid(strings),
            _amountBlock(strings, ticket, totals),
            if ((_method?.requiresReference ?? false))
              _referenceField(strings),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  PosSpace.md,
                  PosSpace.sm,
                  PosSpace.md,
                  0,
                ),
                child: Text(
                  _message!,
                  style: PosText.ui(size: 12, color: context.pos.danger),
                ),
              ),
            Expanded(child: _keypad(strings)),
            PosButton(
              label: strings.takePayment,
              height: 72,
              alignLeft: true,
              background: _busy || _cloudMethodsLoading || _method == null
                  ? context.pos.ctaDisabled
                  : context.pos.ok,
              foreground: context.pos.onOk,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              padding: const EdgeInsets.symmetric(horizontal: PosSpace.lg),
              trailing: Text(
                (_parsedEntry(ticket) ?? totals.due).format(withCurrency: true),
                style: PosText.mono(
                  size: 16,
                  weight: FontWeight.w600,
                  color: context.pos.onOk,
                ),
              ),
              onPressed: _busy || _cloudMethodsLoading || _method == null
                  ? null
                  : () => _take(ticket),
            ),
          ],
        ),
      );

  Widget _methodGrid(AppStrings strings) => Container(
    color: context.pos.lineStrong,
    child: GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 1,
      crossAxisSpacing: 1,
      childAspectRatio: 200 / 64,
      children: [
        for (final method in _methods)
          Material(
            color: method.id == _method?.id
                ? context.pos.ink
                : context.pos.surface,
            child: InkWell(
              onTap: _busy
                  ? null
                  : () => setState(() {
                      _methodId = method.id;
                      _message = null;
                    }),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: PosSpace.s14),
                child: Align(
                  // Directional: this label sits at the START of its tile, which
                  // is the right-hand edge in Arabic. `centerLeft` pinned it to
                  // the far side, so every method read as though it belonged to
                  // the tile beside it.
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    method.label(strings),
                    style: PosText.ui(
                      size: 13.5,
                      weight: FontWeight.w600,
                      color: method.id == _method?.id
                          ? context.pos.onInk
                          : context.pos.inkWarm,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _amountBlock(AppStrings strings, Ticket ticket, TicketTotals totals) =>
      Container(
        padding: const EdgeInsets.all(PosSpace.md),
        decoration: BoxDecoration(
          border: Border(top: context.pos.emphasis, bottom: context.pos.hairline),
        ),
        child: Column(
          children: [
            Row(
              children: [
                MicroLabel(strings.amount),
                const Spacer(),
                Text(
                  _entry.isEmpty ? totals.due.format(withCurrency: true) : '$_entry ${totals.total.currency}',
                  style: PosText.mono(
                    size: 22,
                    color: _entry.isEmpty ? context.pos.muted : context.pos.ink,
                  ),
                ),
              ],
            ),
            const SizedBox(height: PosSpace.md),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: PosSpace.sm,
              crossAxisSpacing: PosSpace.sm,
              childAspectRatio: 120 / PosSize.minTouchTarget,
              children: [
                for (final amount in [50, 100, 200, 500, 1000])
                  PosButton(
                    label: '$amount',
                    background: context.pos.page,
                    border: Border.fromBorderSide(context.pos.resting),
                    onPressed: () => _quickCash(amount, ticket),
                  ),
                PosButton(
                  label: strings.exact,
                  background: context.pos.page,
                  border: Border.fromBorderSide(context.pos.resting),
                  onPressed: () => setState(() => _entry = totals.due.format()),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _referenceField(AppStrings strings) => Padding(
    padding: const EdgeInsets.fromLTRB(
      PosSpace.md,
      PosSpace.sm,
      PosSpace.md,
      0,
    ),
    child: TextField(
      controller: _reference,
      enabled: !_busy,
      maxLength: 80,
      // An approval code or a receipt number, searched for later by typing it
      // in again: ASCII whatever the keyboard produced (XORD-004).
      inputFormatters: const [FoldDigitsFormatter()],
      onChanged: (_) => setState(() => _message = null),
      onSubmitted: (_) => _take(ref.read(ticketProvider)),
      decoration: InputDecoration(
        labelText: strings.paymentReferenceLabel,
        counterText: '',
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: context.pos.resting,
        ),
      ),
    ),
  );

  /// The keypad fills the remaining height as a flex grid rather than a
  /// GridView. A GridView scrolls, and a scrolled keypad silently hides a key —
  /// which is how a cashier ends up unable to find CLR mid-transaction.
  Widget _keypad(AppStrings strings) {
    // 'CLR' is the key's IDENTITY, not its caption — [_key] translates it on
    // the way to the screen. The digits are captions and identities at once,
    // and stay Western in both languages: this pad feeds an amount that is
    // read back off a receipt and counted into a drawer.
    const rows = [
      ['7', '8', '9'],
      ['4', '5', '6'],
      ['1', '2', '3'],
      ['0', '00', _clearKey],
    ];

    return Container(
      color: context.pos.line,
      padding: const EdgeInsets.only(top: 1),
      child: Column(
        children: [
          for (final row in rows)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 1),
                child: Row(
                  children: [
                    for (final key in row) ...[
                      Expanded(child: _key(strings, key)),
                      if (key != row.last) const SizedBox(width: 1),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _key(AppStrings strings, String key) {
    final isClear = key == _clearKey;

    return Material(
      color: isClear ? context.pos.page : context.pos.surface,
      child: InkWell(
        onTap: () => isClear ? _clear() : _digit(key),
        child: Center(
          child: Text(
            isClear ? strings.clear : key,
            style: isClear
                ? PosText.ui(size: 13, color: context.pos.chipText)
                : PosText.mono(color: context.pos.inkWarm, size: 20, weight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

/// The ASCII digit a key press means for the amount, or null: the typed
/// [character] first (folded, so `٥` is `5`), the [key] when it carries none.
@visibleForTesting
String? amountDigitFor(String? character, LogicalKeyboardKey key) {
  if (character != null) {
    final typed = foldDigits(character);
    if (typed.length == 1 &&
        typed.codeUnitAt(0) >= 0x30 &&
        typed.codeUnitAt(0) <= 0x39) {
      return typed;
    }
  }
  return _digitForKey(key);
}

String? _digitForKey(LogicalKeyboardKey key) {
  const digits = {
    '0': [LogicalKeyboardKey.digit0, LogicalKeyboardKey.numpad0],
    '1': [LogicalKeyboardKey.digit1, LogicalKeyboardKey.numpad1],
    '2': [LogicalKeyboardKey.digit2, LogicalKeyboardKey.numpad2],
    '3': [LogicalKeyboardKey.digit3, LogicalKeyboardKey.numpad3],
    '4': [LogicalKeyboardKey.digit4, LogicalKeyboardKey.numpad4],
    '5': [LogicalKeyboardKey.digit5, LogicalKeyboardKey.numpad5],
    '6': [LogicalKeyboardKey.digit6, LogicalKeyboardKey.numpad6],
    '7': [LogicalKeyboardKey.digit7, LogicalKeyboardKey.numpad7],
    '8': [LogicalKeyboardKey.digit8, LogicalKeyboardKey.numpad8],
    '9': [LogicalKeyboardKey.digit9, LogicalKeyboardKey.numpad9],
  };
  for (final entry in digits.entries) {
    if (entry.value.contains(key)) return entry.key;
  }
  return null;
}
