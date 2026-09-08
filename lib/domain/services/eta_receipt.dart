/// Building the document Egypt's tax authority receives.
///
/// **What this is, and what it is not.** The shape below is Receipt v1.2 as
/// ETA publish it, field for field. What it is *not* is a signature: the
/// document leaves here unsigned, with a `uuid` computed and a place for a
/// seal, because the private key that seals it does not live in this process
/// and should not. See [EtaReceiptSigner].
///
/// Every amount is rendered from [Money]'s minor units, never from a `double`.
/// A tax filing is the last place in this product where a rounding error could
/// hide, and the whole money model exists so it cannot.
library;

import '../../core/money/money.dart';
import '../models/receipt_profile.dart';
import '../models/tax.dart';
import 'eta_serialization.dart';

/// What kind of document this is, in ETA's vocabulary.
abstract final class EtaReceiptType {
  /// A sale.
  static const sale = 's';

  /// Money going back. Carries `referenceOldUUID` naming the sale it undoes.
  static const refund = 'r';
}

/// Who bought it.
///
/// A walk-in customer is `type: 'P'` (a person) with nothing else — which is
/// the overwhelmingly common case in a restaurant and the one this defaults
/// to. A company buying lunch for a meeting gives a registration number and
/// becomes `'B'`.
class EtaBuyer {
  const EtaBuyer.person({this.name, this.mobileNumber})
    : type = 'P',
      id = null;

  const EtaBuyer.business({required String this.id, required String this.name})
    : type = 'B',
      mobileNumber = null;

  final String type;
  final String? id;
  final String? name;
  final String? mobileNumber;
}

/// One line of the receipt, as ETA wants it.
class EtaItem {
  const EtaItem({
    required this.description,
    required this.quantity,
    required this.unitPrice,
    required this.totalSale,
    required this.total,
    required this.taxes,
    this.internalCode,
    this.itemCode,
    this.itemType = 'GS1',
    this.unitType = 'EA',
    this.commercialDiscount = Money.zero,
  });

  final String description;
  final int quantity;
  final Money unitPrice;

  /// Before tax and before discount.
  final Money totalSale;

  /// After tax and discount — what this line contributed to the bill.
  final Money total;

  final Money commercialDiscount;
  final List<TaxLine> taxes;

  /// The restaurant's own code for the dish. Sent as `internalCode`; ETA does
  /// not care what it means, and a restaurant that has no SKUs sends none.
  final String? internalCode;

  /// The GS1 or EGS code. Null on a restaurant that has not registered its
  /// menu with a coding scheme, which is nearly all of them.
  final String? itemCode;

  final String itemType;
  final String unitType;

  Money get netSale => totalSale - commercialDiscount;
}

/// Everything needed to write one receipt, gathered.
///
/// A record rather than a pile of arguments because the caller assembles this
/// from three different places — the profile, the order and the till — and a
/// long positional list is where the branch code ends up in the activity code.
class EtaReceiptInput {
  const EtaReceiptInput({
    required this.profile,
    required this.receiptNumber,
    required this.issuedAt,
    required this.deviceSerialNumber,
    required this.items,
    required this.totalSales,
    required this.netAmount,
    required this.totalAmount,
    required this.taxTotals,
    required this.paymentMethod,
    this.buyer = const EtaBuyer.person(),
    this.previousUuid = '',
    this.referenceOldUuid,
    this.receiptType = EtaReceiptType.sale,
    this.currency = 'EGP',
    this.totalCommercialDiscount = Money.zero,
    this.totalItemsDiscount = Money.zero,
  });

  final ReceiptProfile profile;

  /// The restaurant's own invoice number. Not the uuid — this is the one the
  /// customer reads off the paper and quotes on the phone.
  final String receiptNumber;

  final DateTime issuedAt;

  /// The till, as registered with ETA. Per device, not per branch.
  final String deviceSerialNumber;

  final List<EtaItem> items;
  final Money totalSales;
  final Money netAmount;
  final Money totalAmount;
  final List<TaxLine> taxTotals;

