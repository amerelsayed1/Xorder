import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/config/lan_tls.dart';
import 'package:shared_module/features/waiter_link/waiter_link_tls.dart';

/// The till's own certificate, made in Dart, carries a real TLS handshake on
/// the Dart VM's BoringSSL — the same library the handheld's dart:io uses on
/// Android and iOS. A handheld pins it by fingerprint and nothing else.
void main() {
  test('a generated identity serves HTTPS and the client pins its fingerprint', () async {
    final identity = await WaiterLinkIdentity.generate(name: 'Main till — Maadi', random: Random(1));
    expect(identity.isUsable, isTrue);
    expect(identity.sha256, hasLength(64));
    expect(identity.notAfter!.difference(DateTime.now().toUtc()).inDays, inInclusiveRange(820, 825));
    expect(WaiterLinkIdentity.fromJson(identity.toJson())!.sha256, identity.sha256, reason: 'round-trips the store');

    final context = SecurityContext()
      ..useCertificateChainBytes(utf8.encode(identity.certificatePem))
      ..usePrivateKeyBytes(utf8.encode(identity.privateKeyPem));
    final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, context);
    addTearDown(() => server.close(force: true));
    server.listen((request) {
      request.response
        ..write('ok')
        ..close();
    });

    // Trusting nothing by chain: the callback is the whole decision.
    String? presented;
    final client = HttpClient(context: SecurityContext(withTrustedRoots: false))
      ..badCertificateCallback = (certificate, host, port) {
        presented = LanTls.sha256OfDer(certificate.der);
        return presented == identity.sha256;
      };
    addTearDown(() => client.close(force: true));
    final response = await (await client.getUrl(Uri.parse('https://127.0.0.1:${server.port}/'))).close();
    expect(await utf8.decodeStream(response), 'ok');
    expect(presented, identity.sha256, reason: 'the certificate on the wire is the one the till made');

    // A different pin is refused at the handshake, before any request.
    final stranger = HttpClient(context: SecurityContext(withTrustedRoots: false))
      ..badCertificateCallback = (certificate, host, port) => false;
    addTearDown(() => stranger.close(force: true));
    await expectLater(
      stranger.getUrl(Uri.parse('https://127.0.0.1:${server.port}/')).then((r) => r.close()),
      throwsA(isA<HandshakeException>()),
    );
  });

  test('two identities differ; the same seed is the same certificate', () async {
    final a = await WaiterLinkIdentity.generate(name: 'A', random: Random(1), now: DateTime.utc(2026, 11, 9));
    final b = await WaiterLinkIdentity.generate(name: 'A', random: Random(2), now: DateTime.utc(2026, 11, 9));
    final c = await WaiterLinkIdentity.generate(name: 'A', random: Random(1), now: DateTime.utc(2026, 11, 9));
    expect(a.sha256, isNot(b.sha256));
    expect(a.sha256, c.sha256);
    expect(a.certificatePem, contains('BEGIN CERTIFICATE'));
    expect(a.privateKeyPem, contains('BEGIN PRIVATE KEY'));
    expect(a.expiresWithin(const Duration(days: 60), now: DateTime.utc(2026, 11, 9)), isFalse);
    expect(a.expiresWithin(const Duration(days: 60), now: DateTime.utc(2029, 1, 1)), isTrue);
  });
}
