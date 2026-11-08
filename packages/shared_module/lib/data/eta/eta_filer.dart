// The collaborators are private fields with public parameter names: the
// names belong to the call site, the fields do not belong to the API.
// ignore_for_file: prefer_initializing_formals

import '../../core/config/deployment.dart';
import '../../core/money/money.dart';
import '../../domain/models/receipt_profile.dart';
import '../../domain/models/tax.dart';
import '../../domain/repositories/repositories.dart';
import '../../domain/services/eta_filing.dart';
import '../../domain/services/eta_receipt.dart';
import '../postgres/pos_database.dart';
import '../sql/sql.dart';
import '../sql/row_reads.dart';

/// What one pass of [EtaFiler.reconcile] did.
class EtaReconcileReport {
  const EtaReconcileReport({
    this.salesFiled = 0,
    this.refundsFiled = 0,
    this.refundsWaiting = 0,
    this.problem,
  });

  final int salesFiled;
  final int refundsFiled;

  /// Refunds whose sale has no receipt yet. Not a problem — they are filed on
  /// the pass after their sale is.
  final int refundsWaiting;

  /// Why filing stopped, when something a person can fix stopped it: a
  /// half-typed profile, or the queue refusing a write. Null when all is well
  /// — including on a business that has not set filing up at all.
  final EtaFilingSkipped? problem;
}

/// Files receipts from what the database recorded.
///
/// **From the rows, never from the ticket.** A sale filed the second it
/// settles and one caught up a week later have to be the same document, and
/// the only way to be sure is to build both from the same place — the rows the
/// sale was written to, which is also what an audit will compare the filing
/// against. The ticket in memory at settlement is the till's idea of the sale;
/// the rows are the sale.
///
/// **Each till files its own.** ETA's chain is per device, and a receipt says
/// which device issued it. A till catching up another till's sales would file
/// them as its own, so every query here is scoped to [terminalId].
class EtaFiler implements EtaFilingPort {
  EtaFiler({
    required SqlDatabase database,
    required this.config,
    required this.branchId,
    required this.terminalId,
    required EtaQueueRepository queue,
    required Future<ReceiptProfile> Function() profile,
  }) : _db = database,
       _queue = queue,
       _profile = profile;

  final SqlDatabase _db;
  final DeploymentConfig config;
  final int branchId;

  /// This till. Also its device serial on the chain, until the serial
  /// registered with the authority exists — see `ordersRepositoryProvider`.
  final String terminalId;

  final EtaQueueRepository _queue;

  /// Read on every call, so a profile completed in Management a minute ago is
  /// the one the next receipt is filed under.
  final Future<ReceiptProfile> Function() _profile;

  /// The statuses that mean money changed hands and stayed changed. A refund
  /// later does not un-sell the sale: it is its own receipt.
  static const _settled = "('PAID', 'CLOSED', 'PARTIALLY_REFUNDED', 'REFUNDED')";

  /// "This sale already has a receipt", as a clause. Cancelled rows do not
  /// count: a receipt cancelled for a reason is one to be replaced.
  static const _saleFiled =
      'EXISTS (SELECT 1 FROM pos_eta_receipts r WHERE r.order_id = o.id '
      "AND r.refund_id IS NULL AND r.status <> 'cancelled')";

  static const _refundFiled =
      'EXISTS (SELECT 1 FROM pos_eta_receipts r WHERE r.refund_id = f.id '
      "AND r.status <> 'cancelled')";

  @override
  Future<EtaFilingSkipped?> fileOrder(int orderId) async {
    final profile = await _profile();
    return _blocked(profile) ?? (await _fileOrder(orderId, profile)).$2;
  }

  @override
  Future<EtaFilingSkipped?> fileRefund(int refundId) async {
    final profile = await _profile();
    return _blocked(profile) ?? (await _fileRefund(refundId, profile)).$2;
  }

