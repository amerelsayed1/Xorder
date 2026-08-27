/// Integer half-up division.
///
/// Dart's `~/` truncates toward zero and `.round()` on a double is
/// banker's-adjacent and floating point besides. The server rounds half-up
/// (PHP's default for `round()`), and a POS whose tax line disagrees with the
/// backend by one piastre produces a `totals_mismatch` on every single ticket.
///
/// Negative numerators round half **away from zero**, which keeps a refund the
/// exact mirror of the sale it reverses.
int roundHalfUp(int numerator, int denominator) {
  assert(denominator > 0, 'denominator must be positive, got $denominator');

  if (numerator >= 0) {
    return (numerator * 2 + denominator) ~/ (denominator * 2);
  }
  return -((-numerator * 2 + denominator) ~/ (denominator * 2));
}
