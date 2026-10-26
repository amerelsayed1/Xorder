import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/mono_amount.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../core/ui/widgets/reason_picker.dart';
import '../../../domain/models/purchase_order.dart';
import '../../../domain/models/reason_code.dart';
import '../../../domain/models/shift.dart';
import '../../../domain/repositories/admin_repositories.dart';
import '../../../domain/models/supplier.dart';
import '../../../domain/models/supplier_invoice.dart';
import 'admin_messages.dart';
import 'purchase_order_dialog.dart';
import 'stock_item_dialog.dart';
import '../../../domain/models/stock_item.dart';
import 'receive_dialog.dart';
import 'supplier_dialog.dart';
import 'supplier_invoice_dialog.dart';
import 'supplier_payment_dialog.dart';

/// What the restaurant buys, and who from.
///
/// **Its own pane rather than a section of an existing one.** Purchasing is a
/// different job done by a different person on a different day from anything
/// else in Management, and the Money pane is already three sections deep. It is
/// also the first area whose daily use is a *flow* — an order goes out, goods
/// arrive against it — rather than a form somebody edits, which is why the
/// orders list leads and the suppliers sit behind it.
class ManagementPurchasingPane extends ConsumerStatefulWidget {
  const ManagementPurchasingPane({
    required this.admin,
    this.initialTab = PurchasingTab.orders,
    this.create = false,
    this.request,
    super.key,
  });

  final PosStaff admin;

  /// Which half of buying to open on.
  final PurchasingTab initialTab;

  /// Whether to start a new one straight away — "New order" from the menu bar
  /// means the order form, not the list with the button on it.
  final bool create;

  /// A fresh object per request from outside, so the same request twice is
  /// still two requests. See `_answered`.
  final Object? request;

  @override
  ConsumerState<ManagementPurchasingPane> createState() =>
      _ManagementPurchasingPaneState();
}

/// The four halves of buying. Public so a menu can open the one it means.
enum PurchasingTab { orders, suppliers, invoices, payments }

