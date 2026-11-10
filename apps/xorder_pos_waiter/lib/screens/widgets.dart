import 'package:flutter/material.dart';
import 'package:xorder_waiter_link/xorder_waiter_link.dart';

import '../strings.dart';
import '../theme.dart';

/// The handheld's components (design §4). Screens compose these and add no
/// one-off styling of their own.

/// The XOrder mark: an accent square with the letter, as on the till's start screen.
class XorderMark extends StatelessWidget {
  const XorderMark({super.key, this.size = 56});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    color: WaiterColors.accent,
    alignment: Alignment.center,
    child: Text('X', style: WaiterText.mono(size: size * 0.5, weight: FontWeight.w600, color: WaiterColors.onAccent)),
  );
}

/// The micro-label over a section — a dining area, "Not sent", "Round 2" — with
/// an optional count on the end side.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.label, {super.key, this.count, this.trailing, this.color = WaiterColors.muted});

  final String label;
  final int? count;
  final Widget? trailing;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: WaiterSpace.sectionHeader,
    child: Row(
      children: [
        Expanded(
          child: Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: WaiterText.sectionLabel(color: color),
          ),
        ),
        ?trailing,
        if (count != null) Text('$count', style: WaiterText.mono(size: 11, color: color)),
      ],
    ),
  );
}

/// A table's state as a word on a soft ground: never colour alone (design §1).
class StateBadge extends StatelessWidget {
  const StateBadge(this.state, {super.key});
  final WaiterTableState state;

  @override
  Widget build(BuildContext context) {
    final s = WaiterStrings.of(context);
    final (fill, edge, text, word) = switch (state) {
      WaiterTableState.free => (WaiterColors.surface, WaiterColors.lineStrong, WaiterColors.muted, s.tableFree),
      WaiterTableState.open => (WaiterColors.accentSoft, WaiterColors.accent, WaiterColors.ink, s.tableOpen),
      WaiterTableState.billAsked => (WaiterColors.dangerSoft, WaiterColors.danger, WaiterColors.danger, s.tableBillAsked),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: WaiterSpace.sm, vertical: 2),
      decoration: BoxDecoration(color: fill, border: Border.all(color: edge)),
      child: Text(word, style: WaiterText.badge(color: text)),
    );
  }
}

/// The ground under a screen's bottom action: a hairline on top, the safe
/// area below. No shadow — a `BottomAppBar` would cast one.
class BottomBar extends StatelessWidget {
  const BottomBar({super.key, required this.child, this.padding = const EdgeInsets.all(WaiterSpace.md)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: WaiterColors.surface,
      border: Border(top: BorderSide(color: WaiterColors.line)),
    ),
    child: SafeArea(top: false, child: Padding(padding: padding, child: child)),
  );
}

/// The one action a waiter is most likely to take next: full width, 56 tall.
class PrimaryCta extends StatelessWidget {
  const PrimaryCta({super.key, required this.label, required this.onPressed, this.busy = false});

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: WaiterSpace.cta,
    child: FilledButton(onPressed: busy ? null : onPressed, child: busy ? const SmallSpinner() : Text(label)),
  );
}

class ErrorNote extends StatelessWidget {
  const ErrorNote(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(WaiterSpace.md),
    decoration: const BoxDecoration(
      color: WaiterColors.dangerSoft,
      border: Border.fromBorderSide(BorderSide(color: WaiterColors.danger)),
    ),
    child: Text(message, style: WaiterText.ui(weight: FontWeight.w600, color: WaiterColors.danger)),
  );
}

/// Nothing here yet — said in words, with the one thing to do about it.
class EmptyState extends StatelessWidget {
  const EmptyState(this.message, {super.key, this.actionLabel, this.onAction});

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(WaiterSpace.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center, style: WaiterText.body(color: WaiterColors.muted)),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: WaiterSpace.lg),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    ),
  );
}

class SmallSpinner extends StatelessWidget {
  const SmallSpinner({super.key});

  @override
  Widget build(BuildContext context) =>
      const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: WaiterColors.ink));
}

