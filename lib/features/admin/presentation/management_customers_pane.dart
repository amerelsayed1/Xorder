import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/reports_providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/mono_amount.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/customer_summary.dart';
import 'admin_pane_bits.dart';
import 'management_reports_pane.dart' show ReportNote;
import 'shift_history_bits.dart' show shiftStamp;

/// Customers: everyone on file, and what each has bought at this branch.
///
/// **Read-only.** A customer is added at the counter, where an order is being
/// taken for them; this is where the business looks at the people it serves.
/// The phone is a customer's identity, so changing one is not a field edit.
///
/// Read through [customerDirectoryProvider], which asks `reports.view` of the
/// person acting before it reads a name beside what they spend. The directory
/// is the same on a cloud till — it arrives in the platform's bundle — so the
/// pane is not hidden there.
class ManagementCustomersPane extends ConsumerStatefulWidget {
  const ManagementCustomersPane({super.key});

  @override
  ConsumerState<ManagementCustomersPane> createState() =>
      _ManagementCustomersPaneState();
}

class _ManagementCustomersPaneState
    extends ConsumerState<ManagementCustomersPane> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// After a pause, not on every keystroke: each query is a read of the whole
  /// directory with its totals.
  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _query = text.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final pos = context.pos;

    return ListView(
      key: const Key('customers-pane'),
      padding: const EdgeInsets.all(PosSpace.xl),
      children: [
        PaneSection(title: strings.paneCustomers, hint: strings.paneCustomersBlurb),
        const SizedBox(height: PosSpace.md),
        TextField(
          key: const Key('customers-search'),
          controller: _search,
          onChanged: _onChanged,
          decoration: InputDecoration(
            hintText: strings.customersSearchHint,
            prefixIcon: const Icon(Icons.search, size: 18),
          ),
          style: PosText.ui(size: 14, color: pos.ink),
        ),
        const SizedBox(height: PosSpace.md),
        ...switch (ref.watch(customerDirectoryProvider(_query))) {
          AsyncData(value: final customers?) =>
            customers.isEmpty
                ? [
                    ReportNote(
                      _query.isEmpty
                          ? strings.customersNone
                          : strings.customersNoMatch,
                    ),
                  ]
                : [
                    const _Headings(),
                    for (final customer in customers) _Row(summary: customer),
                    const SizedBox(height: PosSpace.md),
                    Text(
                      strings.customersBranchOnly,
                      style: PosText.ui(size: 12, color: pos.muted, height: 1.4),
                    ),
                  ],
          AsyncData(value: null) => [ReportNote(strings.reportNoDatabase)],
          AsyncError() => [ReportNote(strings.reportUnavailable, danger: true)],
          _ => [
            const SizedBox(
              height: 160,
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
        },
      ],
    );
  }
}

const _countWidth = 80.0;
const _moneyWidth = 124.0;
const _lastWidth = 150.0;

class _Headings extends StatelessWidget {
  const _Headings();

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    Widget cell(String label, double width) => SizedBox(
      width: width,
      child: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: MicroLabel(label),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: PosSpace.xs),
      child: Row(
        children: [
          Expanded(child: MicroLabel(s.customersColumnCustomer)),
          cell(s.customersColumnOrders, _countWidth),
          cell(s.customersColumnSpent, _moneyWidth),
          cell(s.customersColumnLast, _lastWidth),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.summary});

  final CustomerSummary summary;

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    final pos = context.pos;
    final customer = summary.customer;

