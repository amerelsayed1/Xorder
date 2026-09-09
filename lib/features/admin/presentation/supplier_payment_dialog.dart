import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/money/money.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/mono_amount.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/supplier.dart';
import '../../../domain/models/supplier_invoice.dart';
import 'admin_messages.dart';

/// Paying a supplier.
///
/// **The amount starts at what the chosen invoice still owes.** Nearly every
/// payment settles a bill in full, so the common case is one tap; typing over it
/// is how a part payment gets recorded. Pointing it at no invoice pays *on
/// account*, which is real — a restaurant hands the dairy man 2,000 on Friday
/// against a running tab — and is offered as its own choice rather than left as
/// what happens when somebody forgets to pick one.
class SupplierPaymentDialog extends StatefulWidget {
  const SupplierPaymentDialog({
    super.key,
    required this.supplier,
    required this.unpaid,
    this.invoice,
  });

  final Supplier supplier;

  /// This supplier's outstanding invoices, oldest due first.
  final List<SupplierInvoice> unpaid;

  /// The bill this was opened from, when it was opened from one.
  final SupplierInvoice? invoice;

  static Future<SupplierPayment?> show(
    BuildContext context, {
    required Supplier supplier,
    required List<SupplierInvoice> unpaid,
    SupplierInvoice? invoice,
  }) => showDialog<SupplierPayment>(
    context: context,
    builder: (_) => SupplierPaymentDialog(
      supplier: supplier,
      unpaid: unpaid,
      invoice: invoice,
    ),
  );

  @override
  State<SupplierPaymentDialog> createState() => _SupplierPaymentDialogState();
}

class _SupplierPaymentDialogState extends State<SupplierPaymentDialog> {
  late int? _invoiceId = widget.invoice?.id ?? widget.unpaid.firstOrNull?.id;
  SupplierPaymentMethod _method = SupplierPaymentMethod.cash;

