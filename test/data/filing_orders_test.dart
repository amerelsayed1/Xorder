import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/data/eta/filing_orders_repository.dart';
import 'package:xorder_pos/domain/models/catalog.dart';
import 'package:xorder_pos/domain/models/eta_submission.dart';
import 'package:xorder_pos/domain/models/receipt_profile.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/domain/repositories/repositories.dart';
import 'package:xorder_pos/domain/services/eta_filing.dart';
import 'package:xorder_pos/domain/services/eta_serialization.dart';

/// Queuing an e-receipt for every sale that reaches the database.
///
/// The rule this exists to hold is that **a filing failure never fails a
/// sale**. The customer is at the counter and the money is in the drawer; an
/// exception thrown on the way to the tax authority would lose a settled order
/// to protect a filing that has twenty-four hours to catch up.
void main() {
  const profile = ReceiptProfile(
    branchId: 1,
    tradeName: 'Koshari Abou Tarek',
    registrationNumber: '123456789',
    activityCode: '5610',
    branchCode: 'B1',
    address: BranchAddress(
      governate: 'Cairo',
      regionCity: 'Downtown',
      street: 'Champollion',
      buildingNumber: '16',
    ),
  );

  const koshari = Product(
    id: 1,
    categoryId: 1,
    nameEn: 'Koshari',
    price: Money(4500),
  );

  Ticket ticket() => Ticket(
    id: 'txn-1',
    orderType: OrderType.takeaway,
    taxConfig: const TaxConfig(serviceBp: 0, vatBp: 1400),
    lines: [TicketLine(product: koshari, quantity: 1)],
  );

  ({
    _Orders orders,
    _Queue queue,
    List<EtaFilingSkipped> problems,
    FilingOrdersRepository filing,
  })
  build({
    ReceiptProfile with_ = profile,
    SubmitOrderResult? result,
    bool queueThrows = false,
  }) {
    final orders = _Orders(result);
    final queue = _Queue(throws: queueThrows);
    final problems = <EtaFilingSkipped>[];
    return (
      orders: orders,
      queue: queue,
      problems: problems,
      filing: FilingOrdersRepository(
        orders,
        queue: queue,
        profile: () => with_,
        deviceSerial: 'TILL-1',
        onProblem: problems.add,
      ),
    );
  }

  test('a settled sale is queued', () async {
    final world = build();
    await world.filing.submit(ticket());

    expect(world.queue.enqueued, hasLength(1));
    expect(world.queue.enqueued.single.receiptNumber, 'INV-0001');
    expect(world.queue.enqueued.single.orderId, 42);
  });

  test('the sale is written first, and its result is returned unchanged',
      () async {
    final world = build();
    final result = await world.filing.submit(ticket());

    expect(world.orders.submitted, hasLength(1));
    expect(result.serverId, 42);
    expect(result.invoiceNumber, 'INV-0001');
  });

  test('a queue that throws does not lose the sale', () async {
    // The whole point. The money is already in the drawer.
    final world = build(queueThrows: true);
    final result = await world.filing.submit(ticket());

    expect(result.serverId, 42);
    expect(world.problems.single, isA<FilingFailed>());
  });

  test('a blank profile files nothing, quietly', () async {
    // A restaurant outside Egypt, or one still in setup. Reporting a problem
    // for every sale it makes would be an alarm that is always on.
    final world = build(with_: const ReceiptProfile(branchId: 1));
    await world.filing.submit(ticket());

    expect(world.queue.enqueued, isEmpty);
    expect(world.problems, isEmpty);
  });

  test('a half-typed profile is reported, not swallowed', () async {
    // Different from blank: somebody has typed a name, so they intend to file
    // and should be told they cannot yet. Silence here is how a queue stops
    // being read.
    const half = ReceiptProfile(branchId: 1, tradeName: 'Koshari');
    final world = build(with_: half);
    await world.filing.submit(ticket());

    expect(world.queue.enqueued, isEmpty);
    final problem = world.problems.single;
    expect(problem, isA<ProfileIncomplete>());
    expect(
      (problem as ProfileIncomplete).problems.map((p) => p.field),
      contains(ProfileField.registrationNumber),
    );
  });

  test('an order that did not reach the database is not queued', () async {
    // No row, nothing to file against.
    final world = build(
      result: const SubmitOrderResult(
        clientTransactionId: 'txn-1',
        queued: true,
      ),
    );
    await world.filing.submit(ticket());
    expect(world.queue.enqueued, isEmpty);
  });

  test('the receipt is built against the chain head the queue supplies',
      () async {
    // Not against one read beforehand. The predecessor has to be the receipt
    // this one is actually written after, and only the queue knows that
    // inside its lock.
    final world = build();
    await world.filing.submit(ticket());

    final built = world.queue.enqueued.single.document;
    final header = built['header']! as EtaObject;
    expect((header['previousUUID']! as EtaText).value, 'chain-head');
  });

  test('the profile is read at settlement, not held', () async {
    // A profile completed in Management five minutes ago is the one this sale
    // is filed under.
    var current = const ReceiptProfile(branchId: 1, tradeName: 'Koshari');
    final orders = _Orders(null);
    final queue = _Queue();
    final filing = FilingOrdersRepository(
      orders,
      queue: queue,
      profile: () => current,
      deviceSerial: 'TILL-1',
    );

    await filing.submit(ticket());
    expect(queue.enqueued, isEmpty, reason: 'incomplete');

    current = profile;
    await filing.submit(ticket());
    expect(queue.enqueued, hasLength(1));
  });

  test('a void is not filed', () async {
    // A void removes an order that was never completed; there is no receipt
    // to undo. A voided order that HAD been filed is a refund receipt, which
    // is its own document.
    final world = build();
    await world.filing.voidOrder(
      ticket(),
      by: const PosStaff(id: 1, name: 'Amer'),
    );

    expect(world.orders.voided, hasLength(1));
    expect(world.queue.enqueued, isEmpty);
  });

  test('the backlog count passes straight through', () async {
    final world = build();
    expect(await world.filing.pendingSyncCount(), 3);
  });
}

