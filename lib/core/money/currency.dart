/// Minor-unit exponent per ISO 4217 code, mirroring the server's `CurrencyEnum`.
///
/// The three-decimal currencies are the reason `Money` carries an exponent at
/// all — see `docs/coordination/BACKEND_TO_POS.md` §A7.
int currencyExponent(String code) => switch (code.toUpperCase()) {
      'KWD' || 'BHD' || 'OMR' || 'JOD' => 3,
      _ => 2,
    };

/// Short display token shown next to prices, matching `CurrencyEnum::symbol()`.
String currencySymbol(String code) => switch (code.toUpperCase()) {
      'SAR' => 'SR',
      'USD' => r'$',
      'KWD' => 'KD',
      'QAR' => 'QR',
      'BHD' => 'BD',
      'JOD' => 'JD',
      'EUR' => '€',
      'GBP' => '£',
      final other => other,
    };
