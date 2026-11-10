import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos_cloud/data/cloud/bootstrap_bundle.dart';
import 'package:shared_module/domain/models/financial_account.dart';

/// Reading `money.financial_accounts` and `money.tender_account_defaults` out
/// of the bundle (XORD-015, stage 1). A PROPOSED contract: the cloud sends the
/// keys; an older cloud sends neither, and the till must carry on.
void main() {
  BootstrapBundle bundle(Map<String, Object?> money) =>
      BootstrapBundle(configVersion: 1, money: money);

  group('accounts', () {
    test('are read with every field the platform sends', () {
      final accounts = bundle({
        'financial_accounts': [
          {
            'id': 7,
            'name': 'CIB main',
            'kind': 'bank',
            'currency': 'EGP',
            'branch_id': null,
            'reference_label': 'CIB 4521',
            'is_active': true,
            'sort_order': 2,
          },
          {'id': 8, 'name': 'Maadi drawer', 'kind': 'cash', 'branch_id': 10},
        ],
      }).financialAccounts;

      expect(accounts.map((a) => a.id), [7, 8]);
      expect(accounts[0].kind, AccountKind.bank);
      expect(accounts[0].currency, 'EGP');
      expect(accounts[0].branchId, isNull);
      expect(accounts[0].referenceLabel, 'CIB 4521');
      expect(accounts[0].sortOrder, 2);
      expect(accounts[1].branchId, 10);
      expect(accounts[1].isActive, isTrue, reason: 'absent means active');
    });

    test('a row this build cannot hold is skipped, never guessed', () {
      final accounts = bundle({
        'financial_accounts': [
          {'id': 1, 'name': 'Crypto', 'kind': 'crypto'},
          {'id': 2, 'name': '   ', 'kind': 'cash'},
          {'name': 'No id', 'kind': 'cash'},
          {'id': 3, 'kind': 'cash'},
          'not a map',
          {'id': 4, 'name': 'Fine', 'kind': 'wallet'},
        ],
      }).financialAccounts;

      expect(accounts.map((a) => a.id), [4]);
    });

    test('a numeric string id is tolerated, a double is not', () {
      final accounts = bundle({
        'financial_accounts': [
          {'id': '9', 'name': 'Wallet', 'kind': 'wallet'},
          {'id': 9.5, 'name': 'Half', 'kind': 'cash'},
        ],
      }).financialAccounts;

      expect(accounts.map((a) => a.id), [9]);
    });
  });

  group('absent is not the same as empty', () {
    test('a platform that predates accounts sends neither key', () {
      final old = bundle({'tender_types': const []});

      expect(old.sendsFinancialAccounts, isFalse);
      expect(old.sendsTenderAccountDefaults, isFalse);
      expect(old.financialAccounts, isEmpty);
      expect(old.tenderAccountDefaults, isEmpty);
    });

    test('a platform that sends an empty list says the business has none', () {
      final none = bundle({
        'financial_accounts': const [],
        'tender_account_defaults': const [],
      });

      expect(none.sendsFinancialAccounts, isTrue);
      expect(none.sendsTenderAccountDefaults, isTrue);
    });

    test('nonsense in the key is neither: it is ignored', () {
      final odd = bundle({'financial_accounts': 'nonsense'});

      expect(odd.sendsFinancialAccounts, isFalse);
      expect(odd.financialAccounts, isEmpty);
    });

    test('a bundle with no money block at all does not throw', () {
      const empty = BootstrapBundle(configVersion: 1);

      expect(empty.sendsFinancialAccounts, isFalse);
      expect(empty.financialAccounts, isEmpty);
    });
  });

  group('defaults', () {
    test('are read as platform ids, with a null branch meaning the business', () {
      final defaults = bundle({
        'tender_account_defaults': [
          {'tender_type_id': 5, 'branch_id': null, 'financial_account_id': 7},
          {'tender_type_id': 5, 'branch_id': 10, 'financial_account_id': 8},
        ],
      }).tenderAccountDefaults;

      expect(defaults.length, 2);
      expect(defaults[0].branchId, isNull);
      expect(defaults[0].tenderTypeId, 5);
      expect(defaults[0].accountId, 7);
      expect(defaults[1].branchId, 10);
    });

    test('a row missing either id is dropped', () {
      final defaults = bundle({
        'tender_account_defaults': [
          {'tender_type_id': 5},
          {'financial_account_id': 7},
          {'tender_type_id': 5, 'financial_account_id': 7},
        ],
      }).tenderAccountDefaults;

      expect(defaults.length, 1);
    });
  });

  test('the existing payment methods parse exactly as before', () {
    // The new keys sit beside `tender_types` and must not disturb it.
    final b = bundle({
      'tender_types': [
        {'id': 1, 'name': 'Cash', 'kind': 'cash'},
      ],
      'financial_accounts': const [],
    });

    expect(b.tenderTypes.single.name, 'Cash');
  });
}
