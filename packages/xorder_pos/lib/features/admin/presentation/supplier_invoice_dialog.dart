import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/money/money.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/mono_amount.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/purchase_order.dart';
import '../../../domain/models/supplier.dart';
import '../../../domain/models/supplier_invoice.dart';

/// Typing an invoice off a supplier's piece of paper.
///
/// **Two numbers, not three.** The total and the tax are what a person can read
/// off an invoice without doing arithmetic; the subtotal is the subtraction of
/// the two and is shown rather than typed, because a third box would be a third
/// number to disagree with the others.
///
/// The tax can also be worked out from a rate, which is what most suppliers
/// print — and the arithmetic there is the one people get wrong, because the VAT
/// inside a gross figure is not the rate times the gross.
class SupplierInvoiceDialog extends StatefulWidget {
  const SupplierInvoiceDialog({
    super.key,
    required this.suppliers,
    this.invoice,
    this.orders = const [],
  });

  final SupplierInvoice? invoice;
  final List<Supplier> suppliers;

  /// Orders this invoice might be billing, so the screen can say whether the
  /// paper agrees with what arrived.
  final List<PurchaseOrder> orders;

  static Future<SupplierInvoice?> show(
    BuildContext context, {
    required List<Supplier> suppliers,
    SupplierInvoice? invoice,
    List<PurchaseOrder> orders = const [],
  }) => showDialog<SupplierInvoice>(
    context: context,
    builder: (_) => SupplierInvoiceDialog(
      suppliers: suppliers,
      invoice: invoice,
      orders: orders,
    ),
  );

  @override
  State<SupplierInvoiceDialog> createState() => _SupplierInvoiceDialogState();
}

class _SupplierInvoiceDialogState extends State<SupplierInvoiceDialog> {
  late int _supplierId =
      widget.invoice?.supplierId ?? widget.suppliers.first.id;
  late int? _orderId = widget.invoice?.purchaseOrderId;

  late final _number = TextEditingController(
    text: widget.invoice?.number ?? '',
  );
  late final _total = TextEditingController(
    text: widget.invoice == null ? '' : widget.invoice!.total.format(),
  );
  late final _tax = TextEditingController(
    text: widget.invoice == null ? '' : widget.invoice!.tax.format(),
  );
  late final _note = TextEditingController(text: widget.invoice?.note ?? '');

  late DateTime _issuedAt = widget.invoice?.issuedAt ?? _today;
  late DateTime? _dueAt = widget.invoice?.dueAt;
  String? _problem;

  static DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void dispose() {
    _number.dispose();
    _total.dispose();
    _tax.dispose();
    _note.dispose();
    super.dispose();
  }

  Supplier get _supplier =>
      widget.suppliers.firstWhere((s) => s.id == _supplierId);

  /// The due date, from the supplier's terms until somebody says otherwise.
  DateTime get _due =>
      _dueAt ?? SupplierInvoice.dueFrom(_issuedAt, _supplier.paymentTermDays);

  Money? get _typedTotal => Money.tryParse(_total.text);
  Money? get _typedTax => Money.tryParse(_tax.text);

  PurchaseOrder? get _order => _orderId == null
      ? null
      : widget.orders.where((o) => o.id == _orderId).firstOrNull;

  /// The orders worth offering: this supplier's, and not the drafts. A draft has
  /// not been sent, so nothing can have arrived against it to be billed for.
  List<PurchaseOrder> get _offerable => [
    for (final order in widget.orders)
      if (order.supplierId == _supplierId &&
          order.status != PurchaseStatus.draft &&
          order.status != PurchaseStatus.cancelled)
        order,
  ];

  SupplierInvoice get _draft => SupplierInvoice(
    id: widget.invoice?.id ?? 0,
    supplierId: _supplierId,
    supplierName: _supplier.nameEn,
    number: _number.text,
    total: _typedTotal ?? Money.zero,
    tax: _typedTax ?? Money.zero,
    issuedAt: _issuedAt,
    dueAt: _due,
    note: _note.text.trim().isEmpty ? null : _note.text.trim(),
    purchaseOrderId: _orderId,
    purchaseOrderReference: _order?.reference,
    paid: widget.invoice?.paid ?? Money.zero,
  );

  /// Fills the tax box from a rate on what has been typed as the total.
  ///
  /// Uses `taxWithinBp`, not `percentBp`: the total on an invoice is gross, and
  /// 14% of a gross figure is not the VAT inside it. Getting this the wrong way
  /// round overstates the reclaim by about two per cent of turnover, which is
  /// the kind of error that is only found by an inspector.
  void _taxFromRate(int basisPoints) {
    final total = _typedTotal;
    if (total == null) return;
    setState(() {
      _tax.text = total.taxWithinBp(basisPoints).format();
      _problem = null;
    });
  }