class _ManagementPurchasingPaneState
    extends ConsumerState<ManagementPurchasingPane> {
  late PurchasingTab _tab = widget.initialTab;
  bool _busy = false;
  String? _note;

  /// Requests already acted on, across every state this pane will ever have.
  ///
  /// Keyed on the request object rather than a flag on this state: the state
  /// is rebuilt when somebody switches area and comes back, and a flag there
  /// would open "New order" all over again. The request is what was asked for,
  /// and it is answered exactly once.
  static final _answered = Expando<bool>('purchasing requests answered');

  @override
  void initState() {
    super.initState();
    _maybeCreate();
  }

  /// Follow a NEW request from outside — "Invoices" from the menu bar while
  /// already on orders. The same bug the management screen had: a field
  /// initialised once would otherwise keep showing whatever was already open.
  @override
  void didUpdateWidget(ManagementPurchasingPane old) {
    super.didUpdateWidget(old);
    if (!identical(widget.request, old.request)) {
      setState(() => _tab = widget.initialTab);
      _maybeCreate();
    }
  }

  void _maybeCreate() {
    final request = widget.request;
    if (!widget.create || request == null || _answered[request] == true) {
      return;
    }
    _answered[request] = true;
    // After the frame: a dialog opened during build has no Navigator to open
    // into yet.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_busy) _create(_tab);
    });
  }

  /// Start a new one of whatever this tab lists. Payments are settled against
  /// an invoice, so "new" on that tab enters the invoice they will pay.
  Future<void> _create(PurchasingTab tab) => switch (tab) {
    PurchasingTab.orders => _editOrder(null),
    PurchasingTab.invoices || PurchasingTab.payments => _editInvoice(null),
    PurchasingTab.suppliers => _editSupplier(null),
  };

  void _refresh() => ref
    ..invalidate(purchaseOrdersProvider)
    ..invalidate(suppliersProvider)
    ..invalidate(unpaidInvoicesProvider)
    ..invalidate(supplierPaymentsProvider)
    ..invalidate(supplierBalancesProvider);

  Future<void> _run(Future<AdminRefusal?> Function() action) async {
    setState(() {
      _busy = true;
      _note = null;
    });
    final refusal = await action();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _note = refusal == null
          ? null
          : AdminText.refusal(context.strings, refusal);
    });
    if (refusal == null) _refresh();
  }

  Future<void> _editSupplier(Supplier? supplier) async {
    final edited = await SupplierDialog.show(
      context,
      supplier: supplier,
      languages: ref.read(contentLanguagesNowProvider),
    );
    if (edited == null || !mounted) return;
    await _run(
      () async => (await ref
              .read(suppliersRepositoryProvider)
              .save(edited, by: widget.admin))
          .refusal,
    );
  }

  Future<void> _editOrder(PurchaseOrder? order) async {
    final suppliers = ref.read(suppliersProvider).valueOrNull ?? const [];
    if (suppliers.isEmpty) {
      // The one dead end worth catching before the dialog opens: an order
      // needs somebody to send it to, and a supplier picker with nothing in it
      // explains nothing.
      setState(() => _note = context.strings.purchaseNeedsASupplier);
      return;
    }

    // Loaded here, before the dialog, so the line picker has them the moment
    // somebody types. An item can be added from a line only where this till
    // writes its own products — see `_authoringPanes`.
    final items = await ref.read(stockItemsProvider.future);
    final units = await ref.read(unitsProvider.future);
    if (!mounted) return;
    final addsItems = ref.read(catalogAdminRepositoryProvider) != null;

    final edited = await PurchaseOrderDialog.show(
      context,
      order: order,
      suppliers: suppliers,
      items: items,
      units: units,
      onCreateItem: addsItems ? _createItem : null,
    );
    if (edited == null || !mounted) return;
    await _run(
      () async => (await ref
              .read(purchaseOrdersRepositoryProvider)
              .saveDraft(edited, by: widget.admin))
          .refusal,
    );
  }

  /// "Add as a new item", from a purchase line: the item dialog with what was
  /// typed, then the item handed back to the line that asked.
  Future<StockItem?> _createItem(String name) async {
    final units = await ref.read(unitsProvider.future);
    if (!mounted) return null;
    final draft = await StockItemDialog.show(
      context,
      units: units,
      initialName: name,
      languages: ref.read(contentLanguagesNowProvider),
    );
    if (draft == null || !mounted) return null;

    final result = await ref
        .read(stockItemsRepositoryProvider)
        .save(draft, by: widget.admin);
    if (!mounted) return null;
    if (!result.succeeded) {
      setState(
        () => _note = AdminText.refusal(context.strings, result.refusal!),
      );
      return null;
    }
    ref
      ..invalidate(stockItemsProvider)
      ..invalidate(stockItemsAllProvider);
    return result.value;
  }

  Future<void> _send(PurchaseOrder order) => _run(
    () async => (await ref
            .read(purchaseOrdersRepositoryProvider)
            .setStatus(
              order.id,
              status: PurchaseStatus.sent,
              by: widget.admin,
              orderedAt: DateTime.now(),
            ))
        .refusal,
  );

  Future<void> _cancel(PurchaseOrder order) => _run(
    () async => (await ref
            .read(purchaseOrdersRepositoryProvider)
            .setStatus(order.id, status: PurchaseStatus.cancelled, by: widget.admin))
        .refusal,
  );

  Future<void> _editInvoice(SupplierInvoice? invoice) async {
    final suppliers = ref.read(suppliersProvider).valueOrNull ?? const [];
    if (suppliers.isEmpty) {
      setState(() => _note = context.strings.purchaseNeedsASupplier);
      return;
    }

    final edited = await SupplierInvoiceDialog.show(
      context,
      suppliers: suppliers,
      invoice: invoice,
      orders: ref.read(purchaseOrdersProvider).valueOrNull ?? const [],
    );
    if (edited == null || !mounted) return;
    await _run(
      () async => (await ref
              .read(supplierInvoicesRepositoryProvider)
              .save(edited, by: widget.admin))
          .refusal,
    );
  }

  Future<void> _pay(SupplierInvoice? invoice, {Supplier? supplier}) async {
    final suppliers = ref.read(suppliersProvider).valueOrNull ?? const [];
    final unpaid = ref.read(unpaidInvoicesProvider).valueOrNull ?? const [];
    final who =
        supplier ??
        suppliers.where((s) => s.id == invoice?.supplierId).firstOrNull;
    if (who == null) {
      setState(() => _note = context.strings.purchaseNeedsASupplier);
      return;
    }

    final request = await SupplierPaymentDialog.show(
      context,
      supplier: who,
      invoice: invoice,
      unpaid: [
        for (final i in unpaid)
          if (i.supplierId == who.id) i,
      ],
      openShift: ref.read(shiftProvider).valueOrNull,
    );
    if (request == null || !mounted) return;
    await _run(
      () async => (await ref
              .read(supplierInvoicesRepositoryProvider)
              .pay(
                request.payment,
                by: widget.admin,
                fromShiftId: request.fromShiftId,
              ))
          .refusal,
    );

    // The expected drawer and its movement list have both changed underneath
    // whatever is showing them — the same invalidation the till's own pay-out
    // does, for the same reason.
    if (request.comesOutOfTheDrawer) {
      ref.invalidate(shiftProvider);
      ref.invalidate(cashMovementsProvider(request.fromShiftId!));
    }
  }

  Future<void> _voidInvoice(SupplierInvoice invoice) async {
    // **The restaurant's own list, not a free-text box.** Cancelling a purchase
    // invoice is one more act in the family `ReasonPicker` exists for — void,
    // refund, pay-out, price override — and asking it a seventh slightly
    // different way is how a restaurant ends up unable to report across them.
    final reasons =
        ref.read(reasonCodesProvider(ReasonScope.invoiceVoid)).valueOrNull ??
        const [];
    if (reasons.isEmpty) {
      setState(() => _note = context.strings.reasonListEmpty);
      return;
    }

    final picked = await ReasonSheet.show(
      context,
      reasons: reasons,
      requirement: SystemReasons.defaultRequirement(ReasonScope.invoiceVoid),
      title: context.strings.invoiceVoidWhy,
      confirmLabel: context.strings.invoiceVoid,
    );
    if (picked?.reasonId == null || !mounted) return;
    await _run(
      () async => (await ref
              .read(supplierInvoicesRepositoryProvider)
              .voidInvoice(
                invoice.id,
                reasonId: picked!.reasonId!,
                note: picked.note,
                by: widget.admin,
              ))
          .refusal,
    );
  }

  Future<void> _voidPayment(SupplierPayment payment) async {
    final reasons =
        ref.read(reasonCodesProvider(ReasonScope.paymentVoid)).valueOrNull ??
        const [];
    if (reasons.isEmpty) {
      setState(() => _note = context.strings.reasonListEmpty);
      return;
    }

    final picked = await ReasonSheet.show(
      context,
      reasons: reasons,
      requirement: SystemReasons.defaultRequirement(ReasonScope.paymentVoid),
      title: context.strings.paymentVoidWhy,
      confirmLabel: context.strings.paymentVoid,
    );
    if (picked?.reasonId == null || !mounted) return;
    await _run(
      () async => (await ref
              .read(supplierInvoicesRepositoryProvider)
              .voidPayment(
                payment.id,
                reasonId: picked!.reasonId!,
                note: picked.note,
                by: widget.admin,
              ))
          .refusal,
    );
  }

  Future<void> _receive(PurchaseOrder order) async {
    final booked = await ReceiveDialog.show(context, order: order);
    if (booked == null || !mounted) return;
    await _run(
      () async => (await ref
              .read(receivingRepositoryProvider)
              .receive(
                purchaseOrderId: order.id,
                byLine: booked,
                by: widget.admin,
              ))
          .refusal,
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;

    // Watched, not read when the payment dialog opens. `ref.read` on a provider
    // nothing else is watching starts the future and hands back `AsyncLoading`,
    // so the first payment of the session would be told no shift was open when
    // one was — and would silently not touch the drawer. The cash dialogs learnt
    // this the same way.
    ref.watch(shiftProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(PosSpace.xl),
          decoration: BoxDecoration(border: Border(bottom: palette.hairline)),
          child: Row(
            children: [
              PosButton(
                key: const Key('purchasing-orders'),
                label: strings.purchaseOrders,
                background: _tab == PurchasingTab.orders
                    ? palette.ink
                    : Colors.transparent,
                foreground: _tab == PurchasingTab.orders ? palette.onInk : null,
                border: Border.fromBorderSide(palette.resting),
                onPressed: () => setState(() => _tab = PurchasingTab.orders),
              ),
              // The owner's map orders these (14 Sep 2026): orders, who they
              // go to, what arrives against them, and what settles that. The
              // bar's Purchasing menu lists them in the same order.
              const SizedBox(width: PosSpace.sm),
              PosButton(
                key: const Key('purchasing-suppliers'),
                label: strings.suppliers,
                background: _tab == PurchasingTab.suppliers
                    ? palette.ink
                    : Colors.transparent,
                foreground: _tab == PurchasingTab.suppliers ? palette.onInk : null,
                border: Border.fromBorderSide(palette.resting),
                onPressed: () => setState(() => _tab = PurchasingTab.suppliers),
              ),
              const SizedBox(width: PosSpace.sm),
              PosButton(
                key: const Key('purchasing-invoices'),
                label: strings.supplierInvoices,
                background: _tab == PurchasingTab.invoices
                    ? palette.ink
                    : Colors.transparent,
                foreground: _tab == PurchasingTab.invoices ? palette.onInk : null,
                border: Border.fromBorderSide(palette.resting),
                onPressed: () => setState(() => _tab = PurchasingTab.invoices),
              ),
              const SizedBox(width: PosSpace.sm),
              PosButton(
                key: const Key('purchasing-payments'),
                label: strings.paymentsList,
                background: _tab == PurchasingTab.payments
                    ? palette.ink
                    : Colors.transparent,
                foreground: _tab == PurchasingTab.payments ? palette.onInk : null,
                border: Border.fromBorderSide(palette.resting),
                onPressed: () => setState(() => _tab = PurchasingTab.payments),
              ),
              const Spacer(),
              PosButton(
                key: const Key('purchasing-new'),
                label: switch (_tab) {
                  PurchasingTab.orders => strings.purchaseOrderNew,
                  PurchasingTab.invoices || PurchasingTab.payments => strings.invoiceNew,
                  PurchasingTab.suppliers => strings.supplierNew,
                },
                background: palette.accent,
                foreground: Colors.white,
                fontWeight: FontWeight.w700,
                onPressed: _busy ? null : () => _create(_tab),
              ),
            ],
          ),
        ),
        if (_note != null)
          Container(
            padding: const EdgeInsets.all(PosSpace.md),
            color: palette.dangerSoft,
            child: Text(
              _note!,
              style: PosText.ui(size: 12.5, color: palette.danger, height: 1.5),
            ),
          ),
        Expanded(
          child: switch (_tab) {
            PurchasingTab.orders => _orders(strings),
            PurchasingTab.invoices => _invoices(strings),
            PurchasingTab.payments => _payments(strings),
            PurchasingTab.suppliers => _suppliers(strings),
          },
        ),
      ],
    );
  }

  Widget _orders(AppStrings strings) => ref
      .watch(purchaseOrdersProvider)
      .when(
        loading: () => Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: context.pos.accent,
          ),
        ),
        error: (error, _) => _Centred(text: '$error'),
        data: (orders) => orders.isEmpty
            ? _Centred(text: strings.purchaseNoOrdersYet)
            : ListView.builder(
                itemCount: orders.length,
                itemBuilder: (context, index) => _OrderRow(
                  order: orders[index],
                  busy: _busy,
                  onEdit: () => _editOrder(orders[index]),
                  onSend: () => _send(orders[index]),
                  onCancel: () => _cancel(orders[index]),
                  onReceive: () => _receive(orders[index]),
                ),
              ),
      );

  /// **The unpaid list, not every invoice.** A restaurant three years old has
  /// thousands of settled ones; this pane is a worklist — what has to be paid,
  /// and what is late.
  Widget _invoices(AppStrings strings) => ref
      .watch(unpaidInvoicesProvider)
      .when(
        loading: () => Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: context.pos.accent,
          ),
        ),
        error: (error, _) => _Centred(text: '$error'),
        data: (invoices) => invoices.isEmpty
            ? _Centred(text: strings.invoiceNoneOutstanding)
            : ListView.builder(
                itemCount: invoices.length,
                itemBuilder: (context, index) => _InvoiceRow(
                  invoice: invoices[index],
                  busy: _busy,
                  onEdit: () => _editInvoice(invoices[index]),
                  onPay: () => _pay(invoices[index]),
                  onVoid: () => _voidInvoice(invoices[index]),
                ),
              ),
      );

  Widget _payments(AppStrings strings) => ref
      .watch(supplierPaymentsProvider)
      .when(
        loading: () => Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: context.pos.accent,
          ),
        ),
        error: (error, _) => _Centred(text: '$error'),
        data: (payments) => payments.isEmpty
            ? _Centred(text: strings.paymentNonePaidYet)
            : ListView.builder(
                itemCount: payments.length,
                itemBuilder: (context, index) => _PaymentRow(
                  payment: payments[index],
                  busy: _busy,
                  onVoid: () => _voidPayment(payments[index]),
                ),
              ),
      );

  Widget _suppliers(AppStrings strings) => ref
      .watch(suppliersProvider)
      .when(
        loading: () => Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: context.pos.accent,
          ),
        ),
        error: (error, _) => _Centred(text: '$error'),
        data: (suppliers) => suppliers.isEmpty
            ? _Centred(text: strings.purchaseNoSuppliersYet)
            : ListView.builder(
                itemCount: suppliers.length,
                itemBuilder: (context, index) => _SupplierRow(
                  supplier: suppliers[index],
                  balance: ref
                      .watch(supplierBalancesProvider)
                      .valueOrNull
                      ?.where((b) => b.supplierId == suppliers[index].id)
                      .firstOrNull,
                  onEdit: () => _editSupplier(suppliers[index]),
                  onPay: () => _pay(null, supplier: suppliers[index]),
                ),
              ),
      );
}

