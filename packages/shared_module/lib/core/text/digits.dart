/// Digits as a till reads them (XORD-004).
///
/// A cashier on an Arabic keyboard, or pasting a number out of a WhatsApp
/// message, types `٠١٢٣٤٥٦٧٨٩` (Arabic-Indic) or `۰۱۲۳۴۵۶۷۸۹` (the Persian forms a
/// Farsi layout produces). Every number this app stores, sends or computes with
/// is ASCII, so the fold happens at the edge: [foldDigits] for strings that are
/// about to be parsed, `FoldDigitsFormatter` for fields as they are typed.
///
/// Pure Dart on purpose — `Money.tryParse` and `Quantity.tryParse` use it.
library;

/// [input] with Arabic-Indic and Persian digits replaced by ASCII, the Arabic
/// decimal separator `٫` by `.` and the Arabic thousands separator `٬` by `,`.
///
/// **Always the same length as [input]**: each character is replaced by exactly
/// one other, so a caret, a selection or an IME composing range that pointed at
/// a position still points at the same character afterwards.
///
/// Nothing else is touched — in particular letters and unknown punctuation
/// survive, so a parser downstream still refuses what is not a number instead
/// of this function guessing what was meant. Phone numbers keep their leading
/// zeros: this works on characters, never on values.
String foldDigits(String input) {
  StringBuffer? out;
  for (var i = 0; i < input.length; i++) {
    final code = input.codeUnitAt(i);
    final replacement = _fold(code);
    if (replacement == null) {
      out?.writeCharCode(code);
      continue;
    }
    // First character that needs folding: copy what came before, once.
    out ??= StringBuffer(input.substring(0, i));
    out.writeCharCode(replacement);
  }
  return out == null ? input : out.toString();
}

int? _fold(int code) {
  if (code >= 0x0660 && code <= 0x0669) return 0x30 + (code - 0x0660); // ٠-٩
  if (code >= 0x06F0 && code <= 0x06F9) return 0x30 + (code - 0x06F0); // ۰-۹
  if (code == 0x066B) return 0x2E; // ٫ → .
  if (code == 0x066C) return 0x2C; // ٬ → ,
  return null;
}
