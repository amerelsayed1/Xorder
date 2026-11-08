@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/data/cloud/bootstrap_bundle.dart';
import 'package:xorder_pos/data/cloud/bootstrap_seeder.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/data/postgres/postgres_catalog_admin_repository.dart';
import 'package:xorder_pos/domain/models/content_languages.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/shift.dart';
import 'package:xorder_pos/domain/repositories/admin_repositories.dart';

import 'pg_fixture.dart';

/// XORD-005 — which languages the menu is written in, on the branch server.
///
/// Migration 57 adds the column (default `both`, which is how every till behaves
/// today); an offline install authors it; a cloud till's bundle writes it, and
/// an older platform that says nothing leaves it alone.
void main() {
  if (PgFixture.host == null) {
    test('content languages (skipped — set POS_PG_HOST)', () {}, skip: true);
    return;
  }

  late PgFixture pg;
  late PosDatabase db;
  late int businessId;

  const manager = PosStaff(
    id: 0,
    name: 'Amer M.',
    role: PosRole(
      id: 1,
      code: 'manager',
      nameEn: 'Manager',
      capabilities: {PosCapability.settingsManage},
    ),
  );
  const cashier = PosStaff(
    id: 0,
    name: 'Rana A.',
    role: PosRole(
      id: 2,
      code: 'cashier',
      nameEn: 'Cashier',
      capabilities: {PosCapability.operate},
    ),
  );

  setUp(() async {
    pg = await PgFixture.open('content_languages');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await pg.truncate();
    await db.query(pg.config, 'DELETE FROM pos_businesses');
    businessId = (await db.query(
      pg.config,
      "INSERT INTO pos_businesses (slug, name) VALUES ('cl', 'CL') RETURNING id",
    )).first[0]! as int;
  });

  tearDown(() => pg.close());

  Future<String> stored() async => (await db.query(
    pg.config,
    'SELECT content_languages FROM pos_businesses WHERE id = @r',
    parameters: {'r': businessId},
  )).first[0]! as String;

  PostgresCatalogAdminRepository repo({bool offline = true}) =>
      PostgresCatalogAdminRepository(
        database: db,
        config: pg.config,
        businessId: businessId,
        offline: offline,
      );

  test('migration 57: a business that existed before it is `both`', () async {
    expect(await stored(), 'both');
  });

  test('the column refuses a value that is not one of the three', () async {
    await expectLater(
      db.query(
        pg.config,
        "UPDATE pos_businesses SET content_languages = 'fr' WHERE id = @r",
        parameters: {'r': businessId},
      ),
      throwsA(anything),
    );
    expect(await stored(), 'both');
  });

  group('an offline install authors it', () {
    test('settings.manage may, and it is audited with before and after', () async {
      final result = await repo().saveContentLanguages(ContentLanguages.arabic, by: manager);
      expect(result.succeeded, isTrue, reason: '${result.refusal}');
      expect(await stored(), 'ar');

      final audit = await db.query(
        pg.config,
        'SELECT before_value, after_value FROM pos_audit_events '
        'WHERE action = @a ORDER BY id DESC LIMIT 1',
        parameters: {'a': AuditAction.contentLanguagesSaved},
      );
      expect(audit.first[0].toString(), contains('both'));
      expect(audit.first[1].toString(), contains('ar'));
    });

    test('somebody without settings.manage may not, and nothing changes', () async {
      final result = await repo().saveContentLanguages(ContentLanguages.english, by: cashier);
      expect(result.refusal, isA<NotPermitted>());
      expect(await stored(), 'both');
    });

    test('a cloud till refuses: the platform owns it', () async {
      final result = await repo(offline: false)
          .saveContentLanguages(ContentLanguages.english, by: manager);
      expect(result.refusal, isA<NotPermitted>());
      expect(await stored(), 'both');
    });

    test('saving what is already stored writes no audit row', () async {
      // Counted before and after: the audit table outlives a test's other rows.
      Future<int> count() async => int.parse('${(await db.query(
        pg.config,
        'SELECT count(*) FROM pos_audit_events WHERE action = @a',
        parameters: {'a': AuditAction.contentLanguagesSaved},
      )).first[0]}');

      final before = await count();
      await repo().saveContentLanguages(ContentLanguages.both, by: manager);
      expect(await count(), before);
    });
  });

  group('a cloud till receives it from the bundle', () {
    BootstrapBundle bundle({String? contentLanguages}) => BootstrapBundle(
      configVersion: 1,
      business: BootstrapBusiness(
        id: businessId,
        name: 'CL',
        slug: 'cl',
        currency: 'EGP',
        exponent: 2,
        contentLanguages: contentLanguages,
      ),
      terminal: const BootstrapTerminal(
        id: '0c9adf1e-9e3f-4a2e-b8a5-6a1f6f0f2f10',
        name: 'Bar 1',
        branchId: 3,
      ),
      branches: const [BootstrapBranch(id: 3, name: 'Maadi', code: 'MAADI')],
      money: const {'tax_rules': [], 'charges': [], 'tender_types': []},
    );

    Future<void> seed(BootstrapBundle b) => BootstrapSeeder(
      database: db,
      config: pg.config.copyWith(mode: DeploymentMode.cloud),
    ).seed(b);

    test('what the platform says is stored', () async {
      await seed(bundle(contentLanguages: 'en'));
      expect(await stored(), 'en');
    });

    test('an older platform that says nothing leaves it alone', () async {
      await repo().saveContentLanguages(ContentLanguages.arabic, by: manager);
      await seed(bundle());
      expect(await stored(), 'ar', reason: 'not reset to both');
    });
  });

  group('the bundle parser', () {
    BootstrapBusiness? parse(Map<String, Object?> extra) =>
        BootstrapBusiness.fromJson({
          'id': 1,
          'name': 'CL',
          'slug': 'cl',
          'currency': 'EGP',
          'exponent': 2,
          ...extra,
        });

    test('maps the two platform flags', () {
      expect(parse({'bilingual': true, 'default_language': 'ar'})!.contentLanguages, 'both');
      expect(parse({'bilingual': false, 'default_language': 'ar'})!.contentLanguages, 'ar');
      expect(parse({'bilingual': false, 'default_language': 'en'})!.contentLanguages, 'en');
    });

    test('silence is null, not both', () {
      expect(parse({'default_language': 'ar'})!.contentLanguages, isNull);
      expect(parse({'bilingual': 'yes'})!.contentLanguages, isNull);
    });
  });
}
