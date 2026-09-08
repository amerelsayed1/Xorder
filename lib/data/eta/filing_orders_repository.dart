// The collaborators are private fields with public parameter names: the
// names belong to the call site, the fields do not belong to the API.
// ignore_for_file: prefer_initializing_formals
import '../../domain/models/receipt_profile.dart';
import '../../domain/models/ticket.dart';
import '../../domain/repositories/repositories.dart';
import '../../domain/services/eta_filing.dart';
import '../../domain/services/eta_receipt.dart';

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
    required ReceiptProfile Function() profile,
    required EtaQueueRepository queue,
    required String deviceSerial,
    this.onProblem,
  }) : _profile = profile,
       _queue = queue,
       _deviceSerial = deviceSerial;

  final OrdersRepository _inner;

  /// Read at settlement rather than held, so a profile completed in Management
  /// five minutes ago is the one this sale is filed under.
  final ReceiptProfile Function() _profile;

  final EtaQueueRepository _queue;
  final String _deviceSerial;

  /// Told when a sale could not be queued, so somebody can be shown it.
  /// Silence here is how a queue stops being read.
  final void Function(EtaFilingSkipped)? onProblem;

  @override
  Future<SubmitOrderResult> submit(Ticket ticket, {PosStaff? servedBy}) async {
    final result = await _inner.submit(ticket, servedBy: servedBy);
    await _file(ticket, result);
    return result;
  }

  Future<void> _file(Ticket ticket, SubmitOrderResult result) async {
    final orderId = result.serverId;
    // No row, nothing to file against. A replayed submission returns the
    // existing order's id, which is right: the uuid is a fingerprint, so
    // enqueuing the same document twice is refused by the unique index rather
    // than producing a second receipt.
    if (orderId == null) return;

    final profile = _profile();
    final input = EtaFiling.inputFor(
      ticket: ticket,
      profile: profile,
      receiptNumber: result.invoiceNumber ?? ticket.id,
      deviceSerial: _deviceSerial,
      issuedAt: DateTime.now(),
    );

    if (input == null) {
      // A blank profile is a restaurant that is not filing — one outside
      // Egypt, or one still in setup — and reporting a problem for every sale
      // it makes would be an alarm that is always on, which is an alarm nobody
      // reads. A *partly* filled one is different: somebody has typed a
      // registration number, so they intend to file and should be told they
      // cannot yet.
      if (!profile.isBlank) {
        onProblem?.call(ProfileIncomplete(profile.filingProblems));
      }
      return;
    }

    try {
      await _queue.enqueue(
        orderId: orderId,
        deviceSerial: _deviceSerial,
        receiptNumber: input.receiptNumber,
        receiptType: EtaReceiptType.sale,
        issuedAt: input.issuedAt,
        // Built inside the queue's lock, against the chain head this receipt
        // is actually written after — see [EtaQueueRepository.enqueue].
        build: (previousUuid) =>
            EtaReceiptBuilder.build(input.chainedTo(previousUuid)),
      );
    } on Object catch (error) {
      // Swallowed on purpose. See the class comment: the sale is already
      // recorded and the reconciler will find this order without a receipt.
      onProblem?.call(FilingFailed('$error'));
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
