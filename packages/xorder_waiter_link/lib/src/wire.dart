/// What travels between a waiter's handheld and the till (waiter-app, WA1).
///
/// **The till prices; the handheld shows.** Every amount here was computed by
/// the till's `TicketEngine` and is carried in integer minor units with the
/// currency's exponent, never a double. The handheld never sends a price: it
/// sends what the waiter did ([WaiterOp]) and gets back the check the till
/// made of it (BR-2).
///
/// Parsing is forgiving the way the till's other wires are: an unknown enum
/// value falls back, a missing list is empty, and a malformed document is a
/// [WaiterWireError] rather than a crash on a phone in the middle of service.
library;

/// The version of this wire. A handheld and a till that disagree on it say
/// "update" instead of guessing (TECHNICAL section 5: an older till than the
/// handheld is told apart from a newer one).
const waiterWireVersion = 1;

class WaiterWireError implements Exception {
  const WaiterWireError(this.message);
  final String message;
  @override
  String toString() => 'WaiterWireError: $message';
}

// ---------------------------------------------------------------------------
// Small readers. Kept private and dull so every class below reads the same.

Map<String, Object?> _map(Object? v, String what) {
  if (v is Map) return v.cast<String, Object?>();
  throw WaiterWireError('$what is not an object');
}

List<Object?> _list(Object? v) => v is List ? v : const [];

int _int(Object? v, {int orElse = 0}) => v is int ? v : orElse;

int? _intOrNull(Object? v) => v is int ? v : null;

String _str(Object? v, {String orElse = ''}) => v is String ? v : orElse;

String? _strOrNull(Object? v) => v is String && v.isNotEmpty ? v : null;

bool _bool(Object? v, {bool orElse = false}) => v is bool ? v : orElse;

/// A name in both languages; the handheld picks by its own locale.
class WaiterName {
  const WaiterName(this.en, [this.ar]);

  final String en;
  final String? ar;

  /// Arabic when asked for and present, English otherwise.
  String pick({required bool arabic}) =>
      arabic && (ar?.trim().isNotEmpty ?? false) ? ar! : en;

  Map<String, Object?> toJson() => {'en': en, if (ar != null) 'ar': ar};

  factory WaiterName.fromJson(Object? json) {
    if (json is String) return WaiterName(json);
    final m = json is Map ? json.cast<String, Object?>() : const {};
    return WaiterName(_str(m['en']), _strOrNull(m['ar']));
  }
}

/// Money as the till computed it.
class WaiterMoney {
  const WaiterMoney(this.minor, {required this.currency, required this.exponent});

  final int minor;
  final String currency;
  final int exponent;

  /// "1234.50" — digits only; the handheld adds the currency label itself.
  String format() {
    final negative = minor < 0;
    final digits = minor.abs().toString().padLeft(exponent + 1, '0');
    final whole = exponent == 0 ? digits : digits.substring(0, digits.length - exponent);
    final frac = exponent == 0 ? '' : '.${digits.substring(digits.length - exponent)}';
    return '${negative ? '-' : ''}$whole$frac';
  }

  @override
  bool operator ==(Object other) =>
      other is WaiterMoney &&
      other.minor == minor &&
      other.currency == currency &&
      other.exponent == exponent;

  @override
  int get hashCode => Object.hash(minor, currency, exponent);
}

/// The currency every amount in one document shares, so amounts can travel
/// as bare integers.
class WaiterCurrency {
  const WaiterCurrency(this.code, this.exponent);
  final String code;
  final int exponent;

  WaiterMoney of(int minor) => WaiterMoney(minor, currency: code, exponent: exponent);

  Map<String, Object?> toJson() => {'code': code, 'exponent': exponent};

  factory WaiterCurrency.fromJson(Object? json) {
    final m = json is Map ? json.cast<String, Object?>() : const {};
    return WaiterCurrency(_str(m['code'], orElse: 'EGP'), _int(m['exponent'], orElse: 2));
  }
}

// ---------------------------------------------------------------------------
// Who is holding the handheld.

class WaiterStaff {
  const WaiterStaff({required this.id, required this.name, this.capabilities = const {}});

  final int id;
  final String name;

  /// Only the ones the handheld uses to grey a control out. The till checks
  /// every edit against the person again; this is a courtesy, not the gate.
  final Set<String> capabilities;