  /// ETA's payment method code — `C` cash, `V` card, and so on.
  final String paymentMethod;

  final EtaBuyer buyer;

  /// The uuid of the previous receipt from **this device**.
  ///
  /// The chain is what makes a missing receipt visible: skip one and every
  /// receipt after it points at a document the authority never received.
  /// Empty on the first receipt a device ever issues, which is the only time
  /// that is a true statement.
  final String previousUuid;

  /// The sale this refund undoes. Null on a sale.
  final String? referenceOldUuid;

  final String receiptType;
  final String currency;
  final Money totalCommercialDiscount;
  final Money totalItemsDiscount;
}

abstract final class EtaReceiptBuilder {
  /// The version of the document type this builds. On the wire, and pinned
  /// here so that changing it is a deliberate act with a test attached.
  static const typeVersion = '1.2';

  /// Builds the document and stamps its uuid.
  ///
  /// The uuid is derived from everything else in the document, so this is the
  /// last step and cannot be reordered: change any field afterwards and the
  /// uuid is a hash of a document that no longer exists.
  static EtaObject build(EtaReceiptInput input) {
    final document = _document(input, uuid: null);
    return document.with_(
      'header',
      (document['header']! as EtaObject).with_(
        'uuid',
        EtaText(EtaSerializer.uuidOf(document)),
      ),
    );
  }

  static EtaObject _document(EtaReceiptInput input, {String? uuid}) {
    final profile = input.profile;

    return EtaObject.of([
      (
        'header',
        EtaObject.of([
          // UTC with a Z, seconds precision. A local timestamp would make a
          // receipt issued at 23:30 in Cairo land on the wrong trading day at
          // the authority's end.
          ('dateTimeIssued', EtaText(_timestamp(input.issuedAt))),
          ('receiptNumber', EtaText(input.receiptNumber)),
          if (uuid != null) ('uuid', EtaText(uuid)),
          ('previousUUID', EtaText(input.previousUuid)),
          if (input.referenceOldUuid case final reference?)
            ('referenceOldUUID', EtaText(reference)),
          ('currency', EtaText(input.currency)),
          // Sent only when the receipt is not in the filing currency. An
          // exchange rate of 1 on an EGP receipt is a field the authority
          // reads as a conversion that did not happen.
          if (input.currency != 'EGP') ('exchangeRate', const EtaText('1')),
        ]),
      ),
      (
        'documentType',
        EtaObject.of([
          ('receiptType', EtaText(input.receiptType)),
          ('typeVersion', const EtaText(typeVersion)),
        ]),
      ),
      (
        'seller',
        EtaObject.of([
          ('rin', EtaText(profile.registrationNumber.trim())),
          ('companyTradeName', EtaText(profile.tradeName.trim())),
          ('branchCode', EtaText(profile.branchCode.trim())),
          ('branchAddress', _address(profile.address)),
          ('deviceSerialNumber', EtaText(input.deviceSerialNumber)),
          ('activityCode', EtaText(profile.activityCode.trim())),
        ]),
      ),
      ('buyer', _buyer(input.buyer)),
      (
        'itemData',
        EtaArray([for (final item in input.items) _item(item)]),
      ),
      ('totalSales', _money(input.totalSales)),
      if (!input.totalCommercialDiscount.isZero)
        ('totalCommercialDiscount', _money(input.totalCommercialDiscount)),
      if (!input.totalItemsDiscount.isZero)
        ('totalItemsDiscount', _money(input.totalItemsDiscount)),
      ('netAmount', _money(input.netAmount)),
      // ETA accepts only zero here, and sends it all the same: an absent field
      // and a zero one are not the same statement.
      ('feesAmount', const EtaText('0')),
      ('totalAmount', _money(input.totalAmount)),
      if (input.taxTotals.isNotEmpty)
        (
          'taxTotals',
          EtaArray([
            for (final tax in input.taxTotals)
              EtaObject.of([
                ('taxType', EtaText(tax.etaTaxType)),
                ('amount', _money(tax.amount)),
              ]),
          ]),
        ),
      ('paymentMethod', EtaText(input.paymentMethod)),
      ('adjustment', const EtaText('0')),
    ]);
  }

