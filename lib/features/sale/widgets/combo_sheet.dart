import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/money/money.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/mono_amount.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/combo.dart';

/// Building a meal.
///
/// One group at a time, in the order the business put them in — "choose a
/// sandwich", then a side, then a drink. The running total is the combo's
/// price plus any upgrades, visible throughout, because the whole reason a
/// customer is buying a meal is that it costs less than the parts and the
/// cashier has to be able to say what it comes to.
///
/// **A fixed meal never gets here.** A combo whose every group offers one
/// option and demands it has nothing to ask, and `Combo.isFixed` is what the
/// caller checks before opening this.
class ComboSheet extends StatefulWidget {
  const ComboSheet({super.key, required this.combo});

  final Combo combo;

  /// Returns the chosen options, or null if nothing was.
  static Future<List<ComboOption>?> show(
    BuildContext context, {
    required Combo combo,
  }) => showDialog<List<ComboOption>>(
    context: context,
    builder: (_) => ComboSheet(combo: combo),
  );

  @override
  State<ComboSheet> createState() => _ComboSheetState();
}

class _ComboSheetState extends State<ComboSheet> {
  /// Chosen option ids, per group.
  final _chosen = <int, List<ComboOption>>{};

  @override
  void initState() {
    super.initState();
    // Anything with no choice in it is answered up front, so the sheet only
    // ever shows what somebody actually has to decide.
    for (final group in widget.combo.groups) {
      if (group.options.length == 1 && group.minSelect >= 1) {
        _chosen[group.id] = [group.options.first];
      }
    }
  }

  List<ComboOption> get _all => [
    for (final group in widget.combo.groups) ...?_chosen[group.id],
  ];

  Money get _total =>
      _all.fold(widget.combo.price, (sum, o) => sum + o.priceDelta);

  /// How many more choices the meal is waiting on.
  int get _outstanding => widget.combo.groups.fold(0, (need, group) {
    final picked = (_chosen[group.id] ?? const []).length;
    return need + (picked < group.minSelect ? group.minSelect - picked : 0);
  });

  void _pick(ComboGroup group, ComboOption option) {
    setState(() {
      final picked = [...?_chosen[group.id]];
      final already = picked.any((o) => o.id == option.id);

      if (already) {
        // Tapping a chosen option again clears it — unless the group demands
        // one and this is it, where clearing would leave the meal incomplete
        // with nothing on screen to say why the button went dead.
        if (picked.length > group.minSelect) {
          picked.removeWhere((o) => o.id == option.id);
        }
      } else if (group.isSingleSelect) {
        picked
          ..clear()
          ..add(option);
      } else if (picked.length < group.maxSelect) {
        picked.add(option);
      }

      _chosen[group.id] = picked;
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;
    final language = strings.languageCode;
    final ready = _outstanding == 0;

    return Dialog(
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: PosSize.dialogCount),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                Navigator.of(context).pop(),
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(strings, palette, language),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(PosSpace.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final group in widget.combo.groups)
                        _group(strings, palette, language, group),
                    ],
                  ),
                ),
              ),
              _footer(strings, palette, ready),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(AppStrings strings, PosPalette palette, String language) =>
      Container(
        padding: const EdgeInsets.all(PosSpace.lg),
        decoration: BoxDecoration(
          border: BorderDirectional(bottom: palette.resting),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.combo.displayName(language),
                    style: PosText.ui(
                      size: 20,
                      weight: FontWeight.w800,
                      color: palette.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    strings.comboBadge,
                    style: PosText.mono(size: 10.5, color: palette.accent),
                  ),
                ],
              ),
            ),
            // The running total, because the reason to buy a meal is that it
            // costs less than the parts and the cashier has to be able to say
            // what it comes to.
            MonoAmount(_total, size: 22, weight: FontWeight.w700),
          ],
        ),
      );

  Widget _group(
    AppStrings strings,
    PosPalette palette,
    String language,
    ComboGroup group,
  ) {
    final picked = _chosen[group.id] ?? const <ComboOption>[];

    return Padding(
      padding: const EdgeInsets.only(bottom: PosSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MicroLabel(strings.comboChoose(group.displayName(language))),
          const SizedBox(height: PosSpace.xs),
          Wrap(
            spacing: PosSpace.sm,
            runSpacing: PosSpace.sm,
            children: [
              for (final option in group.options)
                _option(
                  strings,
                  palette,
                  language,
                  group,
                  option,
                  selected: picked.any((o) => o.id == option.id),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _option(
    AppStrings strings,
    PosPalette palette,
    String language,
    ComboGroup group,
    ComboOption option, {
    required bool selected,
  }) => Material(
    color: selected ? palette.accentSoft : Colors.transparent,
    child: InkWell(
      onTap: () => _pick(group, option),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: PosSpace.md,
          vertical: PosSpace.sm,
        ),
        decoration: BoxDecoration(
          border: Border.fromBorderSide(
            selected ? palette.accentBorder : palette.resting,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              option.product.displayName(language),
              style: PosText.ui(
                size: 13.5,
                weight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? palette.inkWarm : palette.body,
              ),
            ),
            const SizedBox(width: PosSpace.sm),
            // The upgrade, not the product's own price — inside a meal the
            // shelf price is not what anybody pays, and showing it would
            // invite the arithmetic the combo exists to avoid.
            option.priceDelta.isZero
                ? Text(
                    strings.comboIncluded,
                    style: PosText.mono(size: 10.5, color: palette.muted),
                  )
                : MonoAmount(
                    option.priceDelta,
                    size: 11.5,
                    color: palette.accent,
                  ),
          ],
        ),
      ),
    ),
  );

  Widget _footer(AppStrings strings, PosPalette palette, bool ready) =>
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
                // Says what is still missing rather than going quietly dead.
                label: ready
                    ? strings.comboAddToTicket
                    : strings.comboPickMore(_outstanding),
                background: ready ? palette.accent : palette.ctaDisabled,
                foreground: Colors.white,
                fontWeight: FontWeight.w700,
                onPressed: ready
                    ? () => Navigator.of(context).pop(_all)
                    : null,
              ),
            ),
          ],
        ),
      );
}
