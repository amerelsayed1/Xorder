/// What the business has configured.
///
/// **The shape here is a deliberate answer to a named risk.** The gap-closure
/// plan warns that a settings table sprawls: *"a raw map read at forty call
/// sites is how a settings table becomes unmaintainable."* So the map is not
/// the public surface. [PosSettings] parses; the things that *use* settings are
/// value objects built from it — `RefundPolicy`, [DayPolicy], [CashPolicy] —
/// one per decision, each with the SRS's own defaults baked in.
///
/// Nothing outside this file should ever ask for a key by name.
library;

import '../../core/money/money.dart';

/// Which level a value was set at.
///
/// **These strings are data** — the `scope` column's CHECK constraint in
/// migration 14.
enum SettingScope {
  business('business'),
  branch('branch'),
  terminal('terminal');

  const SettingScope(this.wire);

  final String wire;

  /// Higher wins. A terminal's answer beats its branch's, which beats the
  /// business's — the till standing in front of somebody is the most specific
  /// statement anybody made about it.
  int get specificity => index;

  static SettingScope? fromWire(String value) {
    for (final scope in SettingScope.values) {
      if (scope.wire == value) return scope;
    }
    return null;
  }
}

/// One stored row, before resolution.
class PosSettingRow {
  const PosSettingRow({
    required this.scope,
    required this.scopeId,
    required this.key,
    required this.value,
  });

  final SettingScope scope;

  /// Empty for [SettingScope.business]; a branch id or terminal uuid
  /// otherwise. Empty rather than null because the database's uniqueness
  /// constraint depends on it — see migration 14.
  final String scopeId;

  final String key;
  final String value;
}

/// Every key this build knows, with the SRS's default beside it.
///
/// One place, so "what happens when nobody has configured this" has one answer
/// rather than an answer per call site.
abstract final class SettingKey {
  // §92 — the trading day.
  static const dayStartTime = 'day.start_time';

  // §18 — refunds.
  static const refundEnabled = 'refund.enabled';
  static const refundWindow = 'refund.window';
  static const refundMaxValue = 'refund.max_value_minor';
  static const refundApprovalThreshold = 'refund.approval_threshold_minor';
  static const refundReceiptRequired = 'refund.receipt_required';
  static const refundReasonRequired = 'refund.reason_required';

  // §22–§25 — the drawer.
  static const cashBlindClose = 'cash.blind_close';
  static const cashDrawerOpenReason = 'cash.drawer_open_requires_reason';
  static const cashPayOutMax = 'cash.pay_out_max_minor';

  // Backups. Business-scoped rather than terminal-scoped on purpose: there
  // is one database per branch, and two tills disagreeing about where its
  // copies go is two half-filled folders and no complete history in either.
  static const backupDirectory = 'backup.directory';
  static const backupOnDayClose = 'backup.on_day_close';
}

/// Resolved settings for one terminal.
class PosSettings {
  const PosSettings(this._values);

  /// Everything unset. What a till runs on before anybody configures anything,
  /// and what a terminal with no database answers with.
  static const empty = PosSettings({});

  final Map<String, String> _values;

  /// Resolve rows into one map, most specific wins.
  ///
  /// Ties cannot happen — the database's uniqueness constraint is per
  /// (business, scope, scope_id, key) — but rows for *another* branch or
  /// another terminal can arrive in the same read, which is why both ids are
  /// checked rather than assumed filtered.
  factory PosSettings.resolve(
    Iterable<PosSettingRow> rows, {
    required String branchId,
    required String terminalId,
  }) {
    final winners = <String, PosSettingRow>{};

    for (final row in rows) {
      final applies = switch (row.scope) {
        SettingScope.business => true,
        SettingScope.branch => row.scopeId == branchId,
        SettingScope.terminal => row.scopeId == terminalId,
      };
      if (!applies) continue;

      final held = winners[row.key];
      if (held == null || row.scope.specificity > held.scope.specificity) {
        winners[row.key] = row;
      }
    }

    return PosSettings({
      for (final entry in winners.entries) entry.key: entry.value.value,
    });
  }

  bool has(String key) => _values.containsKey(key);

  /// The stored text, or null. Trimmed, and an empty string reads as unset —
  /// a settings row somebody blanked means "no answer", not "the empty answer".
  String? text(String key) {
    final raw = _values[key]?.trim();
    return (raw == null || raw.isEmpty) ? null : raw;
  }

