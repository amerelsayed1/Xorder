// The collaborators are private fields with public parameter names: the
// names belong to the call site, the fields do not belong to the API.
// ignore_for_file: prefer_initializing_formals
import '../../domain/models/ticket.dart';
import '../../domain/repositories/repositories.dart';
import '../../domain/services/eta_filing.dart';

/// Queues an e-receipt for every sale that reaches the database.
///
/// **A decorator rather than a step inside the order's transaction.** The
/// tempting design writes the order and queues its receipt atomically, so one
/// cannot exist without the other. It is the wrong one, and only shows why
/// later: a restaurant that starts filing after six weeks of trading, or one
/// whose receipt profile was still half-typed on Tuesday, has orders that need
/// queueing and no transaction left to put them in. An order with no row in
/// `pos_eta_receipts` is a *query*, and the same reconciler then covers a crash
/// between the two writes, a profile completed late, and a restaurant that
/// turned this on after the fact. Coupling would have covered the first only.
///
/// **A failure here never fails the sale.** The customer is standing at the
/// counter and the money is already in the drawer; an exception thrown on the
/// way to the tax authority would lose a settled order to protect a filing
/// that can be caught up on for the next twenty-four hours.
class FilingOrdersRepository implements OrdersRepository {
  const FilingOrdersRepository(
    this._inner, {
    required EtaFilingPort filer,
    this.onProblem,
  }) : _filer = filer;

  final OrdersRepository _inner;

  /// Reads the sale back from the rows it was written to and files THAT — the
  /// same path the reconciler takes, so a sale filed now and one caught up
  /// next week are the same document.
  final EtaFilingPort _filer;

  /// Told when a sale could not be queued, so somebody can be shown it.
  /// Silence here is how a queue stops being read.
  final void Function(EtaFilingSkipped)? onProblem;

  @override
  Future<SubmitOrderResult> submit(Ticket ticket, {PosStaff? servedBy}) async {
    final result = await _inner.submit(ticket, servedBy: servedBy);
    await _file(result);
    return result;
  }

  Future<void> _file(SubmitOrderResult result) async {
    // No row, nothing to file against. A replayed submission returns the
    // existing order's id, and the filer finds its receipt already there.
    final orderId = result.serverId;
    if (orderId == null) return;

    try {
      report(await _filer.fileOrder(orderId), onProblem);
    } on Object catch (error) {
      // Swallowed on purpose. See the class comment: the sale is already
      // recorded and the reconciler will find this order without a receipt.
      onProblem?.call(FilingFailed('$error'));
    }
  }

  /// Only what a person can act on. A blank profile is a restaurant that is
  /// not filing, and a refund waiting for its sale is the system working.
  static void report(
    EtaFilingSkipped? skipped,
    void Function(EtaFilingSkipped)? onProblem,
  ) {
    if (skipped is ProfileIncomplete || skipped is FilingFailed) {
      onProblem?.call(skipped!);
    }
  }

  @override
  Future<int> pendingSyncCount() => _inner.pendingSyncCount();

  /// Not filed. A void is not a refund: it removes an order that was never
  /// completed, and there is no receipt to undo. A voided order that had
  /// already been filed is a **refund receipt**, which is its own document
  /// with its own uuid, and belongs to the refund path rather than here.
  @override
  Future<SubmitOrderResult> voidOrder(
    Ticket ticket, {
    required PosStaff by,
    int? reasonId,
    String? note,
    PosStaff? approvedBy,
    PosStaff? servedBy,
  }) => _inner.voidOrder(
    ticket,
    by: by,
    reasonId: reasonId,
    note: note,
    approvedBy: approvedBy,
    servedBy: servedBy,
  );
}