  /// File everything this till owes, oldest first: sales, then refunds.
  ///
  /// **Stops at the first failure** rather than skipping past it. Receipts go
  /// on the chain in the order they are queued; carrying on past a sale that
  /// would not queue would put Wednesday's receipts ahead of Tuesday's. The
  /// next pass starts again from the oldest.
  ///
  /// Idempotent: a sale already filed is not selected, and one filed by the
  /// settlement between the select and the write is refused by
  /// `pos_eta_receipts_one_per_sale` and counted as nothing to do.
  Future<EtaReconcileReport> reconcile({int limit = 200}) async {
    final profile = await _profile();
    final blocked = _blocked(profile);
    if (blocked != null) {
      // Blank is a business that is not filing: quiet. Half-typed is one
      // that means to and cannot yet: said out loud, every pass.
      return EtaReconcileReport(
        problem: blocked is ProfileIncomplete ? blocked : null,
      );
    }

    var sales = 0;
    for (final id in await _ids('''
      SELECT o.id FROM pos_orders o
       WHERE o.branch_id = @branch AND o.terminal_id = @terminal::uuid
         AND o.status IN $_settled AND NOT $_saleFiled
       ORDER BY o.occurred_at, o.id LIMIT @limit
      ''', limit)) {
      final (filed, skipped) = await _fileOrder(id, profile);
      if (skipped is FilingFailed) {
        return EtaReconcileReport(salesFiled: sales, problem: skipped);
      }
      if (filed) sales++;
    }

    var refunds = 0;
    var waiting = 0;
    for (final id in await _ids('''
      SELECT f.id FROM pos_refunds f
       WHERE f.branch_id = @branch AND f.terminal_id = @terminal::uuid
         AND NOT $_refundFiled
       ORDER BY f.occurred_at, f.id LIMIT @limit
      ''', limit)) {
      final (filed, skipped) = await _fileRefund(id, profile);
      if (skipped is FilingFailed) {
        return EtaReconcileReport(
          salesFiled: sales,
          refundsFiled: refunds,
          refundsWaiting: waiting,
          problem: skipped,
        );
      }
      if (skipped is RefundAwaitingSale) waiting++;
      if (filed) refunds++;
    }

    return EtaReconcileReport(
      salesFiled: sales,
      refundsFiled: refunds,
      refundsWaiting: waiting,
    );
  }

  static EtaFilingSkipped? _blocked(ReceiptProfile profile) {
    if (profile.canFile) return null;
    return profile.isBlank
        ? const FilingNotInUse()
        : ProfileIncomplete(profile.filingProblems);
  }

  Future<List<int>> _ids(String sql, int limit) async {
    final rows = await _db.query(
      config,
      sql,
      parameters: {'branch': branchId, 'terminal': terminalId, 'limit': limit},
    );
    return [for (final row in rows) row[0]! as int];
  }

  /// (whether a receipt was queued, why not when it was not)
  Future<(bool, EtaFilingSkipped?)> _fileOrder(
    int orderId,
    ReceiptProfile profile,
  ) async {
    final header = await _db.query(
      config,
      'SELECT o.invoice_number, o.occurred_at, o.currency, o.exponent, '
      '  o.subtotal_minor, o.discount_minor, o.total_minor '
      'FROM pos_orders o '
      'WHERE o.id = @id AND o.status IN $_settled AND NOT $_saleFiled',
      parameters: {'id': orderId},
    );
    // Not settled, not there, or already filed: nothing owed.
    if (header.isEmpty) return (false, null);

    final row = header.first;
    final currency = row[2]! as String;
    final exponent = row[3]! as int;
    Money money(Object? minor) =>
        Money(minor as int? ?? 0, currency: currency, exponent: exponent);

    final sale = FilingSale(
      receiptNumber: row[0]! as String,
      issuedAt: (row.dateTime(1)).toUtc(),
      currency: currency,
      subtotal: money(row[4]),
      discount: money(row[5]),
      total: money(row[6]),
      lines: await _saleLines(orderId, money),
      taxLines: await _taxes(orderId, money),
      cashTenders: await _cash(
        'SELECT counts_as_cash FROM pos_order_payments '
        'WHERE order_id = @id ORDER BY id',
        orderId,
      ),
    );

    return _enqueue(
      orderId: orderId,
      input: EtaFiling.inputFrom(
        sale,
        profile: profile,
        deviceSerial: terminalId,
      )!,
    );
  }