class _Orders implements OrdersRepository {
  _Orders(this._result);

  final SubmitOrderResult? _result;
  final submitted = <Ticket>[];
  final voided = <Ticket>[];

  @override
  Future<SubmitOrderResult> submit(Ticket ticket, {PosStaff? servedBy}) async {
    submitted.add(ticket);
    return _result ??
        const SubmitOrderResult(
          clientTransactionId: 'txn-1',
          queued: false,
          serverId: 42,
          invoiceNumber: 'INV-0001',
        );
  }

  @override
  Future<int> pendingSyncCount() async => 3;

  @override
  Future<SubmitOrderResult> voidOrder(
    Ticket ticket, {
    required PosStaff by,
    int? reasonId,
    String? note,
    PosStaff? approvedBy,
    PosStaff? servedBy,
  }) async {
    voided.add(ticket);
    return const SubmitOrderResult(
      clientTransactionId: 'txn-1',
      queued: false,
      serverId: 42,
    );
  }
}

class _Queue implements EtaQueueRepository {
  _Queue({this.throws = false});

  final bool throws;
  final enqueued = <({int orderId, String receiptNumber, EtaObject document})>[];

  @override
  Future<EtaEnqueued> enqueue({
    required int orderId,
    required String deviceSerial,
    required String receiptNumber,
    required String receiptType,
    required DateTime issuedAt,
    required EtaObject Function(String previousUuid) build,
    int? refundId,
  }) async {
    if (throws) throw StateError('connection reset');
    final document = build('chain-head');
    enqueued.add((
      orderId: orderId,
      receiptNumber: receiptNumber,
      document: document,
    ));
    return EtaEnqueued(
      id: 1,
      uuid: 'a' * 64,
      previousUuid: 'chain-head',
      document: document,
    );
  }

  @override
  Future<List<EtaSubmission>> outstanding({int limit = 200}) async => const [];

  @override
  Future<EtaQueueSummary> summary({required DateTime now}) async =>
      EtaQueueSummary.empty;

  @override
  Future<String?> canonicalFor(int id) => throw UnimplementedError();

  @override
  Future<void> markSigned(int id, String signature) =>
      throw UnimplementedError();

  @override
  Future<void> markAccepted(
    int id, {
    required String submissionUuid,
    String? longId,
  }) => throw UnimplementedError();

  @override
  Future<void> markRejected(int id, String message) =>
      throw UnimplementedError();

  @override
  Future<void> markAttempted(int id, String message) =>
      throw UnimplementedError();
}
