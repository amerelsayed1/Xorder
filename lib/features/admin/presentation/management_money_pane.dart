import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/shift.dart';
import '../../../domain/models/ticket.dart';
import '../../../core/ui/widgets/mono_amount.dart';
import '../../../core/money/money.dart';
import '../../../domain/models/service_charge.dart';
import '../../../domain/models/tender_method.dart';
import 'admin_messages.dart';
import 'service_charge_dialog.dart';
import 'tender_type_dialog.dart';

/// What the restaurant charges on top of the food.
///
/// **Offline only**, for the same reason the Menu pane is: on a cloud till the
/// platform authors tax (POS-BE-013) and the bootstrap seeder overwrites the
/// row.
///
/// This closes a quiet and expensive gap. Nothing outside the cloud seeder ever
/// wrote `pos_money_config`, so an offline till fell back to a built-in 12%
/// service / 14% VAT and disclosed `deviceConfig` as the source on every slip —
/// truthful, and wrong for almost every restaurant that is not the one those
/// numbers were written for.
///
/// Rates are held as **basis points** end to end: 1200 is 12%. Percent is only
/// a presentation of that, parsed back on save, so a rate can never arrive as a
/// float and be rounded into somebody's bill.
class ManagementMoneyPane extends ConsumerStatefulWidget {
  const ManagementMoneyPane({required this.admin, super.key});

  final PosStaff admin;

  @override
  ConsumerState<ManagementMoneyPane> createState() =>
      _ManagementMoneyPaneState();
}

class _ManagementMoneyPaneState extends ConsumerState<ManagementMoneyPane> {
  final _service = TextEditingController();
  final _vat = TextEditingController();
  bool _dineInOnly = true;
  bool _loaded = false;
  bool _busy = false;
  String? _note;

  @override
  void dispose() {
    _service.dispose();
    _vat.dispose();
    super.dispose();
  }

  /// Basis points as a percentage string, without trailing noise: 1250 → 12.5,
  /// 1200 → 12.
  static String _percent(int bp) {
    final value = bp / 100;
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }

  /// The inverse. Returns null when the box does not hold a number, so the
  /// caller can say which one.
  static int? _basisPoints(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return 0;
    final value = double.tryParse(trimmed);
    if (value == null || value < 0) return null;
    return (value * 100).round();
  }

  Future<void> _save() async {
    final repository = ref.read(catalogAdminRepositoryProvider);
    if (repository == null || _busy) return;

    final service = _basisPoints(_service.text);
    final vat = _basisPoints(_vat.text);
    if (service == null || vat == null) {
      setState(() => _note = context.strings.rateIsNotANumber);
      return;
    }

    setState(() {
      _busy = true;
      _note = null;
    });

    final result = await repository.saveMoneyConfig(
      TaxConfig(serviceBp: service, vatBp: vat, serviceDineInOnly: _dineInOnly),
      by: widget.admin,
    );

    if (!mounted) return;
    setState(() {
      _busy = false;
      _note = result.refusal == null
          ? context.strings.ratesSaved
          : AdminText.refusal(context.strings, result.refusal!);
    });

    // The ticket engine reads `taxConfigProvider`, which reads this. Without
    // the invalidation the next sale would price with the old rates until the
    // app restarted — the same trap the Menu pane has.
    if (result.refusal == null) ref.invalidate(moneyConfigProvider);
  }

  Future<void> _editCharge(ServiceCharge? charge) async {
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
    // until the app restarted — the same trap the Menu pane has.
    if (result.succeeded) {
      ref
        ..invalidate(serviceChargesProvider)
        ..invalidate(serviceChargesAllProvider);
    }
  }

