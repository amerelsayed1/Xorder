import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/money/money.dart';
import 'package:xorder_pos/data/eta/filing_orders_repository.dart';
import 'package:xorder_pos/domain/models/catalog.dart';
import 'package:xorder_pos/domain/models/receipt_profile.dart';
import 'package:xorder_pos/domain/models/ticket.dart';
import 'package:xorder_pos/domain/repositories/repositories.dart';
import 'package:xorder_pos/domain/services/eta_filing.dart';

/// Queuing an e-receipt for every sale that reaches the database.
///
/// The rule this exists to hold is that **a filing failure never fails a
/// sale**. The customer is at the counter and the money is in the drawer; an
/// exception thrown on the way to the tax authority would lose a settled order
/// to protect a filing that has twenty-four hours to catch up.
void main() {
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
    _Filer filer,
    List<EtaFilingSkipped> problems,
    FilingOrdersRepository filing,
  })
  build({
    SubmitOrderResult? result,
    EtaFilingSkipped? answer,
    bool filerThrows = false,
  }) {
    final orders = _Orders(result);
    final filer = _Filer(answer: answer, throws: filerThrows);
    final problems = <EtaFilingSkipped>[];
    return (
      orders: orders,
      filer: filer,
      problems: problems,
      filing: FilingOrdersRepository(
        orders,
        filer: filer,
        onProblem: problems.add,
      ),
    );
  }

  test('a settled sale is filed, by the id it was written under', () async {
    // By id, not by ticket: the filer reads the sale back from the rows it
    // was written to — the same path the reconciler takes a week later.
    final world = build();
    await world.filing.submit(ticket());

    expect(world.filer.orders, [42]);
  });

  test('the sale is written first, and its result is returned unchanged',
      () async {
    final world = build();
    final result = await world.filing.submit(ticket());

    expect(world.orders.submitted, hasLength(1));
    expect(result.serverId, 42);
    expect(result.invoiceNumber, 'INV-0001');
  });

  test('a filer that throws does not lose the sale', () async {
    // The whole point. The money is already in the drawer.
    final world = build(filerThrows: true);
    final result = await world.filing.submit(ticket());

    expect(result.serverId, 42);
    expect(world.problems.single, isA<FilingFailed>());
  });

  test('a restaurant that is not filing is not told off for it', () async {
    // A blank profile: one outside Egypt, or one still in setup. Reporting a
    // problem for every sale it makes would be an alarm that is always on.
    final world = build(answer: const FilingNotInUse());
    await world.filing.submit(ticket());

    expect(world.problems, isEmpty);
  });

  test('a half-typed profile is reported, not swallowed', () async {
    // Somebody typed a name, so they intend to file and should be told they
    // cannot yet. Silence here is how a queue stops being read.
    final world = build(
      answer: const ProfileIncomplete([
        ProfileProblem(ProfileField.registrationNumber, 'nine digits'),
      ]),
    );
    await world.filing.submit(ticket());

    expect(world.problems.single, isA<ProfileIncomplete>());
  });

  test('an order that did not reach the database is not filed', () async {
    // No row, nothing to file against.
    final world = build(
      result: const SubmitOrderResult(
        clientTransactionId: 'txn-1',
        queued: true,
      ),
    );
    await world.filing.submit(ticket());
    expect(world.filer.orders, isEmpty);
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
    expect(world.filer.orders, isEmpty);
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
  Future<SubmitOrderResult> submit(
    Ticket ticket, {
    PosStaff? servedBy,
    int? parkedVersion,
  }) async {
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
    Approval? approval,
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

class _Filer implements EtaFilingPort {
  _Filer({this.answer, this.throws = false});

  final EtaFilingSkipped? answer;
  final bool throws;
  final orders = <int>[];
  final refunds = <int>[];

  @override
  Future<EtaFilingSkipped?> fileOrder(int orderId) async {
    if (throws) throw StateError('connection reset');
    orders.add(orderId);
    return answer;
  }

  @override
  Future<EtaFilingSkipped?> fileRefund(int refundId) async {
    if (throws) throw StateError('connection reset');
    refunds.add(refundId);
    return answer;
  }
}