  void _save() {
    final draft = _draft;
    final problems = draft.problems;
    if (problems.isNotEmpty) {
      setState(() => _problem = problems.first.message);
      return;
    }
    Navigator.of(context).pop(draft);
  }

  Future<void> _pickIssued() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _issuedAt,
      firstDate: DateTime(2020),
      lastDate: DateTime(_today.year + 2),
    );
    if (picked == null) return;
    setState(() {
      _issuedAt = picked;
      // The due date follows the invoice date until somebody overrides it, so
      // changing the one has to move the other — otherwise a corrected date
      // silently leaves the terms measured from the wrong day.
      _dueAt = null;
      _problem = null;
    });
  }

  Future<void> _pickDue() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _due,
      firstDate: _issuedAt,
      lastDate: DateTime(_today.year + 3),
    );
    if (picked == null) return;
    setState(() {
      _dueAt = picked;
      _problem = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;
    final draft = _draft;
    final order = _order;

    return Dialog(
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 800),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(PosSpace.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.invoice == null
                        ? strings.invoiceNew
                        : strings.invoiceEdit,
                    style: PosText.ui(
                      size: 18,
                      weight: FontWeight.w800,
                      color: palette.ink,
                    ),
                  ),
                  const SizedBox(height: PosSpace.xs),
                  Text(
                    strings.invoiceHint,
                    style: PosText.ui(
                      size: 12.5,
                      color: palette.muted,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: PosSpace.lg),
                children: [
                  MicroLabel(strings.suppliers),
                  const SizedBox(height: PosSpace.xs),
                  Wrap(
                    spacing: PosSpace.sm,
                    runSpacing: PosSpace.sm,
                    children: [
                      for (final supplier in widget.suppliers)
                        PosButton(
                          label: supplier.displayName(strings.languageCode),
                          background: supplier.id == _supplierId
                              ? palette.ink
                              : Colors.transparent,
                          foreground: supplier.id == _supplierId
                              ? Colors.white
                              : null,
                          border: Border.fromBorderSide(palette.resting),
                          onPressed: widget.invoice != null
                              ? null
                              : () => setState(() {
                                  _supplierId = supplier.id;
                                  // The order belonged to the old supplier.
                                  _orderId = null;
                                  _dueAt = null;
                                }),
                        ),
                    ],
                  ),
                  const SizedBox(height: PosSpace.md),

                  MicroLabel(strings.invoiceNumber),
                  const SizedBox(height: PosSpace.xs),
                  TextField(
                    key: const Key('invoice-number'),
                    controller: _number,
                    onChanged: (_) => setState(() => _problem = null),
                    textDirection: TextDirection.ltr,
                    style: PosText.mono(size: 15, color: palette.ink),
                  ),
                  const SizedBox(height: PosSpace.md),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            MicroLabel(strings.invoiceTotal),
                            const SizedBox(height: PosSpace.xs),
                            TextField(
                              key: const Key('invoice-total'),
                              controller: _total,
                              onChanged: (_) => setState(() => _problem = null),
                              textDirection: TextDirection.ltr,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              style: PosText.mono(size: 15, color: palette.ink),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: PosSpace.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            MicroLabel(strings.invoiceTax),
                            const SizedBox(height: PosSpace.xs),
                            TextField(
                              key: const Key('invoice-tax'),
                              controller: _tax,
                              onChanged: (_) => setState(() => _problem = null),
                              textDirection: TextDirection.ltr,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              style: PosText.mono(size: 15, color: palette.ink),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: PosSpace.xs),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          strings.invoiceTaxFromRate,
                          overflow: TextOverflow.ellipsis,
                          style: PosText.ui(size: 11.5, color: palette.muted),
                        ),
                      ),
                      const SizedBox(width: PosSpace.sm),
                      for (final rate in const [1400, 1000, 500])
                        Padding(
                          padding: const EdgeInsetsDirectional.only(
                            end: PosSpace.xs,
                          ),
                          child: PosButton(
                            key: Key('invoice-rate-$rate'),
                            label: '${rate ~/ 100}%',
                            border: Border.fromBorderSide(palette.resting),
                            padding: const EdgeInsets.symmetric(
                              horizontal: PosSpace.sm,
                              vertical: 4,
                            ),
                            onPressed: () => _taxFromRate(rate),
                          ),
                        ),
                      const Spacer(),
                      Text(
                        strings.subtotal,
                        style: PosText.ui(size: 11.5, color: palette.muted),
                      ),
                      const SizedBox(width: PosSpace.xs),
                      MonoAmount(draft.subtotal, size: 12.5),
                    ],
                  ),
                  const SizedBox(height: PosSpace.md),

                  Row(
                    children: [
                      Expanded(
                        child: _DateBox(
                          label: strings.invoiceIssued,
                          value: _issuedAt,
                          onPressed: _pickIssued,
                        ),
                      ),
                      const SizedBox(width: PosSpace.md),
                      Expanded(
                        child: _DateBox(
                          label: _dueAt == null
                              ? strings.invoiceDueOnTerms(
                                  _supplier.paymentTermDays,
                                )
                              : strings.invoiceDue,
                          value: _due,
                          onPressed: _pickDue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: PosSpace.md),

                  if (_offerable.isNotEmpty) ...[
                    MicroLabel(strings.invoiceAgainstOrder),
                    const SizedBox(height: PosSpace.xs),
                    Wrap(
                      spacing: PosSpace.sm,
                      runSpacing: PosSpace.sm,
                      children: [
                        PosButton(
                          label: strings.invoiceNoOrder,
                          background: _orderId == null
                              ? palette.ink
                              : Colors.transparent,
                          foreground: _orderId == null ? Colors.white : null,
                          border: Border.fromBorderSide(palette.resting),
                          onPressed: () => setState(() => _orderId = null),
                        ),
                        for (final candidate in _offerable)
                          PosButton(
                            key: Key('invoice-order-${candidate.id}'),
                            label: candidate.reference,
                            background: _orderId == candidate.id
                                ? palette.ink
                                : Colors.transparent,
                            foreground: _orderId == candidate.id
                                ? Colors.white
                                : null,
                            border: Border.fromBorderSide(palette.resting),
                            onPressed: () =>
                                setState(() => _orderId = candidate.id),
                          ),
                      ],
                    ),
                    if (order != null && _typedTotal != null) ...[
                      const SizedBox(height: PosSpace.sm),
                      _Variance(invoice: draft, order: order),
                    ],
                    const SizedBox(height: PosSpace.md),
                  ],

                  MicroLabel(strings.optionalField(strings.notes)),
                  const SizedBox(height: PosSpace.xs),
                  TextField(
                    controller: _note,
                    style: PosText.ui(size: 15, color: palette.ink),
                  ),

                  if (_problem != null) ...[
                    const SizedBox(height: PosSpace.md),
                    Text(
                      _problem!,
                      style: PosText.ui(size: 12.5, color: palette.danger),
                    ),
                  ],
                  const SizedBox(height: PosSpace.lg),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(PosSpace.lg),
              decoration: BoxDecoration(
                border: BorderDirectional(top: palette.resting),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: PosButton(
                      label: strings.cancel,
                      border: Border.fromBorderSide(palette.resting),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: PosSpace.sm),
                  Expanded(
                    child: PosButton(
                      key: const Key('invoice-save'),
                      label: strings.save,
                      background: palette.ink,
                      foreground: palette.onInk,
                      onPressed: _save,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Whether the paper agrees with what arrived.
///
/// Shown rather than enforced. A supplier who has billed for more than they
/// delivered is a phone call, not a refusal — the invoice still says what it
/// says, and recording it is how the query gets raised at all.
class _Variance extends StatelessWidget {
  const _Variance({required this.invoice, required this.order});

  final SupplierInvoice invoice;
  final PurchaseOrder order;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;
    final off = invoice.varianceAgainst(order);
    final agrees = invoice.matches(order, tolerance: const Money(5));

    return Container(
      padding: const EdgeInsets.all(PosSpace.sm),
      color: agrees ? palette.okSoft : palette.warnSoft,
      child: Row(
        children: [
          Expanded(
            child: Text(
              agrees
                  ? strings.invoiceAgreesWithDelivery
                  : off.isPositive
                  ? strings.invoiceBilledMore
                  : strings.invoiceBilledLess,
              style: PosText.ui(
                size: 12,
                color: agrees ? palette.ok : palette.warn,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(width: PosSpace.sm),
          MonoCode(
            order.receivedTotal.format(withCurrency: true),
            size: 12,
            color: palette.muted,
          ),
          if (!agrees) ...[
            const SizedBox(width: PosSpace.sm),
            MonoCode(
              '${off.isPositive ? '+' : ''}${off.format(withCurrency: true)}',
              size: 12.5,
              color: palette.warn,
            ),
          ],
        ],
      ),
    );
  }
}

class _DateBox extends StatelessWidget {
  const _DateBox({
    required this.label,
    required this.value,
    required this.onPressed,
  });

  final String label;
  final DateTime value;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.pos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MicroLabel(label),
        const SizedBox(height: PosSpace.xs),
        PosButton(
          label:
              '${value.year}-'
              '${value.month.toString().padLeft(2, '0')}-'
              '${value.day.toString().padLeft(2, '0')}',
          border: Border.fromBorderSide(palette.resting),
          onPressed: onPressed,
        ),
      ],
    );
  }
}
