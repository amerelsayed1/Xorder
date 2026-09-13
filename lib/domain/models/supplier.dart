/// Who the restaurant buys from.
///
/// The first row of the purchasing chain, and the reason it comes first:
/// nothing downstream is honest without it. A cost price nobody purchased is a
/// number somebody typed; an inventory valuation built on typed costs is a
/// number nobody should put in a return.
///
/// **There is deliberately no balance column.** What a supplier is owed is
/// invoices minus payments, and a stored total drifts the first time somebody
/// voids an invoice inside a transaction that fails halfway. It is derived
/// where it is shown — see [SupplierBalance] — which costs one join and buys
/// a number that cannot be wrong.
library;

import '../../core/money/money.dart';

/// One thing wrong with a supplier, and which field it is wrong on.
class SupplierProblem {
  const SupplierProblem(this.field, this.message);

  final String field;
  final String message;
}

abstract final class SupplierField {
  static const name = 'name';
  static const code = 'code';
  static const taxNumber = 'tax_number';
  static const paymentTermDays = 'payment_term_days';
}

class Supplier {
  const Supplier({
    required this.id,
    required this.nameEn,
    this.nameAr,
    this.code = '',
    this.contactName,
    this.phone,
    this.email,
    this.address,
    this.taxNumber,
    this.paymentTermDays = 0,
    this.notes,
    this.isActive = true,
  });

  final int id;
  final String nameEn;
  final String? nameAr;

  /// The restaurant's own reference — an account number with the supplier, or
  /// whatever the bookkeeper already writes on the invoices. Optional, because
  /// most small restaurants have none and inventing one would be a field they
  /// have to fill in with a lie.
  final String code;

  final String? contactName;
  final String? phone;
  final String? email;
  final String? address;

  /// The supplier's tax registration number, off their invoice.
  ///
  /// Kept because a purchase invoice is the *input* side of the same VAT the
  /// receipt reports, and a return that claims input tax has to say whose.
  /// Nine digits in Egypt — validated in shape only, for the same reason the
  /// receipt profile's is: a list that changes must not stop a restaurant
  /// recording a delivery.
  final String? taxNumber;

  /// How long after an invoice the supplier expects to be paid. Zero means
  /// cash on delivery, which is most of them.
  final int paymentTermDays;

  final String? notes;
  final bool isActive;

  bool get isCashOnDelivery => paymentTermDays == 0;

  String displayName(String locale) =>
      locale.startsWith('ar') && (nameAr?.isNotEmpty ?? false)
      ? nameAr!
      : nameEn;

  /// What must be fixed before this can be saved.
  ///
  /// Short on purpose. A restaurant recording a delivery at seven in the
  /// morning needs to write down who it came from, not fill in a form — and
  /// everything else here can be added when somebody has the invoice in front
  /// of them.
  List<SupplierProblem> get problems => [
    if (nameEn.trim().isEmpty)
      const SupplierProblem(SupplierField.name, 'A supplier needs a name.'),
    if (paymentTermDays < 0)
      const SupplierProblem(
        SupplierField.paymentTermDays,
        'Payment terms cannot be negative.',
      ),
    if (taxNumber != null &&
        taxNumber!.trim().isNotEmpty &&
        !_isNineDigits(taxNumber!))
      const SupplierProblem(
        SupplierField.taxNumber,
        'A tax registration number is nine digits.',
      ),
  ];

  bool get isValid => problems.isEmpty;

  static bool _isNineDigits(String value) {
    final trimmed = value.trim();
    return trimmed.length == 9 &&
        trimmed.codeUnits.every((c) => c >= 0x30 && c <= 0x39);
  }

  Supplier copyWith({
    String? nameEn,
    String? nameAr,
    String? code,
    String? contactName,
    String? phone,
    String? email,
    String? address,
    String? taxNumber,
    int? paymentTermDays,
    String? notes,
    bool? isActive,
  }) => Supplier(
    id: id,
    nameEn: nameEn ?? this.nameEn,
    nameAr: nameAr ?? this.nameAr,
    code: code ?? this.code,
    contactName: contactName ?? this.contactName,
    phone: phone ?? this.phone,
    email: email ?? this.email,
    address: address ?? this.address,
    taxNumber: taxNumber ?? this.taxNumber,
    paymentTermDays: paymentTermDays ?? this.paymentTermDays,
    notes: notes ?? this.notes,
    isActive: isActive ?? this.isActive,
  );
}

/// What a supplier is owed, derived rather than stored.
///
/// [invoiced] less [paid], with [overdue] the part whose payment term has
/// already run out. The three travel together because a screen that showed the
/// balance without the overdue share would answer the wrong question: a
/// restaurant does not ask *what do I owe*, it asks *what do I owe now*.
class SupplierBalance {
  const SupplierBalance({
    required this.supplierId,
    required this.invoiced,
    required this.paid,
    required this.overdue,
  });

  final int supplierId;
  final Money invoiced;
  final Money paid;

  /// The unpaid part of invoices whose terms have expired.
  final Money overdue;

  Money get outstanding => invoiced - paid;

  bool get isSettled => outstanding.isZero || outstanding.isNegative;

  /// Paid more than invoiced — a deposit, or a credit note nobody has used.
  /// Worth its own question because it reads as a negative balance and a
  /// bookkeeper will assume it is a mistake unless the screen says otherwise.
  bool get isInCredit => outstanding.isNegative;
}
