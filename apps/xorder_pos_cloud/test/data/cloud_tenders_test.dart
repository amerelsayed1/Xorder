@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/config/deployment.dart';
import 'package:xorder_pos_cloud/data/cloud/bootstrap_bundle.dart';
import 'package:xorder_pos_cloud/data/cloud/bootstrap_seeder.dart';
import 'package:shared_module/data/cloud/cloud_api.dart';
import 'package:xorder_pos_cloud/data/cloud/outbox_drain.dart';
import 'package:shared_module/data/postgres/local_bootstrap.dart';
import 'package:shared_module/data/postgres/migrations.dart';
import 'package:shared_module/data/postgres/pos_database.dart';
import 'package:shared_module/data/postgres/postgres_tender_types_repository.dart';
import 'package:shared_module/domain/models/tender_method.dart';

import 'package:xorder_pos_test_support/pg_fixture.dart';

/// Payment methods on a cloud till: the platform's, sent by the platform's id.
///
/// **The defect behind this file.** A cloud terminal sent every payment with
/// its OWN `tender_type_id` — 1 to 4 from the compiled-in list, or a local row
/// — and the platform checked it against ITS tenders. So a payment was either
/// refused, or booked against whichever platform tender happened to share the
/// number: a card sale counted as cash in somebody's cash-up. POS-BE-013 has
/// the platform author tenders and deliver them in the bundle; the seeder now
/// writes them, and the drain sends only what they name.
void main() {
  if (PgFixture.host == null) {
    test('cloud tenders (skipped — set POS_PG_HOST to run)', () {}, skip: true);
    return;
  }

  late PgFixture pg;
  late PosDatabase db;
  late DeploymentConfig cloud;
  late int businessId;
  var invoice = 0;

  const branchId = 3;
  const terminalId = '0c9adf1e-9e3f-4a2e-b8a5-6a1f6f0f2f10';

  setUp(() async {
    pg = await PgFixture.open('cloud_tenders');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await pg.truncate();
    await db.query(pg.config, 'DELETE FROM pos_businesses');
    cloud = pg.config.copyWith(mode: DeploymentMode.cloud);

    businessId = (await db.query(
      pg.config,
      "INSERT INTO pos_businesses (slug, name) VALUES ('cloud', 'Cloud') "
      'RETURNING id',
    )).first[0]! as int;
  });

  tearDown(() => pg.close());

  BootstrapBundle bundle(
    int version, [
    List<Map<String, Object?>>? tenders,
  ]) => BootstrapBundle(
    configVersion: version,
    business: BootstrapBusiness(
      id: businessId,
      name: 'Cloud',
      slug: 'cloud',
      currency: 'EGP',
      exponent: 2,
    ),
    terminal: const BootstrapTerminal(
      id: terminalId,
      name: 'Bar 1',
      branchId: branchId,
    ),
    branches: const [BootstrapBranch(id: branchId, name: 'Maadi', code: 'MAADI')],
    money: {'tax_rules': const [], 'charges': const [], 'tender_types': ?tenders},
  );

  Future<void> seed(BootstrapBundle b, {PosDatabase? on, DeploymentConfig? as}) =>
      BootstrapSeeder(database: on ?? db, config: as ?? cloud).seed(b);

  /// Every tender row for the business, keyed by what matters here.
  Future<List<Map<String, Object?>>> rows() async => [
    for (final row in await db.query(
      pg.config,
      'SELECT id, platform_id, code, name_en, name_ar, kind, counts_as_cash, '
      '       opens_drawer, requires_reference, refund_allowed, is_active, '
      '       sort_order '
      'FROM pos_tender_types WHERE business_id = @r ORDER BY id',
      parameters: {'r': businessId},
    ))
      {
        'id': row[0],
        'platform_id': row[1],
        'code': row[2],
        'name_en': row[3],
        'name_ar': row[4],
        'kind': row[5],
        'counts_as_cash': row[6],
        'opens_drawer': row[7],
        'requires_reference': row[8],
        'refund_allowed': row[9],
        'is_active': row[10],
        'sort_order': row[11],
      },
  ];

  Future<Map<String, Object?>> platformRow(int platformId) async =>
      (await rows()).singleWhere((r) => r['platform_id'] == platformId);

  /// The four a till had before any bundle, at the ids the compiled-in list
  /// uses — exactly what migration 23 writes on an existing business.
  Future<void> legacyFour() => db.query(
    pg.config,
    '''
    INSERT INTO pos_tender_types
      (id, business_id, code, name_en, name_ar, kind, counts_as_cash,
       opens_drawer, requires_reference, sort_order)
    SELECT v.id, @r, v.code, v.name_en, v.name_ar, v.kind, v.cash, v.drawer,
           v.reference, v.id
      FROM (VALUES
        (1, 'cash',    'Cash',             'نقدي',       'cash',    true,  true,  false),
        (2, 'card',    'Card',             'بطاقة',      'card',    false, false, true),
        (3, 'wallet',  'Wallet · InstaPay','محفظة',      'wallet',  false, false, true),
        (4, 'account', 'On account',       'على الحساب', 'account', false, false, false)
      ) AS v(id, code, name_en, name_ar, kind, cash, drawer, reference)
    ''',
    parameters: {'r': businessId},
  );

  /// The platform's list, numbered 1–4 on purpose: the collision case. Tender
  /// 1 is a CARD here while the till's own row 1 is Cash, so a single flag
  /// carried across would show.
  const colliding = <Map<String, Object?>>[
    {'id': 1, 'name': 'Card (bank terminal)', 'kind': 'card', 'sort_order': 2},
    {'id': 2, 'name': 'Cash', 'kind': 'cash', 'sort_order': 1},
    {'id': 3, 'name': 'Bank terminal', 'kind': 'external', 'sort_order': 3},
    {'id': 4, 'name': 'Mystery', 'kind': 'crypto', 'sort_order': 4},
  ];

  group('seeding', () {
    test('writes the platform\'s tenders under the platform\'s ids', () async {
      await seed(bundle(1, colliding));

      final cash = await platformRow(2);
      expect(cash['code'], 'platform-2');
      expect(cash['name_en'], 'Cash');
      expect(cash['name_ar'], isNull, reason: 'one name came; none is invented');
      expect(cash['kind'], 'cash');
      expect(cash['counts_as_cash'], isTrue);
      expect(cash['opens_drawer'], isTrue);
      expect(cash['requires_reference'], isFalse);
      expect(cash['refund_allowed'], isTrue);

      final card = await platformRow(1);
      expect(card['kind'], 'card');
      expect(card['counts_as_cash'], isFalse);
      expect(card['opens_drawer'], isFalse);

      expect(
        (await platformRow(3))['kind'],
        'card',
        reason: 'external is a card on the bank\'s own terminal',
      );
      final unknown = await platformRow(4);
      expect(unknown['kind'], 'other', reason: 'unknown is takeable');
      expect(unknown['counts_as_cash'], isFalse, reason: 'and is not cash');

      for (final row in await rows()) {
        expect(
          row['id'] as int,
          greaterThan(TenderMethod.seededIdCeiling),
          reason: 'no platform row may share an id with the fallback list',
        );
      }

      // And that is what the payment screen is offered, in the platform's
      // order.
      final offered = await PostgresTenderTypesRepository(
        database: db,
        config: cloud,
        businessId: businessId,
      ).all();
      expect(offered.map((t) => t.nameEn), [
        'Cash',
        'Card (bank terminal)',
        'Bank terminal',
        'Mystery',
      ]);
    });

    test('the till\'s own four are retired, not overwritten, where the ids '
        'collide', () async {
      await legacyFour();
      await seed(bundle(1, colliding));

      final all = await rows();
      final legacy = all.where((r) => r['platform_id'] == null).toList();
      expect(legacy.map((r) => r['id']), [1, 2, 3, 4], reason: 'still there');
      expect(legacy.map((r) => r['code']), ['cash', 'card', 'wallet', 'account']);
      expect(
        legacy.every((r) => r['is_active'] == false),
        isTrue,
        reason: 'the platform did not send them',
      );
      // Row 1 keeps its OWN flags. Had the upsert landed on it, it would now
      // be the platform's card, and a queued payment naming id 1 would drain
      // as that card.
      expect(legacy.first['name_en'], 'Cash');
      expect(legacy.first['counts_as_cash'], isTrue);

      final platformCard = await platformRow(1);
      expect(platformCard['id'], isNot(1));
      expect(platformCard['counts_as_cash'], isFalse);
      expect(platformCard['name_ar'], isNull, reason: 'nothing of row 1 came');
      expect(all.where((r) => r['platform_id'] != null), hasLength(4));
    });

    test('a reseed updates in place and retires what the platform dropped',
        () async {
      await seed(bundle(1, colliding));
      final before = {
        for (final r in await rows()) r['platform_id']: r['id'],
      };

      // Same bundle again, forced past the version check: nothing moves.
      await BootstrapSeeder(database: db, config: cloud)
          .seed(bundle(1, colliding), force: true);
      expect(
        {for (final r in await rows()) r['platform_id']: r['id']},
        before,
      );

      // The platform renames Cash, retires the external one and stops sending
      // the unknown one altogether.
      await seed(
        bundle(2, [
          {'id': 1, 'name': 'Card (bank terminal)', 'kind': 'card'},
          {'id': 2, 'name': 'Cash · EGP', 'kind': 'cash'},
          {'id': 3, 'name': 'Bank terminal', 'kind': 'external', 'is_active': false},
        ]),
      );

      final after = await rows();
      expect(after, hasLength(4), reason: 'nothing deleted');
      expect(
        {for (final r in after) r['platform_id']: r['id']},
        before,
        reason: 'the same local id for the same platform tender, always — a '
            'queued payment names it by that id',
      );
      expect((await platformRow(2))['name_en'], 'Cash · EGP');
      expect((await platformRow(3))['is_active'], isFalse);
      expect((await platformRow(4))['is_active'], isFalse);
      expect((await platformRow(1))['is_active'], isTrue);
    });

    test('an empty list leaves the table as it is', () async {
      await legacyFour();
      await seed(bundle(1, colliding));
      final before = await rows();

      await seed(bundle(2, const []));
      expect(await rows(), before);

      await seed(bundle(3));
      expect(await rows(), before, reason: 'nor does no list at all');
    });

    test('an empty list on a till the platform never seeded offers its own four',
        () async {
      // Stated, not endorsed: the platform promises a POS business is never
      // delivered an empty list. If it were, the till keeps what it has — and
      // the drain holds every payment taken on it.
      await legacyFour();
      await seed(bundle(1, const []));

      final offered = await PostgresTenderTypesRepository(
        database: db,
        config: cloud,
        businessId: businessId,
      ).all();
      expect(offered.map((t) => t.code), ['cash', 'card', 'wallet', 'account']);
    });

    test('runs on the till\'s own cloud credential', () async {
      // The superuser needs no grant, so every other test here would pass on
      // an install where the seeder is refused. This one is refused if the
      // cloud grant list is missing anything the tenders need.
      // Per checkout: the role is cluster-wide even though the database is
      // not, so a fixed name was shared with every other worktree's run.
      final role = PgFixture.roleFor('cloud_tender_probe');
      const password = 'probe-only';
      await _dropRole(db, pg, role);
      addTearDown(() => _dropRole(db, pg, role));
      await db.query(
        pg.config,
        'CREATE ROLE "$role" LOGIN PASSWORD \'$password\'',
      );
      for (final statement in LocalBootstrap.tillGrants(
        database: pg.config.databaseName,
        role: role,
        cloudSeeding: true,
      )) {
        await db.query(pg.config, statement);
      }

      final till = PosDatabase(credentials: InMemoryPosDbCredentials(password));
      addTearDown(till.close);
      final tillConfig = cloud.copyWith(databaseUser: role);

      await legacyFour();
      await seed(bundle(1, colliding), on: till, as: tillConfig);

      expect((await rows()).where((r) => r['platform_id'] != null), hasLength(4));
    });
  });

  group('the table itself', () {
    // The seeder keeps these promises; the CHECK is what keeps them for the
    // second writer. So each is tried by going round the seeder.

    Future<Object?> refusalOf(String sql) async {
      try {
        await db.query(pg.config, sql, parameters: {'r': businessId});
        return null;
      } on Object catch (error) {
        return error;
      }
    }

    test('a row the platform did not send may not wear its prefix', () async {
      expect(
        await refusalOf(
          'INSERT INTO pos_tender_types (business_id, code, name_en) '
          "VALUES (@r, 'platform-9', 'Impostor')",
        ),
        isNotNull,
      );
    });

    test('a platform row carries exactly its own code', () async {
      expect(
        await refusalOf(
          'INSERT INTO pos_tender_types (business_id, platform_id, code, '
          "  name_en) VALUES (@r, 9, 'cash', 'Cash')",
        ),
        isNotNull,
      );
    });

    test('a platform row never sits at a compiled-in id', () async {
      expect(
        await refusalOf(
          'INSERT INTO pos_tender_types (id, business_id, platform_id, code, '
          "  name_en) VALUES (1, @r, 9, 'platform-9', 'Cash')",
        ),
        isNotNull,
        reason: 'the fallback Cash is id 1, and must never drain as tender 9',
      );
    });
  });

  /// One settled sale, queued, with one payment per entry in [tenderTypeIds].
  Future<int> queueSale(List<int> tenderTypeIds) async {
    invoice++;
    final orderId = (await db.query(
      pg.config,
      '''
      INSERT INTO pos_orders (client_transaction_id, business_id, branch_id,
        terminal_id, invoice_number, order_type, currency, exponent,
        subtotal_minor, service_minor, vat_minor, total_minor, occurred_at)
      VALUES (gen_random_uuid(), @r, @b, @t, @invoice, 'takeaway', 'EGP', 2,
        10000, 0, 1400, 11400, now())
      RETURNING id
      ''',
      parameters: {
        'r': businessId,
        'b': branchId,
        't': terminalId,
        'invoice': 'MAADI-${invoice.toString().padLeft(6, '0')}',
      },
    )).first[0]! as int;
    for (final type in tenderTypeIds) {
      await db.query(
        pg.config,
        'INSERT INTO pos_order_payments (order_id, tender_type_id, label, '
        "  amount_minor, counts_as_cash) VALUES (@o, @type, 'Cash', @amount, true)",
        parameters: {
          'o': orderId,
          'type': type,
          'amount': 11400 ~/ tenderTypeIds.length,
        },
      );
    }
    return (await db.query(
      pg.config,
      'INSERT INTO pos_outbox (order_id, client_transaction_id, business_id, '
      '  branch_id) SELECT id, client_transaction_id, business_id, branch_id '
      'FROM pos_orders WHERE id = @o RETURNING id',
      parameters: {'o': orderId},
    )).first[0]! as int;
  }

  Future<List<Object?>> outboxRow(int id) async => (await db.query(
    pg.config,
    'SELECT quarantined_at, quarantine_code, delivered_at, last_error, attempts '
    'FROM pos_outbox WHERE id = @id',
    parameters: {'id': id},
  )).first;

  Future<(DrainReport, _RecordingApi)> drain() async {
    final api = _RecordingApi();
    final report = await OutboxDrain(database: db, config: cloud, api: api).run();
    return (report, api);
  }

  group('the drain', () {
    test('holds a payment on a tender the platform never sent', () async {
      // The defect, exactly: a sale taken on the till's own Cash before this
      // build, still in the queue.
      await LocalBootstrap(db).seedTenderTypes(pg.config, businessId);
      final localCash = (await db.query(
        pg.config,
        "SELECT id FROM pos_tender_types WHERE code = 'cash' AND business_id = @r",
        parameters: {'r': businessId},
      )).first[0]! as int;
      final outboxId = await queueSale([localCash]);

      final (report, api) = await drain();

      expect(api.sent, isEmpty, reason: 'a guessed tender id is never sent');
      expect(report.quarantined, 1);
      expect(report.delivered, 0);

      final row = await outboxRow(outboxId);
      expect(row[0], isNotNull, reason: 'held for a person');
      expect(row[1], OutboxDrain.tenderNotFromPlatform);
      expect(row[1], 'TENDER_NOT_FROM_PLATFORM');
      expect(row[2], isNull, reason: 'and not marked as sent');
      expect(row[3] as String?, contains('Cash'));
      expect(row[4], 0, reason: 'nothing was said to the platform');
    });

    test('sends a platform tender by the platform\'s id, not the till\'s',
        () async {
      await legacyFour();
      await seed(bundle(1, colliding));
      final cash = await platformRow(2);
      final outboxId = await queueSale([cash['id']! as int]);

      final (report, api) = await drain();

      expect(report.delivered, 1);
      final payment =
          ((api.sent.single['payments'] as List).single as Map<String, Object?>);
      expect(payment['tender_type_id'], 2, reason: 'the platform\'s Cash');
      expect(payment['tender_type_id'], isNot(cash['id']));
      expect((await outboxRow(outboxId))[2], isNotNull);
    });

    test('a tender the platform has since retired still drains', () async {
      // The money moved while it was active. Retiring it on the dashboard must
      // not strand a sale already taken on it.
      await seed(bundle(1, colliding));
      final external = await platformRow(3);
      await queueSale([external['id']! as int]);
      await seed(bundle(2, [colliding[0], colliding[1]]));

      final (report, api) = await drain();

      expect(report.delivered, 1);
      final payment =
          ((api.sent.single['payments'] as List).single as Map<String, Object?>);
      expect(payment['tender_type_id'], 3);
    });

    test('the compiled-in fallback never drains, however the platform numbered '
        'its tenders', () async {
      // A fresh cloud till: no local four at all, and the platform's tenders
      // are 1–4. The payment screen shows `TenderMethod.seeded` while its list
      // loads, so a payment can carry id 1 without any row having been chosen.
      await seed(bundle(1, colliding));
      final outboxId = await queueSale([TenderMethod.seeded.first.id]);

      final (report, api) = await drain();

      expect(api.sent, isEmpty);
      expect(report.quarantined, 1);
      expect((await outboxRow(outboxId))[1], OutboxDrain.tenderNotFromPlatform);
    });

    test('one stranded payment holds the whole sale', () async {
      // Sending the half that can be sent would record the order as underpaid
      // on the platform, which is a second problem, not half a solution.
      await legacyFour();
      await seed(bundle(1, colliding));
      final platformCash = (await platformRow(2))['id']! as int;
      final outboxId = await queueSale([platformCash, 1]);

      final (report, api) = await drain();

      expect(api.sent, isEmpty);
      expect(report.quarantined, 1);
      final row = await outboxRow(outboxId);
      expect(row[1], OutboxDrain.tenderNotFromPlatform);
      expect(row[3] as String?, contains('payment method 1 on this till'));
    });
  });
}

/// Records what would have gone to the platform, and says yes to all of it.
class _RecordingApi extends PosCloudApi {
  _RecordingApi() : super(baseUrl: 'http://127.0.0.1:9');

  final sent = <Map<String, Object?>>[];

  @override
  Future<CloudReply> submitOrder(Map<String, Object?> request) async {
    sent.add(request);
    return CloudReply(
      status: 201,
      body: {
        'data': {'id': 100 + sent.length, 'invoice_number': 'MAADI-000001'},
      },
    );
  }
}

/// Same as the grant suites': grants must go before the role can.
Future<void> _dropRole(PosDatabase db, PgFixture pg, String role) async {
  for (final statement in [
    'DROP OWNED BY "$role"',
    'DROP ROLE IF EXISTS "$role"',
  ]) {
    try {
      await db.query(pg.config, statement);
    } on Object {
      // Nothing to revoke, or nothing to drop.
    }
  }
}