  bool can(String capability) => capabilities.contains(capability);

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'capabilities': capabilities.toList()..sort(),
  };

  factory WaiterStaff.fromJson(Object? json) {
    final m = _map(json, 'staff');
    return WaiterStaff(
      id: _int(m['id']),
      name: _str(m['name']),
      capabilities: {for (final c in _list(m['capabilities'])) if (c is String) c},
    );
  }
}

/// A signed-in waiter: who, and the session the till gave them.
///
/// [deviceToken] rides along the first time a handheld signs in: the till
/// registered it as a device on that sign-in and this is the token it keeps
/// for every later request (WA3: sign-in registers, there is no pairing code).
class WaiterSession {
  const WaiterSession({required this.token, required this.staff, this.deviceToken});
  final String token;
  final WaiterStaff staff;
  final String? deviceToken;

  Map<String, Object?> toJson() => {
    'session': token,
    'staff': staff.toJson(),
    'device_token': ?deviceToken,
  };

  factory WaiterSession.fromJson(Object? json) {
    final m = _map(json, 'session');
    final token = _str(m['session']);
    if (token.isEmpty) throw const WaiterWireError('session has no token');
    return WaiterSession(
      token: token,
      staff: WaiterStaff.fromJson(m['staff']),
      deviceToken: _strOrNull(m['device_token']),
    );
  }
}

// ---------------------------------------------------------------------------
// The menu, as the till prices it.

class WaiterModifier {
  const WaiterModifier({
    required this.id,
    required this.name,
    required this.deltaMinor,
    this.available = true,
    this.isDefault = false,
  });

  final int id;
  final WaiterName name;
  final int deltaMinor;
  final bool available;
  final bool isDefault;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name.toJson(),
    'delta_minor': deltaMinor,
    'available': available,
    'default': isDefault,
  };

  factory WaiterModifier.fromJson(Object? json) {
    final m = _map(json, 'modifier');
    return WaiterModifier(
      id: _int(m['id']),
      name: WaiterName.fromJson(m['name']),
      deltaMinor: _int(m['delta_minor']),
      available: _bool(m['available'], orElse: true),
      isDefault: _bool(m['default']),
    );
  }
}

class WaiterModifierGroup {
  const WaiterModifierGroup({
    required this.id,
    required this.name,
    required this.modifiers,
    this.minSelect = 0,
    this.maxSelect = 1,
    this.isVariant = false,
  });

  final int id;
  final WaiterName name;
  final List<WaiterModifier> modifiers;
  final int minSelect;
  final int maxSelect;
  final bool isVariant;

  bool get isRequired => minSelect > 0;
  bool get isSingle => maxSelect == 1;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name.toJson(),
    'min': minSelect,
    'max': maxSelect,
    'variant': isVariant,
    'modifiers': [for (final m in modifiers) m.toJson()],
  };

  factory WaiterModifierGroup.fromJson(Object? json) {
    final m = _map(json, 'modifier group');
    return WaiterModifierGroup(
      id: _int(m['id']),
      name: WaiterName.fromJson(m['name']),
      minSelect: _int(m['min']),
      maxSelect: _int(m['max'], orElse: 1),
      isVariant: _bool(m['variant']),
      modifiers: [for (final x in _list(m['modifiers'])) WaiterModifier.fromJson(x)],
    );
  }
}

class WaiterProduct {
  const WaiterProduct({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.priceMinor,
    this.available = true,
    this.groupIds = const [],
  });

  final int id;
  final int categoryId;
  final WaiterName name;

  /// The till's selling price for one, before modifiers.
  final int priceMinor;
  final bool available;
  final List<int> groupIds;

  Map<String, Object?> toJson() => {
    'id': id,
    'category_id': categoryId,
    'name': name.toJson(),
    'price_minor': priceMinor,
    'available': available,
    'groups': groupIds,
  };

  factory WaiterProduct.fromJson(Object? json) {
    final m = _map(json, 'product');
    return WaiterProduct(
      id: _int(m['id']),
      categoryId: _int(m['category_id']),
      name: WaiterName.fromJson(m['name']),
      priceMinor: _int(m['price_minor']),
      available: _bool(m['available'], orElse: true),
      groupIds: [for (final g in _list(m['groups'])) if (g is int) g],
    );
  }
}

class WaiterCategory {
  const WaiterCategory({required this.id, required this.name});
  final int id;
  final WaiterName name;

