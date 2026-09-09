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
import '../../../domain/models/tax.dart';
import 'admin_messages.dart';
import 'admin_pane_bits.dart';
import 'tax_group_dialog.dart';

/// What the restaurant charges in tax (§17).
///
/// **Offline only**, for the same reason the Menu pane is: on a cloud till the
/// platform authors tax (POS-BE-013) and the bootstrap seeder overwrites the
/// row. The payment methods and service charges that used to share this pane are
/// *not* the platform's, which is why they are now panes of their own rather
/// than sections gated by a different rule from the one above them.
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
class ManagementTaxesPane extends ConsumerStatefulWidget {
  const ManagementTaxesPane({required this.admin, super.key});

  final PosStaff admin;

  @override
  ConsumerState<ManagementTaxesPane> createState() =>
      _ManagementTaxesPaneState();
}

class _ManagementTaxesPaneState extends ConsumerState<ManagementTaxesPane> {
  final _service = TextEditingController();
  final _vat = TextEditingController();
  bool _dineInOnly = true;

  /// **Carried, not rebuilt.** `saveMoneyConfig` replaces the whole payload and
  /// the codec writes `tax_mode` into it, so a `TaxConfig` constructed here
  /// without this field silently reset an inclusive restaurant to exclusive —
  /// and every ticket afterwards added 14% on top of prices that already
  /// contained it. Nothing on any screen sets the mode yet, which is exactly why
  /// saving an unrelated rate must not change it.
  TaxMode _taxMode = TaxMode.exclusive;

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

  Future<void> _editGroup(TaxGroup? group) async {
    final repository = ref.read(catalogAdminRepositoryProvider);
    if (repository == null) return;

    final edited = await TaxGroupDialog.show(context, group: group);
    if (edited == null || !mounted) return;

    setState(() {
      _busy = true;
      _note = null;
    });
    final result = await repository.saveTaxGroup(edited, by: widget.admin);
    if (!mounted) return;

    setState(() {
      _busy = false;
      _note = result.succeeded
          ? null
          : AdminText.refusal(context.strings, result.refusal!);
    });

    // The ticket prices off `taxConfigProvider`, which folds these in. Without
    // the invalidation a rate change would reach the till on the next restart —
    // and the till would keep charging the old one in the meantime.
    if (result.succeeded) {
      ref
        ..invalidate(taxGroupsProvider)
        ..invalidate(taxGroupsAllProvider);
    }
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
      TaxConfig(
        serviceBp: service,
        vatBp: vat,
        serviceDineInOnly: _dineInOnly,
        taxMode: _taxMode,
      ),
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

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final authors = ref.watch(catalogAdminRepositoryProvider) != null;
    final config = ref.watch(moneyConfigProvider);

    return config.when(
      loading: () => Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: context.pos.accent,
        ),
      ),
      error: (error, _) => PaneMessage(text: '$error'),
      data: (stored) {
        // Seed the boxes once. Re-seeding on every rebuild would fight the
        // operator's typing, and this rebuilds on each keystroke.
        if (!_loaded) {
          _loaded = true;
          final current = stored ?? const TaxConfig();
          _service.text = _percent(current.serviceBp);
          _vat.text = _percent(current.vatBp);
          _dineInOnly = current.serviceDineInOnly;
          _taxMode = current.taxMode;
        }

        // A cloud till is told, and shown nothing to type. The whole pane, not
        // half of it: unlike the payment methods and the service charges, every
        // figure here is the platform's.
        if (!authors) {
          return ListView(
            padding: const EdgeInsets.all(PosSpace.xl),
            children: [
              PlatformOwnedNotice(text: strings.moneyComesFromPlatform),
            ],
          );
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
            RateBox(
              boxKey: const Key('rate-service'),
              controller: _service,
              label: strings.serviceCharge,
            ),
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
            RateBox(
              boxKey: const Key('rate-vat'),
              controller: _vat,
              label: strings.vat,
            ),
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
                key: const Key('rates-save'),
                label: strings.saveRates,
                background: context.pos.ink,
                foreground: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: PosSpace.xl),
                onPressed: _busy ? null : _save,
              ),
            ),

            // The named rates, under the single one they supersede — the same
            // placement the service charges had under theirs, and for the same
            // reason: a manager can see which of the two is actually charged.
            const SizedBox(height: PosSpace.s28),
            Container(height: 1, color: context.pos.line),
            const SizedBox(height: PosSpace.xl),
            PaneSection(title: strings.taxGroups, hint: strings.taxGroupsHint),
            ...ref
                .watch(taxGroupsAllProvider)
                .when(
                  loading: () => const [SizedBox(height: 40)],
                  error: (error, _) => [
                    Text(
                      '$error',
                      style: PosText.ui(size: 13, color: context.pos.danger),
                    ),
                  ],
                  data: (groups) => groups.isEmpty
                      ? [
                          // The state worth naming: with no groups every product
                          // is charged the single rate above, whatever a
                          // restaurant has written on its menu about water.
                          Text(
                            strings.taxGroupsFallback,
                            style: PosText.ui(
                              size: 12.5,
                              color: context.pos.warn,
                            ),
                          ),
                        ]
                      : [
                          for (final group in groups)
                            _GroupRow(
                              group: group,
                              onEdit: () => _editGroup(group),
                            ),
                        ],
                ),
            const SizedBox(height: PosSpace.md),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: PosButton(
                key: const Key('tax-group-new'),
                label: strings.taxGroupNew,
                border: Border.fromBorderSide(context.pos.resting),
                onPressed: _busy ? null : () => _editGroup(null),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// One named rate, as the editor lists them.
class _GroupRow extends StatelessWidget {
  const _GroupRow({required this.group, required this.onEdit});

  final TaxGroup group;
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
          opacity: group.isActive ? 1 : 0.5,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  group.displayName(strings.languageCode),
                  style: PosText.ui(size: 13.5, color: palette.ink),
                ),
              ),
              if (group.isDefault)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: PosSpace.sm,
                    vertical: 2,
                  ),
                  color: palette.chipBg,
                  child: Text(
                    // Which one an unclassified product is charged at — the
                    // question this whole table answers.
                    strings.taxGroupIsDefault,
                    style: PosText.ui(
                      size: 10.5,
                      weight: FontWeight.w700,
                      color: palette.chipText,
                    ),
                  ),
                ),
              if (!group.isActive)
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: PosSpace.sm,
                  ),
                  child: Text(
                    strings.tenderRetired,
                    style: PosText.ui(size: 11.5, color: palette.muted),
                  ),
                ),
              const SizedBox(width: PosSpace.sm),
              MonoCode(AdminText.rateBp(group.rateBp), size: 12.5),
            ],
          ),
        ),
      ),
    );
  }
}
