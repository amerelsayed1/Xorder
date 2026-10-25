import 'package:flutter/services.dart';

import '../../text/digits.dart';

/// Turns Arabic-Indic and Persian digits into ASCII as they are typed or pasted
/// (XORD-004).
///
/// Put it FIRST in a field's `inputFormatters`. A `FilteringTextInputFormatter`
/// that only allows `[0-9.]` would otherwise drop `٣` and the cashier would see
/// the key do nothing.
///
/// [foldDigits] keeps the length, so the selection and the composing range are
/// carried over untouched: the caret does not jump, and replacing a selection
/// or editing mid-string behaves as it does with ASCII digits.
class FoldDigitsFormatter extends TextInputFormatter {
  const FoldDigitsFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final folded = foldDigits(newValue.text);
    return folded == newValue.text ? newValue : newValue.copyWith(text: folded);
  }
}
