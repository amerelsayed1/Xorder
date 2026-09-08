/// Who the receipt says sold the food.
///
/// **This is one thing wearing two hats, on purpose.** The top of a printed
/// slip and the `seller` block of an Egyptian e-receipt are the same facts —
/// trade name, tax registration number, branch, address — and a restaurant
/// asked to type them twice will eventually type them differently. So they are
/// entered once, in Management, and both the paper and the filing read them
/// from here.
///
/// The field names lean towards the ETA vocabulary (`rin`, `activityCode`,
/// `governate` — including that spelling, which is theirs) rather than towards
/// prettier English, because the one place a mismatch costs real money is the
/// submission, and a name that reads oddly in Dart is cheaper than a mapping
/// table nobody maintains.
library;

/// A branch address, in the shape Egypt's tax authority asks for.
class BranchAddress {
  const BranchAddress({
    this.country = 'EG',
    this.governate = '',
    this.regionCity = '',
    this.street = '',
    this.buildingNumber = '',
    this.postalCode,
    this.floor,
    this.room,
    this.landmark,
    this.additionalInformation,
  });

  /// ISO 3166-1 alpha-2. Defaults to Egypt rather than to empty, because a
  /// blank country is never the right answer and 'EG' is right for every till
  /// this product will run on before it is right for none.
  final String country;

  /// ETA's spelling, not "governorate". Theirs is the one on the wire.
  final String governate;
  final String regionCity;
  final String street;
  final String buildingNumber;
  final String? postalCode;
  final String? floor;
  final String? room;
  final String? landmark;
  final String? additionalInformation;

  /// The one-line form, for the top of a printed slip.
  ///
  /// Empty parts are dropped rather than printed as gaps, so a restaurant that
  /// has filled in half of this still gets a sensible header.
  String get printed => [
    if (buildingNumber.trim().isNotEmpty) buildingNumber.trim(),
    if (street.trim().isNotEmpty) street.trim(),
    if (regionCity.trim().isNotEmpty) regionCity.trim(),
    if (governate.trim().isNotEmpty) governate.trim(),
  ].join(', ');

  BranchAddress copyWith({
    String? country,
    String? governate,
    String? regionCity,
    String? street,
    String? buildingNumber,
    String? postalCode,
    String? floor,
    String? room,
    String? landmark,
    String? additionalInformation,
  }) => BranchAddress(
    country: country ?? this.country,
    governate: governate ?? this.governate,
    regionCity: regionCity ?? this.regionCity,
    street: street ?? this.street,
    buildingNumber: buildingNumber ?? this.buildingNumber,
    postalCode: postalCode ?? this.postalCode,
    floor: floor ?? this.floor,
    room: room ?? this.room,
    landmark: landmark ?? this.landmark,
    additionalInformation: additionalInformation ?? this.additionalInformation,
  );
}

/// One thing wrong with a profile, and which field it is wrong on.
///
/// Carries the field rather than a sentence so the pane can put the message
/// under the box it belongs to. A list of complaints at the bottom of a form
/// with fourteen inputs is a list nobody reads twice.
class ProfileProblem {
  const ProfileProblem(this.field, this.message);

  final String field;
  final String message;
}

/// Fields, as [ProfileProblem.field] names them.
abstract final class ProfileField {
  static const tradeName = 'trade_name';
  static const registrationNumber = 'registration_number';
  static const activityCode = 'activity_code';
  static const branchCode = 'branch_code';
  static const country = 'country';
  static const governate = 'governate';
  static const regionCity = 'region_city';
  static const street = 'street';
  static const buildingNumber = 'building_number';
}

class ReceiptProfile {
  const ReceiptProfile({
    required this.branchId,
    this.tradeName = '',
    this.registrationNumber = '',
    this.activityCode = '',
    this.branchCode = '',
    this.address = const BranchAddress(),
    this.phone,
    this.headerNote,
    this.footerNote,
    this.revision = 0,
  });

  final int branchId;

  /// `companyTradeName` on the wire, and the first line of the slip.
  final String tradeName;

  /// The taxpayer's registration number — ETA's `rin`. Nine digits in Egypt.
  final String registrationNumber;

  /// ETA's activity code for what this branch sells. Four digits, from their
  /// published list; this validates the shape and not the membership, because
  /// the list changes and a till that refused a newly issued code would be
  /// wrong in the direction that stops a restaurant trading.
  final String activityCode;

