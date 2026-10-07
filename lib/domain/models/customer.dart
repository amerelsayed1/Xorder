/// Somebody the food is for.
///
/// **The phone is the identity** (POS-BE-014). The platform's directory keys on
/// `restaurant_id + phone` and normalises Arabic-Indic digits before it looks,
/// so the till does the same and matches on the same form — a second rule here
/// would split one regular into two the first time somebody typed ٠١٠ instead
/// of 010, and nobody would notice until a report asked how often they order.
///
/// [platformId] is null until the outbox has delivered a customer created at
/// the counter. That is the ordinary state for the first thirty seconds of a
/// phone order taken during an outage, and a sale may reference such a
/// customer perfectly well — the drain fills the id in when it lands.
class PosCustomer {
  const PosCustomer({
    required this.id,
    required this.name,
    required this.phone,
    this.platformId,
    this.email,
    this.address,
    this.note,
  });

  /// This till's own row id. What an order references.
  final int id;

  /// The platform's id, once it has one.
  final int? platformId;

  final String name;

  /// Stored normalised — see [normalisePhone].
  final String phone;
  final String? email;
  final String? address;
  final String? note;

  /// A delivery needs somewhere to go. Named rather than checked at the call
  /// site so the rule reads the same in the payment screen and in the docket.
  bool get canTakeDelivery => (address ?? '').trim().isNotEmpty;

  /// The platform's rule, verbatim: Arabic-Indic and Eastern Arabic digits
  /// folded to ASCII, everything that is not a digit or a leading `+` dropped.
  ///
  /// Kept beside the model rather than in the repository because the payment
  /// screen matches against it as the cashier types, and a search that
  /// normalised differently from the write would fail to find the customer it
  /// had just saved.
  static String normalisePhone(String raw) {
    final buffer = StringBuffer();
    for (var i = 0; i < raw.length; i++) {
      final code = raw.codeUnitAt(i);
      if (code >= 0x0660 && code <= 0x0669) {
        // ٠-٩
        buffer.writeCharCode(0x30 + (code - 0x0660));
      } else if (code >= 0x06F0 && code <= 0x06F9) {
        // ۰-۹, the Persian forms a Farsi keyboard produces.
        buffer.writeCharCode(0x30 + (code - 0x06F0));
      } else if (code >= 0x30 && code <= 0x39) {
        buffer.writeCharCode(code);
      } else if (code == 0x2B && buffer.isEmpty) {
        buffer.writeCharCode(code);
      }
    }
    return buffer.toString();
  }

  /// Whether this customer answers to [query] — a name fragment, or any run of
  /// digits from the number.
  ///
  /// Case- and digit-form-insensitive, and the phone is matched on `contains`
  /// rather than `startsWith` because a cashier is read the last four digits
  /// over a counter far more often than the first four.
  bool matches(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return true;

    final digits = normalisePhone(trimmed);
    if (digits.isNotEmpty && phone.contains(digits)) return true;

    return name.toLowerCase().contains(trimmed.toLowerCase());
  }

  PosCustomer copyWith({int? platformId}) => PosCustomer(
    id: id,
    platformId: platformId ?? this.platformId,
    name: name,
    phone: phone,
    email: email,
    address: address,
    note: note,
  );

  @override
  bool operator ==(Object other) => other is PosCustomer && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