  /// A refund receipt: the lines that went back, the tax that went back with
  /// them, and the sale it undoes by uuid.
  Future<(bool, EtaFilingSkipped?)> _fileRefund(
    int refundId,
    ReceiptProfile profile,
  ) async {
    final header = await _db.query(
      config,
      '''
      SELECT f.order_id, f.occurred_at, f.subtotal_minor, f.discount_minor,
             f.vat_minor, f.total_minor, o.invoice_number, o.currency,
             o.exponent, o.subtotal_minor, o.vat_minor,
             (SELECT r.uuid FROM pos_eta_receipts r
               WHERE r.order_id = f.order_id AND r.refund_id IS NULL
                 AND r.status <> 'cancelled'
               ORDER BY r.id LIMIT 1)
        FROM pos_refunds f JOIN pos_orders o ON o.id = f.order_id
       WHERE f.id = @id AND NOT $_refundFiled
      ''',
      parameters: {'id': refundId},
    );
    if (header.isEmpty) return (false, null);

    final row = header.first;
    // The sale has no receipt: a refund pointing at nothing is the dangling
    // reference the authority rejects. It waits for its sale.
    final saleUuid = row[11] as String?;
    if (saleUuid == null) return (false, const RefundAwaitingSale());

    final orderId = row[0]! as int;
    final currency = row[7]! as String;
    final exponent = row[8]! as int;
    Money money(Object? minor) =>
        Money(minor as int? ?? 0, currency: currency, exponent: exponent);

    final refundSubtotal = money(row[2]);
    final refundVat = money(row[4]);

    var lines = await _lines(
      '''
      SELECT rl.name_snapshot, rl.quantity, rl.unit_price_minor,
             rl.line_total_minor, p.sku
        FROM pos_refund_lines rl
        LEFT JOIN pos_order_lines l ON l.id = rl.order_line_id
        LEFT JOIN pos_products p ON p.id = l.menu_item_id
       WHERE rl.refund_id = @id ORDER BY rl.id
      ''',
      refundId,
      money,
    );
    // A full refund names no lines: everything that was charged went back.
    if (lines.isEmpty) lines = await _saleLines(orderId, money);

    final refund = FilingSale(
      receiptNumber: '${row[6]! as String}-R$refundId',
      issuedAt: (row.dateTime(1)).toUtc(),
      currency: currency,
      subtotal: refundSubtotal,
      discount: money(row[3]),
      total: money(row[5]),
      lines: lines,
      taxLines: _scaled(
        await _taxes(orderId, money),
        saleSubtotal: money(row[9]),
        saleVat: money(row[10]),
        refundSubtotal: refundSubtotal,
        refundVat: refundVat,
      ),
      cashTenders: await _cash(
        'SELECT counts_as_cash FROM pos_refund_payments '
        'WHERE refund_id = @id ORDER BY id',
        refundId,
      ),
    );

    return _enqueue(
      orderId: orderId,
      refundId: refundId,
      input: EtaFiling.inputFrom(
        refund,
        profile: profile,
        deviceSerial: terminalId,
        referenceOldUuid: saleUuid,
      )!,
    );
  }

  /// The sale's tax, in the proportion the refund gave back.
  ///
  /// Scaled from the sale's own per-rate figures so the refund's tax is what
  /// the refund row says went back — to the piastre, the last rate taking the
  /// remainder — rather than a recomputation that could disagree with it.
  static List<TaxLine> _scaled(
    List<TaxLine> sale, {
    required Money saleSubtotal,
    required Money saleVat,
    required Money refundSubtotal,
    required Money refundVat,
  }) {
    if (sale.isEmpty) return const [];
    // The Finance tab's taxes split refunds by the same function, so what a
    // credit note files and what the tax report shows cannot drift apart.
    final shares = TaxEngine.refundShares(
      saleAmounts: [for (final line in sale) line.amount.minor],
      saleVat: saleVat.minor,
      refundVat: refundVat.minor,
    );
    return [
      for (var i = 0; i < sale.length; i++)
        () {
          final line = sale[i];
          final amount = shares[i];
          return TaxLine(
            name: line.name,
            rateBp: line.rateBp,
            base: Money(
              saleSubtotal.minor == 0
                  ? 0
                  : line.base.minor * refundSubtotal.minor ~/
                        saleSubtotal.minor,
              currency: line.base.currency,
              exponent: line.base.exponent,
            ),
            amount: Money(
              amount,
              currency: line.amount.currency,
              exponent: line.amount.exponent,
            ),
            taxGroupId: line.taxGroupId,
            etaTaxType: line.etaTaxType,
            etaSubType: line.etaSubType,
          );
        }(),
    ];
  }