  Map<String, Object?> toJson() => {'id': id, 'name': name.toJson()};

  factory WaiterCategory.fromJson(Object? json) {
    final m = _map(json, 'category');
    return WaiterCategory(id: _int(m['id']), name: WaiterName.fromJson(m['name']));
  }
}

class WaiterMenu {
  const WaiterMenu({
    required this.currency,
    required this.categories,
    required this.products,
    required this.groups,
  });

  final WaiterCurrency currency;
  final List<WaiterCategory> categories;
  final List<WaiterProduct> products;
  final List<WaiterModifierGroup> groups;

  List<WaiterProduct> inCategory(int categoryId) =>
      [for (final p in products) if (p.categoryId == categoryId) p];

  List<WaiterModifierGroup> groupsOf(WaiterProduct product) => [
    for (final id in product.groupIds)
      for (final g in groups) if (g.id == id) g,
  ];

  Map<String, Object?> toJson() => {
    'currency': currency.toJson(),
    'categories': [for (final c in categories) c.toJson()],
    'products': [for (final p in products) p.toJson()],
    'groups': [for (final g in groups) g.toJson()],
  };

  factory WaiterMenu.fromJson(Object? json) {
    final m = _map(json, 'menu');
    return WaiterMenu(
      currency: WaiterCurrency.fromJson(m['currency']),
      categories: [for (final x in _list(m['categories'])) WaiterCategory.fromJson(x)],
      products: [for (final x in _list(m['products'])) WaiterProduct.fromJson(x)],
      groups: [for (final x in _list(m['groups'])) WaiterModifierGroup.fromJson(x)],
    );
  }
}

// ---------------------------------------------------------------------------
// The floor.

enum WaiterTableState {
  free,
  open,

  /// The guests asked for the bill.
  billAsked;

  static WaiterTableState parse(Object? v) => switch (v) {
    'open' => open,
    'bill_asked' => billAsked,
    _ => free,
  };

  String get wire => switch (this) {
    free => 'free',
    open => 'open',
    billAsked => 'bill_asked',
  };
}

class WaiterTable {
  const WaiterTable({
    required this.id,
    required this.label,
    this.area,
    this.seats,
    this.state = WaiterTableState.free,
    this.totalMinor = 0,
    this.items = 0,
    this.guests,
  });

  final int id;
  final String label;
  final String? area;
  final int? seats;
  final WaiterTableState state;

  /// The open check's total, 0 on a free table.
  final int totalMinor;

  /// Live lines on the open check.
  final int items;
  final int? guests;

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    if (area != null) 'area': area,
    if (seats != null) 'seats': seats,
    'state': state.wire,
    'total_minor': totalMinor,
    'items': items,
    if (guests != null) 'guests': guests,
  };

  factory WaiterTable.fromJson(Object? json) {
    final m = _map(json, 'table');
    return WaiterTable(
      id: _int(m['id']),
      label: _str(m['label']),
      area: _strOrNull(m['area']),
      seats: _intOrNull(m['seats']),
      state: WaiterTableState.parse(m['state']),
      totalMinor: _int(m['total_minor']),
      items: _int(m['items']),
      guests: _intOrNull(m['guests']),
    );
  }
}

class WaiterFloor {
  const WaiterFloor({required this.currency, required this.tables});
  final WaiterCurrency currency;
  final List<WaiterTable> tables;

  Map<String, Object?> toJson() => {
    'currency': currency.toJson(),
    'tables': [for (final t in tables) t.toJson()],
  };

  factory WaiterFloor.fromJson(Object? json) {
    final m = _map(json, 'floor');
    return WaiterFloor(
      currency: WaiterCurrency.fromJson(m['currency']),
      tables: [for (final x in _list(m['tables'])) WaiterTable.fromJson(x)],
    );
  }
}

// ---------------------------------------------------------------------------
// One table's check.

enum WaiterLineStage {
  /// Not yet sent: the waiter may change or remove it.
  draft,

  /// Sent to the kitchen in a round. Only the till voids it (WA1).
  sent,

  /// Sent, then voided at the till: shown struck through.
  voided;

  static WaiterLineStage parse(Object? v) => switch (v) {
    'sent' => sent,
    'voided' => voided,
    _ => draft,
  };

  String get wire => name;
}

