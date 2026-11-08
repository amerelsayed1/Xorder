import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/money/money.dart';
import '../../../core/money/quantity.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../domain/repositories/admin_repositories.dart';
import 'admin_messages.dart';

final _activityProvider = FutureProvider.autoDispose<List<AuditEntry>>(
  (ref) => ref.watch(auditRepositoryProvider).recent(),
);

/// The audit trail, as a manager reads it.
///
/// Read-only, and not because the screen was not finished: the ledger has no
/// edit and no delete anywhere in the stack. The interface has no method for
/// it, the till's database role is granted only INSERT and SELECT, and a
/// trigger refuses UPDATE, DELETE and TRUNCATE even from an admin connection.
/// A record somebody can quietly correct is not a record.
class ManagementActivityPane extends ConsumerWidget {
  const ManagementActivityPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(_activityProvider);

    return entries.when(
      loading: () => Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: context.pos.accent,
        ),
      ),
      error: (error, _) => _Centred(text: '$error'),
      data: (all) => all.isEmpty
          ? _Centred(text: context.strings.nothingRecordedYet)
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: PosSpace.sm),
              itemCount: all.length,
              itemBuilder: (context, index) => _EntryRow(entry: all[index]),
            ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});

  final AuditEntry entry;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: PosSpace.xl,
      vertical: PosSpace.md,
    ),
    decoration: BoxDecoration(
      border: Border(bottom: context.pos.hairline),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 150,
          child: Text(
            _stamp(entry.occurredAt),
            style: PosText.mono(size: 11.5, color: context.pos.muted),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The sentence, not the key. `AdminText.auditAction` falls back
              // to the stored string for a row written by a newer build —
              // deliberately, because an audit log that hides what it cannot
              // name is an audit log nobody can rely on.
              Text(
                AdminText.auditAction(context.strings, entry.action),
                style: PosText.ui(
                  color: context.pos.inkWarm,
                  size: 13,
                  weight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: PosSpace.xs),
              Text(
                entry.wasOverridden
                    ? context.strings.approvedByLine(
                        entry.actorName,
                        entry.approvedByName ?? '',
                      )
                    : entry.actorName,
                style: PosText.ui(size: 12.5, color: context.pos.body),
              ),
              if (entry.reason != null) ...[
                const SizedBox(height: PosSpace.xs),
                Text(
                  entry.reason!,
                  style: PosText.ui(
                    size: 12,
                    color: context.pos.muted,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
        SizedBox(
          width: 260,
          child: Text(
            _change(context.strings, entry),
            style: PosText.mono(
              size: 11.5,
              color: context.pos.muted,
              height: 1.5,
            ),
          ),
        ),
      ],
    ),
  );

  /// What actually changed, rather than the whole row.
  ///
  /// A ledger that prints both snapshots in full is a ledger nobody reads: the
  /// answer to "what did they change" is buried in nine fields that did not.
  static String _change(AppStrings s, AuditEntry entry) {
    final before = entry.before ?? const {};
    final after = entry.after ?? const {};
    final keys = {
      ...before.keys,
      ...after.keys,
    }.where((key) => '${before[key]}' != '${after[key]}').toList();

    if (keys.isEmpty) return entry.entityId == null ? '' : '#${entry.entityId}';
    return keys
        .map((key) {
          final label = _fieldName(key);
          final from = before[key];
          final to = after[key];
          if (from == null) return '$label: ${_value(s, key, to)}';
          if (to == null) return '$label: was ${_value(s, key, from)}';
          return '$label: ${_value(s, key, from)} → ${_value(s, key, to)}';
        })
        .join('\n');
  }

  /// The column name, as a phrase.
  ///
  /// **The suffix is a rule, not a list.** The schema is consistent about them —
  /// `_minor` is money in minor units, `_milli` is a quantity in thousandths,
  /// `_bp` is a rate in basis points — so the unit belongs to the *value* and
  /// repeating it in the name would read as "total minor: 1,000.00". A leading
  /// `is_` goes too, because "active: yes" is the sentence and "is active: yes"
  /// is not.
  ///
  /// Rules rather than a map, so a column added next year comes out right the
  /// first time and there is no list to fall out of date. The words themselves
  /// stay English: these are the business's own field names as the database
  /// records them, and inventing Arabic for a column nobody has translated
  /// would be inventing meaning rather than showing it.
  static String _fieldName(String key) {
    var name = key;
    for (final suffix in const ['_minor', '_milli', '_bp']) {
      if (name.endsWith(suffix)) {
        name = name.substring(0, name.length - suffix.length);
        break;
      }
    }
    if (name.startsWith('is_')) name = name.substring(3);
    return name.replaceAll('_', ' ');
  }

  /// The value, in the units the column is stored in.
  ///
  /// **`total_minor: 100000` was the bug.** A hundred thousand *piastres* is a
  /// thousand pounds, and the column printed the integer — on an audit trail,
  /// beside a supplier's name, where the whole question is how much money moved.
  ///
  /// Currency and exponent are left at their defaults, which is what every other
  /// price in the app does until §93 makes them configurable: the audit payload
  /// records the minor units and not the currency they were counted in.
  static String _value(AppStrings s, String key, Object? value) {
    if (value is bool) return value ? s.fieldYes : s.fieldNo;

    final number = value is int
        ? value
        : (value is String ? int.tryParse(value) : null);

    if (number != null) {
      if (key.endsWith('_minor')) return Money(number).format(withCurrency: true);
      if (key.endsWith('_milli')) return Quantity(number).format();
      if (key.endsWith('_bp')) return AdminText.rateBp(number);
    }

    return _short(value);
  }

  static String _short(Object? value) {
    final text = value is List ? value.join(', ') : '$value';
    return text.length <= 60 ? text : '${text.substring(0, 57)}…';
  }

  /// Western digits in both languages, as everywhere else in the till.
  static String _stamp(DateTime at) {
    final local = at.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

class _Centred extends StatelessWidget {
  const _Centred({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(PosSpace.s28),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: PosText.ui(size: 13, color: context.pos.muted, height: 1.6),
      ),
    ),
  );
}
