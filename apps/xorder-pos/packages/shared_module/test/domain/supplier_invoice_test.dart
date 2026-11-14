import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/money/money.dart';
import 'package:shared_module/core/money/quantity.dart';
import 'package:shared_module/domain/models/purchase_order.dart';
import 'package:shared_module/domain/models/supplier_invoice.dart';

/// What is owed, and what settles it (§37).
///
/// The arithmetic here decides whether a business pays a supplier twice, so
/// every claim in the model gets a test — including the two that are decisions
/// rather than sums: an on-account payment reduces the balance without clearing
/// a bill, and an over-payment is a credit on the account rather than a negative
/// invoice.
void main() {
  DateTime day(int d) => DateTime.utc(2026, 3, d);

  SupplierInvoice invoice({
    int id = 1,
    int supplierId = 7,
    String number = 'INV-900',
    int totalMinor = 100000,
    int taxMinor = 12281,
    int paidMinor = 0,
    int issued = 1,
    int due = 31,
    DateTime? voidedAt,
  }) => SupplierInvoice(
    id: id,
    supplierId: supplierId,
    number: number,
    total: Money(totalMinor),
    tax: Money(taxMinor),
    paid: Money(paidMinor),
    issuedAt: day(issued),
    dueAt: day(due),
    voidedAt: voidedAt,
    voidReasonId: voidedAt == null ? null : 41,
  );

  SupplierPayment payment({
    int id = 1,
    int supplierId = 7,
    int? invoiceId = 1,
    int amountMinor = 50000,
    SupplierPaymentMethod method = SupplierPaymentMethod.cash,
    DateTime? voidedAt,
  }) => SupplierPayment(
    id: id,
    supplierId: supplierId,
    invoiceId: invoiceId,
    amount: Money(amountMinor),
    method: method,
    paidAt: day(5),
    voidedAt: voidedAt,
    voidReasonId: voidedAt == null ? null : 42,
  );

  group('an invoice', () {
    test('the subtotal is derived, not a third number to disagree', () {
      // The total and the tax are the two figures a person reads off a piece of
      // paper without doing arithmetic. Typing the subtotal as well would be
      // inviting three numbers to contradict each other.
      final bill = invoice(totalMinor: 100000, taxMinor: 12281);
      expect(bill.subtotal, const Money(87719));
      expect(bill.subtotal + bill.tax, bill.total);
    });

    test('the tax can be worked out from a rate on a gross figure', () {
      // What `Money.taxWithinBp` is for: a supplier's invoice quotes the gross
      // and the rate, and the tax inside it is not 14% of the gross.
      const gross = Money(114000);
      expect(gross.taxWithinBp(1400), const Money(14000));
      expect(
        invoice(totalMinor: 114000, taxMinor: 14000).subtotal,
        const Money(100000),
      );
    });

    test('outstanding is the total less what is paid', () {
      expect(
        invoice(totalMinor: 100000, paidMinor: 40000).outstanding,
        const Money(60000),
      );
    });

    test('overpaying does not make the invoice negative', () {
      // Paying more than a bill asks for is a credit with the supplier, which
      // is a fact about the account and not about this piece of paper. A
      // negative outstanding here would subtract from every other bill's total.
      final bill = invoice(totalMinor: 100000, paidMinor: 130000);
      expect(bill.outstanding, Money.zero);
      expect(bill.isSettled, isTrue);
    });

    test('settled the moment the payments reach the total', () {
      expect(invoice(totalMinor: 100000, paidMinor: 99999).isSettled, isFalse);
      expect(invoice(totalMinor: 100000, paidMinor: 100000).isSettled, isTrue);
    });

    group('overdue', () {
      test('is asked as at a date, not as at now', () {
        // So a statement can be run for the end of last month, and so a test
        // does not depend on what day somebody runs it.
        final bill = invoice(due: 31);
        expect(bill.isOverdue(day(30)), isFalse);
        expect(
          bill.isOverdue(day(31)),
          isFalse,
          reason: 'due today is not late',
        );
        expect(bill.isOverdue(DateTime.utc(2026, 4, 1)), isTrue);
      });

      test('a settled invoice is never overdue, however old', () {
        expect(
          invoice(due: 1, paidMinor: 100000).isOverdue(DateTime.utc(2027)),
          isFalse,
        );
      });

      test('a cancelled invoice is not a debt', () {
        expect(
          invoice(due: 1, voidedAt: day(2)).isOverdue(DateTime.utc(2027)),
          isFalse,
        );
      });

      test('days late, for a screen that sorts by urgency', () {
        expect(invoice(due: 10).daysLate(day(17)), 7);
        expect(invoice(due: 10).daysLate(day(9)), 0);
      });
    });

    group('what must be fixed before saving', () {
      test('an invoice needs the number off the paper', () {
        expect(
          invoice(number: '   ').problems.first.field,
          InvoiceField.number,
        );
      });

      test('and a positive total', () {
        expect(
          invoice(totalMinor: 0, taxMinor: 0).problems.first.field,
          InvoiceField.total,
        );
      });

      test('the tax cannot exceed the invoice', () {
        expect(
          invoice(totalMinor: 10000, taxMinor: 10001).problems.first.field,
          InvoiceField.tax,
        );
      });

      test('and cannot be due before it was issued', () {
        expect(
          invoice(issued: 20, due: 10).problems.first.field,
          InvoiceField.dueAt,
        );
      });

      test('an ordinary invoice has nothing wrong with it', () {
        expect(invoice().problems, isEmpty);
        expect(invoice().isValid, isTrue);
      });
    });

    test('the due date the supplier terms imply', () {
      expect(SupplierInvoice.dueFrom(day(1), 30), DateTime.utc(2026, 3, 31));
      expect(
        SupplierInvoice.dueFrom(day(1), 0),
        day(1),
        reason: 'cash on delivery is due the day it is issued',
      );
    });
  });

  group('against the delivery', () {
    PurchaseOrder order({
      int orderedUnits = 10,
      int receivedUnits = 10,
      int unitCostMinor = 10000,
      int taxRateBp = 1400,
    }) => PurchaseOrder(
      id: 3,
      supplierId: 7,
      reference: 'PO-1',
      status: PurchaseStatus.sent,
      lines: [
        PurchaseOrderLine(
          id: 11,
          description: 'Milk 1L',
          ordered: Quantity.of(orderedUnits),
          received: Quantity.of(receivedUnits),
          unitCost: Money(unitCostMinor),
          taxRateBp: taxRateBp,
        ),
      ],
    );

    test('the received total is what an invoice should say', () {
      // Ten at 100.00 plus 14% is 1,140.00.
      expect(order().receivedTotal, const Money(114000));
    });

    test('a short delivery is not a pricing dispute', () {
      // Eight of ten crates arrived, so the invoice should be for eight. The
      // comparison is against what came, not what was asked for — otherwise
      // every short delivery would be flagged as an overcharge.
      final eight = order(receivedUnits: 8);
      expect(eight.totals.total, const Money(114000));
      expect(eight.receivedTotal, const Money(91200));
      expect(
        invoice(totalMinor: 91200, taxMinor: 11200).varianceAgainst(eight),
        Money.zero,
      );
    });

    test('billing for more than arrived is a phone call', () {
      final eight = order(receivedUnits: 8);
      final bill = invoice(totalMinor: 114000, taxMinor: 14000);
      expect(bill.varianceAgainst(eight), const Money(22800));
      expect(bill.matches(eight), isFalse);
    });

    test('a rounded delivery charge is not a dispute', () {
      // A tolerance rather than an equality, because a supplier who rounds to
      // the piastre is not a supplier in dispute — and a flag that fires on
      // every invoice is a flag nobody reads.
      final bill = invoice(totalMinor: 114003, taxMinor: 14000);
      expect(bill.matches(order()), isFalse);
      expect(bill.matches(order(), tolerance: const Money(5)), isTrue);
    });

    test('nothing received yet means the whole invoice is the variance', () {
      final bill = invoice(totalMinor: 114000, taxMinor: 14000);
      expect(
        bill.varianceAgainst(order(receivedUnits: 0)),
        const Money(114000),
      );
    });
  });

  group('a payment', () {
    test('on account is money with no bill attached', () {
      expect(payment(invoiceId: null).isOnAccount, isTrue);
      expect(payment(invoiceId: 1).isOnAccount, isFalse);
    });

    test('a cheque expects a number somebody can quote to a bank', () {
      expect(SupplierPaymentMethod.cheque.expectsAReference, isTrue);
      expect(SupplierPaymentMethod.bankTransfer.expectsAReference, isTrue);
      expect(SupplierPaymentMethod.cash.expectsAReference, isFalse);
    });

    test('an unknown method reads as `other` rather than throwing', () {
      // Unlike a purchase status, guessing is safe: the row still records that
      // the money left, and `other` says exactly as much as it can be trusted
      // to mean.
      expect(
        SupplierPaymentMethod.fromWire('crypto'),
        SupplierPaymentMethod.other,
      );
      expect(
        SupplierPaymentMethod.fromWire('bank_transfer'),
        SupplierPaymentMethod.bankTransfer,
      );
    });

    test('needs an amount and somebody to pay', () {
      expect(payment(amountMinor: 0).problems.first.field, InvoiceField.amount);
      expect(
        payment(supplierId: 0).problems.first.field,
        InvoiceField.supplier,
      );
    });
  });

  group('the account', () {
    SupplierAccount account({
      List<SupplierInvoice>? invoices,
      List<SupplierPayment>? payments,
      int asOf = 15,
    }) => SupplierAccount(
      supplierId: 7,
      invoices: invoices ?? [invoice()],
      payments: payments ?? const [],
      asOf: day(asOf),
    );

    test('the balance is invoices less payments', () {
      final a = account(
        invoices: [invoice(id: 1, totalMinor: 100000)],
        payments: [payment(amountMinor: 30000)],
      );
      expect(a.invoiced, const Money(100000));
      expect(a.paid, const Money(30000));
      expect(a.outstanding, const Money(70000));
    });

    test('a voided invoice is evidence, not a debt', () {
      final a = account(
        invoices: [
          invoice(id: 1, totalMinor: 100000),
          invoice(
            id: 2,
            number: 'INV-901',
            totalMinor: 50000,
            voidedAt: day(3),
          ),
        ],
      );
      expect(a.invoiced, const Money(100000));
    });

    test('a voided payment stops being money that left', () {
      final a = account(
        invoices: [invoice(totalMinor: 100000)],
        payments: [
          payment(id: 1, amountMinor: 30000),
          payment(id: 2, amountMinor: 20000, voidedAt: day(6)),
        ],
      );
      expect(a.paid, const Money(30000));
      expect(a.outstanding, const Money(70000));
    });

    test('on-account money reduces the balance and clears no bill', () {
      // **The decision worth a test.** A business hands the dairy man 2,000
      // on Friday against a running tab. It reduces what he is owed — that is
      // arithmetic — but it does not make an overdue invoice current, because
      // nobody has said which invoice it was for. Guessing would turn a sum
      // into a fold, and two screens would disagree about whether the
      // business was late.
      final overdueBill = invoice(id: 1, totalMinor: 100000, due: 10);
      final a = account(
        invoices: [overdueBill],
        payments: [payment(invoiceId: null, amountMinor: 200000)],
        asOf: 20,
      );

      expect(a.outstanding, const Money(-100000), reason: 'in credit overall');
      expect(a.isInCredit, isTrue);
      expect(
        a.overdue,
        const Money(100000),
        reason: 'the bill itself is still unpaid and still late',
      );
      expect(a.onAccount, const Money(200000));
    });

    test('money allocated to the bill does clear it', () {
      final a = account(
        invoices: [
          invoice(id: 1, totalMinor: 100000, paidMinor: 100000, due: 10),
        ],
        payments: [payment(invoiceId: 1, amountMinor: 100000)],
        asOf: 20,
      );
      expect(a.overdue, Money.zero);
      expect(a.outstanding, Money.zero);
    });

    test('partly paid and late counts only the unpaid part as overdue', () {
      final a = account(
        invoices: [
          invoice(id: 1, totalMinor: 100000, paidMinor: 40000, due: 10),
        ],
        payments: [payment(invoiceId: 1, amountMinor: 40000)],
        asOf: 20,
      );
      expect(a.overdue, const Money(60000));
    });

    test('every figure is a sum, so the order of the rows cannot matter', () {
      // The property that makes two screens agree. Reversing the lists must
      // change nothing — which is exactly what a fold over allocations would
      // break.
      final invoices = [
        invoice(id: 1, number: 'A', totalMinor: 100000, due: 10),
        invoice(id: 2, number: 'B', totalMinor: 50000, due: 20),
      ];
      final paid = [
        payment(id: 1, invoiceId: 1, amountMinor: 30000),
        payment(id: 2, invoiceId: null, amountMinor: 20000),
      ];

      final forwards = SupplierAccount(
        supplierId: 7,
        invoices: invoices,
        payments: paid,
        asOf: day(15),
      );
      final backwards = SupplierAccount(
        supplierId: 7,
        invoices: invoices.reversed.toList(),
        payments: paid.reversed.toList(),
        asOf: day(15),
      );

      expect(forwards.invoiced, backwards.invoiced);
      expect(forwards.paid, backwards.paid);
      expect(forwards.outstanding, backwards.outstanding);
      expect(forwards.overdue, backwards.overdue);
      expect(forwards.onAccount, backwards.onAccount);
    });

    test('an empty account is settled and owes nothing', () {
      final a = account(invoices: const [], payments: const []);
      expect(a.invoiced, Money.zero);
      expect(a.outstanding, Money.zero);
      expect(a.overdue, Money.zero);
      expect(a.balance.isSettled, isTrue);
    });
  });
}
