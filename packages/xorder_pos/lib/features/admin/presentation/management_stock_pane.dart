import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/mono_amount.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/permissions.dart';
import '../../../domain/models/shift.dart';
import '../../../domain/models/stock_level.dart';
import '../../../domain/services/authorization.dart';
import 'admin_messages.dart';
import 'admin_pane_bits.dart';
import 'opening_cost_dialog.dart';

/// How much of each counted item this branch holds, and what it is worth.
///
/// Read-only, and on purpose for now: stock moves when a delivery is received,
/// and a number somebody could type over here would be a number no delivery
/// note explains. Counts, waste and adjustments are the next wave, and each
/// will be a movement with a reason — never an edit to this figure.
class ManagementStockPane extends ConsumerWidget {
  const ManagementStockPane({required this.admin, super.key});

  /// Who is looking — for whether they may give an uncosted item its first cost.
  final PosStaff admin;

  /// The same permission receiving needs: both set the figure every margin is
  /// measured against.
  bool get _mayCost =>
      Authorization.check(admin, PosCapability.purchaseManage).isAllowed;

  Future<void> _setCost(
    BuildContext context,
    WidgetRef ref,
    StockLevel level,
    String unitName,
  ) async {
    final cost = await OpeningCostDialog.show(
      context,
      level: level,
      unitName: unitName,
    );
    if (cost == null || !context.mounted) return;

    final strings = context.strings;
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref
        .read(receivingRepositoryProvider)
        .setOpeningCost(productId: level.productId, unitCost: cost, by: admin);

    final refusal = result.refusal;
    if (refusal != null) {
      messenger.showSnackBar(
        SnackBar(content: Text(AdminText.refusal(strings, refusal))),
      );
      return;
    }
    // The list is what shows the cost, the total and the "not counted" line.
    ref.invalidate(stockLevelsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.strings;
    final palette = context.pos;
    final named = {
      for (final unit in ref.watch(unitsAllProvider).valueOrNull ?? const [])
        unit.code: unit.displayName(strings.languageCode),
    };

    return ListView(
      padding: const EdgeInsets.all(PosSpace.xl),
      children: [
        PaneSection(title: strings.paneStock, hint: strings.paneStockBlurb),
        ...ref
            .watch(stockLevelsProvider)
            .when(
              loading: () => const [SizedBox(height: 40)],
              error: (error, _) => [
                Text('$error', style: PosText.ui(size: 13, color: palette.danger)),
              ],
              data: (levels) {
                if (levels.isEmpty) {
                  return [
                    Text(
                      strings.stockEmpty,
                      style: PosText.ui(size: 13, color: palette.muted),
                    ),
                  ];
                }
                final valuation = StockValuation.of(levels);
                // One slot for the button in every row or in none, so the
                // columns stay under their headings whichever rows have one.
                final showAction =
                    _mayCost && levels.any((level) => !level.hasCost);
                return [
                  Text(
                    strings.stockTotalValue(valuation.total.format(withCurrency: true)),
                    key: const Key('stock-total'),
                    style: PosText.ui(
                      size: 15,
                      weight: FontWeight.w700,
                      color: palette.ink,
                    ),
                  ),
                  // What the total leaves out, beside it — so it is not read as
                  // the worth of the whole shelf when part of the shelf has
                  // never been priced.
                  if (!valuation.isComplete) ...[
                    const SizedBox(height: PosSpace.xs),
                    Text(
                      strings.stockExcludesUncosted(valuation.unvalued),
                      key: const Key('stock-unvalued'),
                      style: PosText.ui(
                        size: 12.5,
                        weight: FontWeight.w600,
                        color: palette.warn,
                      ),
                    ),
                  ],
                  // Said once, with the figure it explains and above the table rather
                  // than inside it, and only when a row needs it: a note on a page
                  // where every item is costed is noise.
                  if (levels.any((level) => !level.hasCost)) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: PosSpace.xs),
                      child: Text(
                        strings.stockNoCostNote,
                        key: const Key('stock-no-cost-note'),
                        style: PosText.ui(
                          size: 12,
                          color: palette.muted,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: PosSpace.md),
                  _Header(showAction: showAction),
                  for (final level in levels)
                    _LevelRow(
                      level: level,
                      unitName:
                          named[level.onHand.unit.wire] ??
                          AdminText.unit(strings, level.onHand.unit),
                      reserveAction: showAction,
                      onSetCost: _mayCost && !level.hasCost
                          ? () => _setCost(
                              context,
                              ref,
                              level,
                              named[level.onHand.unit.wire] ??
                                  AdminText.unit(strings, level.onHand.unit),
                            )
                          : null,
                    ),
                ];
              },
            ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.showAction});

  /// Whether any row carries a button, so the headings stay over their columns.
  final bool showAction;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Padding(
      padding: const EdgeInsets.only(bottom: PosSpace.xs),
      child: Row(
        children: [
          Expanded(child: MicroLabel(strings.stockColumnItem)),
          SizedBox(width: 150, child: MicroLabel(strings.stockColumnOnHand)),
          SizedBox(width: 120, child: MicroLabel(strings.stockColumnAvgCost)),
          SizedBox(width: 120, child: MicroLabel(strings.stockColumnValue)),
          if (showAction) const SizedBox(width: _actionWidth),
        ],
      ),
    );
  }
}

/// The room a row's "Set cost" button takes.
const _actionWidth = 112.0;

class _LevelRow extends StatelessWidget {
  const _LevelRow({
    required this.level,
    required this.unitName,
    required this.reserveAction,
    this.onSetCost,
  });

  final StockLevel level;
  final String unitName;

  /// Another row has a button, so this one leaves room for it.
  final bool reserveAction;

  /// Null when the item has a cost, or the person may not give it one.
  final VoidCallback? onSetCost;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;
    // Below zero is a real state and is shown as one: something was sold that
    // never arrived as far as the system knows.
    final short = level.onHand.isNegative;

    return Container(
      key: Key('stock-row-${level.productId}'),
      padding: const EdgeInsets.symmetric(vertical: PosSpace.sm),
      decoration: BoxDecoration(
        border: BorderDirectional(bottom: palette.hairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    level.displayName(strings.languageCode),
                    style: PosText.ui(size: 13.5, color: palette.ink),
                  ),
                ),
                if (level.onMenu) ...[
                  const SizedBox(width: PosSpace.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: PosSpace.sm,
                      vertical: 2,
                    ),
                    color: palette.accentSoft,
                    child: Text(
                      strings.itemOnMenu,
                      style: PosText.ui(
                        size: 10.5,
                        weight: FontWeight.w700,
                        color: palette.ink,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(
            width: 150,
            child: Text(
              '${level.onHand.format()} $unitName',
              style: PosText.mono(
                size: 13,
                color: short ? palette.danger : palette.ink,
              ),
            ),
          ),
          SizedBox(
            width: 120,
            // A dash and a tag, never 0.00: nothing has set a cost, which is
            // not the same as the item being free (`StockLevel.hasCost`).
            child: level.hasCost
                ? MonoAmount(level.unitCost, size: 13)
                : Row(
                    key: Key('stock-no-cost-${level.productId}'),
                    children: [
                      Text(
                        '—',
                        style: PosText.mono(size: 13, color: palette.muted),
                      ),
                      const SizedBox(width: PosSpace.sm),
                      Flexible(
                        child: Text(
                          strings.profitNoCostTag,
                          overflow: TextOverflow.ellipsis,
                          style: PosText.ui(size: 11.5, color: palette.muted),
                        ),
                      ),
                    ],
                  ),
          ),
          SizedBox(
            width: 120,
            // Unknown, not nothing: an uncosted item's worth is not in the
            // total above, and 0.00 here would say it had been counted.
            child: level.hasCost
                ? MonoAmount(level.value, size: 13)
                : Text('—', style: PosText.mono(size: 13, color: palette.muted)),
          ),
          if (reserveAction)
            SizedBox(
              width: _actionWidth,
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: onSetCost == null
                    ? null
                    : TextButton(
                        key: Key('stock-set-cost-${level.productId}'),
                        onPressed: onSetCost,
                        child: Text(strings.stockSetCost),
                      ),
              ),
            ),
        ],
      ),
    );
  }
}