class WaiterLine {
  const WaiterLine({
    required this.key,
    required this.name,
    required this.quantity,
    required this.totalMinor,
    this.modifiers = const [],
    this.note,
    this.stage = WaiterLineStage.draft,
    this.round,
  });

  /// The till's line key: what [WaiterOp]s name the line by.
  final String key;
  final WaiterName name;
  final int quantity;
  final int totalMinor;
  final List<WaiterName> modifiers;
  final String? note;
  final WaiterLineStage stage;
  final int? round;

  bool get isDraft => stage == WaiterLineStage.draft;

  Map<String, Object?> toJson() => {
    'key': key,
    'name': name.toJson(),
    'qty': quantity,
    'total_minor': totalMinor,
    'modifiers': [for (final m in modifiers) m.toJson()],
    if (note != null) 'note': note,
    'stage': stage.wire,
    if (round != null) 'round': round,
  };

  factory WaiterLine.fromJson(Object? json) {
    final m = _map(json, 'line');
    return WaiterLine(
      key: _str(m['key']),
      name: WaiterName.fromJson(m['name']),
      quantity: _int(m['qty'], orElse: 1),
      totalMinor: _int(m['total_minor']),
      modifiers: [for (final x in _list(m['modifiers'])) WaiterName.fromJson(x)],
      note: _strOrNull(m['note']),
      stage: WaiterLineStage.parse(m['stage']),
      round: _intOrNull(m['round']),
    );
  }
}

class WaiterCheck {
  const WaiterCheck({
    required this.tableId,
    required this.tableLabel,
    required this.currency,
    required this.lines,
    this.version,
    this.subtotalMinor = 0,
    this.serviceMinor = 0,
    this.taxMinor = 0,
    this.discountMinor = 0,
    this.totalMinor = 0,
    this.roundsSent = 0,
    this.guests,
  });

  /// An empty check on a free table: what the handheld shows before the first
  /// item, and what it saves as the table's first version.
  const WaiterCheck.empty({
    required this.tableId,
    required this.tableLabel,
    required this.currency,
  }) : lines = const [],
       version = null,
       subtotalMinor = 0,
       serviceMinor = 0,
       taxMinor = 0,
       discountMinor = 0,
       totalMinor = 0,
       roundsSent = 0,
       guests = null;

  final int tableId;
  final String tableLabel;
  final WaiterCurrency currency;
  final List<WaiterLine> lines;

  /// The table's saved version, null while nothing is saved on it. Every edit
  /// names the version it was made against; the till refuses a stale one
  /// (XORD-044) and the handheld reloads.
  final int? version;

  final int subtotalMinor;
  final int serviceMinor;
  final int taxMinor;
  final int discountMinor;
  final int totalMinor;
  final int roundsSent;
  final int? guests;

  bool get hasDraft => lines.any((l) => l.isDraft);
  bool get isEmpty => lines.isEmpty;

  Map<String, Object?> toJson() => {
    'table_id': tableId,
    'table_label': tableLabel,
    'currency': currency.toJson(),
    if (version != null) 'version': version,
    'lines': [for (final l in lines) l.toJson()],
    'subtotal_minor': subtotalMinor,
    'service_minor': serviceMinor,
    'tax_minor': taxMinor,
    'discount_minor': discountMinor,
    'total_minor': totalMinor,
    'rounds_sent': roundsSent,
    if (guests != null) 'guests': guests,
  };

  factory WaiterCheck.fromJson(Object? json) {
    final m = _map(json, 'check');
    return WaiterCheck(
      tableId: _int(m['table_id']),
      tableLabel: _str(m['table_label']),
      currency: WaiterCurrency.fromJson(m['currency']),
      version: _intOrNull(m['version']),
      lines: [for (final x in _list(m['lines'])) WaiterLine.fromJson(x)],
      subtotalMinor: _int(m['subtotal_minor']),
      serviceMinor: _int(m['service_minor']),
      taxMinor: _int(m['tax_minor']),
      discountMinor: _int(m['discount_minor']),
      totalMinor: _int(m['total_minor']),
      roundsSent: _int(m['rounds_sent']),
      guests: _intOrNull(m['guests']),
    );
  }
}

// ---------------------------------------------------------------------------
// What the waiter did. The till applies these in order, all or none.

sealed class WaiterOp {
  const WaiterOp();

  Map<String, Object?> toJson();