class _OrderRow extends StatelessWidget {
  const _OrderRow({
    required this.order,
    required this.busy,
    required this.onEdit,
    required this.onSend,
    required this.onCancel,
    required this.onReceive,
  });

  final PurchaseOrder order;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onSend;
  final VoidCallback onCancel;
  final VoidCallback onReceive;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;

    return Container(
      padding: const EdgeInsets.all(PosSpace.lg),
      decoration: BoxDecoration(border: Border(bottom: palette.hairline)),
      child: Row(
        children: [
          SizedBox(width: 160, child: MonoCode(order.reference, size: 12.5)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.supplierName ?? '',
                  style: PosText.ui(size: 13.5, color: palette.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  strings.purchaseLineCount(order.lines.length),
                  style: PosText.ui(size: 11.5, color: palette.muted),
                ),
              ],
            ),
          ),
          _StatusChip(status: order.status),
          const SizedBox(width: PosSpace.md),
          MonoAmount(order.totals.total, size: 13.5),
          const SizedBox(width: PosSpace.lg),

          // One button per state, not four greyed out. A row that offered
          // "Send" on a received order would be asking somebody to work out
          // which of four things is currently legal.
          if (order.status == PurchaseStatus.draft) ...[
            PosButton(
              label: strings.edit,
              border: Border.fromBorderSide(palette.resting),
              onPressed: busy ? null : onEdit,
            ),
            const SizedBox(width: PosSpace.sm),
            PosButton(
              key: Key('purchase-send-${order.id}'),
              label: strings.purchaseSend,
              background: palette.ink,
              foreground: palette.onInk,
              onPressed: busy ? null : onSend,
            ),
          ] else if (order.status.isOpen) ...[
            PosButton(
              key: Key('purchase-receive-${order.id}'),
              label: strings.purchaseReceive,
              background: palette.accent,
              foreground: Colors.white,
              fontWeight: FontWeight.w700,
              onPressed: busy ? null : onReceive,
            ),
            if (order.status == PurchaseStatus.sent) ...[
              const SizedBox(width: PosSpace.sm),
              PosButton(
                label: strings.cancel,
                foreground: palette.danger,
                border: Border.fromBorderSide(palette.resting),
                onPressed: busy ? null : onCancel,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final PurchaseStatus status;

  @override
  Widget build(BuildContext context) {
    final palette = context.pos;
    final (background, ink) = switch (status) {
      PurchaseStatus.draft => (palette.chipBg, palette.chipText),
      PurchaseStatus.sent => (palette.accentSoft, palette.inkWarm),
      PurchaseStatus.partiallyReceived => (palette.warnSoft, palette.warn),
      PurchaseStatus.received => (palette.okSoft, palette.ok),
      PurchaseStatus.cancelled => (palette.chipBg, palette.muted),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: PosSpace.sm, vertical: 3),
      color: background,
      child: Text(
        AdminText.purchaseStatus(context.strings, status),
        style: PosText.ui(size: 10.5, weight: FontWeight.w700, color: ink),
      ),
    );
  }
}

/// One outstanding invoice.
///
/// The days-late badge earns its place: the number a bookkeeper is deciding
/// with is not what is owed but what is owed *now*, and a list sorted by due
/// date without saying which rows are past it makes them do the arithmetic.
class _InvoiceRow extends StatelessWidget {
  const _InvoiceRow({
    required this.invoice,
    required this.busy,
    required this.onEdit,
    required this.onPay,
    required this.onVoid,
  });

  final SupplierInvoice invoice;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onPay;
  final VoidCallback onVoid;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;
    final late = invoice.daysLate(DateTime.now());
    final part = invoice.paid.isPositive;

    return Container(
      padding: const EdgeInsets.all(PosSpace.lg),
      decoration: BoxDecoration(border: Border(bottom: palette.hairline)),
      child: Row(
        children: [
          SizedBox(width: 140, child: MonoCode(invoice.number, size: 12.5)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invoice.supplierName ?? '',
                  style: PosText.ui(size: 13.5, color: palette.ink),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (late > 0)
                      Text(
                        strings.invoiceDaysLate(late),
                        style: PosText.ui(
                          size: 11,
                          weight: FontWeight.w700,
                          color: palette.danger,
                        ),
                      )
                    else
                      MonoCode(
                        '${invoice.dueAt.year}-'
                        '${invoice.dueAt.month.toString().padLeft(2, '0')}-'
                        '${invoice.dueAt.day.toString().padLeft(2, '0')}',
                        size: 11,
                        color: palette.muted,
                      ),
                    if (invoice.purchaseOrderReference != null) ...[
                      const SizedBox(width: PosSpace.sm),
                      MonoCode(
                        invoice.purchaseOrderReference!,
                        size: 11,
                        color: palette.muted,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // Both figures where anything has been paid, because "600 of 1,000"
          // is the sentence, and the outstanding number alone reads as a
          // smaller invoice.
          if (part) ...[
            MonoCode(invoice.total.format(withCurrency: true), size: 11.5, color: palette.muted),
            const SizedBox(width: PosSpace.xs),
          ],
          MonoAmount(invoice.outstanding, size: 13.5),
          const SizedBox(width: PosSpace.lg),
          PosButton(
            label: strings.edit,
            border: Border.fromBorderSide(palette.resting),
            onPressed: busy ? null : onEdit,
          ),
          const SizedBox(width: PosSpace.sm),
          // Cancelling is offered only while nothing has been paid. Once money
          // is against it the answer is to reverse the payment first, and the
          // repository says so — but a button that always refused would be a
          // button that teaches people to ignore refusals.
          if (!part) ...[
            PosButton(
              key: Key('invoice-void-${invoice.id}'),
              label: strings.invoiceVoid,
              foreground: palette.danger,
              border: Border.fromBorderSide(palette.resting),
              onPressed: busy ? null : onVoid,
            ),
            const SizedBox(width: PosSpace.sm),
          ],
          PosButton(
            key: Key('invoice-pay-${invoice.id}'),
            label: strings.invoicePay,
            background: palette.accent,
            foreground: Colors.white,
            fontWeight: FontWeight.w700,
            onPressed: busy ? null : onPay,
          ),
        ],
      ),
    );
  }
}

/// One payment made, with the way back.
///
/// **Reversed payments stay on the list, struck through.** A cheque that bounced
/// is part of the account's history, and a screen that removed the row would
/// leave a bookkeeper unable to see that anything had happened at all.
class _PaymentRow extends StatelessWidget {
  const _PaymentRow({
    required this.payment,
    required this.busy,
    required this.onVoid,
  });

  final SupplierPayment payment;
  final bool busy;
  final VoidCallback onVoid;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;
    final gone = payment.isVoided;

    return Container(
      padding: const EdgeInsets.all(PosSpace.lg),
      decoration: BoxDecoration(border: Border(bottom: palette.hairline)),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: MonoCode(
              '${payment.paidAt.year}-'
              '${payment.paidAt.month.toString().padLeft(2, '0')}-'
              '${payment.paidAt.day.toString().padLeft(2, '0')}',
              size: 12,
              color: palette.muted,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  payment.supplierName ?? '',
                  style: PosText.ui(
                    size: 13.5,
                    color: gone ? palette.muted : palette.ink,
                  ).copyWith(
                    decoration: gone ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      AdminText.paymentMethod(strings, payment.method),
                      style: PosText.ui(size: 11.5, color: palette.muted),
                    ),
                    if (payment.reference != null) ...[
                      const SizedBox(width: PosSpace.sm),
                      MonoCode(
                        payment.reference!,
                        size: 11,
                        color: palette.muted,
                      ),
                    ],
                    const SizedBox(width: PosSpace.sm),
                    Text(
                      payment.invoiceNumber ?? strings.paymentOnAccount,
                      style: PosText.ui(size: 11.5, color: palette.muted),
                    ),
                  ],
                ),
              ],
            ),
          ),
          MonoAmount(payment.amount, size: 13.5),
          const SizedBox(width: PosSpace.lg),
          if (gone)
            _StruckChip(label: strings.paymentVoid)
          else
            PosButton(
              key: Key('payment-void-${payment.id}'),
              label: strings.paymentVoid,
              foreground: palette.danger,
              border: Border.fromBorderSide(palette.resting),
              onPressed: busy ? null : onVoid,
            ),
        ],
      ),
    );
  }
}

