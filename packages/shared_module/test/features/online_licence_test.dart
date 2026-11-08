import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/config/deployment.dart';
import 'package:shared_module/data/cloud/cloud_api.dart';
import 'package:shared_module/features/licensing/data/licence_check_store.dart';
import 'package:shared_module/features/licensing/data/licence_service.dart';
import 'package:shared_module/features/licensing/data/license_store.dart';
import 'package:shared_module/features/licensing/data/online_licence_service.dart';
import 'package:shared_module/features/licensing/domain/license.dart';
import 'package:shared_module/features/licensing/domain/license_verifier.dart';
import 'package:shared_module/features/licensing/domain/online_verdict.dart';

/// POS-BE-031 on the till: the platform's verdict for a connected till, the
/// cache that stands in for it offline, and the rule that a till is only ever
/// moved off its signed file by a real answer from a platform that has the
/// endpoint.
///
/// What is pinned is the gate the start screen reads: every refusal stops the
/// NEXT shift and never the open one (`canSell` stays true), and nothing about
/// the network — slow, down, throttled, an older platform — is ever a refusal
/// on its own.
void main() {
  const cloud = DeploymentConfig(mode: DeploymentMode.cloud);
  final now = DateTime.utc(2026, 10, 7, 12);

  /// The signed-file path, recognisable by a state the online path never uses.
  const fileVerdict = LicenseEntitlement(
    state: LicenseState.terminalNotLicensed,
    canOpenShift: true,
    canSell: true,
    canChangeConfiguration: true,
  );

  late InMemoryLicenceCheckStore store;
  late List<Map<String, Object?>> asked;
  late CloudReply reply;
  late DateTime clock;

  OnlineLicenceService service() => OnlineLicenceService(
    inner: _FileService(fileVerdict),
    checks: store,
    check: (body) async {
      asked.add(body);
      return reply;
    },
    fingerprint: const _Fingerprint(),
    clock: () => clock,
    appVersion: '1.0.0',
  );

  CloudReply ok(String status, {Map<String, Object?> extra = const {}}) =>
      CloudReply(
        status: 200,
        body: {
          'status': status,
          'enforcement': 'online',
          'expires_at': '2027-10-07T00:00:00+00:00',
          'grace_days': 14,
          'grace_policy': {'cache_seconds': 259200},
          ...extra,
        },
      );

  setUp(() {
    store = InMemoryLicenceCheckStore();
    asked = [];
    clock = now;
    reply = const CloudReply.offline();
  });

  group('a till never told where its verdict comes from', () {
    test('a real answer moves it onto the online path', () async {
      reply = ok('valid');

      final verdict = await service().current(cloud);

      expect(verdict.state, LicenseState.valid);
      expect(verdict.canOpenShift, isTrue);
      final record = await store.read();
      expect(record?.enforcement, 'online');
      expect(record?.checkedAt, now);
      expect(asked.single['fingerprint'], 'fp');
      expect(asked.single['deployment_mode'], 'cloud');
    });

    test(
      'an older platform with no such route leaves it on its file',
      () async {
        reply = const CloudReply(status: 404, body: {'message': 'Not Found'});

        expect(await service().current(cloud), fileVerdict);
        expect(await store.read(), isNull);
      },
    );

    test('no platform at all leaves it on its file', () async {
      expect(await service().current(cloud), fileVerdict);
    });

    test('told it is islanded, it keeps its file and stops asking', () async {
      reply = const CloudReply(
        status: 200,
        body: {'status': 'valid', 'enforcement': 'offline'},
      );

      expect(await service().current(cloud), fileVerdict);
      expect((await store.read())?.enforcement, 'offline');

      await service().current(cloud);
      expect(asked, hasLength(1));
    });
  });

  group('the verdict, mapped onto the gate', () {
    test('suspended stops the next shift, never the open one', () async {
      reply = ok('suspended', extra: {'message': 'Invoice unpaid'});

      final verdict = await service().current(cloud);

      expect(verdict.state, LicenseState.suspended);
      expect(verdict.canOpenShift, isFalse);
      expect(verdict.canSell, isTrue);
      expect(verdict.canCashUp, isTrue);
      expect((verdict.notice! as LicenceSuspended).reason, 'Invoice unpaid');
    });

    test('expired is the same shape', () async {
      reply = ok('expired');

      final verdict = await service().current(cloud);

      expect(verdict.state, LicenseState.expired);
      expect(verdict.canOpenShift, isFalse);
      expect(verdict.canSell, isTrue);
    });

    test('not started is the platform\'s word, not a clock problem', () async {
      reply = ok(
        'not_yet_valid',
        extra: {'starts_at': '2026-11-01T00:00:00+00:00'},
      );

      final verdict = await service().current(cloud);

      expect(verdict.canOpenShift, isFalse);
      expect(verdict.canSell, isTrue);
      expect(
        (verdict.notice! as LicenceNotStarted).startsOn,
        DateTime.utc(2026, 11),
      );
    });

    test('no licence on the platform is a verdict, and is kept', () async {
      reply = const CloudReply(
        status: 404,
        body: {'code': 'licence_not_found', 'message': 'none'},
      );

      final verdict = await service().current(cloud);

      expect(verdict.notice, isA<LicenceNotIssued>());
      expect(verdict.canOpenShift, isFalse);
      expect(verdict.canSell, isTrue);
      expect((await store.read())?.verdict?.status, OnlineVerdict.notIssued);
    });

    test('in grace freezes configuration and counts the grace left', () async {
      clock = DateTime.utc(2027, 10, 10);
      reply = ok('in_grace');

      final verdict = await service().current(cloud);

      expect(verdict.canOpenShift, isTrue);
      expect(verdict.canChangeConfiguration, isFalse);
      // Expired 7 Oct with 14 days of grace: grace ends 21 Oct, 11 days on.
      expect((verdict.notice! as LicenceInGrace).daysLeft, 11);
    });
  });

  group('offline, on the cache', () {
    Future<void> confirmedValid() async {
      reply = ok('valid');
      await service().current(cloud);
      reply = const CloudReply.offline();
    }

    test('the last verdict stands in for up to 72 hours', () async {
      await confirmedValid();
      clock = now.add(const Duration(hours: 71));

      expect((await service().current(cloud)).state, LicenseState.valid);
    });

    test('past the window the next shift waits for the platform', () async {
      await confirmedValid();
      clock = now.add(const Duration(hours: 73));

      final verdict = await service().current(cloud);

      expect(verdict.state, LicenseState.unconfirmed);
      expect(verdict.canOpenShift, isFalse);
      expect(verdict.canSell, isTrue);
      expect((verdict.notice! as LicenceUnconfirmed).lastConfirmed, now);
    });

    test('a server asking for a month is held to seven days', () async {
      reply = ok(
        'valid',
        extra: {
          'grace_policy': {'cache_seconds': 30 * 24 * 3600},
        },
      );
      await service().current(cloud);
      reply = const CloudReply.offline();

      clock = now.add(const Duration(days: 6));
      expect((await service().current(cloud)).state, LicenseState.valid);
      clock = now.add(const Duration(days: 8));
      expect((await service().current(cloud)).state, LicenseState.unconfirmed);
    });

    test('throttled or a server error is the same as no answer', () async {
      await confirmedValid();
      for (final status in [429, 500, 401, 403]) {
        reply = CloudReply(status: status, body: const {'code': 'X'});
        expect((await service().current(cloud)).state, LicenseState.valid);
      }
    });

    test('unknown never overwrites a good verdict and never blocks', () async {
      await confirmedValid();
      clock = now.add(const Duration(hours: 1));
      reply = ok('unknown');

      expect((await service().current(cloud)).canOpenShift, isTrue);
      expect((await store.read())?.checkedAt, now);
    });

    test('a suspension heard before going offline is still heard', () async {
      reply = ok('suspended');
      await service().current(cloud);
      reply = const CloudReply.offline();
      clock = now.add(const Duration(hours: 5));

      expect((await service().current(cloud)).state, LicenseState.suspended);
    });
  });

  group('the cache file', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('licence-check'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('round-trips a verdict', () async {
      final file = FileLicenceCheckStore(directory: () async => dir);
      await file.write(
        LicenceCheckRecord(
          enforcement: 'online',
          verdict: OnlineVerdict.tryParse({
            'status': 'expiring_soon',
            'expires_at': '2026-10-20T00:00:00+00:00',
            'grace_policy': {'cache_seconds': 3600},
          }),
          checkedAt: now,
        ),
      );

      final back = await file.read();
      expect(back?.enforcement, 'online');
      expect(back?.verdict?.status, 'expiring_soon');
      expect(back?.verdict?.cacheSeconds, 3600);
      expect(back?.checkedAt, now);
    });

    test('a damaged file reads as nothing cached', () async {
      File('${dir.path}/${FileLicenceCheckStore.fileName}')
          .writeAsStringSync('{not json');

      expect(
        await FileLicenceCheckStore(directory: () async => dir).read(),
        isNull,
      );
    });
  });
}

class _Fingerprint implements TerminalFingerprint {
  const _Fingerprint();
  @override
  Future<String> value() async => 'fp';
}

class _FileService implements LicenceService {
  _FileService(this.verdict);
  final LicenseEntitlement verdict;

  @override
  bool get canActivateOnline => false;
  @override
  Future<LicenseEntitlement> current(DeploymentConfig deployment) async =>
      verdict;
  @override
  Future<LicenseEntitlement> evaluate(
    LicenseFile file,
    DeploymentConfig deployment,
  ) async => verdict;
  @override
  Future<LicenceFetch> fetchByKey(
    String key,
    DeploymentConfig deployment,
  ) async => const LicenceFetch.failed(NoLicenceServer());
  @override
  Future<LicenseFile?> installed() async => null;
  @override
  Future<void> store(LicenseFile file) async {}
}