  /// `true` and `false`, case-insensitively, plus `1`/`0`.
  ///
  /// Anything else falls back to [orElse] rather than guessing. A misconfigured
  /// blind-close flag that silently read as `true` would hide a figure nobody
  /// meant to hide.
  bool boolean(String key, {required bool orElse}) => switch (text(
    key,
  )?.toLowerCase()) {
    'true' || '1' || 'yes' => true,
    'false' || '0' || 'no' => false,
    _ => orElse,
  };

  /// Minor units. Null when unset **or unparseable** — a ceiling nobody can
  /// read is safer as no ceiling than as a number somebody guessed.
  Money? money(String key, {String currency = 'EGP', int exponent = 2}) {
    final raw = text(key);
    if (raw == null) return null;
    final minor = int.tryParse(raw);
    if (minor == null || minor < 0) return null;
    return Money(minor, currency: currency, exponent: exponent);
  }

  /// `HH:mm`, as minutes past midnight. Null when unset or unreadable.
  int? minutesPastMidnight(String key) {
    final raw = text(key);
    if (raw == null) return null;

    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(raw);
    if (match == null) return null;

    final hours = int.parse(match.group(1)!);
    final minutes = int.parse(match.group(2)!);
    if (hours > 23 || minutes > 59) return null;
    return hours * 60 + minutes;
  }
}

/// When one trading day ends and the next begins (§92).
class DayPolicy {
  const DayPolicy({this.startMinutes = 6 * 60});

  /// Six in the morning, per the SRS.
  ///
  /// Not midnight: a business that closes at 2 a.m. takes money on Saturday
  /// that belongs to Friday's takings, and a calendar day would split one
  /// evening's trading across two reports.
  static const defaults = DayPolicy();

  factory DayPolicy.from(PosSettings settings) => DayPolicy(
    startMinutes:
        settings.minutesPastMidnight(SettingKey.dayStartTime) ?? 6 * 60,
  );

  /// Minutes past local midnight at which the business day rolls over.
  final int startMinutes;

  /// The business date [at] belongs to.
  ///
  /// Local, and deliberately a `DateTime` at midnight rather than a formatted
  /// string: `pos_business_days.business_date` is a `date`, and the conversion
  /// belongs in one place.
  DateTime dateFor(DateTime at) {
    final minutes = at.hour * 60 + at.minute;
    // Before the roll-over, the takings still belong to yesterday.
    final day = minutes < startMinutes
        ? at.subtract(const Duration(days: 1))
        : at;
    return DateTime(day.year, day.month, day.day);
  }

  String get label {
    final hours = (startMinutes ~/ 60).toString().padLeft(2, '0');
    final minutes = (startMinutes % 60).toString().padLeft(2, '0');
    return '$hours:$minutes';
  }
}

/// How the drawer behaves (§22–§25).
class CashPolicy {
  const CashPolicy({
    this.blindClose = false,
    this.drawerOpenNeedsReason = true,
    this.payOutCeiling,
  });

  /// Blind close **off** by default.
  ///
  /// The safe default is the one that surprises nobody: a business that has
  /// not asked for blind counting gets the figure it has always seen. Turning
  /// it on is a decision somebody makes, and §25 makes it a setting precisely
  /// so it can be made.
  static const defaults = CashPolicy();

  factory CashPolicy.from(PosSettings settings) => CashPolicy(
    blindClose: settings.boolean(SettingKey.cashBlindClose, orElse: false),
    drawerOpenNeedsReason: settings.boolean(
      SettingKey.cashDrawerOpenReason,
      orElse: true,
    ),
    payOutCeiling: settings.money(SettingKey.cashPayOutMax),
  );

  /// Hide the expected figure and the live variance while counting.
  final bool blindClose;

  /// Opening the drawer without a sale asks why. On by default: §23 exists
  /// because an unexplained drawer opening is the one thing a till can notice.
  final bool drawerOpenNeedsReason;

  /// The most one pay-out may be. Null means no ceiling.
  final Money? payOutCeiling;

  bool permitsPayOut(Money amount) {
    final ceiling = payOutCeiling;
    return ceiling == null || amount.minor <= ceiling.minor;
  }
}
