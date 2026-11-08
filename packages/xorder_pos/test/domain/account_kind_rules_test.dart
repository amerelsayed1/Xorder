import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/domain/models/financial_account.dart';
import 'package:xorder_pos/domain/models/tender_method.dart';

/// Which accounts a payment method may pay into, by kind
/// (finance-account-kind-per-method, 26 Oct 2026).
///
/// The cloud holds the same pairing over the platform's vocabulary
/// (`FinancialAccountsTest` there); [platform] below is that table, and the two
/// must say the same for every kind the two share.
void main() {
  FinancialAccount account(
    AccountKind kind, {
    int? branchId,
    bool active = true,
  }) => FinancialAccount(
    id: 1,
    name: 'A',
    kind: kind,
    branchId: branchId,
    isActive: active,
  );

  group('the pairing table', () {
    // method kind → the account kinds it may pay into; null = any.
    const expected = <TenderKind, Set<AccountKind>?>{
      TenderKind.cash: {AccountKind.cash},
      TenderKind.card: {AccountKind.bank},
      TenderKind.wallet: {AccountKind.wallet},
      TenderKind.account: null,
      TenderKind.voucher: null,
      TenderKind.other: null,
    };

    test('every method kind is covered, and says what it says', () {
      expect(expected.keys.toSet(), TenderKind.values.toSet());
      for (final entry in expected.entries) {
        expect(
          AccountRules.kindsFor(entry.key),
          entry.value,
          reason: '${entry.key}',
        );
      }
    });

    for (final method in TenderKind.values) {
      for (final kind in AccountKind.values) {
        final allowed = expected[method]?.contains(kind) ?? true;
        test('$method → $kind is ${allowed ? 'offered' : 'refused'}', () {
          expect(AccountRules.fits(method, kind), allowed);
          expect(
            AccountRules.defaultProblem(
              account(kind),
              branchId: null,
              method: method,
            ),
            allowed ? isNull : AccountProblem.accountKindMismatch,
          );
        });
      }
    }
  });

  group('the platform\'s vocabulary, read the way the till reads it', () {
    // `external` is a card taken on the bank's own terminal (PlatformTenderKind
    // .tillKind), so it pays into a bank, exactly as Card does; `wallet` is the
    // same kind on both sides.
    const platform = <PlatformTenderKind, Set<AccountKind>?>{
      PlatformTenderKind.cash: {AccountKind.cash},
      PlatformTenderKind.card: {AccountKind.bank},
      PlatformTenderKind.wallet: {AccountKind.wallet},
      PlatformTenderKind.external: {AccountKind.bank},
      PlatformTenderKind.other: null,
    };

    test('each platform kind pairs as its till kind does', () {
      expect(platform.keys.toSet(), PlatformTenderKind.values.toSet());
      for (final entry in platform.entries) {
        expect(
          AccountRules.kindsFor(entry.key.tillKind),
          entry.value,
          reason: '${entry.key}',
        );
      }
    });
  });

  group('the other rules still come first', () {
    test('a switched-off account is unavailable, whatever its kind', () {
      expect(
        AccountRules.defaultProblem(
          account(AccountKind.cash, active: false),
          branchId: null,
          method: TenderKind.card,
        ),
        AccountProblem.accountUnavailable,
      );
    });

    test(
      'another branch\'s drawer is the branch problem, not the kind one',
      () {
        expect(
          AccountRules.defaultProblem(
            account(AccountKind.cash, branchId: 10),
            branchId: 11,
            method: TenderKind.card,
          ),
          AccountProblem.accountOfAnotherBranch,
        );
      },
    );
  });
}
