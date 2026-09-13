import '../../domain/models/ticket.dart';

/// Turns the platform's money rules into the till's [TaxConfig].
///
/// **The server is the author of tax** (POS-BE-013). Before this existed the
/// till priced from a device-config default — 12% service, 14% VAT — while the
/// platform priced from the tenant's own rules, so a tenant with no rules
/// configured had its customers charged 27.68% more than the ledger recorded.
/// The `totals_mismatch` marker caught it, but only after the money had moved.
///
/// The reduction is deliberate and narrow for v1: the platform models many
/// rules with scopes, the ticket models one service rate and one tax rate.
/// So the first **percent charge** becomes the service rate and the first
/// **exclusive tax rule** becomes the tax rate, and anything richer than that
/// waits until the engine models it rather than being silently approximated.
///
/// An empty configuration means **zero**, not the old default. A tenant that
/// has configured no tax charges no tax — inventing one is precisely the bug
/// this file exists to end.
abstract final class MoneyConfigCodec {
  static TaxConfig toTaxConfig(Map<String, Object?> money) {
    final charges = _maps(money['charges']);
    final taxRules = _maps(money['tax_rules']);

    final service = charges
        .where((c) => c['kind'] == 'percent' && _bp(c['rate_bp']) != null)
        .firstOrNull;
    final tax = taxRules.where((t) => _bp(t['rate_bp']) != null).firstOrNull;

    return TaxConfig(
      serviceBp: _bp(service?['rate_bp']) ?? 0,
      vatBp: _bp(tax?['rate_bp']) ?? 0,
      // A charge scoped to order types applies only to those; the ticket can
      // express "dine-in only", which is what a service charge almost always
      // is. Anything else scoped is treated as applying everywhere rather
      // than being dropped — under-charging is the safer error at a till.
      serviceDineInOnly: _dineInOnly(service),
      // Absent means exclusive, which is what every row written before §37
      // meant — so a payload from an older platform changes nobody's bill.
      taxMode: TaxMode.fromWire(money['tax_mode'] as String?),
      // Only now is this true: the rates came from the platform.
      source: TaxSource.server,
    );
  }

  /// The reverse, for a till that authors its own money rules.
  ///
  /// Only an OFFLINE terminal writes this. On a cloud till the platform is the
  /// author (POS-BE-013) and `BootstrapSeeder` overwrites the row wholesale.
  ///
  /// Round-trips through [toTaxConfig] exactly, which is the property that
  /// matters: what the back office saves is what the ticket then prices with,
  /// and a lossy encode here would charge somebody the wrong amount. The shape
  /// deliberately matches the platform's — one percent charge, one tax rule —
  /// so a database written by hand and one written by the platform read the
  /// same way.
  ///
  /// [TaxConfig.source] is NOT encoded: it describes where the rates came
  /// from, and reading them back out of this row means they came from the
  /// server side of the till, which is what [toTaxConfig] already stamps.
  static Map<String, Object?> fromTaxConfig(TaxConfig config) => {
    'charges': [
      {
        'kind': 'percent',
        'rate_bp': config.serviceBp,
        if (config.serviceDineInOnly)
          'applies_to': {
            'order_types': ['dine_in'],
          },
      },
    ],
    'tax_mode': config.taxMode.wire,
    'tax_rules': [
      {'rate_bp': config.vatBp},
    ],
  };

  static bool _dineInOnly(Map<String, Object?>? charge) {
    final scope = charge?['applies_to'];
    if (scope is! Map) return false;
    final types = scope['order_types'];
    if (types is! List || types.isEmpty) return false;
    return types.length == 1 && types.first == 'dine_in';
  }

  static int? _bp(Object? value) => switch (value) {
    final int v => v,
    final String v => int.tryParse(v),
    // A rate arriving as a float is a contract violation (rates are basis
    // points) and is refused rather than rounded into somebody's bill.
    _ => null,
  };

  static List<Map<String, Object?>> _maps(Object? value) => [
    if (value is List)
      for (final item in value)
        if (item is Map) item.cast<String, Object?>(),
  ];
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