/// Minus · value · plus, each a 48 target; the value in mono.
class QuantityStepper extends StatelessWidget {
  const QuantityStepper({super.key, required this.value, required this.onChanged, this.min = 1, this.max = 99});

  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      OutlinedButton(
        key: const Key('qty-minus'),
        onPressed: value > min ? () => onChanged(value - 1) : null,
        child: const Icon(Icons.remove, size: 20),
      ),
      SizedBox(width: 52, child: Text('$value', textAlign: TextAlign.center, style: WaiterText.keypad())),
      OutlinedButton(
        key: const Key('qty-plus'),
        onPressed: value < max ? () => onChanged(value + 1) : null,
        child: const Icon(Icons.add, size: 20),
      ),
    ],
  );
}

/// One option in a group: a square indicator (radio for a single choice,
/// check for several), the name, the price change in mono on the end side.
class OptionRow extends StatelessWidget {
  const OptionRow({
    super.key,
    required this.name,
    required this.selected,
    required this.single,
    required this.onTap,
    this.trailing,
    this.enabled = true,
  });

  final String name;
  final bool selected;
  final bool single;
  final VoidCallback? onTap;

  /// The price change, a [MoneyText]; null when the option costs nothing.
  final Widget? trailing;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final ink = enabled ? WaiterColors.ink : WaiterColors.muted;
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Container(
        constraints: const BoxConstraints(minHeight: WaiterSpace.touch),
        padding: const EdgeInsets.symmetric(vertical: WaiterSpace.sm),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: selected ? WaiterColors.ink : WaiterColors.surface,
                border: Border.all(color: enabled ? WaiterColors.ink : WaiterColors.lineStrong, width: 2),
                shape: BoxShape.rectangle,
              ),
              child: selected
                  ? Icon(single ? Icons.circle : Icons.check, size: single ? 8 : 14, color: WaiterColors.surface)
                  : null,
            ),
            const SizedBox(width: WaiterSpace.md),
            Expanded(child: Text(name, style: WaiterText.ui(size: 14.5, weight: FontWeight.w500, color: ink))),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// Two words on one line in the subtitle position: "{area} · {n} guests".
String dotJoin(Iterable<String?> parts) => parts.where((p) => p != null && p.isNotEmpty).join(' · ');

/// The currency's label beside an amount. Arabic gets the Egyptian pound's own
/// label, as on the till's receipts.
String currencyLabel(WaiterCurrency currency, {required bool arabic}) =>
    arabic && currency.code == 'EGP' ? 'ج.م' : currency.code;

/// "1234.50 EGP" — the till's figure in the till's currency, never recomputed
/// here. The plain-text form, for places a widget cannot go.
String moneyText(WaiterCurrency currency, int minor, {required bool arabic}) =>
    '${currency.of(minor).format()} ${currencyLabel(currency, arabic: arabic)}';

/// An amount as the till computed it: the number in mono, the currency label
/// in the UI face — the mono face has no Arabic glyphs, and "ج.م" must read
/// as the pound, not as boxes. [style] is the number's style; the label takes
/// its colour and decoration, one size down.
class MoneyText extends StatelessWidget {
  const MoneyText(this.currency, this.minor, {super.key, required this.style, this.prefix = '', this.textAlign});

  final WaiterCurrency currency;
  final int minor;
  final TextStyle style;

  /// Put before the number: "+" for an option's price change, "≈" for an estimate.
  final String prefix;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final s = WaiterStrings.of(context);
    final labelStyle = WaiterText.ui(
      size: (style.fontSize ?? 14) - 1,
      weight: FontWeight.w500,
      color: style.color ?? WaiterColors.ink,
      decoration: style.decoration,
    );
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: '$prefix${currency.of(minor).format()}', style: style),
        TextSpan(text: ' ${currencyLabel(currency, arabic: s.arabic)}', style: labelStyle),
      ]),
      textAlign: textAlign,
      maxLines: 1,
      // Digits and the label stay in reading order whatever the screen's direction.
      textDirection: TextDirection.ltr,
    );
  }
}
