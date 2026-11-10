import 'package:flutter/material.dart';

/// A catalogue name — a product, a meal — as the till shows it.
///
/// **The ellipsis lands at the end the name is read from.** A `Text` takes its
/// direction from the surrounding `Directionality`, and that is the till's
/// language, not the name's: an Arabic menu on an English till, or an English
/// name on an Arabic till, is laid out in the *wrong* base direction. The bidi
/// algorithm then reorders the runs around the ellipsis rather than inside the
/// name, and «شاورما فراخ سبيشال» came up on the audit's screenshots with the
/// "…" in the middle of the word and the halves swapped — unreadable, on the
/// one screen a cashier reads forty times an hour.
///
/// So the name decides its own direction, from its first strong character
/// ([scriptDirectionOf]), and the ellipsis is only ever an *end* ellipsis of
/// that direction. The alignment stays with the surrounding layout, so a
/// column of names still lines up on the column's edge whichever script each
/// one is in.
///
/// Where the layout has the room, [maxLines] lets a name wrap before it is
/// cut: a truncated name is a name the cashier has to guess at, and two
/// dishes that share a first word are the ones that get rung up wrong.
class ItemName extends StatelessWidget {
  const ItemName(
    this.text, {
    super.key,
    required this.style,
    this.maxLines = 1,
  });

  final String text;
  final TextStyle style;

  /// How far the name may wrap before the end ellipsis. One where a row has a
  /// fixed height to keep; two or three where the tile is tall enough.
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final ambient = Directionality.of(context);
    final own = scriptDirectionOf(text) ?? ambient;

    return Text(
      text,
      maxLines: maxLines,
      softWrap: maxLines > 1,
      overflow: TextOverflow.ellipsis,
      textDirection: own,
      // Pinned to the layout's edge, not the name's: `TextAlign.start` would
      // resolve against `own` and push an Arabic name to the far side of an
      // English column.
      textAlign: ambient == TextDirection.ltr ? TextAlign.left : TextAlign.right,
      style: style,
    );
  }
}

/// Arabic, Hebrew, Syriac, Thaana and their presentation forms — anything
/// written right to left that a menu in this region can hold.
final _rtl = RegExp(r'[\u0590-\u08FF\uFB1D-\uFDFF\uFE70-\uFEFF]');

/// Latin, including the accented letters a French or Turkish dish name needs.
final _ltr = RegExp(r'[A-Za-z\u00C0-\u024F]');

/// The direction [text] reads in, from its first strong character — what the
/// Unicode bidi algorithm would choose for a paragraph of it.
///
/// Null when it has none ("330", "—", a bare SKU): a string with no letters
/// reads the same either way and should follow whatever surrounds it rather
/// than override it.
TextDirection? scriptDirectionOf(String text) {
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    if (_rtl.hasMatch(char)) return TextDirection.rtl;
    if (_ltr.hasMatch(char)) return TextDirection.ltr;
  }
  return null;
}
