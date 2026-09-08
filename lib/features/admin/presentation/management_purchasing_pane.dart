import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/mono_amount.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/purchase_order.dart';
import '../../../domain/models/shift.dart';
import '../../../domain/repositories/admin_repositories.dart';
import '../../../domain/models/supplier.dart';
import 'admin_messages.dart';
import 'purchase_order_dialog.dart';
import 'receive_dialog.dart';
import 'supplier_dialog.dart';

/// What the restaurant buys, and who from.
///
/// **Its own pane rather than a section of an existing one.** Purchasing is a
/// different job done by a different person on a different day from anything
/// else in Management, and the Money pane is already three sections deep. It is
/// also the first area whose daily use is a *flow* — an order goes out, goods
/// arrive against it — rather than a form somebody edits, which is why the
/// orders list leads and the suppliers sit behind it.
class ManagementPurchasingPane extends ConsumerStatefulWidget {
  const ManagementPurchasingPane({required this.admin, super.key});

  final PosStaff admin;

  @override
  ConsumerState<ManagementPurchasingPane> createState() =>
      _ManagementPurchasingPaneState();
}

enum _Tab { orders, suppliers }

class _ManagementPurchasingPaneState
    extends ConsumerState<ManagementPurchasingPane> {
  _Tab _tab = _Tab.orders;
  bool _busy = false;
  String? _note;

  void _refresh() => ref
    ..invalidate(purchaseOrdersProvider)
    ..invalidate(suppliersProvider);

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
    final edited = await SupplierDialog.show(context, supplier: supplier);
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

    final edited = await PurchaseOrderDialog.show(
      context,
      order: order,
      suppliers: suppliers,
    );
    if (edited == null || !mounted) return;
    await _run(
      () async => (await ref
              .read(purchaseOrdersRepositoryProvider)
              .saveDraft(edited, by: widget.admin))
          .refusal,
    );
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
                background: _tab == _Tab.orders
                    ? palette.ink
                    : Colors.transparent,
                foreground: _tab == _Tab.orders ? Colors.white : null,
                border: Border.fromBorderSide(palette.resting),
                onPressed: () => setState(() => _tab = _Tab.orders),
              ),
              const SizedBox(width: PosSpace.sm),
              PosButton(
                key: const Key('purchasing-suppliers'),
                label: strings.suppliers,
                background: _tab == _Tab.suppliers
                    ? palette.ink
                    : Colors.transparent,
                foreground: _tab == _Tab.suppliers ? Colors.white : null,
                border: Border.fromBorderSide(palette.resting),
                onPressed: () => setState(() => _tab = _Tab.suppliers),
              ),
              const Spacer(),
              PosButton(
                key: const Key('purchasing-new'),
                label: _tab == _Tab.orders
                    ? strings.purchaseOrderNew
                    : strings.supplierNew,
                background: palette.accent,
                foreground: Colors.white,
                fontWeight: FontWeight.w700,
                onPressed: _busy
                    ? null
                    : () => _tab == _Tab.orders
                          ? _editOrder(null)
                          : _editSupplier(null),
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
          child: _tab == _Tab.orders ? _orders(strings) : _suppliers(strings),
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
                  onEdit: () => _editSupplier(suppliers[index]),
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
              foreground: Colors.white,
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
        context.strings.purchaseStatus(status.wire),
        style: PosText.ui(size: 10.5, weight: FontWeight.w700, color: ink),
      ),
    );
  }
}

class _SupplierRow extends StatelessWidget {
  const _SupplierRow({required this.supplier, required this.onEdit});

  final Supplier supplier;
  final VoidCallback onEdit;

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