class _StruckChip extends StatelessWidget {
  const _StruckChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.pos;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: PosSpace.sm, vertical: 3),
      color: palette.chipBg,
      child: Text(
        label,
        style: PosText.ui(
          size: 10.5,
          weight: FontWeight.w700,
          color: palette.muted,
        ),
      ),
    );
  }
}

class _SupplierRow extends StatelessWidget {
  const _SupplierRow({
    required this.supplier,
    required this.onEdit,
    required this.onPay,
    this.balance,
  });

  final Supplier supplier;
  final SupplierBalance? balance;
  final VoidCallback onEdit;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;

    return InkWell(
      onTap: onEdit,
      child: Container(
        padding: const EdgeInsets.all(PosSpace.lg),
        decoration: BoxDecoration(border: Border(bottom: palette.hairline)),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    supplier.displayName(strings.languageCode),
                    style: PosText.ui(size: 13.5, color: palette.ink),
                  ),
                  if (supplier.contactName != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      supplier.contactName!,
                      style: PosText.ui(size: 11.5, color: palette.muted),
                    ),
                  ],
                ],
              ),
            ),
            Text(
              supplier.isCashOnDelivery
                  ? strings.supplierCashOnDelivery
                  : strings.supplierTermDays(supplier.paymentTermDays),
              style: PosText.ui(size: 12, color: palette.muted),
            ),
            if (supplier.phone != null) ...[
              const SizedBox(width: PosSpace.lg),
              MonoCode(supplier.phone!, size: 12),
            ],
            // What they are owed, beside them. A supplier list without it is a
            // list of names, and the question anybody opens it with is money.
            if (balance case final owed? when !owed.outstanding.isZero) ...[
              const SizedBox(width: PosSpace.lg),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      Text(
                        strings.supplierOwes,
                        style: PosText.ui(size: 10.5, color: palette.muted),
                      ),
                      const SizedBox(width: PosSpace.xs),
                      MonoAmount(owed.outstanding, size: 13),
                    ],
                  ),
                  if (owed.overdue.isPositive)
                    Text(
                      '${owed.overdue.format(withCurrency: true)} ${strings.supplierOverdue}',
                      style: PosText.ui(
                        size: 10.5,
                        weight: FontWeight.w700,
                        color: palette.danger,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: PosSpace.md),
              PosButton(
                key: Key('supplier-pay-${supplier.id}'),
                label: strings.invoicePay,
                border: Border.fromBorderSide(palette.resting),
                onPressed: onPay,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Centred extends StatelessWidget {
  const _Centred({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(PosSpace.xl),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: PosText.ui(size: 13.5, color: context.pos.muted, height: 1.6),
      ),
    ),
  );
}
