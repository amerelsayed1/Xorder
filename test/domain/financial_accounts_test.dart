import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/domain/models/financial_account.dart';
import 'package:xorder_pos/domain/models/permissions.dart';

/// Financial accounts, stage 1 (XORD-015): the rules both the cloud and the
/// offline till apply, and the permission that guards authoring them.
void main() {
  const shared = FinancialAccount(
    id: 1,
    name: 'Company bank',
    kind: AccountKind.bank,
  );
  const maadiDrawer = FinancialAccount(
    id: 2,
    name: 'Maadi drawer',
    kind: AccountKind.cash,
    branchId: 10,
  );
  const off = FinancialAccount(
    id: 3,
    name: 'Old wallet',
    kind: AccountKind.wallet,
    isActive: false,
  );

  group('kinds', () {
    test('are cash, bank and wallet, by the platform\'s words', () {
      expect([for (final k in AccountKind.values) k.wire], [
        'cash',
        'bank',
        'wallet',
      ]);
      expect(AccountKind.fromWire('bank'), AccountKind.bank);
    });

    test('a word this build does not know is null, not guessed', () {
      expect(AccountKind.fromWire('crypto'), isNull);
      expect(AccountKind.fromWire(null), isNull);
    });
  });

  group('which account may be a default', () {
    test('an active shared account may serve any branch and the whole business',
        () {
      expect(AccountRules.defaultProblem(shared, branchId: null), isNull);
      expect(AccountRules.defaultProblem(shared, branchId: 10), isNull);
      expect(AccountRules.defaultProblem(shared, branchId: 99), isNull);
    });

    test('a branch\'s own account serves that branch and no other', () {
      expect(AccountRules.defaultProblem(maadiDrawer, branchId: 10), isNull);
      expect(
        AccountRules.defaultProblem(maadiDrawer, branchId: 11),
        AccountProblem.accountOfAnotherBranch,
      );
    });

    test('a branch\'s own account cannot be the business-wide fallback', () {
      expect(
        AccountRules.defaultProblem(maadiDrawer, branchId: null),
        AccountProblem.accountOfAnotherBranch,
      );
    });

    test('a switched-off account is never a default', () {
      expect(
        AccountRules.defaultProblem(off, branchId: null),
        AccountProblem.accountUnavailable,
      );
    });
  });

  group('the account a method pays into at a branch', () {
    const rows = [
      TenderAccountDefault(tenderTypeId: 5, accountId: 1),
      TenderAccountDefault(tenderTypeId: 5, branchId: 10, accountId: 2),
      TenderAccountDefault(tenderTypeId: 6, accountId: 1),
    ];

    test('is the branch\'s own row when there is one', () {
      expect(
        AccountRules.effectiveAccountId(rows, tenderTypeId: 5, branchId: 10),
        2,
      );
    });

    test('falls back to the business-wide row', () {
      expect(
        AccountRules.effectiveAccountId(rows, tenderTypeId: 5, branchId: 11),
        1,
      );
      expect(
        AccountRules.effectiveAccountId(rows, tenderTypeId: 5, branchId: null),
        1,
      );
    });

    test('is none for a method that has no row at all', () {
      expect(
        AccountRules.effectiveAccountId(rows, tenderTypeId: 7, branchId: 10),
        isNull,
      );
    });
  });

  group('the reference', () {
    test('a short label is fine', () {
      for (final label in ['CIB 4521', 'Maadi', '•••• 4521', null, '']) {
        expect(AccountRules.referenceLooksLikeNumber(label), isFalse, reason: '$label');
      }
    });

    test('nine or more digits, however spaced, is an account number', () {
      for (final number in [
        '123456789',
        '1234 5678 9012',
        '1234-5678-9012-3456',
        '1234.5678.9012',
        '1234/5678/9012',
        'EG38 0019 0005 0000 0000 2631 8000 2',
      ]) {
        expect(AccountRules.referenceLooksLikeNumber(number), isTrue, reason: number);
      }
    });
  });

  group('a number in another script is still a number', () {
    // Arabic-Indic, Eastern Arabic-Indic and full-width digits: the keyboard of
    // the people this till is sold to.
    test('in the reference and in the name', () {
      for (final number in ['٠١٢٣٤٥٦٧٨٩٠١', '۱۲۳۴۵۶۷۸۹۰', '１２３４５６７８９０']) {
        expect(AccountRules.referenceLooksLikeNumber(number), isTrue, reason: number);
        expect(AccountRules.looksLikeNumber(number), isTrue, reason: number);
      }
    });

    test('an Arabic name, or a few Arabic digits, is not', () {
      expect(AccountRules.looksLikeNumber('حساب البنك الأهلي'), isFalse);
      expect(AccountRules.referenceLooksLikeNumber('آخر أربعة ٤٥٢١'), isFalse);
    });
  });

  group('the permission', () {
    test('is the platform\'s string, verbatim', () {
      // A cloud till gets roles from the bundle untouched, so the two sides
      // must spell it the same.
      expect(PosCapability.financeAccounts, 'finance.accounts');
    });

    test('is registered, classified and kept off the cashier', () {
      expect(PosCapability.all, contains(PosCapability.financeAccounts));
      expect(PosCapability.isClassified(PosCapability.financeAccounts), isTrue);
      expect(PosCapability.backOffice, contains(PosCapability.financeAccounts));
      expect(
        CapabilityGroup.values.where(
          (g) => g.capabilities.contains(PosCapability.financeAccounts),
        ),
        hasLength(1),
      );
    });

    test('the owner holds it and nobody else does by default', () {
      expect(SystemRoles.owner, contains(PosCapability.financeAccounts));
      expect(SystemRoles.manager, isNot(contains(PosCapability.financeAccounts)));
      expect(SystemRoles.supervisor, isNot(contains(PosCapability.financeAccounts)));
      expect(SystemRoles.cashier, isNot(contains(PosCapability.financeAccounts)));
    });

    test('is not a supervisor override: it cannot be lent for a moment', () {
      expect(PosCapability.overridable, isNot(contains(PosCapability.financeAccounts)));
    });
  });
}
