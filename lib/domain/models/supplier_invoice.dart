/// What the business owes, and what it has paid (§37).
///
/// The end of the purchasing chain, and the point of the rest of it. A purchase
/// order is a request and a goods receipt is a fact about the store room;
/// neither is a debt. The invoice is the debt, and the payment is what settles
/// it.
///
/// **Three things this deliberately does not do.**
///
/// It does not carry lines. A bookkeeper types an invoice off a piece of paper
/// with the supplier on the phone, and a form that demanded twelve lines before
/// it would save is a form that leaves the invoice in a drawer. What the lines
/// *should* have come to is already known — the goods receipt recorded it — so
/// the useful number is the difference between the two, and that needs only the
/// total. See [SupplierInvoice.varianceAgainst].
///
/// It does not re-cost the stock. Receiving valued the goods at the ordered
/// cost; if the invoice disagrees, the difference is surfaced as a variance and
/// **not** silently folded into the moving average. Re-costing would mean
/// rewriting a ledger whose whole value is that nobody can rewrite it, and half
/// the stock is usually sold by the time the invoice arrives.
///
/// It does not store a balance. What is outstanding is invoices less payments,
/// derived at the point it is shown — the same decision, for the same reason, as
/// the missing balance column on [Supplier].
library;

import '../../core/money/money.dart';
import 'purchase_order.dart';
import 'supplier.dart';

/// One thing wrong with an invoice, and which field it is wrong on.
class InvoiceProblem {
  const InvoiceProblem(this.field, this.message);

  final String field;
  final String message;
}

abstract final class InvoiceField {
  static const number = 'number';
  static const total = 'total';
  static const tax = 'tax';
  static const dueAt = 'due_at';
  static const amount = 'amount';
  static const supplier = 'supplier';
}

/// A bill from a supplier.
class SupplierInvoice {
  const SupplierInvoice({
    required this.id,
    required this.supplierId,
    required this.number,
    required this.total,
    required this.issuedAt,
    required this.dueAt,
    this.tax = const Money(0),
    this.supplierName,
    this.purchaseOrderId,
    this.purchaseOrderReference,
    this.note,
    this.paid = const Money(0),
    this.voidedAt,
    this.voidReasonId,
    this.voidNote,
  });

  final int id;
  final int supplierId;

  /// The supplier as the invoice named them, snapshotted for the same reason a
  /// purchase order snapshots it: a ledger has to still say who was owed after
  /// somebody corrects a spelling.
  final String? supplierName;

  /// **The supplier's number, off their paper — not one of ours.**
  ///
  /// This is the only string the two businesses have in common, so it is what a
  /// query on the phone is conducted in, and it is unique per supplier in the
  /// database. Entering the same invoice twice is the most common error in
  /// purchase bookkeeping and the one a screen can actually prevent.
  final String number;

  /// The order it bills, when there is one. Null for the things that arrive
  /// without one — a repair, a delivery charge, the gas bottle somebody
  /// collected — which is a real and ordinary case and not a gap to be filled
  /// in later.
  final int? purchaseOrderId;
  final String? purchaseOrderReference;

  /// **Typed off the paper.** The total and the tax are the two numbers a
  /// person can read off an invoice without doing arithmetic: the total is what
  /// gets paid and what the supplier chases, and the tax is what the VAT return
  /// reclaims. The subtotal is the subtraction of the two, so it is derived
  /// rather than typed — one fewer number to disagree with the others.
  final Money total;
  final Money tax;

  Money get subtotal => total - tax;

  /// Off the paper as well. Not the day it was entered: an invoice dated the
  /// 3rd and typed on the 20th is due on the supplier's terms from the 3rd, and
  /// stamping it with `now()` would quietly give the business three free
  /// weeks that the supplier does not agree to.
  final DateTime issuedAt;

  /// [issuedAt] plus the supplier's terms, unless somebody agreed otherwise.
  /// Stored rather than derived, because the terms on the supplier record can
  /// change and this invoice's due date must not move when they do.
  final DateTime dueAt;

  final String? note;

  /// **Derived, never a column.** The repository fills this in from the sum of
  /// the payments allocated to this invoice; nothing writes it. A stored figure
  /// here would be a second copy of what the payments already say, and the two
  /// would part company the first time a payment was voided.
  final Money paid;

