import 'package:postgres/postgres.dart';

/// The shift this terminal has open **right now**, read inside the write that
/// needs it.
///
/// Sales, refunds and audit rows name the shift whose drawer the money went
/// into. That is a fact about the moment of the write, not about the moment the
/// repository was built: a till closes a shift and opens the next without
/// restarting, and a repository that remembered the first shift's id kept
/// stamping it (audit, 17 Oct 2026 — two cash sales, 4,520.00 EGP, landed on a
/// shift that had closed before they were rung up, and the open shift's Z
/// report left them out).
///
/// Asked on the caller's own transaction so the answer cannot change between
/// the lookup and the insert, and so a drawer closing mid-sale is seen as
/// closed. `pos_shifts_one_open_per_terminal` makes the answer at most one row.
///
/// Null is a real answer: no drawer is open. The write is still recorded — a
/// sale that cannot name its shift is still a sale — and it shows up as
/// unattributed rather than being credited to a drawer that was already
/// counted. Also null when [terminalId] is, which is what an islanded branch
/// server without a registered till writes.
Future<int?> openShiftIdFor(TxSession tx, String? terminalId) async {
  if (terminalId == null) return null;
  final rows = await tx.execute(
    Sql.named(
      'SELECT id FROM pos_shifts '
      'WHERE terminal_id::text = @terminal AND closed_at IS NULL',
    ),
    parameters: {'terminal': terminalId},
  );
  return rows.isEmpty ? null : rows.first[0] as int;
}