  static WaiterOp fromJson(Object? json) {
    final m = _map(json, 'op');
    return switch (m['op']) {
      'add' => WaiterAdd(
        productId: _int(m['product_id']),
        modifierIds: [for (final x in _list(m['modifier_ids'])) if (x is int) x],
        quantity: _int(m['qty'], orElse: 1),
        note: _strOrNull(m['note']),
      ),
      'qty' => WaiterChangeQuantity(lineKey: _str(m['line']), delta: _int(m['delta'])),
      'remove' => WaiterRemoveLine(lineKey: _str(m['line'])),
      'note' => WaiterSetNote(lineKey: _str(m['line']), note: _str(m['note'])),
      'guests' => WaiterSetGuests(_int(m['guests'], orElse: 1)),
      'send' => const WaiterSendRound(),
      final other => throw WaiterWireError('unknown op $other'),
    };
  }
}

class WaiterAdd extends WaiterOp {
  const WaiterAdd({
    required this.productId,
    this.modifierIds = const [],
    this.quantity = 1,
    this.note,
  });
  final int productId;
  final List<int> modifierIds;
  final int quantity;
  final String? note;

  @override
  Map<String, Object?> toJson() => {
    'op': 'add',
    'product_id': productId,
    'modifier_ids': modifierIds,
    'qty': quantity,
    if (note != null) 'note': note,
  };
}

class WaiterChangeQuantity extends WaiterOp {
  const WaiterChangeQuantity({required this.lineKey, required this.delta});
  final String lineKey;
  final int delta;

  @override
  Map<String, Object?> toJson() => {'op': 'qty', 'line': lineKey, 'delta': delta};
}

/// Take an unsent line off. A sent line is the till's to void (WA1).
class WaiterRemoveLine extends WaiterOp {
  const WaiterRemoveLine({required this.lineKey});
  final String lineKey;

  @override
  Map<String, Object?> toJson() => {'op': 'remove', 'line': lineKey};
}

class WaiterSetNote extends WaiterOp {
  const WaiterSetNote({required this.lineKey, required this.note});
  final String lineKey;
  final String note;

  @override
  Map<String, Object?> toJson() => {'op': 'note', 'line': lineKey, 'note': note};
}

class WaiterSetGuests extends WaiterOp {
  const WaiterSetGuests(this.guests);
  final int guests;

  @override
  Map<String, Object?> toJson() => {'op': 'guests', 'guests': guests};
}

/// Send every unsent line to the kitchen as the next round.
class WaiterSendRound extends WaiterOp {
  const WaiterSendRound();

  @override
  Map<String, Object?> toJson() => {'op': 'send'};
}

// ---------------------------------------------------------------------------
// Why the till said no. One code per reason, so the handheld words it in its
// own language rather than showing the till's.

abstract final class WaiterError {
  /// No or unknown device token: sign in again, which registers the device.
  static const unpaired = 'UNPAIRED';

  /// This device was revoked on the till.
  static const revoked = 'DEVICE_REVOKED';

  /// No or expired waiter session: sign in again with the PIN.
  static const signInRequired = 'SIGN_IN_REQUIRED';

  static const wrongPin = 'PIN_WRONG';

  /// Too many wrong PINs or codes from this device; wait and try again.
  static const tooManyAttempts = 'TOO_MANY_ATTEMPTS';

  /// The person may not do this (a capability is missing).
  static const notPermitted = 'NOT_PERMITTED';

  /// The table changed on another device since this check was read
  /// (XORD-044). The body carries the current check.
  static const checkChanged = 'CHECK_CHANGED';

  /// The till's ticket rules refused the edit (out of stock, a required
  /// option missing, a sent line ...). The body's `reason` says which.
  static const refused = 'REFUSED';

  static const notFound = 'NOT_FOUND';
  static const badRequest = 'BAD_REQUEST';

  /// The till is not ready to serve tables (no database, no catalog yet).
  static const unavailable = 'TILL_UNAVAILABLE';

  /// Wire versions differ; one side must be updated.
  static const versionMismatch = 'VERSION_MISMATCH';

  /// Client-side only (WA4): the till's certificate has not been confirmed
  /// on this handheld yet; the failure carries it to compare.
  static const certificateUntrusted = 'CERTIFICATE_UNTRUSTED';

  /// Client-side only (WA4): the till answered with a certificate other than
  /// the confirmed one.
  static const certificateChanged = 'CERTIFICATE_CHANGED';
}