  /// Entered in error, and kept. An invoice a bookkeeper typed twice has to be
  /// visibly cancelled rather than deleted — the supplier's numbering is the
  /// evidence, and a gap in it is a question nobody can answer later.
  ///
  /// **The reason is one of the business's own codes**, not a sentence
  /// somebody typed. `ReasonScope.invoiceVoid` holds the list, and the point of
  /// a code is that "how many did we cancel for *entered twice* last month" is
  /// a question with an answer — which is what finds the process that keeps
  /// producing them. The note is for the rest.
  final DateTime? voidedAt;
  final int? voidReasonId;
  final String? voidNote;

  bool get isVoided => voidedAt != null;

  /// What is still owed on it. Never negative: paying more than an invoice asks
  /// for is a credit with the supplier, which is a fact about the *account* and
  /// not about this piece of paper.
  Money get outstanding => (total - paid).clampToZero();

  bool get isSettled => paid.minor >= total.minor;

  /// Whether the terms have run out with money still on it.
  ///
  /// Takes the date rather than reading the clock, so a report can be run for
  /// the end of last month and a test does not depend on what day it is.
  bool isOverdue(DateTime asOf) =>
      !isVoided && !isSettled && asOf.isAfter(dueAt);

  /// How many days late, or zero. For a screen that has to sort by urgency.
  int daysLate(DateTime asOf) =>
      isOverdue(asOf) ? asOf.difference(dueAt).inDays : 0;

  /// The invoice against what actually arrived.
  ///
  /// Positive means the supplier has billed more than they delivered, which is
  /// the direction worth catching — it is a phone call, not a payment. Negative
  /// means less, which usually means the rest is still coming on another
  /// invoice.
  ///
  /// **Compared against the received value, not the ordered one.** An order for
  /// ten crates that arrived as eight should be invoiced for eight, and
  /// checking against the order would flag every short delivery as a pricing
  /// dispute.
  Money varianceAgainst(PurchaseOrder order) => total - order.receivedTotal;

  /// Whether the invoice and the delivery agree, within [tolerance].
  ///
  /// A tolerance rather than an equality, because a supplier who rounds a
  /// delivery charge to the piastre is not a supplier in dispute, and a screen
  /// that flagged them would be a screen nobody reads.
  bool matches(PurchaseOrder order, {Money tolerance = const Money(0)}) {
    final off = varianceAgainst(order);
    return off.minor.abs() <= tolerance.minor.abs();
  }

  /// What must be fixed before this can be saved.
  List<InvoiceProblem> get problems => [
    if (number.trim().isEmpty)
      const InvoiceProblem(
        InvoiceField.number,
        'An invoice needs the number printed on it.',
      ),
    if (!total.isPositive)
      const InvoiceProblem(
        InvoiceField.total,
        'An invoice is for more than nothing.',
      ),
    if (tax.isNegative)
      const InvoiceProblem(InvoiceField.tax, 'Tax cannot be negative.'),
    if (tax.minor > total.minor)
      const InvoiceProblem(
        InvoiceField.tax,
        'The tax cannot be more than the invoice.',
      ),
    if (dueAt.isBefore(issuedAt))
      const InvoiceProblem(
        InvoiceField.dueAt,
        'An invoice cannot be due before it was issued.',
      ),
  ];

  bool get isValid => problems.isEmpty;

  /// The due date the supplier's terms imply.
  ///
  /// A helper rather than a default on the constructor, so that a due date is
  /// always something the caller decided: an invoice whose date came from a
  /// field that happened to be blank is worse than one that refuses to save.
  static DateTime dueFrom(DateTime issuedAt, int paymentTermDays) =>
      issuedAt.add(Duration(days: paymentTermDays));

  SupplierInvoice copyWith({
    String? number,
    Money? total,
    Money? tax,
    DateTime? issuedAt,
    DateTime? dueAt,
    String? note,
    Money? paid,
    int? purchaseOrderId,
    String? purchaseOrderReference,
    DateTime? voidedAt,
    int? voidReasonId,
    String? voidNote,
  }) => SupplierInvoice(
    id: id,
    supplierId: supplierId,
    supplierName: supplierName,
    number: number ?? this.number,
    total: total ?? this.total,
    tax: tax ?? this.tax,
    issuedAt: issuedAt ?? this.issuedAt,
    dueAt: dueAt ?? this.dueAt,
    note: note ?? this.note,
    paid: paid ?? this.paid,
    purchaseOrderId: purchaseOrderId ?? this.purchaseOrderId,
    purchaseOrderReference:
        purchaseOrderReference ?? this.purchaseOrderReference,
    voidedAt: voidedAt ?? this.voidedAt,
    voidReasonId: voidReasonId ?? this.voidReasonId,
    voidNote: voidNote ?? this.voidNote,
  );
}

