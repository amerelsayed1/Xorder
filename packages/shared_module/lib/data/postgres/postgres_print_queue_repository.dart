import 'dart:typed_data';

import '../../core/config/deployment.dart';
import '../../domain/repositories/repositories.dart';
import 'postgres_orders_repository.dart' show PosWriteContext;
import '../sql/sql.dart';
import '../sql/row_reads.dart';

/// Receipts owed to paper, on the branch database.
///
/// **Why the branch database and not a file on the till.** The obvious place
/// for a print spool is local disk, and it was rejected: a receipt that failed
/// to print is evidence about a sale, and every other piece of evidence about
/// that sale is a row in PostgreSQL where the manager, the Z report and the
/// filing can all see it. A queue on disk is a queue nobody can look at from
/// anywhere else, and it disappears with the machine.
///
/// The till holds `SELECT, INSERT` and a column-scoped `UPDATE` — never on
/// `payload`. See `LocalBootstrap.tillGrants`.
class PostgresPrintQueueRepository implements PrintQueueRepository {
  const PostgresPrintQueueRepository({
    required SqlDatabase database,
    required this.config,
    required this.context,
  }) : _db = database;

  final SqlDatabase _db;
  final DeploymentConfig config;
  final PosWriteContext context;

  @override
  Future<int> enqueue({
    required String printerName,
    required List<int> bytes,
    required bool isReprint,
    int? orderId,
    String? invoiceNumber,
  }) async {
    final rows = await _db.query(
      config,
      'INSERT INTO pos_print_jobs (business_id, branch_id, terminal_id, '
      '  order_id, invoice_number, printer_name, kind, payload) '
      'VALUES (@business, @branch, @terminal, @order, @invoice, @printer, '
      '  @kind, @payload) RETURNING id',
      parameters: {
        'business': context.businessId,
        'branch': context.branchId,
        'terminal': context.terminalId,
        'order': orderId,
        'invoice': invoiceNumber,
        'printer': printerName,
        'kind': isReprint ? 'reprint' : 'receipt',
        // Uint8List, so the driver sends it as `bytea` rather than as a string
        // it would have to escape. A list of ints goes over as an int array and
        // comes back as one, which is a receipt that will not print.
        'payload': Uint8List.fromList(bytes),
      },
    );
    return rows.first[0]! as int;
  }

  /// This terminal's outstanding paper, oldest first.
  ///
  /// Scoped to the terminal, not the branch: the customer is standing at *this*
  /// counter, and a till catching up another till's receipts would hand a
  /// cashier paper for sales they never made.
  @override
  Future<List<QueuedPrintJob>> pending({int limit = 5}) async {
    final rows = await _db.query(
      config,
      'SELECT id, printer_name, payload, attempts, invoice_number '
      '  FROM pos_print_jobs '
      ' WHERE branch_id = @branch AND terminal_id = @terminal '
      "   AND status = 'pending' "
      ' ORDER BY id LIMIT @limit',
      parameters: {
        'branch': context.branchId,
        'terminal': context.terminalId,
        'limit': limit,
      },
    );

    return [
      for (final row in rows)
        QueuedPrintJob(
          id: row[0]! as int,
          printerName: row[1]! as String,
          bytes: row.bytes(2)!,
          attempts: row[3]! as int,
          invoiceNumber: row[4] as String?,
        ),
    ];
  }

  /// Marked printed the moment the socket accepted it.
  ///
  /// **The guard is `status = 'pending'` in the WHERE, not a read first.** Two
  /// drains racing — the same till relaunched, or a second window — would
  /// otherwise both see 'pending' and both print. The UPDATE that loses the
  /// race matches nothing, and the trigger in migration 34 refuses it outright
  /// if it somehow does.
  @override
  Future<void> markPrinted(int id) => _db.query(
    config,
    "UPDATE pos_print_jobs SET status = 'printed', printed_at = now(), "
    '  attempts = attempts + 1, last_attempt_at = now(), last_error = NULL '
    " WHERE id = @id AND status = 'pending'",
    parameters: {'id': id},
  );

  @override
  Future<void> markAttempted(int id, {String? error}) => _db.query(
    config,
    'UPDATE pos_print_jobs SET attempts = attempts + 1, '
    '  last_attempt_at = now(), last_error = @error '
    " WHERE id = @id AND status = 'pending'",
    parameters: {'id': id, 'error': error},
  );
}
