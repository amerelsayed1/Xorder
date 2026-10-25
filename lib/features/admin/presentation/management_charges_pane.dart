import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/money/money.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/mono_amount.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/service_charge.dart';
import '../../../domain/models/shift.dart';
import 'admin_messages.dart';
import 'admin_pane_bits.dart';
import 'service_charge_dialog.dart';

/// What the restaurant adds on top of the food (§38).
///
/// **Its own pane, out of the Money pane.** It sat under the single service rate
/// it supersedes, which was the right place while it was a new section beside
/// the thing it replaced — and the wrong one once there were three sections and
/// a manager had to scroll past tax to reach it.
///
/// Local on both deployments. Nothing seeds `pos_service_charges`, so a cloud
/// restaurant configures its own — unlike the tax rates, which are the
/// platform's.
class ManagementChargesPane extends ConsumerStatefulWidget {
  const ManagementChargesPane({required this.admin, super.key});

  final PosStaff admin;

  @override
  ConsumerState<ManagementChargesPane> createState() =>
      _ManagementChargesPaneState();
}

class _ManagementChargesPaneState extends ConsumerState<ManagementChargesPane> {
  bool _busy = false;
  String? _note;

  Future<void> _edit(ServiceCharge? charge) async {
    final edited = await ServiceChargeDialog.show(context, charge: charge);
    if (edited == null || !mounted) return;

    setState(() => _busy = true);
    final result = await ref
        .read(serviceChargesRepositoryProvider)
        .save(edited, by: widget.admin);
    if (!mounted) return;

    setState(() {
      _busy = false;
      _note = result.succeeded
          ? null
          : AdminText.refusal(context.strings, result.refusal!);
    });

    // `taxConfigProvider` folds these in, and the ticket engine reads that.
    // Without the invalidation the next sale would price with the old charges
    // until the app restarted.
    if (result.succeeded) {
      ref
        ..invalidate(serviceChargesProvider)
        ..invalidate(serviceChargesAllProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return ListView(
      padding: const EdgeInsets.all(PosSpace.xl),
      children: [
        PaneSection(
          title: strings.serviceCharges,
          hint: strings.serviceChargesHint,
        ),
        ...ref
            .watch(serviceChargesAllProvider)
            .when(
              loading: () => const [SizedBox(height: 40)],
              error: (error, _) => [
                Text(
                  '$error',
                  style: PosText.ui(size: 13, color: context.pos.danger),
                ),
              ],
              data: (all) => all.isEmpty
                  ? [
                      // The state that matters most: nothing here means the
                      // single rate in Tax is what customers pay, and a blank
                      // list reads as "no service charge" to everybody.
                      Text(
                        strings.serviceChargesFallback,
                        style: PosText.ui(size: 12.5, color: context.pos.warn),
                      ),
                    ]
                  : [
                      for (final charge in all)
                        _ChargeRow(charge: charge, onEdit: () => _edit(charge)),
                    ],
            ),
        if (_note != null) ...[
          const SizedBox(height: PosSpace.md),
          Text(_note!, style: PosText.ui(size: 12.5, color: context.pos.danger)),
        ],
        const SizedBox(height: PosSpace.md),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: PosButton(
            key: const Key('charge-new'),
            label: strings.chargeNew,
            border: Border.fromBorderSide(context.pos.resting),
            onPressed: _busy ? null : () => _edit(null),
          ),
        ),
      ],
    );
  }
}

/// One service charge, as the editor lists them.
class _ChargeRow extends StatelessWidget {
  const _ChargeRow({required this.charge, required this.onEdit});

  final ServiceCharge charge;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;

    return InkWell(
      onTap: onEdit,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: PosSpace.sm),
        decoration: BoxDecoration(
          border: BorderDirectional(bottom: palette.hairline),
        ),
        child: Opacity(
          opacity: charge.isActive ? 1 : 0.5,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  charge.displayName(strings.languageCode),
                  style: PosText.ui(size: 13.5, color: palette.ink),
                ),
              ),
              if (!charge.isTaxable)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: PosSpace.sm),
                  child: Text(
                    // Worth surfacing in the list: it is the flag with the
                    // consequences a filing cares about.
                    strings.chargeTaxable,
                    style: PosText.ui(
                      size: 10.5,
                      weight: FontWeight.w700,
                      color: palette.warn,
                    ),
                  ),
                ),
              MonoCode(
                charge.isFixed
                    ? Money(charge.fixedMinor!).format(withCurrency: true)
                    : AdminText.rateBp(charge.rateBp!),
                size: 12.5,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