  late final _amount = TextEditingController(
    text: _outstanding?.format() ?? '',
  );
  final _reference = TextEditingController();
  final _note = TextEditingController();
  String? _problem;

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _note.dispose();
    super.dispose();
  }

  SupplierInvoice? get _selected => _invoiceId == null
      ? null
      : widget.unpaid.where((i) => i.id == _invoiceId).firstOrNull ??
            widget.invoice;

  Money? get _outstanding => _selected?.outstanding;

  Money? get _typed => Money.tryParse(_amount.text);

  /// The one thing worth catching before the repository does: money that will
  /// not fit on the bill it is pointed at. The refusal is the same either way,
  /// but saying it here means the amount is still on screen to change.
  String? get _overAllocation {
    final room = _outstanding;
    final amount = _typed;
    if (room == null || amount == null) return null;
    if (amount.minor <= room.minor) return null;
    return context.strings.paymentMoreThanTheBill(room.format());
  }

  void _selectInvoice(int? id) => setState(() {
    _invoiceId = id;
    _problem = null;
    // The amount follows the bill. Leaving the previous invoice's figure in the
    // box is how somebody pays 400 against a 90 invoice and finds out from a
    // refusal.
    final room = _outstanding;
    _amount.text = room?.format() ?? '';
  });

  void _save() {
    final amount = _typed;
    if (amount == null || !amount.isPositive) {
      setState(() => _problem = context.strings.paymentNeedsAnAmount);
      return;
    }
    final over = _overAllocation;
    if (over != null) {
      setState(() => _problem = over);
      return;
    }

    Navigator.of(context).pop(
      SupplierPayment(
        id: 0,
        supplierId: widget.supplier.id,
        supplierName: widget.supplier.nameEn,
        invoiceId: _invoiceId,
        invoiceNumber: _selected?.number,
        amount: amount,
        method: _method,
        reference: _reference.text.trim().isEmpty
            ? null
            : _reference.text.trim(),
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        paidAt: DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;
    final over = _overAllocation;

    return Dialog(
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 760),
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
                    strings.paymentTo(
                      widget.supplier.displayName(strings.languageCode),
                    ),
                    style: PosText.ui(
                      size: 18,
                      weight: FontWeight.w800,
                      color: palette.ink,
                    ),
                  ),
                  const SizedBox(height: PosSpace.xs),
                  Text(
                    strings.paymentDoesNotTouchTheDrawer,
                    style: PosText.ui(
                      size: 11.5,
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
                  MicroLabel(strings.paymentAgainst),
                  const SizedBox(height: PosSpace.xs),
                  for (final bill in widget.unpaid)
                    _InvoiceChoice(
                      invoice: bill,
                      selected: bill.id == _invoiceId,
                      onPressed: () => _selectInvoice(bill.id),
                    ),
                  _OnAccountChoice(
                    selected: _invoiceId == null,
                    onPressed: () => _selectInvoice(null),
                  ),
                  const SizedBox(height: PosSpace.md),

                  MicroLabel(strings.paymentAmount),
                  const SizedBox(height: PosSpace.xs),
                  TextField(
                    key: const Key('payment-amount'),
                    controller: _amount,
                    onChanged: (_) => setState(() => _problem = null),
                    textDirection: TextDirection.ltr,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: PosText.mono(size: 20, color: palette.ink),
                  ),
                  if (over != null) ...[
                    const SizedBox(height: PosSpace.xs),
                    Text(
                      over,
                      style: PosText.ui(size: 11.5, color: palette.warn),
                    ),
                  ],
                  const SizedBox(height: PosSpace.md),

                  MicroLabel(strings.paymentMethod),
                  const SizedBox(height: PosSpace.xs),
                  Wrap(
                    spacing: PosSpace.sm,
                    runSpacing: PosSpace.sm,
                    children: [
                      for (final method in SupplierPaymentMethod.values)
                        PosButton(
                          key: Key('payment-method-${method.wire}'),
                          label: AdminText.paymentMethod(strings, method),
                          background: method == _method
                              ? palette.ink
                              : Colors.transparent,
                          foreground: method == _method ? Colors.white : null,
                          border: Border.fromBorderSide(palette.resting),
                          onPressed: () => setState(() => _method = method),
                        ),
                    ],
                  ),

                  // Only where a bank would need one. A reference box on a cash
                  // payment is a box somebody has to decide to leave empty.
                  if (_method.expectsAReference) ...[
                    const SizedBox(height: PosSpace.md),
                    MicroLabel(strings.paymentReference),
                    const SizedBox(height: PosSpace.xs),
                    TextField(
                      key: const Key('payment-reference'),
                      controller: _reference,
                      textDirection: TextDirection.ltr,
                      style: PosText.mono(size: 15, color: palette.ink),
                    ),
                  ],

                  const SizedBox(height: PosSpace.md),
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
                    flex: 2,
                    child: PosButton(
                      key: const Key('payment-save'),
                      label: strings.paymentPay,
                      background: palette.accent,
                      foreground: Colors.white,
                      fontWeight: FontWeight.w700,
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

class _InvoiceChoice extends StatelessWidget {
  const _InvoiceChoice({
    required this.invoice,
    required this.selected,
    required this.onPressed,
  });

  final SupplierInvoice invoice;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;
    final late = invoice.daysLate(DateTime.now());

    return InkWell(
      key: Key('payment-invoice-${invoice.id}'),
      onTap: onPressed,
      child: Container(
        margin: const EdgeInsets.only(bottom: 3),
        padding: const EdgeInsets.all(PosSpace.sm),
        decoration: BoxDecoration(
          color: selected ? palette.chipBg : null,
          border: Border.fromBorderSide(
            selected ? BorderSide(color: palette.ink) : palette.resting,
          ),
        ),
        child: Row(
          children: [
            MonoCode(invoice.number, size: 12.5),
            if (late > 0) ...[
              const SizedBox(width: PosSpace.sm),
              Text(
                strings.invoiceDaysLate(late),
                style: PosText.ui(
                  size: 11,
                  weight: FontWeight.w700,
                  color: palette.danger,
                ),
              ),
            ],
            const Spacer(),
            MonoAmount(invoice.outstanding, size: 13),
          ],
        ),
      ),
    );
  }
}

class _OnAccountChoice extends StatelessWidget {
  const _OnAccountChoice({required this.selected, required this.onPressed});

  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;

    return InkWell(
      key: const Key('payment-on-account'),
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.all(PosSpace.sm),
        decoration: BoxDecoration(
          color: selected ? palette.chipBg : null,
          border: Border.fromBorderSide(
            selected ? BorderSide(color: palette.ink) : palette.resting,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.paymentOnAccount,
                    style: PosText.ui(size: 13, color: palette.ink),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    strings.paymentOnAccountHint,
                    style: PosText.ui(size: 11, color: palette.muted),
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