  Future<void> _editTender(TenderMethod? method) async {
    final repository = ref.read(catalogAdminRepositoryProvider);
    if (repository == null) return;

    final edited = await TenderTypeDialog.show(context, method: method);
    if (edited == null || !mounted) return;

    setState(() => _busy = true);
    final result = await repository.saveTenderType(edited, by: widget.admin);
    if (!mounted) return;

    setState(() {
      _busy = false;
      _note = result.succeeded
          ? null
          : AdminText.refusal(context.strings, result.refusal!);
    });

    // The payment screen reads this. Without the invalidation a cashier would
    // keep being offered a method that was retired a minute ago.
    if (result.succeeded) {
      ref
        ..invalidate(tenderTypesProvider)
        ..invalidate(tenderTypesAllProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final repository = ref.watch(catalogAdminRepositoryProvider);
    if (repository == null) {
      return _Centred(text: strings.moneyComesFromPlatform);
    }

    final config = ref.watch(moneyConfigProvider);

    return config.when(
      loading: () => Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: context.pos.accent,
        ),
      ),
      error: (error, _) => _Centred(text: '$error'),
      data: (stored) {
        // Seed the boxes once. Re-seeding on every rebuild would fight the
        // operator's typing, and this rebuilds on each keystroke.
        if (!_loaded) {
          _loaded = true;
          final current = stored ?? const TaxConfig();
          _service.text = _percent(current.serviceBp);
          _vat.text = _percent(current.vatBp);
          _dineInOnly = current.serviceDineInOnly;
        }

        return ListView(
          padding: const EdgeInsets.all(PosSpace.xl),
          children: [
            Text(
              // `stored == null` is the dangerous state, and it is worth
              // saying out loud rather than showing plausible numbers.
              stored == null
                  ? strings.ratesNotSetYet
                  : strings.ratesFromThisTerminal,
              style: PosText.ui(
                size: 13,
                color: stored == null ? context.pos.warn : context.pos.muted,
                height: 1.6,
              ),
            ),
            const SizedBox(height: PosSpace.xl),
            _Rate(controller: _service, label: strings.serviceCharge),
            const SizedBox(height: PosSpace.md),
            SwitchListTile(
              value: _dineInOnly,
              onChanged: (value) => setState(() => _dineInOnly = value),
              contentPadding: EdgeInsets.zero,
              title: Text(
                strings.serviceDineInOnly,
                style: PosText.ui(size: 13.5, color: context.pos.body),
              ),
            ),
            const SizedBox(height: PosSpace.lg),
            _Rate(controller: _vat, label: strings.vat),
            if (_note != null) ...[
              const SizedBox(height: PosSpace.lg),
              Text(
                _note!,
                style: PosText.ui(size: 12.5, color: context.pos.body),
              ),
            ],
            const SizedBox(height: PosSpace.xl),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: PosButton(
                label: strings.saveRates,
                background: context.pos.ink,
                foreground: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: PosSpace.xl),
                onPressed: _busy ? null : _save,
              ),
            ),

            // What the restaurant adds on top of the food (§38). Directly
            // under the single rate it supersedes, so a manager can see which
            // of the two is actually being charged.
            const SizedBox(height: PosSpace.s28),
            Container(height: 1, color: context.pos.line),
            const SizedBox(height: PosSpace.xl),
            MicroLabel(strings.serviceCharges),
            const SizedBox(height: PosSpace.xs),
            Text(
              strings.serviceChargesHint,
              style: PosText.ui(size: 12.5, color: context.pos.muted),
            ),
            const SizedBox(height: PosSpace.md),
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
                          // rate above is what customers pay, and a blank list
                          // reads as "no service charge" to everybody.
                          Text(
                            strings.serviceChargesFallback,
                            style: PosText.ui(
                              size: 12.5,
                              color: context.pos.warn,
                            ),
                          ),
                        ]
                      : [
                          for (final charge in all)
                            _ChargeRow(
                              charge: charge,
                              onEdit: () => _editCharge(charge),
                            ),
                        ],
                ),
            const SizedBox(height: PosSpace.md),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: PosButton(
                key: const Key('charge-new'),
                label: strings.chargeNew,
                border: Border.fromBorderSide(context.pos.resting),
                onPressed: _busy ? null : () => _editCharge(null),
              ),
            ),

            // Payment methods live here rather than in a pane of their own for
            // now: "what the restaurant charges and how it takes it" is one
            // question a manager asks in one sitting. They move to Settings ›
            // Restaurant when Wave D's navigation lands.
            const SizedBox(height: PosSpace.s28),
            Container(height: 1, color: context.pos.line),
            const SizedBox(height: PosSpace.xl),
            MicroLabel(strings.tenderTypes),
            const SizedBox(height: PosSpace.xs),
            Text(
              strings.tenderTypesHint,
              style: PosText.ui(size: 12.5, color: context.pos.muted),
            ),
            const SizedBox(height: PosSpace.md),
            ...ref
                .watch(tenderTypesAllProvider)
                .when(
                  loading: () => const [SizedBox(height: 40)],
                  error: (error, _) => [
                    Text(
                      '$error',
                      style: PosText.ui(size: 13, color: context.pos.danger),
                    ),
                  ],
                  data: (methods) => [
                    for (final method in methods)
                      _TenderRow(
                        method: method,
                        onEdit: () => _editTender(method),
                      ),
                  ],
                ),
            const SizedBox(height: PosSpace.md),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: PosButton(
                key: const Key('tender-new'),
                label: strings.tenderNew,
                border: Border.fromBorderSide(context.pos.resting),
                onPressed: _busy ? null : () => _editTender(null),
              ),
            ),
          ],
        );
      },
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
                    ? Money(charge.fixedMinor!).format()
                    : '${(charge.rateBp! / 100).toStringAsFixed(
                        charge.rateBp! % 100 == 0 ? 0 : 1,
                      )}%',
                size: 12.5,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One payment method, as the editor lists them.
class _TenderRow extends StatelessWidget {
  const _TenderRow({required this.method, required this.onEdit});

  final TenderMethod method;
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
          // Retired methods stay listed, greyed. They have to: a manager who
          // turned one off needs a way to turn it back on.
          opacity: method.isActive ? 1 : 0.5,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  method.displayName(strings.languageCode),
                  style: PosText.ui(size: 13.5, color: palette.ink),
                ),
              ),
              if (!method.isActive)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: PosSpace.sm),
                  child: Text(
                    strings.tenderRetired,
                    style: PosText.ui(size: 11.5, color: palette.muted),
                  ),
                ),
              if (method.countsAsCash)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: PosSpace.sm,
                    vertical: 2,
                  ),
                  color: palette.okSoft,
                  child: Text(
                    strings.tenderCountsAsCash,
                    style: PosText.ui(
                      size: 10.5,
                      weight: FontWeight.w700,
                      color: palette.ok,
                    ),
                  ),
                ),
              const SizedBox(width: PosSpace.sm),
              MonoCode(method.code),
            ],
          ),
        ),
      ),
    );
  }
}

/// A percentage box. Stored as basis points; shown as a percent because that
/// is what a restaurant says out loud.
class _Rate extends StatelessWidget {
  const _Rate({required this.controller, required this.label});

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      MicroLabel(label),
      const SizedBox(height: PosSpace.sm),
      Row(
        children: [
          SizedBox(
            width: 140,
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: PosText.mono(size: 15, color: context.pos.ink),
            ),
          ),
          const SizedBox(width: PosSpace.sm),
          Text('%', style: PosText.mono(size: 15, color: context.pos.muted)),
        ],
      ),
    ],
  );
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
        style: PosText.ui(size: 13, color: context.pos.muted),
      ),
    ),
  );
}
