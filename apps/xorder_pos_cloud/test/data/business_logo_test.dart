@Tags(['integration'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/config/deployment.dart';
import 'package:xorder_pos_cloud/data/cloud/bootstrap_bundle.dart';
import 'package:xorder_pos_cloud/data/cloud/bootstrap_seeder.dart';
import 'package:xorder_pos_cloud/data/cloud/logo_sync.dart';
import 'package:shared_module/data/postgres/migrations.dart';
import 'package:shared_module/data/postgres/pos_database.dart';
import 'package:shared_module/data/postgres/postgres_business_logo_repository.dart';
import 'package:shared_module/domain/models/business_logo.dart';
import 'package:shared_module/domain/models/permissions.dart';
import 'package:shared_module/domain/models/shift.dart';
import 'package:shared_module/domain/repositories/admin_repositories.dart';

import 'package:xorder_pos_test_support/pg_fixture.dart';

/// XORD-021 — the business logo, on the branch server.
///
/// Migration 58 adds the storage, 59 gives the owner the key; an offline install
/// authors the picture; a cloud till is told where the platform keeps it and
/// downloads a copy it then shows with no network at all.
void main() {
  if (PgFixture.host == null) {
    test('business logo (skipped — set POS_PG_HOST)', () {}, skip: true);
    return;
  }

  late PgFixture pg;
  late PosDatabase db;
  late int businessId;

  PosStaff holder(Set<String> capabilities) => PosStaff(
    id: 0,
    name: 'Amer M.',
    role: PosRole(id: 1, code: 'x', nameEn: 'X', capabilities: capabilities),
  );
  final owner = holder({PosCapability.brandingManage});
  final manager = holder({PosCapability.settingsManage, PosCapability.operate});

  Uint8List png(int w, int h, {int seed = 0}) {
    final b = BytesBuilder();
    b.add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13]);
    b.add('IHDR'.codeUnits);
    b.add([w >> 24, w >> 16, w >> 8, w, h >> 24, h >> 16, h >> 8, h]);
    b.add([8, 6, 0, 0, 0, seed, seed]);
    return b.toBytes();
  }

  setUp(() async {
    pg = await PgFixture.open('business_logo');
    db = pg.database;
    await PosMigrator(db).migrate(pg.config);
    await pg.truncate();
    await db.query(pg.config, 'DELETE FROM pos_businesses');
    businessId = (await db.query(
      pg.config,
      "INSERT INTO pos_businesses (slug, name) VALUES ('bl', 'BL') RETURNING id",
    )).first[0]! as int;
  });

  tearDown(() => pg.close());

  Future<List<Object?>> row() async => (await db.query(
    pg.config,
    'SELECT logo_bytes, logo_mime, logo_source, logo_remote_url, '
    '       logo_fetched_url FROM pos_businesses WHERE id = @r',
    parameters: {'r': businessId},
  )).first;

  PostgresBusinessLogoRepository repo({
    bool offline = true,
    bool adminAvailable = true,
  }) => PostgresBusinessLogoRepository(
    database: db,
    config: pg.config,
    businessId: businessId,
    offline: offline,
    adminAvailable: adminAvailable,
  );

  group('migration 58', () {
    test('a business that existed before it has no logo', () async {
      final r = await row();
      expect(r.every((v) => v == null), isTrue, reason: '$r');
    });

    test('bytes never come without a type and a source', () async {
      await expectLater(
        db.query(
          pg.config,
          "UPDATE pos_businesses SET logo_bytes = '\\x00'::bytea WHERE id = @r",
          parameters: {'r': businessId},
        ),
        throwsA(anything),
      );
      expect((await row())[0], isNull);
    });

    test('and the type is one of the three this till draws', () async {
      await expectLater(
        db.query(
          pg.config,
          "UPDATE pos_businesses SET logo_bytes = '\\x00'::bytea, "
          "logo_mime = 'image/gif', logo_source = 'local' WHERE id = @r",
          parameters: {'r': businessId},
        ),
        throwsA(anything),
      );
    });
  });

  group('migration 59', () {
    Future<List<String>> held(String code) async => ((await db.query(
      pg.config,
      'SELECT capabilities FROM pos_roles WHERE business_id = @r AND code = @c',
      parameters: {'r': businessId, 'c': code},
    )).first[0]! as List).cast<String>();

    Future<void> role(String code, Set<String> capabilities) => db.query(
      pg.config,
      'INSERT INTO pos_roles (business_id, code, name_en, name_ar, '
      '  capabilities, is_system) VALUES (@r, @c, @c, @c, @caps, false)',
      parameters: {'r': businessId, 'c': code, 'caps': capabilities.toList()},
    );

    Future<List<int>> rerun() async {
      await db.query(pg.config, 'DELETE FROM schema_migrations WHERE version = 59');
      return PosMigrator(db).migrate(pg.config);
    }

    test('the owner keeps authority, and nobody else gains it', () async {
      await role('owner', {PosCapability.operate, PosCapability.settingsManage});
      await role('manager', {PosCapability.operate, PosCapability.settingsManage});
      await role('floor_lead', {PosCapability.operate});

      expect(await rerun(), [59]);
      expect(await held('owner'), contains(PosCapability.brandingManage));
      expect(await held('manager'), isNot(contains(PosCapability.brandingManage)));
      expect(await held('floor_lead'), isNot(contains(PosCapability.brandingManage)));
    });

    test('nothing is taken away, and running it again adds it once', () async {
      await role('owner', {PosCapability.operate});
      await rerun();
      await rerun();
      final owner = await held('owner');
      expect(owner.where((c) => c == PosCapability.brandingManage), hasLength(1));
      expect(owner, contains(PosCapability.operate));
    });
  });

  group('an offline install authors it', () {
    test('the owner stores a picture; it is kept as bytes, with its type', () async {
      final image = png(300, 200);
      final result = await repo().save(image, by: owner);
      expect(result.succeeded, isTrue, reason: '${result.refusal}');

      final r = await row();
      expect(r[0], image);
      expect(r[1], 'image/png');
      expect(r[2], 'local');
    });

    test('it is audited with sizes and never with the picture', () async {
      await repo().save(png(300, 200), by: owner);
      final audit = await db.query(
        pg.config,
        'SELECT before_value, after_value FROM pos_audit_events '
        'WHERE action = @a ORDER BY id DESC LIMIT 1',
        parameters: {'a': AuditAction.businessLogoSaved},
      );
      final after = audit.first[1].toString();
      expect(after, contains('image/png'));
      expect(after, contains('300'));
      expect(after, isNot(contains('89504e47')));
      expect(audit.first[0], isNull, reason: 'there was no logo before');
    });

    test('replacing records what was there', () async {
      await repo().save(png(300, 200), by: owner);
      await repo().save(png(400, 400, seed: 7), by: owner);
      final audit = await db.query(
        pg.config,
        'SELECT before_value FROM pos_audit_events WHERE action = @a '
        'ORDER BY id DESC LIMIT 1',
        parameters: {'a': AuditAction.businessLogoSaved},
      );
      expect(audit.first[0].toString(), contains('image/png'));
      expect((await row())[0], png(400, 400, seed: 7));
    });

    test('somebody without the key may not, even with settings.manage', () async {
      final result = await repo().save(png(300, 200), by: manager);
      expect(result.refusal, isA<NotPermitted>());
      expect((await row())[0], isNull);
    });

    test('a cloud till refuses: the platform owns the logo', () async {
      final result = await repo(offline: false).save(png(300, 200), by: owner);
      expect(result.refusal, isA<NotPermitted>());
      expect((await row())[0], isNull);
    });

    test('without the administrator credential nothing is written', () async {
      final result = await repo(adminAvailable: false).save(png(300, 200), by: owner);
      expect(result.refusal, isA<AdministratorCredentialRequired>());
      expect((await row())[0], isNull);
    });

    test('a file that is not a logo is refused with its reason, and nothing changes', () async {
      await repo().save(png(300, 200), by: owner);

      final tiny = await repo().save(png(32, 32), by: owner);
      expect((tiny.refusal as LogoRejected).reason, LogoRefusal.tooSmall);
      final text = await repo().save(Uint8List.fromList('not an image'.codeUnits), by: owner);
      expect((text.refusal as LogoRejected).reason, LogoRefusal.unsupported);

      expect((await row())[0], png(300, 200), reason: 'the old logo is untouched');
    });

    test('removing takes it off, audits it, and a second removal is a quiet no-op', () async {
      // Counted before and after: the audit table outlives a test's other rows.
      Future<int> removals() async => int.parse('${(await db.query(
        pg.config,
        'SELECT count(*) FROM pos_audit_events WHERE action = @a',
        parameters: {'a': AuditAction.businessLogoRemoved},
      )).first[0]}');

      await repo().save(png(300, 200), by: owner);
      final before = await removals();

      final first = await repo().remove(by: owner);
      expect(first.value, isTrue);
      final r = await row();
      expect(r[0], isNull);
      expect(r[1], isNull);
      expect(r[2], isNull);
      expect(await removals(), before + 1);

      final second = await repo().remove(by: owner);
      expect(second.succeeded, isTrue);
      expect(second.value, isFalse);
      expect(await removals(), before + 1, reason: 'nothing was removed, nothing is recorded');
    });

    test('removing without the key is refused', () async {
      await repo().save(png(300, 200), by: owner);
      final result = await repo().remove(by: manager);
      expect(result.refusal, isA<NotPermitted>());
      expect((await row())[0], isNotNull);
    });
  });

  group('a cloud till receives it from the platform', () {
    const platform = 'https://xorder.test';
    const url = '$platform/storage/logos/a.webp';

    BootstrapBundle bundle({BootstrapBranding? branding}) => BootstrapBundle(
      configVersion: 1,
      business: BootstrapBusiness(
        id: businessId,
        name: 'BL',
        slug: 'bl',
        currency: 'EGP',
        exponent: 2,
      ),
      terminal: const BootstrapTerminal(
        id: '0c9adf1e-9e3f-4a2e-b8a5-6a1f6f0f2f10',
        name: 'Bar 1',
        branchId: 3,
      ),
      branches: const [BootstrapBranch(id: 3, name: 'Maadi', code: 'MAADI')],
      money: const {'tax_rules': [], 'charges': [], 'tender_types': []},
      branding: branding,
    );

    var version = 1;
    Future<void> seed(BootstrapBranding? branding) => BootstrapSeeder(
      database: db,
      config: pg.config.copyWith(mode: DeploymentMode.cloud),
    ).seed(
      BootstrapBundle(
        configVersion: ++version,
        business: bundle().business,
        terminal: bundle().terminal,
        branches: bundle().branches,
        money: bundle().money,
        branding: branding,
      ),
    );

    Uint8List webp(int w, int h) {
      final b = BytesBuilder();
      b.add('RIFF'.codeUnits);
      b.add([0, 0, 0, 0]);
      b.add('WEBPVP8X'.codeUnits);
      b.add([0, 0, 0, 0, 0, 0, 0, 0]);
      b.add([(w - 1) & 255, ((w - 1) >> 8) & 255, 0]);
      b.add([(h - 1) & 255, ((h - 1) >> 8) & 255, 0]);
      b.add(List.filled(8, 0));
      return b.toBytes();
    }

    LogoSync sync(Map<String, Uint8List?> served, [List<String>? asked]) =>
        LogoSync(
          database: db,
          config: pg.config,
          businessId: businessId,
          platformBase: platform,
          fetch: (uri) async {
            asked?.add(uri.toString());
            return served[uri.toString()];
          },
        );

    setUp(() => version = 1);

    test('the bundle only records where the logo is; it fetches nothing', () async {
      await seed(const BootstrapBranding(logoUrl: url));
      final r = await row();
      expect(r[3], url);
      expect(r[0], isNull, reason: 'the download is a separate step');
    });

    test('the sync downloads it, keeps the bytes and says which address they came from', () async {
      await seed(const BootstrapBranding(logoUrl: url));
      final image = webp(400, 400);

      expect(await sync({url: image}).run(), isTrue);

      final r = await row();
      expect(r[0], image);
      expect(r[1], 'image/webp');
      expect(r[2], 'platform');
      expect(r[4], url);
    });

    test('nothing is asked of the network when the stored copy is already that address', () async {
      await seed(const BootstrapBranding(logoUrl: url));
      await sync({url: webp(400, 400)}).run();

      final asked = <String>[];
      expect(await sync({url: webp(400, 400)}, asked).run(), isFalse);
      expect(asked, isEmpty);
    });

    test('a new address is fetched, and the old picture stays until it arrives', () async {
      await seed(const BootstrapBranding(logoUrl: url));
      final first = webp(400, 400);
      await sync({url: first}).run();

      const next = '$platform/storage/logos/b.webp';
      await seed(const BootstrapBranding(logoUrl: next));

      expect(await sync({}).run(), isFalse, reason: 'offline: the fetch fails');
      expect((await row())[0], first, reason: 'the till keeps showing the old logo');

      final second = webp(500, 500);
      expect(await sync({next: second}).run(), isTrue);
      expect((await row())[0], second);
      expect((await row())[4], next);
    });

    test('an address the till cannot reach is retried under the platform it talks to', () async {
      const baked = 'http://admin.localhost:8080/storage/logos/a.webp';
      await seed(const BootstrapBranding(logoUrl: baked));
      final image = webp(400, 400);
      final asked = <String>[];

      expect(
        await sync({'$platform/storage/logos/a.webp': image}, asked).run(),
        isTrue,
      );
      expect(asked, [baked, '$platform/storage/logos/a.webp']);
      expect((await row())[0], image);
    });

    test('something that is not a picture is never stored', () async {
      await seed(const BootstrapBranding(logoUrl: url));
      final html = Uint8List.fromList('<html>404</html>'.codeUnits);

      expect(await sync({url: html}).run(), isFalse);
      expect((await row())[0], isNull);
    });

    test('a link that is not http(s) is never fetched', () async {
      await seed(const BootstrapBranding(logoUrl: 'file:///etc/passwd'));
      final asked = <String>[];
      expect(await sync({}, asked).run(), isFalse);
      expect(asked, isEmpty);
    });

    test('a platform that says there is no logo removes its copy', () async {
      await seed(const BootstrapBranding(logoUrl: url));
      await sync({url: webp(400, 400)}).run();

      await seed(const BootstrapBranding());
      final r = await row();
      expect(r.every((v) => v == null), isTrue, reason: '$r');
    });

    test('…but never a logo that was chosen on the till itself', () async {
      final image = png(300, 200);
      await repo().save(image, by: owner);

      await seed(const BootstrapBranding());
      expect((await row())[0], image);
      expect((await row())[2], 'local');
    });

    test('an older platform that sends no branding block leaves the logo alone', () async {
      await seed(const BootstrapBranding(logoUrl: url));
      final image = webp(400, 400);
      await sync({url: image}).run();

      await seed(null);
      expect((await row())[0], image, reason: 'silence is not removal');
      expect((await row())[3], url);
    });

    test('a bundle that lands during a download is not overwritten by it', () async {
      await seed(const BootstrapBranding(logoUrl: url));
      const newer = '$platform/storage/logos/newer.webp';
      final late = LogoSync(
        database: db,
        config: pg.config,
        businessId: businessId,
        platformBase: platform,
        fetch: (uri) async {
          await seed(const BootstrapBranding(logoUrl: newer));
          return webp(300, 300);
        },
      );

      expect(await late.run(), isFalse);
      expect((await row())[0], isNull);
      expect((await row())[3], newer);
    });
  });

}
