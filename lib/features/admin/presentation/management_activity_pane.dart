import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
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
            _change(entry),
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
  static String _change(AuditEntry entry) {
    final before = entry.before ?? const {};
    final after = entry.after ?? const {};
    final keys = {
      ...before.keys,
      ...after.keys,
    }.where((key) => '${before[key]}' != '${after[key]}').toList();

    if (keys.isEmpty) return entry.entityId == null ? '' : '#${entry.entityId}';
    return keys
        .map((key) {
          final from = before[key];
          final to = after[key];
          if (from == null) return '$key: ${_short(to)}';
          if (to == null) return '$key: was ${_short(from)}';
          return '$key: ${_short(from)} → ${_short(to)}';
        })
        .join('\n');
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