  /// The branch as ETA knows it, which is **not** [pos_branches.code]: that
  /// one is the invoice prefix and a restaurant is free to choose it. Keeping
  /// them apart costs one text box and saves the day somebody renames a
  /// prefix.
  final String branchCode;

  final BranchAddress address;

  /// Printed. Not sent — ETA's seller block has nowhere to put it.
  final String? phone;

  /// Free text above the items and below the totals. A thank-you, a wifi
  /// password, an offer.
  final String? headerNote;
  final String? footerNote;

  /// Bumped on every save, and checked on the next one. Two managers on two
  /// tills editing the same profile is not hypothetical in a restaurant with
  /// an office and a counter.
  final int revision;

  /// What must be fixed before this can be printed on a slip.
  ///
  /// Deliberately short: a restaurant that has typed its name can print
  /// receipts, and should not be blocked from trading by an address field it
  /// has not got to yet.
  List<ProfileProblem> get printProblems => [
    if (tradeName.trim().isEmpty)
      const ProfileProblem(ProfileField.tradeName, 'A receipt needs a name.'),
  ];

  /// What must be fixed before a receipt can be filed with ETA.
  ///
  /// Longer, and separate from [printProblems] on purpose. The two audiences
  /// are different: the first is a customer holding a piece of paper, the
  /// second is a tax authority that will reject the submission and give back a
  /// property path. Answering the second one here, before anything is sent, is
  /// the difference between a settings screen and a queue full of rejections.
  List<ProfileProblem> get filingProblems => [
    ...printProblems,
    if (!_digits(registrationNumber, 9))
      const ProfileProblem(
        ProfileField.registrationNumber,
        'A tax registration number is nine digits.',
      ),
    if (!_digits(activityCode, 4))
      const ProfileProblem(
        ProfileField.activityCode,
        'An activity code is four digits.',
      ),
    if (branchCode.trim().isEmpty)
      const ProfileProblem(
        ProfileField.branchCode,
        'The branch needs the code it is registered under.',
      ),
    if (address.country.trim().length != 2)
      const ProfileProblem(
        ProfileField.country,
        'A country is a two-letter code.',
      ),
    if (address.governate.trim().isEmpty)
      const ProfileProblem(ProfileField.governate, 'A governorate is required.'),
    if (address.regionCity.trim().isEmpty)
      const ProfileProblem(ProfileField.regionCity, 'A city is required.'),
    if (address.street.trim().isEmpty)
      const ProfileProblem(ProfileField.street, 'A street is required.'),
    if (address.buildingNumber.trim().isEmpty)
      const ProfileProblem(
        ProfileField.buildingNumber,
        'A building number is required.',
      ),
  ];

  /// Enough to print.
  bool get canPrint => printProblems.isEmpty;

  /// Enough to file. The e-receipt wave gates submission on this.
  bool get canFile => filingProblems.isEmpty;

  /// Nothing has been entered at all — a fresh install, not a bad one.
  ///
  /// Worth its own question because the pane says something different: "set
  /// this up" rather than "seven problems".
  bool get isBlank =>
      tradeName.trim().isEmpty &&
      registrationNumber.trim().isEmpty &&
      branchCode.trim().isEmpty &&
      address.street.trim().isEmpty;

  static bool _digits(String value, int length) {
    final trimmed = value.trim();
    return trimmed.length == length &&
        trimmed.codeUnits.every((c) => c >= 0x30 && c <= 0x39);
  }

  ReceiptProfile copyWith({
    String? tradeName,
    String? registrationNumber,
    String? activityCode,
    String? branchCode,
    BranchAddress? address,
    String? phone,
    String? headerNote,
    String? footerNote,
    int? revision,
  }) => ReceiptProfile(
    branchId: branchId,
    tradeName: tradeName ?? this.tradeName,
    registrationNumber: registrationNumber ?? this.registrationNumber,
    activityCode: activityCode ?? this.activityCode,
    branchCode: branchCode ?? this.branchCode,
    address: address ?? this.address,
    phone: phone ?? this.phone,
    headerNote: headerNote ?? this.headerNote,
    footerNote: footerNote ?? this.footerNote,
    revision: revision ?? this.revision,
  );
}
