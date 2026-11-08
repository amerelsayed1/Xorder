@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos_cloud/data/cloud/bootstrap_bundle.dart';
import 'package:xorder_pos_cloud/data/cloud/bootstrap_seeder.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/data/postgres/postgres_receipt_profile_repository.dart';
import 'package:xorder_pos/domain/models/receipt_profile.dart';

import 'package:xorder_pos_test_support/pg_fixture.dart';

/// Who the receipt says sold the food, on a cloud till.
///
/// **The defect behind this file.** Nothing in `lib/data/cloud/` ever wrote
/// `pos_receipt_profiles`, so a cloud till's `receiptProfileProvider` found no
/// row, fell back to `ReceiptProfile(branchId: 0)` — which is correct
/// behaviour for a branch nobody has set up — and printed the compiled-in
/// blank on every slip it handed a customer, with the business's real trade
/// name and tax registration number sitting on the dashboard the whole time.
/// A3 makes the platform the author and puts `receipt_profiles[]` in the
/// bundle; `BootstrapSeeder` now upserts it.
///
/// The claim is asserted twice, as the house rule asks: through
/// `PostgresReceiptProfileRepository.load()` — the reader the receipt and the
/// filing actually use — and in raw SQL, where the columns the seeder writes
/// can be checked one at a time.
void main() {
  if (PgFixture.host == null) {
    test(
      'cloud receipt profiles (skipped — set POS_PG_HOST to run)',
      () {},
      skip: true,
    );
    return;
  }

  late PgFixture pg;
  late PosDatabase db;
  late DeploymentConfig cloud;
  late int businessId;

  // Two branches, because one profile per branch is the whole point: a
  // business group filing one address for four branches is filing three
  // wrong ones.
  const maadi = 3;
  const zamalek = 9;
  const terminalId = '0c9adf1e-9e3f-4a2e-b8a5-6a1f6f0f2f10';

  setUp(() async {
    pg = await PgFixture.open('cloud_receipt_profile');
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
    int version, {
    List<ReceiptProfile>? profiles,
    List<int> branches = const [maadi, zamalek],
  }) => BootstrapBundle(
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
      branchId: maadi,
    ),
    branches: [
      for (final id in branches)
        BootstrapBranch(id: id, name: 'Branch $id', code: 'BR$id'),
    ],
    receiptProfiles: profiles ?? const [],
  );

  Future<void> seed(BootstrapBundle b, {bool force = false}) =>
      BootstrapSeeder(database: db, config: cloud).seed(b, force: force);

  /// As the platform sends it for an authored branch.
  ReceiptProfile authored(int branchId, {String? trade, int revision = 3}) =>
      ReceiptProfile(
        branchId: branchId,
        tradeName: trade ?? 'Koshary House LLC',
        registrationNumber: '123456789',
        activityCode: '5610',
        // ETA's, not the invoice prefix — `BR3` is that, and it is not this.
        branchCode: '0042',
        address: const BranchAddress(
          governate: 'Cairo',
          regionCity: 'Maadi',
          street: 'Road 9',
          buildingNumber: '12',
        ),
        phone: '+201000000001',
        headerNote: 'Welcome',
        footerNote: 'Wifi: guest',
        revision: revision,
      );

  /// One row, column by column, as PostgreSQL holds it.
  Future<Map<String, Object?>> row(int branchId) async {
    final rows = await db.query(
      pg.config,
      'SELECT trade_name, registration_number, activity_code, branch_code, '
      '       country, governate, region_city, street, building_number, '
      '       postal_code, floor, room, landmark, additional_info, phone, '
      '       header_note, footer_note, revision, business_id, updated_by '
      'FROM pos_receipt_profiles WHERE branch_id = @b',
      parameters: {'b': branchId},
    );
    expect(rows, hasLength(1), reason: 'one profile per branch, branch $branchId');
    const names = [
      'trade_name', 'registration_number', 'activity_code', 'branch_code',
      'country', 'governate', 'region_city', 'street', 'building_number',
      'postal_code', 'floor', 'room', 'landmark', 'additional_info', 'phone',
      'header_note', 'footer_note', 'revision', 'restaurant_id', 'updated_by',
    ];
    return {
      for (var i = 0; i < names.length; i++) names[i]: rows.first[i],
    };
  }

  /// What the receipt and the filing read, on the branch the terminal is at.
  Future<ReceiptProfile> asRead(int branchId) => PostgresReceiptProfileRepository(
    database: db,
    config: cloud,
    readDatabase: db,
    readConfig: cloud,
    adminAvailable: true,
    businessId: businessId,
    branchId: branchId,
  ).load();

  Future<int> profileCount() async =>
      (await db.query(pg.config, 'SELECT count(*) FROM pos_receipt_profiles'))
          .first[0]!
      as int;

  test('a cloud till prints what the platform authored, not a blank', () async {
    await seed(bundle(1, profiles: [authored(maadi)]));

    // The claim, through the reader the slip uses.
    final profile = await asRead(maadi);
    expect(profile.tradeName, 'Koshary House LLC');
    expect(profile.registrationNumber, '123456789');
    expect(profile.activityCode, '5610');
    expect(profile.branchCode, '0042');
    expect(profile.address.governate, 'Cairo');
    expect(profile.address.street, 'Road 9');
    expect(profile.address.buildingNumber, '12');
    expect(profile.phone, '+201000000001');
    expect(profile.footerNote, 'Wifi: guest');
    expect(profile.isBlank, isFalse, reason: 'this is the whole bug');
    expect(profile.canPrint, isTrue);
    expect(profile.canFile, isTrue);

    // And again in SQL, where each column the seeder writes is its own claim.
    final stored = await row(maadi);
    expect(stored['restaurant_id'], businessId);
    expect(stored['branch_code'], '0042');
    expect(stored['region_city'], 'Maadi');
    // NOT NULL DEFAULT '' on every text column; the wire's nulls are flattened
    // by the seeder rather than at the read.
    expect(stored['postal_code'], '');
    expect(stored['floor'], '');
    expect(stored['landmark'], '');
    expect(stored['additional_info'], '');
    expect(
      stored['updated_by'],
      isNull,
      reason: 'a sync wrote this, and no person at this till did',
    );
  });

  test("the platform's revision is taken verbatim, not counted here", () async {
    // The counter is the dashboard's stale-save guard. A local `revision + 1`
    // would put the two permanently out of step, and 0 carries real news: this
    // branch is a projection of the business, nobody has authored it.
    await seed(
      bundle(
        1,
        profiles: [
          authored(maadi, revision: 7),
          const ReceiptProfile(
            branchId: zamalek,
            tradeName: 'Cloud',
            registrationNumber: '123456789',
          ),
        ],
      ),
    );

    expect((await row(maadi))['revision'], 7);
    expect((await row(zamalek))['revision'], 0);
    expect((await asRead(zamalek)).revision, 0);
  });

  test('every active branch gets a row, authored or not', () async {
    await seed(
      bundle(
        1,
        profiles: [
          authored(maadi),
          // A branch nobody has typed, projected from the business.
          const ReceiptProfile(
            branchId: zamalek,
            tradeName: 'Cloud',
            registrationNumber: '123456789',
          ),
        ],
      ),
    );

    expect(await profileCount(), 2);
    final unauthored = await asRead(zamalek);
    expect(unauthored.tradeName, 'Cloud');
    expect(
      unauthored.canPrint,
      isTrue,
      reason: 'enough to hand somebody paper on day one',
    );
    expect(unauthored.canFile, isFalse, reason: 'and the till still says so');
  });

  test('a profile for a branch the bundle did not carry is skipped, and the '
      'rest of the seed survives', () async {
    // `branch_id` is a foreign key. One row naming a branch the bundle omitted
    // would roll back the whole transaction — the catalog, the staff and the
    // floor with it — over a settings field.
    await seed(
      bundle(
        1,
        branches: const [maadi],
        profiles: [authored(maadi), authored(zamalek)],
      ),
    );

    expect(await profileCount(), 1);
    expect((await asRead(maadi)).tradeName, 'Koshary House LLC');
    expect(
      (await db.query(
        pg.config,
        'SELECT count(*) FROM pos_branches WHERE business_id = @r',
        parameters: {'r': businessId},
      )).first[0],
      1,
      reason: 'the identity block landed rather than rolling back',
    );
  });

  test('a later bundle rewrites the row in place', () async {
    await seed(bundle(1, profiles: [authored(maadi)]));
    final first = (await db.query(
      pg.config,
      'SELECT id FROM pos_receipt_profiles WHERE branch_id = @b',
      parameters: {'b': maadi},
    )).first[0];

    await seed(
      bundle(2, profiles: [authored(maadi, trade: 'Koshary House', revision: 4)]),
    );

    expect(await profileCount(), 1, reason: 'upserted, not duplicated');
    expect(
      (await db.query(
        pg.config,
        'SELECT id FROM pos_receipt_profiles WHERE branch_id = @b',
        parameters: {'b': maadi},
      )).first[0],
      first,
      reason: 'the same row, so nothing pointing at it is orphaned',
    );
    expect((await asRead(maadi)).tradeName, 'Koshary House');
    expect((await row(maadi))['revision'], 4);
  });

  test('a sync clears whoever last edited it in the back office', () async {
    // An offline till that moved to cloud, or a profile typed before A3
    // shipped. The row no longer says what that manager said, and leaving
    // their id on it would name them as the author of the platform's text.
    final staffId = (await db.query(
      pg.config,
      'INSERT INTO pos_users (business_id, name, username, pin_salt, '
      "  pin_hash, capabilities) VALUES (@r, 'Mona', 'mona', '', '', '{}') "
      'RETURNING id',
      parameters: {'r': businessId},
    )).first[0]! as int;
    await seed(bundle(1, profiles: [authored(maadi)]));
    await db.query(
      pg.config,
      'UPDATE pos_receipt_profiles SET updated_by = @s WHERE branch_id = @b',
      parameters: {'s': staffId, 'b': maadi},
    );

    await seed(bundle(2, profiles: [authored(maadi, trade: 'Koshary House')]));

    expect((await row(maadi))['updated_by'], isNull);
  });

  test('a platform that predates A3 sends none, and nothing is blanked',
      () async {
    // The regression that matters most: an empty list must not wipe what the
    // till already prints with, or a rollback to an older backend would put
    // every slip back to the compiled-in blank.
    await seed(bundle(1, profiles: [authored(maadi)]));

    await seed(bundle(2));

    expect(await profileCount(), 1);
    expect((await asRead(maadi)).tradeName, 'Koshary House LLC');
  });

  test('a branch that goes inactive keeps its row', () async {
    // The branch is switched off rather than removed, so its profile is
    // unreachable already; `ON DELETE CASCADE` takes it the day the branch
    // really goes. Deleting here would need a grant with no other caller.
    await seed(
      bundle(1, profiles: [authored(maadi), authored(zamalek, trade: 'Zamalek')]),
    );

    await seed(bundle(2, branches: const [maadi], profiles: [authored(maadi)]));

    expect(await profileCount(), 2);
    expect(
      (await db.query(
        pg.config,
        'SELECT is_active FROM pos_branches WHERE id = @b',
        parameters: {'b': zamalek},
      )).first[0],
      isFalse,
    );

    // And the cascade is what removes it, when the branch really goes.
    await db.query(
      pg.config,
      'DELETE FROM pos_branches WHERE id = @b',
      parameters: {'b': zamalek},
    );
    expect(await profileCount(), 1);
  });
}
