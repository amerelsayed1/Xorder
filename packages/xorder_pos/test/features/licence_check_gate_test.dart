import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/data/cloud/cloud_api.dart';
import 'package:xorder_pos/features/licensing/data/licence_check_gate.dart';
import 'package:xorder_pos/features/licensing/data/licence_check_store.dart';
import 'package:xorder_pos/features/licensing/data/licence_service.dart';
import 'package:xorder_pos/features/licensing/data/license_store.dart';
import 'package:xorder_pos/features/licensing/data/online_licence_service.dart';
import 'package:xorder_pos/features/licensing/domain/license.dart';
import 'package:xorder_pos/features/licensing/domain/license_verifier.dart';

/// One licence check leaves the till for one question (S3-4).
///
/// The audit counted three identical `POST /api/pos/license/check` in the
/// first second after launch. The entitlement provider asked once; the
/// licence service it asked was rebuilt three times as the vault, the config
/// and the API settled, and each one asked for itself. The gate is what the
/// rebuilt services share, so what is pinned here is the gate's two rules —
/// one in flight, one a minute — and that services built around one gate
/// honour them.
void main() {
  const cloud = DeploymentConfig(mode: DeploymentMode.cloud);
  final now = DateTime.utc(2026, 10, 16, 9);

  const fileVerdict = LicenseEntitlement(
    state: LicenseState.terminalNotLicensed,
    canOpenShift: true,
    canSell: true,
    canChangeConfiguration: true,
  );

  CloudReply valid() => const CloudReply(
    status: 200,
    body: {
      'status': 'valid',
      'enforcement': 'online',
      'expires_at': '2027-10-07T00:00:00+00:00',
      'grace_days': 14,
      'grace_policy': {'cache_seconds': 259200},
    },
  );

  late _CountingTransport transport;
  late DateTime clock;
  late LicenceCheckGate gate;
  late InMemoryLicenceCheckStore store;

  /// A fresh service around the shared [gate] — what every provider rebuild
  /// at launch amounts to.
  OnlineLicenceService rebuilt() => OnlineLicenceService(
    inner: _FileService(fileVerdict),
    checks: store,
    check: transport.send,
    fingerprint: const _Fingerprint(),
    clock: () => clock,
    appVersion: '1.0.0',
    gate: gate,
  );

  setUp(() {
    transport = _CountingTransport(valid());
    clock = now;
    gate = LicenceCheckGate();
    store = InMemoryLicenceCheckStore();
  });

  group('the gate', () {
    test('three services rebuilt in a second send one check', () async {
      final verdicts = await Future.wait([
        rebuilt().current(cloud),
        rebuilt().current(cloud),
        rebuilt().current(cloud),
      ]);

      expect(transport.calls, 1);
      // And all three got the platform's answer, not a stand-in.
      for (final verdict in verdicts) {
        expect(verdict.state, LicenseState.valid);
      }
    });

    test('a second ask while one is in flight waits for the same answer', () async {
      transport.hold = Completer<void>();

      final first = gate.ask(transport.sendNothing, now: now);
      final second = gate.ask(transport.sendNothing, now: now);
      expect(transport.calls, 1);

      transport.hold!.complete();
      final replies = await Future.wait([first, second]);
      expect(replies.first, same(replies.last));
      expect(transport.calls, 1);
    });

    test('an answer stands for a minute, then it is asked again', () async {
      await rebuilt().current(cloud);
      clock = now.add(const Duration(seconds: 59));
      await rebuilt().current(cloud);
      expect(transport.calls, 1);

      clock = now.add(const Duration(seconds: 61));
      await rebuilt().current(cloud);
      expect(transport.calls, 2);
    });

    test('forced, it asks now whatever the clock says', () async {
      await rebuilt().current(cloud);
      expect(transport.calls, 1);

      await rebuilt().current(cloud, force: true);
      expect(transport.calls, 2);
    });

    test('"no answer" is held for the minute too', () async {
      // An offline till rebuilding its providers must not retry on each one.
      transport.reply = const CloudReply.offline();

      expect(await rebuilt().current(cloud), fileVerdict);
      expect(await rebuilt().current(cloud), fileVerdict);
      expect(transport.calls, 1);
    });

    test('a transport that throws is one failed ask, not a stuck gate', () async {
      transport.explode = true;
      expect(await gate.ask(transport.sendNothing, now: now), isNull);

      transport.explode = false;
      clock = now.add(const Duration(minutes: 2));
      final reply = await gate.ask(transport.sendNothing, now: clock);
      expect(reply, isNotNull);
      expect(transport.calls, 2);
    });

    test('the window is measured on the clock the service keeps', () async {
      // A clock that went backwards — the OS correcting itself at boot — does
      // not hold the gate shut: an ask from "before" the last one is sent.
      await rebuilt().current(cloud);
      clock = now.subtract(const Duration(hours: 1));
      await rebuilt().current(cloud);
      expect(transport.calls, 2);
    });
  });

  group('without a shared gate', () {
    test('each service is on its own, as the unit tests build them', () async {
      final loner = OnlineLicenceService(
        inner: _FileService(fileVerdict),
        checks: store,
        check: transport.send,
        fingerprint: const _Fingerprint(),
        clock: () => clock,
      );
      await loner.current(cloud);
      await loner.current(cloud);
      expect(transport.calls, 1, reason: 'one service still shares with itself');

      final another = OnlineLicenceService(
        inner: _FileService(fileVerdict),
        checks: store,
        check: transport.send,
        fingerprint: const _Fingerprint(),
        clock: () => clock,
      );
      await another.current(cloud);
      expect(transport.calls, 2, reason: 'a service with its own gate asks');
    });
  });
}

/// Counts what actually leaves, and can be held open or made to throw.
class _CountingTransport {
  _CountingTransport(this.reply);

  CloudReply reply;
  int calls = 0;
  Completer<void>? hold;
  bool explode = false;

  Future<CloudReply> send(Map<String, Object?> body) async {
    calls++;
    if (explode) throw StateError('the socket went away');
    if (hold case final gate?) await gate.future;
    return reply;
  }

  /// The same, with no body — for asking the gate directly.
  Future<CloudReply?> sendNothing() => send(const {});
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