/// How the money left the business.
///
/// **Deliberately not `pos_tender_types`.** Those describe how a customer pays
/// the business and carry `counts_as_cash` so the drawer can be counted;
/// these describe how the business pays somebody else, and the two lists
/// share nothing but the word "cash". Modelling them once would mean a Visa
/// terminal appearing as a way to pay a vegetable supplier.
enum SupplierPaymentMethod {
  cash('cash'),
  bankTransfer('bank_transfer'),
  cheque('cheque'),
  card('card'),
  other('other');

  const SupplierPaymentMethod(this.wire);

  final String wire;

  /// A cheque or a transfer is identified by a number somebody has to be able
  /// to quote back to a bank. Cash is not.
  bool get expectsAReference =>
      this == cheque || this == bankTransfer || this == card;

  static SupplierPaymentMethod fromWire(String value) =>
      SupplierPaymentMethod.values.firstWhere(
        (m) => m.wire == value,
        // Unlike a purchase status, guessing is safe here: an unrecognised
        // method still records that the money left, and `other` says exactly
        // as much as the row can be trusted to mean.
        orElse: () => SupplierPaymentMethod.other,
      );
}

/// Money paid to a supplier.
class SupplierPayment {
  const SupplierPayment({
    required this.id,
    required this.supplierId,
    required this.amount,
    required this.method,
    required this.paidAt,
    this.supplierName,
    this.invoiceId,
    this.invoiceNumber,
    this.reference,
    this.note,
    this.cashMovementId,
    this.voidedAt,
    this.voidReasonId,
    this.voidNote,
  });

  final int id;
  final int supplierId;
  final String? supplierName;

  /// The invoice this settles, or null for money paid **on account**.
  ///
  /// A real and common case: a business hands the dairy man 2,000 on Friday
  /// against a running tab. It reduces what the supplier is owed straight away
  /// — see [SupplierBalance.outstanding] — but it does **not** clear any
  /// particular bill, so it does not make an overdue invoice stop being
  /// overdue. Guessing which invoice it meant would turn a sum into a fold, and
  /// the answer would depend on the order the rows were read in.
  final int? invoiceId;
  final String? invoiceNumber;

  final Money amount;
  final SupplierPaymentMethod method;

  /// The cheque number, the transfer reference — whatever a bank would need to
  /// find it again.
  final String? reference;

  final DateTime paidAt;
  final String? note;

  /// The drawer movement this money left through, when it left a till.
  ///
  /// **Set only when somebody said the cash came out of the drawer.** Paying a
  /// supplier out of the office safe and paying them out of the till are
  /// different acts, and both are ordinary: the first touches no drawer, the
  /// second leaves a till 500 short that a manager has to be able to account
  /// for. So the payment dialog asks, the answer defaults to *no*, and only a
  /// yes writes a `pay_out` in the same transaction as the payment — see
  /// [SupplierPaymentRequest].
  ///
  /// Null therefore means "not out of a drawer", not "we do not know". The
  /// rejected alternative was inferring it from `method == cash`, which would
  /// have moved the drawer every time a bookkeeper typed last week's cash
  /// payment in from a receipt book.
  final int? cashMovementId;

  /// One of `ReasonScope.paymentVoid`'s codes, for the same reason an invoice's
  /// is a code.
  final DateTime? voidedAt;
  final int? voidReasonId;
  final String? voidNote;

  bool get isVoided => voidedAt != null;

  /// Money that is not tied to a particular bill.
  bool get isOnAccount => invoiceId == null;

  List<InvoiceProblem> get problems => [
    if (!amount.isPositive)
      const InvoiceProblem(
        InvoiceField.amount,
        'A payment is for more than nothing.',
      ),
    if (supplierId == 0)
      const InvoiceProblem(
        InvoiceField.supplier,
        'A payment has to be to somebody.',
      ),
  ];

  bool get isValid => problems.isEmpty;

  SupplierPayment copyWith({
    Money? amount,
    SupplierPaymentMethod? method,
    String? reference,
    DateTime? paidAt,
    String? note,
    int? invoiceId,
    String? invoiceNumber,
    DateTime? voidedAt,
    int? voidReasonId,
    String? voidNote,
  }) => SupplierPayment(
    id: id,
    supplierId: supplierId,
    supplierName: supplierName,
    invoiceId: invoiceId ?? this.invoiceId,
    invoiceNumber: invoiceNumber ?? this.invoiceNumber,
    amount: amount ?? this.amount,
    method: method ?? this.method,
    reference: reference ?? this.reference,
    paidAt: paidAt ?? this.paidAt,
    note: note ?? this.note,
    cashMovementId: cashMovementId,
    voidedAt: voidedAt ?? this.voidedAt,
    voidReasonId: voidReasonId ?? this.voidReasonId,
    voidNote: voidNote ?? this.voidNote,
  );
}