  Future<List<FilingLine>> _saleLines(
    int orderId,
    Money Function(Object?) money,
  ) => _lines(
    '''
    SELECT l.name_snapshot, l.quantity, l.unit_price_minor, l.line_total_minor,
           p.sku
      FROM pos_order_lines l
      LEFT JOIN pos_products p ON p.id = l.menu_item_id
     -- A voided line is on the slip and off the filing: nobody was charged.
     WHERE l.order_id = @id AND l.voided_at IS NULL
     ORDER BY l.id
    ''',
    orderId,
    money,
  );

  Future<List<FilingLine>> _lines(
    String sql,
    int id,
    Money Function(Object?) money,
  ) async {
    final rows = await _db.query(config, sql, parameters: {'id': id});
    return [
      for (final row in rows)
        FilingLine(
          description: row[0]! as String,
          quantity: row[1]! as int,
          unitPrice: money(row[2]),
          lineTotal: money(row[3]),
          sku: row[4] as String?,
        ),
    ];
  }

  Future<List<TaxLine>> _taxes(
    int orderId,
    Money Function(Object?) money,
  ) async {
    final rows = await _db.query(
      config,
      'SELECT name_snapshot, rate_bp, base_minor, amount_minor, tax_group_id '
      'FROM pos_order_taxes WHERE order_id = @id ORDER BY id',
      parameters: {'id': orderId},
    );
    return [
      for (final row in rows)
        TaxLine(
          name: row[0]! as String,
          rateBp: row[1]! as int,
          base: money(row[2]),
          amount: money(row[3]),
          taxGroupId: row[4] as int?,
        ),
    ];
  }

  Future<List<bool>> _cash(String sql, int id) async {
    final rows = await _db.query(config, sql, parameters: {'id': id});
    return [for (final row in rows) row.booleanOrNull(0) ?? false];
  }

  Future<(bool, EtaFilingSkipped?)> _enqueue({
    required int orderId,
    required EtaReceiptInput input,
    int? refundId,
  }) async {
    try {
      await _queue.enqueue(
        orderId: orderId,
        refundId: refundId,
        deviceSerial: terminalId,
        receiptNumber: input.receiptNumber,
        receiptType: input.receiptType,
        issuedAt: input.issuedAt,
        // Built inside the queue's lock, against the chain head this receipt
        // is actually written after.
        build: (previousUuid) =>
            EtaReceiptBuilder.build(input.chainedTo(previousUuid)),
      );
      return (true, null);
    } on Object catch (error) {
      // Filed by somebody else between the select and the write — the
      // settlement racing a reconcile pass. Not a failure: it is filed.
      if (_alreadyFiled(error)) return (false, null);
      return (false, FilingFailed('$error'));
    }
  }

  static bool _alreadyFiled(Object error) =>
      error is PosDbException && error.sqlState == '23505';
}

/// Runs [EtaFiler.reconcile] on a schedule, one pass at a time.
///
/// A timer firing while the previous pass is still going — a slow disk, a
/// long backlog on the first day filing is switched on — would run two passes
/// over the same unfiled sales. The index would keep the second from filing
/// anything twice, but it would still spend a queue lock per sale finding
/// that out, so the second one simply does not start.
class EtaReconciler {
  EtaReconciler(this._filer, {this.onReport});

  final EtaFiler _filer;

  /// Told after every pass, including one that threw — so the screens can say
  /// what filing is doing rather than what it did the last time it worked.
  final void Function(EtaReconcileReport)? onReport;

  bool _running = false;

  /// Null when a pass was already running.
  Future<EtaReconcileReport?> run() async {
    if (_running) return null;
    _running = true;
    try {
      final report = await _filer.reconcile();
      onReport?.call(report);
      return report;
    } on Object catch (error) {
      final report = EtaReconcileReport(problem: FilingFailed('$error'));
      onReport?.call(report);
      return report;
    } finally {
      _running = false;
    }
  }
}
