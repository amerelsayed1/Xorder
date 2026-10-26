@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/data/cloud/bootstrap_bundle.dart';
import 'package:xorder_pos/data/cloud/bootstrap_seeder.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/data/postgres/postgres_financial_accounts_admin_repository.dart';
import 'package:xorder_pos/data/postgres/postgres_financial_accounts_repository.dart';
import 'package:xorder_pos/domain/models/financial_account.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/repositories/admin_repositories.dart';

import 'pg_fixture.dart';

/// Financial accounts, stage 1 (XORD-015), against a real PostgreSQL.
///
/// What is proved here is the part a unit test cannot see: the constraints the
/// migration adds, the owner getting the key on an existing install, an offline
/// till authoring accounts and the account each payment method pays into, and a
/// cloud till seeding the platform's accounts without ever deleting one.
void main() {
  if (PgFixture.host == null) {
    test('financial accounts (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  late PgFixture pg;
  late PosDatabase db;
  late int restaurantId;
  late int branchId;
  late int cashId;
  late int cardId;

  PosStaff holder(Set<String> capabilities) => PosStaff(
    id: 1,
    name: 'Amer M.',
    role: PosRole(id: 1, code: 'x', nameEn: 'X', capabilities: capabilities),
  );
  final owner = holder({PosCapability.financeAccounts});
  final cashier = holder({PosCapability.operate});

  setUp(() async {
    pg = await PgFixture.open('financial_accounts');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await pg.truncate();
    await db.query(pg.config, 'DELETE FROM pos_restaurants');

    restaurantId = (await db.query(
      pg.config,
      "INSERT INTO pos_restaurants (slug, name) VALUES ('fa', 'Accounts') "
      'RETURNING id',
    )).first[0]! as int;
    branchId = (await db.query(
      pg.config,
      "INSERT INTO pos_branches (restaurant_id, code, name) "
      "VALUES (@r, 'MAIN', 'Main') RETURNING id",
      parameters: {'r': restaurantId},
    )).first[0]! as int;
    final ids = await db.query(
      pg.config,
      "INSERT INTO pos_tender_types (restaurant_id, code, name_en, kind, "
      "  counts_as_cash, opens_drawer, sort_order) VALUES "
      "(@r, 'cash', 'Cash', 'cash', true, true, 1), "
      "(@r, 'card', 'Card', 'card', false, false, 2) RETURNING id",
      parameters: {'r': restaurantId},
    );
    cashId = ids[0][0]! as int;
    cardId = ids[1][0]! as int;
  });

  tearDown(() => pg.close());

  PostgresFinancialAccountsAdminRepository admin({
    bool offline = true,
    bool adminAvailable = true,
    int? onRestaurant,
  }) => PostgresFinancialAccountsAdminRepository(
    database: db,
    config: pg.config,
    restaurantId: onRestaurant ?? restaurantId,
    branchId: branchId,
    offline: offline,
    adminAvailable: adminAvailable,
  );

  PostgresFinancialAccountsRepository reader({int? onRestaurant}) =>
      PostgresFinancialAccountsRepository(
        database: db,
        config: pg.config,
        restaurantId: onRestaurant ?? restaurantId,
      );

  FinancialAccount draft({
    String name = 'Company bank',
    AccountKind kind = AccountKind.bank,
    int? branch,
    String? reference,
    bool active = true,
    int id = 0,
  }) => FinancialAccount(
    id: id,
    name: name,
    kind: kind,
    branchId: branch,
    referenceLabel: reference,
    isActive: active,
  );

  Future<FinancialAccount> save(FinancialAccount a) async {
    final result = await admin().saveAccount(a, by: owner);
    expect(result.refusal, isNull, reason: '${result.refusal}');
    return result.value!;
  }

  Future<List<String>> audit() async => [
    for (final row in await db.query(
      pg.config,
      'SELECT action FROM pos_audit_events WHERE restaurant_id = @r '
      "AND action IN ('financial_account.saved', 'tender_account_default.saved') "
      'ORDER BY id',
      parameters: {'r': restaurantId},
    ))
      row[0]! as String,
  ];

  group('the schema', () {
    test('an account has one of three kinds, and a name', () async {
      Future<void> insert(String name, String kind) => db.query(
        pg.config,
        'INSERT INTO pos_financial_accounts (restaurant_id, name, kind) '
        'VALUES (@r, @n, @k)',
        parameters: {'r': restaurantId, 'n': name, 'k': kind},
      );

      await expectLater(insert('Bad', 'crypto'), throwsA(anything));
      await expectLater(insert('   ', 'cash'), throwsA(anything));
      await insert('Fine', 'wallet');
    });

    test('a payment method has one default per branch, and one for the business',
        () async {
      final account = await save(draft());

      Future<void> insert(int? branch) => db.query(
        pg.config,
        'INSERT INTO pos_tender_account_defaults (restaurant_id, '
        '  tender_type_id, branch_id, branch_key, financial_account_id) '
        'VALUES (@r, @t, @b, @k, @a)',
        parameters: {
          'r': restaurantId,
          't': cardId,
          'b': branch,
          'k': branch ?? 0,
          'a': account.id,
        },
      );

      await insert(null);
      // The business-wide row is unique even though its branch is NULL — the
      // whole reason `branch_key` exists.
      await expectLater(insert(null), throwsA(anything));
      await insert(branchId);
      await expectLater(insert(branchId), throwsA(anything));
    });

    test('the key always agrees with the branch', () async {
      final account = await save(draft());
      await expectLater(
        db.query(
          pg.config,
          'INSERT INTO pos_tender_account_defaults (restaurant_id, '
          '  tender_type_id, branch_id, branch_key, financial_account_id) '
          'VALUES (@r, @t, NULL, 7, @a)',
          parameters: {'r': restaurantId, 't': cardId, 'a': account.id},
        ),
        throwsA(anything),
      );
    });

    test('an account cannot be deleted while a default points at it', () async {
      final account = await save(draft());
      await admin().setDefault(
        tenderTypeId: cardId,
        branchId: null,
        accountId: account.id,
        by: owner,
      );
      await expectLater(
        db.query(
          pg.config,
          'DELETE FROM pos_financial_accounts WHERE id = @a',
          parameters: {'a': account.id},
        ),
        throwsA(anything),
      );
    });
  });

  group('migration 60', () {
    Future<List<String>> held(String code) async => ((await db.query(
      pg.config,
      'SELECT capabilities FROM pos_roles WHERE restaurant_id = @r AND code = @c',
      parameters: {'r': restaurantId, 'c': code},
    )).first[0]! as List).cast<String>();

    Future<void> role(String code, Set<String> capabilities) => db.query(
      pg.config,
      'INSERT INTO pos_roles (restaurant_id, code, name_en, name_ar, '
      '  capabilities, is_system) VALUES (@r, @c, @c, @c, @caps, false)',
      parameters: {'r': restaurantId, 'c': code, 'caps': capabilities.toList()},
    );

    Future<List<int>> rerun() async {
      await db.query(pg.config, 'DELETE FROM schema_migrations WHERE version = 60');
      return PosMigrator(db).migrate(pg.config);
    }

    test('the owner is given the key, and nobody else', () async {
      await role('owner', {PosCapability.operate, PosCapability.settingsManage});
      await role('manager', {PosCapability.operate, PosCapability.settingsManage});

      expect(await rerun(), [60]);
      expect(await held('owner'), contains(PosCapability.financeAccounts));
      expect(await held('manager'), isNot(contains(PosCapability.financeAccounts)));
    });

    test('nothing is taken away, and running it again adds it once', () async {
      await role('owner', {PosCapability.operate});
      await rerun();
      await rerun();

      final owner = await held('owner');
      expect(owner.where((c) => c == PosCapability.financeAccounts), hasLength(1));
      expect(owner, contains(PosCapability.operate));
    });

    test('re-running the tables is harmless and loses no account', () async {
      await save(draft());
      await rerun();

      expect(await reader().accounts(), hasLength(1));
    });
  });

  group('an offline till authors accounts', () {
    test('the owner adds one; it is stored trimmed and shared by default',
        () async {
      final saved = await save(draft(name: '  Company bank  ', reference: 'CIB 4521'));

      expect(saved.id, greaterThan(0));
      expect(saved.name, 'Company bank');
      expect(saved.branchId, isNull);
      expect(saved.referenceLabel, 'CIB 4521');
      expect(saved.currency, isNull, reason: 'nothing offline knows it');
      expect(await audit(), ['financial_account.saved']);
    });

    test('and nothing is queued for the cloud: it is this location\'s alone',
        () async {
      Future<int> queued() async => (await db.query(
        pg.config,
        'SELECT count(*) FROM pos_outbox',
      )).first[0]! as int;

      final before = await queued();
      final bank = await save(draft());
      await admin().setDefault(
        tenderTypeId: cardId,
        branchId: null,
        accountId: bank.id,
        by: owner,
      );

      expect(await queued(), before);
    });

    test('an account can be tied to the branch, and renamed and switched off',
        () async {
      final saved = await save(draft(name: 'Drawer', kind: AccountKind.cash, branch: branchId));
      expect(saved.branchId, branchId);

      final renamed = await save(
        draft(id: saved.id, name: 'Main drawer', kind: AccountKind.cash, branch: branchId),
      );
      expect(renamed.name, 'Main drawer');

      final off = await save(
        draft(id: saved.id, name: 'Main drawer', kind: AccountKind.cash, branch: branchId, active: false),
      );
      expect(off.isActive, isFalse);
      expect(await reader().accounts(), isEmpty);
      expect(await reader().accounts(includeInactive: true), hasLength(1));
    });

    test('is refused to a cashier, on a cloud till, and without the credential',
        () async {
      for (final (repo, by) in [
        (admin(), cashier),
        (admin(offline: false), owner),
      ]) {
        final result = await repo.saveAccount(draft(), by: by);
        expect(result.refusal, isA<NotPermitted>());
      }
      final noCredential = await admin(adminAvailable: false).saveAccount(draft(), by: owner);
      expect(noCredential.refusal, isA<AdministratorCredentialRequired>());
      expect(await reader().accounts(includeInactive: true), isEmpty);
    });

    test('each rule is a refusal, not an exception', () async {
      await save(draft(name: 'Company bank'));

      Future<AccountProblem?> problem(FinancialAccount a) async {
        final refusal = (await admin().saveAccount(a, by: owner)).refusal;
        return refusal is AccountRefused ? refusal.problem : null;
      }

      expect(await problem(draft(name: '   ')), AccountProblem.nameMissing);
      expect(await problem(draft(name: 'company BANK')), AccountProblem.nameTaken);
      expect(
        await problem(draft(name: 'Other', reference: '1234 5678 9012')),
        AccountProblem.referenceLooksLikeNumber,
      );
      expect(
        await problem(draft(name: 'Other', reference: '٠١٢٣٤٥٦٧٨٩٠١')),
        AccountProblem.referenceLooksLikeNumber,
        reason: 'an Arabic-Indic number is a number',
      );
      expect(
        await problem(draft(name: '1234 5678 9012')),
        AccountProblem.nameLooksLikeNumber,
      );
      expect(await problem(draft(name: 'Other', branch: 99999)), AccountProblem.branchUnknown);
    });

    test('another restaurant\'s branch and accounts are not reachable', () async {
      final other = (await db.query(
        pg.config,
        "INSERT INTO pos_restaurants (slug, name) VALUES ('other', 'Other') RETURNING id",
      )).first[0]! as int;
      final theirBranch = (await db.query(
        pg.config,
        "INSERT INTO pos_branches (restaurant_id, code, name) "
        "VALUES (@r, 'X', 'X') RETURNING id",
        parameters: {'r': other},
      )).first[0]! as int;

      final result = await admin().saveAccount(draft(branch: theirBranch), by: owner);
      expect((result.refusal! as AccountRefused).problem, AccountProblem.branchUnknown);

      final theirs = (await admin(onRestaurant: other).saveAccount(draft(name: 'Theirs'), by: owner)).value!;
      expect(await reader().accounts(includeInactive: true), isEmpty);
      expect(await reader(onRestaurant: other).accounts(), hasLength(1));

      // Editing another restaurant's account by id is a lost row, not an edit.
      final edit = await admin().saveAccount(draft(id: theirs.id, name: 'Mine now'), by: owner);
      expect(edit.refusal, isA<EditedElsewhere>());
    });
  });

  group('the account a payment method pays into', () {
    test('is set, replaced and cleared as one row', () async {
      final bank = await save(draft(name: 'Bank'));
      final wallet = await save(draft(name: 'Wallet', kind: AccountKind.wallet));

      Future<void> set(int? account) async {
        final r = await admin().setDefault(
          tenderTypeId: cardId,
          branchId: null,
          accountId: account,
          by: owner,
        );
        expect(r.refusal, isNull, reason: '${r.refusal}');
      }

      await set(bank.id);
      await set(wallet.id);
      final rows = await reader().defaults();
      expect(rows, hasLength(1));
      expect(rows.single.accountId, wallet.id);
      expect(rows.single.branchId, isNull);

      await set(null);
      expect(await reader().defaults(), isEmpty);
      expect(
        await audit(),
        containsAllInOrder([
          'financial_account.saved',
          'financial_account.saved',
          'tender_account_default.saved',
          'tender_account_default.saved',
          'tender_account_default.saved',
        ]),
      );
    });

    test('a branch can have its own, beside the business-wide one', () async {
      final bank = await save(draft(name: 'Bank'));
      final drawer = await save(draft(name: 'Drawer', kind: AccountKind.cash, branch: branchId));

      await admin().setDefault(tenderTypeId: cashId, branchId: null, accountId: bank.id, by: owner);
      final branchRow = await admin().setDefault(
        tenderTypeId: cashId,
        branchId: branchId,
        accountId: drawer.id,
        by: owner,
      );
      expect(branchRow.refusal, isNull);

      final rows = await reader().defaults();
      expect(rows, hasLength(2));
      expect(
        AccountRules.effectiveAccountId(rows, tenderTypeId: cashId, branchId: branchId),
        drawer.id,
      );
      expect(
        AccountRules.effectiveAccountId(rows, tenderTypeId: cashId, branchId: null),
        bank.id,
      );
    });

    test('each rule is a refusal, and a refused default changes nothing', () async {
      final bank = await save(draft(name: 'Bank'));
      final drawer = await save(draft(name: 'Drawer', kind: AccountKind.cash, branch: branchId));
      final off = await save(draft(name: 'Old', active: false));

      Future<AccountProblem?> problem({
        int? tender,
        int? branch,
        int? account,
      }) async {
        final refusal = (await admin().setDefault(
          tenderTypeId: tender ?? cardId,
          branchId: branch,
          accountId: account,
          by: owner,
        )).refusal;
        return refusal is AccountRefused ? refusal.problem : null;
      }

      expect(await problem(tender: 99999, account: bank.id), AccountProblem.methodUnknown);
      expect(await problem(branch: 99999, account: bank.id), AccountProblem.branchUnknown);
      expect(await problem(account: 99999), AccountProblem.accountUnavailable);
      expect(await problem(account: off.id), AccountProblem.accountUnavailable);
      // The drawer belongs to this branch: not to the whole business.
      expect(await problem(account: drawer.id), AccountProblem.accountOfAnotherBranch);

      expect(await reader().defaults(), isEmpty);
    });

    test('is refused to a cashier and on a cloud till', () async {
      final bank = await save(draft(name: 'Bank'));

      final byCashier = await admin().setDefault(
        tenderTypeId: cardId, branchId: null, accountId: bank.id, by: cashier);
      final onCloud = await admin(offline: false).setDefault(
        tenderTypeId: cardId, branchId: null, accountId: bank.id, by: owner);

      expect(byCashier.refusal, isA<NotPermitted>());
      expect(onCloud.refusal, isA<NotPermitted>());
      expect(await reader().defaults(), isEmpty);
    });

    test('an account that is a default cannot be switched off or retied', () async {
      final bank = await save(draft(name: 'Bank'));
      await admin().setDefault(tenderTypeId: cardId, branchId: null, accountId: bank.id, by: owner);

      final off = await admin().saveAccount(
        draft(id: bank.id, name: 'Bank', active: false), by: owner);
      expect((off.refusal! as AccountRefused).problem, AccountProblem.accountIsDefault);

      final retied = await admin().saveAccount(
        draft(id: bank.id, name: 'Bank', branch: branchId), by: owner);
      expect((retied.refusal! as AccountRefused).problem, AccountProblem.accountIsDefault);

      // Once the default is cleared, both are allowed.
      await admin().setDefault(tenderTypeId: cardId, branchId: null, accountId: null, by: owner);
      expect((await admin().saveAccount(draft(id: bank.id, name: 'Bank', active: false), by: owner)).refusal, isNull);
    });
  });

  group('a cloud till takes the platform\'s accounts', () {
    late DeploymentConfig cloud;

    setUp(() => cloud = pg.config.copyWith(mode: DeploymentMode.cloud));

    BootstrapBundle bundle(
      int version, {
      List<Map<String, Object?>>? accounts,
      List<Map<String, Object?>>? defaults,
      List<Map<String, Object?>>? tenders,
    }) => BootstrapBundle(
      configVersion: version,
      restaurant: BootstrapRestaurant(
        id: restaurantId,
        name: 'Accounts',
        slug: 'fa',
        currency: 'EGP',
        exponent: 2,
      ),
      terminal: BootstrapTerminal(
        id: '0c9adf1e-9e3f-4a2e-b8a5-6a1f6f0f2f10',
        name: 'Bar 1',
        branchId: branchId,
      ),
      branches: [BootstrapBranch(id: branchId, name: 'Main', code: 'MAIN')],
      money: {
        'tax_rules': const [],
        'charges': const [],
        'tender_types': tenders ?? const [
          {'id': 501, 'name': 'Card', 'kind': 'card'},
        ],
        'financial_accounts': ?accounts,
        'tender_account_defaults': ?defaults,
      },
    );

    Future<void> seed(BootstrapBundle b) =>
        BootstrapSeeder(database: db, config: cloud).seed(b);

    const bank = {
      'id': 71,
      'name': 'CIB main',
      'kind': 'bank',
      'currency': 'EGP',
      'branch_id': null,
      'reference_label': 'CIB 4521',
      'is_active': true,
      'sort_order': 1,
    };

    test('keeping their ids, currency and branch', () async {
      await seed(bundle(1, accounts: [
        bank,
        {'id': 72, 'name': 'Drawer', 'kind': 'cash', 'currency': 'EGP', 'branch_id': branchId, 'sort_order': 2},
      ]));

      final accounts = await reader().accounts();
      expect(accounts.map((a) => a.id), [71, 72]);
      expect(accounts[0].currency, 'EGP');
      expect(accounts[0].branchId, isNull);
      expect(accounts[1].branchId, branchId);
    });

    test('and the default of each payment method, found through its platform id',
        () async {
      await seed(bundle(
        1,
        accounts: [bank],
        defaults: [
          {'tender_type_id': 501, 'branch_id': null, 'financial_account_id': 71},
          {'tender_type_id': 501, 'branch_id': branchId, 'financial_account_id': 71},
        ],
      ));

      final localCard = (await db.query(
        pg.config,
        'SELECT id FROM pos_tender_types WHERE restaurant_id = @r AND platform_id = 501',
        parameters: {'r': restaurantId},
      )).first[0]! as int;
      final rows = await reader().defaults();

      expect(rows, hasLength(2));
      expect(rows.every((r) => r.tenderTypeId == localCard && r.accountId == 71), isTrue,
          reason: 'the LOCAL method id, not the platform\'s 501');
    });

    test('an account the platform stops sending is switched off, never deleted',
        () async {
      await seed(bundle(1, accounts: [bank]));
      await seed(bundle(2, accounts: const []));

      final all = await reader().accounts(includeInactive: true);
      expect(all, hasLength(1));
      expect(all.single.isActive, isFalse);
    });

    test('an older platform that sends no accounts leaves the till\'s alone',
        () async {
      await seed(bundle(1, accounts: [bank], defaults: [
        {'tender_type_id': 501, 'branch_id': null, 'financial_account_id': 71},
      ]));
      await seed(bundle(2));

      expect(await reader().accounts(), hasLength(1));
      expect(await reader().defaults(), hasLength(1));
    });

    test('defaults are replaced wholesale, and an empty list clears them', () async {
      await seed(bundle(1, accounts: [bank], defaults: [
        {'tender_type_id': 501, 'branch_id': null, 'financial_account_id': 71},
      ]));
      await seed(bundle(2, accounts: [bank], defaults: const []));

      expect(await reader().defaults(), isEmpty);
      expect(await reader().accounts(), hasLength(1));
    });

    test('a row it cannot place is skipped, and the rest still seed', () async {
      await seed(bundle(
        1,
        accounts: [
          bank,
          // Tied to a branch this till does not hold: skipped, NOT widened into
          // an account the whole business shares.
          {'id': 80, 'name': 'Ghost drawer', 'kind': 'cash', 'branch_id': 999999},
          {'id': 81, 'name': 'Crypto', 'kind': 'crypto'},
        ],
        defaults: [
          {'tender_type_id': 501, 'branch_id': null, 'financial_account_id': 71},
          {'tender_type_id': 777, 'branch_id': null, 'financial_account_id': 71},
          {'tender_type_id': 501, 'branch_id': 999999, 'financial_account_id': 71},
          {'tender_type_id': 501, 'branch_id': branchId, 'financial_account_id': 80},
        ],
      ));

      expect((await reader().accounts()).map((a) => a.id), [71]);
      expect(await reader().defaults(), hasLength(1));
    });
  });

  test('the branches an account can be tied to are this restaurant\'s own', () async {
    final other = (await db.query(
      pg.config,
      "INSERT INTO pos_restaurants (slug, name) VALUES ('o2', 'O2') RETURNING id",
    )).first[0]! as int;
    await db.query(
      pg.config,
      "INSERT INTO pos_branches (restaurant_id, code, name) VALUES (@r, 'Z', 'Zed')",
      parameters: {'r': other},
    );

    expect((await reader().branches()).map((b) => b.name), ['Main']);
  });
}
