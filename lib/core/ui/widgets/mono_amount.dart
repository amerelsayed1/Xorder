import 'package:flutter/material.dart';

import '../../money/money.dart';
import '../theme.dart';
import '../tokens.dart';

/// A number, rendered the one way this product renders numbers.
///
/// Mono, and **left-to-right regardless of the surrounding text direction**.
/// That second property is the entire reason this widget exists rather than a
/// `Text` with a mono style at each call site.
///
/// Arabic is an RTL language, but the digits in `486.50` and the characters in
/// `INV-2481` are not. Rendered inside an RTL paragraph without an explicit
/// direction, the bidirectional algorithm keeps the digit runs themselves in
/// order but reorders what surrounds them — so `-50.00` renders with its minus
/// on the wrong end, `1,240.50 EGP` puts the currency first, and a column of
/// prices stops aligning on its decimal point. A cashier reading a total off a
/// screen, or a manager comparing a column, cannot afford either.
///
/// The rule the patterns handoff states — *numbers stay LTR inside RTL text* —
/// is therefore held **by construction**. Forty call sites cannot each remember
/// to wrap a `Directionality`; one widget can make it impossible to forget.
///
/// This is also where the "Arabic-Indic digits in prose, Western digits in data"
/// split is enforced. Prose belongs to `AppStrings`; anything that renders here
/// is data, and data stays Western so that a price column aligns and an invoice
/// number can be read aloud to a supplier.
class MonoAmount extends StatelessWidget {
  const MonoAmount(
    this.value, {
    super.key,
    this.size = 13,
    this.weight = FontWeight.w400,
    this.color,
    this.masked = false,
    this.withCurrency = false,
    this.semanticLabel,
  });

  /// The amount, already in minor units. See [Money] — never a `double`.
  final Money value;

  final double size;
  final FontWeight weight;

  /// Null resolves to the palette's `ink` for a positive amount and `danger`
  /// for a negative one. Pass a colour to override — a total on the dark cart
  /// panel is `accent`, and a value on the shell needs `shellText`.
  ///
  /// **Overriding does not disable the negative treatment silently**: an
  /// explicit colour is taken as a deliberate decision by the caller, which is
  /// why it wins.
  final Color? color;

  /// Render a fixed-width mask instead of the value.
  ///
  /// Blind cash-up (patterns 5.4) turns this on for the *expected* figure. The
  /// mask deliberately has a fixed length rather than one derived from the
  /// value: a mask that grew with the number would leak its magnitude, which is
  /// the one thing blind mode exists to withhold.
  ///
  /// Masking here is a **display** guard, not the security boundary. The
  /// expected figure should not be handed to the widget at all in blind mode —
  /// see `BlindCountDialog`. This exists so that a value which legitimately is
  /// present, and merely must not be read yet, has one way to be hidden.
  final bool masked;

  final bool withCurrency;

  /// What a screen reader announces. Defaults to the formatted value.
  final String? semanticLabel;

  /// Fixed-length regardless of the value behind it. Eight marks, because the
  /// widest figure a drawer count realistically shows is `12,340.00`.
  static const _mask = '••••••••';

  @override
  Widget build(BuildContext context) {
    final palette = context.pos;
    final resolved =
        color ?? (value.isNegative ? palette.danger : palette.ink);
    final text = masked ? _mask : value.format(withCurrency: withCurrency);

    return Semantics(
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: Directionality(
        // The whole point. Not `TextDirection.of(context)`, not inherited —
        // always LTR, in every locale, for every number.
        textDirection: TextDirection.ltr,
        child: Text(
          text,
          style: PosText.mono(
            size: size,
            weight: weight,
            color: masked ? palette.muted : resolved,
          ),
        ),
      ),
    );
  }
}

/// The same guarantee for a code rather than an amount — an invoice number, a
/// SKU, a pairing code, a terminal id.
///
/// Separate from [MonoAmount] because these are not money: they have no sign,
/// no currency and no masked state, and giving them a [Money] to carry would
/// mean inventing a currency for a barcode.
class MonoCode extends StatelessWidget {
  const MonoCode(
    this.text, {
    super.key,
    this.size = 11.5,
    this.weight = FontWeight.w400,
    this.color,
  });

  final String text;
  final double size;
  final FontWeight weight;

  /// Null resolves to the palette's `muted` — a code is nearly always meta.
  final Color? color;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: Text(
      text,
      style: PosText.mono(
        size: size,
        weight: weight,
        color: color ?? context.pos.muted,
      ),
    ),
  );
}