/// A payment somebody has filled in, and whether the cash is to leave a till.
///
/// **The shift is on the request rather than on [SupplierPayment], because it
/// is an instruction and not a fact about the row.** `SupplierPayment` is what
/// a `pos_supplier_payments` row says, and after the write the fact is
/// [SupplierPayment.cashMovementId] — the movement that actually happened. A
/// `takeFromTheDrawer` boolean living on the model would be a field that is
/// meaningful for one instant and misleading for the rest of the row's life,
/// which is how a screen ends up reading it back and offering to move the
/// money a second time.
class SupplierPaymentRequest {
  const SupplierPaymentRequest(this.payment, {this.fromShiftId});

  final SupplierPayment payment;

  /// The open shift whose drawer the cash comes out of, or null for money paid
  /// from the office. An id rather than a flag: the drawer that goes short is a
  /// particular till's on a particular shift, and the office may well be a
  /// different machine from the one the shift is open on.
  final int? fromShiftId;

  bool get comesOutOfTheDrawer => fromShiftId != null;
}

/// What a supplier's account comes to, from the invoices and the payments.
///
/// A sum, not a fold. Every figure here is order-independent — which is the
/// reason [SupplierPayment.isOnAccount] money reduces [outstanding] without
/// touching [overdue]: deciding which bill an unallocated payment cleared would
/// make the answer depend on the order the rows arrived in, and two screens
/// would disagree about whether the business was late.
class SupplierAccount {
  const SupplierAccount({
    required this.supplierId,
    required this.invoices,
    required this.payments,
    required this.asOf,
  });

  final int supplierId;

  /// Live invoices only — a voided one is evidence, not a debt.
  final List<SupplierInvoice> invoices;
  final List<SupplierPayment> payments;
  final DateTime asOf;

  Money get _zero => invoices.isEmpty
      ? const Money(0)
      : invoices.first.total.copyWith(minor: 0);

  Money get invoiced =>
      invoices.where((i) => !i.isVoided).fold(_zero, (sum, i) => sum + i.total);

  Money get paid => payments
      .where((p) => !p.isVoided)
      .fold(_zero, (sum, p) => sum + p.amount);

  Money get outstanding => invoiced - paid;

  /// The unpaid part of invoices whose terms have run out.
  ///
  /// Counts only what has been **allocated** to each invoice. On-account money
  /// reduces the balance but does not make a specific bill current, because
  /// nobody has said which bill it was for.
  Money get overdue => invoices
      .where((i) => i.isOverdue(asOf))
      .fold(_zero, (sum, i) => sum + i.outstanding);

  /// Money paid without being pointed at an invoice, and still unallocated.
  Money get onAccount => payments
      .where((p) => !p.isVoided && p.isOnAccount)
      .fold(_zero, (sum, p) => sum + p.amount);

  bool get isInCredit => outstanding.isNegative;

  SupplierBalance get balance => SupplierBalance(
    supplierId: supplierId,
    invoiced: invoiced,
    paid: paid,
    overdue: overdue,
  );
}

/// Why an invoice or a payment cannot be written as asked.
sealed class InvoiceRefusal {
  const InvoiceRefusal();
}

/// This supplier already has an invoice with that number.
class InvoiceNumberAlreadyEntered extends InvoiceRefusal {
  const InvoiceNumberAlreadyEntered(this.number, this.existingId);

  final String number;
  final int existingId;
}

/// A voided invoice is a record, not a document — nothing may be changed on it
/// and nothing may be paid against it.
class InvoiceIsVoided extends InvoiceRefusal {
  const InvoiceIsVoided();
}

/// Payments have been made against it. Voiding it would leave money allocated
/// to a bill that no longer exists.
class InvoiceHasPayments extends InvoiceRefusal {
  const InvoiceHasPayments(this.paid);

  final Money paid;
}

/// The payments allocated to an invoice would come to more than it asks for.
class PaymentExceedsInvoice extends InvoiceRefusal {
  const PaymentExceedsInvoice({
    required this.invoiceTotal,
    required this.alreadyPaid,
    required this.attempted,
  });

  final Money invoiceTotal;
  final Money alreadyPaid;
  final Money attempted;

  Money get room => (invoiceTotal - alreadyPaid).clampToZero();
}

/// The invoice belongs to a different supplier from the payment.
class PaymentIsForAnotherSupplier extends InvoiceRefusal {
  const PaymentIsForAnotherSupplier();
}
