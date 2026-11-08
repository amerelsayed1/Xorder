import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/domain/models/receipt_profile.dart';

/// Who the receipt says sold the food.
///
/// The interesting property is not the validation, it is that there are **two**
/// validations. A business with a name can print; a business that can print
/// still cannot necessarily file. Collapsing those into one rule would either
/// stop a till trading over an address field or let a receipt reach the tax
/// authority with a nine-digit number that has eight digits in it.
void main() {
  ReceiptProfile filable({
    String rin = '123456789',
    String activity = '5610',
    String branchCode = 'B1',
    String country = 'EG',
  }) => ReceiptProfile(
    branchId: 1,
    tradeName: 'Koshari Abou Tarek',
    registrationNumber: rin,
    activityCode: activity,
    branchCode: branchCode,
    address: BranchAddress(
      country: country,
      governate: 'Cairo',
      regionCity: 'Downtown',
      street: 'Champollion',
      buildingNumber: '16',
    ),
  );

  group('printing', () {
    test('a name is all it takes', () {
      const profile = ReceiptProfile(branchId: 1, tradeName: 'Koshari');
      expect(profile.canPrint, isTrue);
    });

    test('a nameless profile cannot print', () {
      const profile = ReceiptProfile(branchId: 1);
      expect(profile.canPrint, isFalse);
      expect(profile.printProblems.single.field, ProfileField.tradeName);
    });

    test('a whitespace name is not a name', () {
      const profile = ReceiptProfile(branchId: 1, tradeName: '   ');
      expect(profile.canPrint, isFalse);
    });

    test('an address prints only the parts that are filled in', () {
      const address = BranchAddress(
        governate: 'Cairo',
        street: 'Champollion',
      );
      // No empty commas where the building number and city should be.
      expect(address.printed, 'Champollion, Cairo');
    });

    test('an empty address prints as nothing, not as punctuation', () {
      expect(const BranchAddress().printed, isEmpty);
    });
  });

  group('filing', () {
    test('a complete profile can be filed', () {
      expect(filable().canFile, isTrue);
      expect(filable().filingProblems, isEmpty);
    });

    test('printing is a subset of filing, not a separate list', () {
      // A profile that cannot print certainly cannot file, and the missing
      // name has to appear in both lists or the ETA block would say "ready"
      // for a receipt with no seller on it.
      const profile = ReceiptProfile(branchId: 1);
      expect(
        profile.filingProblems.map((p) => p.field),
        contains(ProfileField.tradeName),
      );
    });

    test('a registration number is nine digits, not eight and not ten', () {
      expect(filable(rin: '12345678').canFile, isFalse);
      expect(filable(rin: '1234567890').canFile, isFalse);
      expect(filable(rin: '123456789').canFile, isTrue);
    });

    test('a registration number with a letter in it is refused', () {
      // Arabic-Indic digits included: they are not what goes on the wire.
      expect(filable(rin: '12345678A').canFile, isFalse);
      expect(filable(rin: '١٢٣٤٥٦٧٨٩').canFile, isFalse);
    });

    test('an activity code is four digits', () {
      expect(filable(activity: '561').canFile, isFalse);
      expect(filable(activity: '56100').canFile, isFalse);
      expect(filable(activity: '5610').canFile, isTrue);
    });

    test('a country is two letters', () {
      expect(filable(country: 'EGY').canFile, isFalse);
      expect(filable(country: '').canFile, isFalse);
    });

    test('a missing branch code is named', () {
      final problems = filable(branchCode: '').filingProblems;
      expect(problems.single.field, ProfileField.branchCode);
    });

    test('each missing address part names itself', () {
      const profile = ReceiptProfile(
        branchId: 1,
        tradeName: 'Koshari',
        registrationNumber: '123456789',
        activityCode: '5610',
        branchCode: 'B1',
      );
      expect(
        profile.filingProblems.map((p) => p.field),
        containsAll(<String>[
          ProfileField.governate,
          ProfileField.regionCity,
          ProfileField.street,
          ProfileField.buildingNumber,
        ]),
      );
    });

    test('a filable profile can still print — the two never disagree', () {
      expect(filable().canPrint, isTrue);
    });
  });

  group('blank', () {
    test('a fresh branch knows it has never been set up', () {
      // The pane says "not set up yet" rather than "seven problems", which is
      // a different and much less alarming sentence on day one.
      expect(const ReceiptProfile(branchId: 1).isBlank, isTrue);
    });

    test('a half-typed profile is not blank', () {
      const profile = ReceiptProfile(branchId: 1, tradeName: 'Koshari');
      expect(profile.isBlank, isFalse);
      expect(profile.canFile, isFalse);
    });

    test('the country default does not make a profile look started', () {
      // 'EG' is a default, not something somebody typed.
      expect(const ReceiptProfile(branchId: 1).address.country, 'EG');
      expect(const ReceiptProfile(branchId: 1).isBlank, isTrue);
    });
  });

  test('copyWith keeps the branch it belongs to', () {
    // The branch is identity, not a field: a profile that could be copied onto
    // another branch would file one branch's address under another's code.
    final moved = filable().copyWith(tradeName: 'Elsewhere');
    expect(moved.branchId, 1);
  });
}