  static EtaObject _address(BranchAddress address) => EtaObject.of([
    ('country', EtaText(address.country.trim())),
    ('governate', EtaText(address.governate.trim())),
    ('regionCity', EtaText(address.regionCity.trim())),
    ('street', EtaText(address.street.trim())),
    ('buildingNumber', EtaText(address.buildingNumber.trim())),
    if (_some(address.postalCode) case final value?)
      ('postalCode', EtaText(value)),
    if (_some(address.floor) case final value?) ('floor', EtaText(value)),
    if (_some(address.room) case final value?) ('room', EtaText(value)),
    if (_some(address.landmark) case final value?) ('landmark', EtaText(value)),
    if (_some(address.additionalInformation) case final value?)
      ('additionalInformation', EtaText(value)),
  ]);

  static EtaObject _buyer(EtaBuyer buyer) => EtaObject.of([
    ('type', EtaText(buyer.type)),
    if (_some(buyer.id) case final value?) ('id', EtaText(value)),
    if (_some(buyer.name) case final value?) ('name', EtaText(value)),
    if (_some(buyer.mobileNumber) case final value?)
      ('mobileNumber', EtaText(value)),
  ]);

  static EtaObject _item(EtaItem item) => EtaObject.of([
    if (_some(item.internalCode) case final value?)
      ('internalCode', EtaText(value)),
    ('description', EtaText(item.description)),
    ('itemType', EtaText(item.itemType)),
    if (_some(item.itemCode) case final value?) ('itemCode', EtaText(value)),
    ('unitType', EtaText(item.unitType)),
    ('quantity', EtaText('${item.quantity}')),
    ('unitPrice', _money(item.unitPrice)),
    ('netSale', _money(item.netSale)),
    ('totalSale', _money(item.totalSale)),
    ('total', _money(item.total)),
    if (!item.commercialDiscount.isZero)
      (
        'commercialDiscountData',
        EtaArray([
          EtaObject.of([
            ('amount', _money(item.commercialDiscount)),
            ('description', const EtaText('discount')),
          ]),
        ]),
      ),
    if (item.taxes.isNotEmpty)
      (
        'taxableItems',
        EtaArray([
          for (final tax in item.taxes)
            EtaObject.of([
              ('taxType', EtaText(tax.etaTaxType)),
              ('amount', _money(tax.amount)),
              ('subType', EtaText(tax.etaSubType)),
              ('rate', EtaText(_rate(tax.rateBp))),
            ]),
        ]),
      ),
  ]);

  /// An amount, as a decimal string with the currency's own number of places.
  ///
  /// Straight from minor units by string surgery — 4500 becomes "45.00" — so
  /// no amount in this file ever passes through a binary float. The string
  /// produced here is both what is hashed and what is sent, because they come
  /// from the same tree.
  static EtaText _money(Money value) {
    final negative = value.minor < 0;
    final digits = value.minor.abs().toString().padLeft(
      value.exponent + 1,
      '0',
    );
    final whole = digits.substring(0, digits.length - value.exponent);
    final fraction = value.exponent == 0
        ? ''
        : '.${digits.substring(digits.length - value.exponent)}';
    return EtaText('${negative ? '-' : ''}$whole$fraction');
  }

  /// A rate in basis points as a percentage: 1400 → "14", 1450 → "14.5".
  static String _rate(int basisPoints) {
    if (basisPoints % 100 == 0) return '${basisPoints ~/ 100}';
    final whole = basisPoints ~/ 100;
    final fraction = (basisPoints % 100).toString().padLeft(2, '0');
    return '$whole.${fraction.endsWith('0') ? fraction[0] : fraction}';
  }

  /// UTC, to the second, with the `Z` ETA expects.
  static String _timestamp(DateTime at) {
    final utc = at.toUtc();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${utc.year}-${two(utc.month)}-${two(utc.day)}T'
        '${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}Z';
  }

  static String? _some(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
}