    return InkWell(
      key: Key('customer-row-${customer.id}'),
      onTap: () => CustomerDetailDialog.show(context, summary),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: PosSpace.sm),
        decoration: BoxDecoration(border: Border(bottom: pos.hairline)),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customer.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PosText.ui(
                      size: 13.5,
                      weight: FontWeight.w600,
                      color: pos.ink,
                    ),
                  ),
                  Text(
                    customer.phone,
                    textDirection: TextDirection.ltr,
                    style: PosText.mono(size: 12, color: pos.muted),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: _countWidth,
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Text(
                  '${summary.orders}',
                  textDirection: TextDirection.ltr,
                  style: PosText.mono(size: 13, color: pos.ink),
                ),
              ),
            ),
            SizedBox(
              width: _moneyWidth,
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                // A dash for nobody who has bought: zero spent is a claim about
                // purchases, and there were none.
                child: summary.hasOrdered
                    ? MonoAmount(summary.net, size: 13)
                    : Text('—', style: PosText.mono(size: 13, color: pos.muted)),
              ),
            ),
            SizedBox(
              width: _lastWidth,
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: summary.lastOrderAt == null
                    ? Text(
                        s.customersNever,
                        style: PosText.ui(size: 12.5, color: pos.muted),
                      )
                    : Text(
                        shiftStamp(summary.lastOrderAt!),
                        textDirection: TextDirection.ltr,
                        style: PosText.mono(size: 12, color: pos.muted),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One customer: how to reach them, what they have bought, and their latest
/// orders.
class CustomerDetailDialog extends ConsumerWidget {
  const CustomerDetailDialog({required this.summary, super.key});

  final CustomerSummary summary;

  static Future<void> show(BuildContext context, CustomerSummary summary) =>
      showDialog<void>(
        context: context,
        builder: (_) => CustomerDetailDialog(summary: summary),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.strings;
    final pos = context.pos;
    final customer = summary.customer;

    Widget contact(String label, String? value) {
      if (value == null || value.trim().isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: PosSpace.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MicroLabel(label),
            const SizedBox(height: 2),
            Text(value, style: PosText.ui(size: 13.5, color: pos.ink)),
          ],
        ),
      );
    }

    Widget figure(String label, Widget value) => Padding(
      padding: const EdgeInsetsDirectional.only(end: PosSpace.s24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [MicroLabel(label), const SizedBox(height: 2), value],
      ),
    );

    return Dialog(
      key: const Key('customer-detail'),
      backgroundColor: pos.surface,
      shape: const RoundedRectangleBorder(),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(PosSpace.lg),
              child: Text(
                customer.name,
                style: PosText.ui(
                  size: 18,
                  weight: FontWeight.w800,
                  color: pos.ink,
                ),
              ),
            ),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: PosSpace.lg),
                children: [
                  contact(s.customersPhone, customer.phone),
                  contact(s.customersEmail, customer.email),
                  contact(s.customersAddress, customer.address),
                  contact(s.customersNote, customer.note),
                  const SizedBox(height: PosSpace.sm),
                  Wrap(
                    runSpacing: PosSpace.md,
                    children: [
                      figure(
                        s.customersColumnOrders,
                        Text(
                          '${summary.orders}',
                          key: const Key('customer-orders'),
                          style: PosText.mono(
                            size: 20,
                            weight: FontWeight.w600,
                            color: pos.ink,
                          ),
                        ),
                      ),
                      figure(
                        s.customersColumnSpent,
                        MonoAmount(
                          summary.net,
                          size: 20,
                          weight: FontWeight.w600,
                        ),
                      ),
                      if (summary.averageOrder != null)
                        figure(
                          s.customersDetailAverage,
                          MonoAmount(summary.averageOrder!, size: 20),
                        ),
                      if (summary.refunded.minor > 0)
                        figure(
                          s.customersDetailRefunded,
                          MonoAmount(summary.refunded, size: 20),
                        ),
                    ],
                  ),
                  const SizedBox(height: PosSpace.lg),
                  MicroLabel(s.customersDetailRecent),
                  const SizedBox(height: PosSpace.sm),
                  ...switch (ref.watch(customerOrdersProvider(customer.id))) {
                    AsyncData(value: final orders) =>
                      orders.isEmpty
                          ? [
                              Text(
                                s.customersNoOrders,
                                key: const Key('customer-no-orders'),
                                style: PosText.ui(size: 13, color: pos.muted),
                              ),
                            ]
                          : [
                              for (final order in orders)
                                _OrderLine(order: order),
                            ],
                    AsyncError() => [
                      ReportNote(s.reportUnavailable, danger: true),
                    ],
                    _ => const [
                      SizedBox(
                        height: 60,
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ],
                  },
                  const SizedBox(height: PosSpace.lg),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(PosSpace.lg),
              decoration: BoxDecoration(
                border: BorderDirectional(top: pos.resting),
              ),
              child: PosButton(
                label: s.close,
                border: Border.fromBorderSide(pos.resting),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderLine extends StatelessWidget {
  const _OrderLine({required this.order});

  final CustomerOrder order;

  @override
  Widget build(BuildContext context) {
    final pos = context.pos;
    return Container(
      key: Key('customer-order-${order.orderId}'),
      padding: const EdgeInsets.symmetric(vertical: PosSpace.sm),
      decoration: BoxDecoration(border: Border(top: pos.hairline)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.invoiceNumber,
                  textDirection: TextDirection.ltr,
                  style: PosText.mono(size: 13, color: pos.ink),
                ),
                Text(
                  shiftStamp(order.occurredAt),
                  textDirection: TextDirection.ltr,
                  style: PosText.mono(size: 11.5, color: pos.muted),
                ),
              ],
            ),
          ),
          MonoAmount(order.net, size: 13),
        ],
      ),
    );
  }
}
