import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_module/core/config/deployment.dart';
import 'package:shared_module/core/config/lan_tls.dart';
import 'package:shared_module/data/postgres/pos_database.dart';
import 'package:shared_module/data/postgres/pos_tls.dart';

import 'package:xorder_pos_test_support/lan_tls_fixtures.dart';

/// A refused handshake is an error, never a plaintext retry (ADR-006 §TLS
/// downgrade test).
///
/// Against a fake PostgreSQL on 127.0.0.1 that speaks only the first eight
/// bytes of the protocol — the SSLRequest — and then TLS, so it needs no
/// database and runs in every `flutter test`. It counts every StartupMessage
/// it is sent in the clear: that packet carries the role name and is followed
/// by the password exchange, and the number this suite exists to keep at
/// zero.
///
/// The real transport rule never encrypts loopback, so the till's decision is
/// injected through [PosDatabase]'s `transportFor` — the one thing that
/// parameter exists for.
///
/// The `pinned` cases also check, on whatever machine runs them, the three
/// `dart:io` assumptions `pos_tls.dart` lists: a self-signed certificate is
/// accepted as its own anchor, it is the only anchor, and the address is
/// checked against its IP SAN.
void main() {
  test('the fixtures have not expired', () {
    expect(
      DateTime.now().toUtc().isBefore(fixtureNotAfter),
      isTrue,
      reason: 'regenerate test/support/lan_tls_fixtures.dart (how is written '
          'at its top) — every case below would fail for the wrong reason',
    );
  });

  final servers = <_FakePostgres>[];
  final databases = <PosDatabase>[];
  tearDown(() async {
    for (final database in databases) {
      await database.close();
    }
    databases.clear();
    for (final server in servers) {
      await server.close();
    }
    servers.clear();
  });

  Future<_FakePostgres> serve(_Answer answer) async {
    final server = await _FakePostgres.start(answer);
    servers.add(server);
    return server;
  }

  DeploymentConfig configFor(_FakePostgres server) => DeploymentConfig(
    mode: DeploymentMode.offline,
    databaseHost: '127.0.0.1',
    databasePort: server.port,
    databaseUser: 'pos_till',
    role: TerminalRole.child,
  );

  PosDatabase databaseWith(LanTlsDecision decision) {
    final database = PosDatabase(
      credentials: InMemoryPosDbCredentials('till-secret'),
      transportFor: (_) => decision,
    );
    databases.add(database);
    return database;
  }

  LanTlsDecision pinnedTo(String pem) => LanTls.decide(
    host: '192.168.1.20',
    allowInsecureLan: false,
    pinnedSha256: LanTls.sha256OfPem(pem),
    pinnedPem: pem,
  );

  const verified = LanTlsDecision(LanTransport.verifiedChain);

  Matcher refusedAs(PosDbFailure failure) => throwsA(
    isA<PosDbException>().having((e) => e.failure, 'failure', failure),
  );

  group('a server that does not offer TLS', () {
    test('is a TLS failure, and the till never sends its login in the clear',
        () async {
      final server = await serve(_Answer.noTls);
      final database = databaseWith(verified);

      await expectLater(
        database.query(configFor(server), 'SELECT 1'),
        refusedAs(PosDbFailure.tls),
      );
      // Asked twice, to be sure a retry does not change its mind.
      await expectLater(
        database.query(configFor(server), 'SELECT 1'),
        refusedAs(PosDbFailure.tls),
      );

      expect(server.sslRequests, greaterThanOrEqualTo(1));
      expect(server.plaintextStartups, 0);
    });
  });

  group('a handshake that dies', () {
    test('surfaces as an error and is not retried in plaintext', () async {
      final server = await serve(_Answer.yesThenHangUp);
      final database = databaseWith(pinnedTo(fixtureACertificate));

      await expectLater(
        database.query(configFor(server), 'SELECT 1'),
        throwsA(isA<PosDbException>()),
      );
      expect(server.plaintextStartups, 0);
    });
  });

  group('a certificate the till does not trust', () {
    test('a self-signed server fails verification — no pin, no connection',
        () async {
      final server = await serve(_Answer.tlsAsA);
      final database = databaseWith(verified);

      await expectLater(
        database.query(configFor(server), 'SELECT 1'),
        refusedAs(PosDbFailure.tls),
      );
      expect(server.tlsStartups, 0);
      expect(server.plaintextStartups, 0);
    });

    test('a server presenting another certificate than the pinned one is '
        'refused, not tried again without it', () async {
      final server = await serve(_Answer.tlsAsA);
      final database = databaseWith(pinnedTo(fixtureBCertificate));

      await expectLater(
        database.query(configFor(server), 'SELECT 1'),
        refusedAs(PosDbFailure.tls),
      );
      expect(server.tlsStartups, 0, reason: 'nothing crossed the handshake');
      expect(server.plaintextStartups, 0);
    });
  });

  group('the pinned certificate', () {
    test('is trusted: the login travels inside TLS', () async {
      final server = await serve(_Answer.tlsAsA);
      final database = databaseWith(pinnedTo(fixtureACertificate));

      // The fake hangs up after the StartupMessage, so the query itself fails
      // — what matters is where that message arrived.
      await expectLater(
        database.query(configFor(server), 'SELECT 1'),
        throwsA(anything),
      );
      expect(server.tlsStartups, 1);
      expect(server.plaintextStartups, 0);
    });

    test('a pin whose PEM and fingerprint disagree opens nothing', () async {
      final server = await serve(_Answer.tlsAsA);
      final database = databaseWith(
        const LanTlsDecision(
          LanTransport.pinned,
          pin: PinnedCertificate(
            sha256: fixtureBSha256,
            pem: fixtureACertificate,
          ),
        ),
      );

      await expectLater(
        database.query(configFor(server), 'SELECT 1'),
        refusedAs(PosDbFailure.tls),
      );
      expect(server.sslRequests, 0, reason: 'refused before any socket');
    });
  });

  group('reading the certificate for pairing', () {
    const probe = PostgresCertificateProbe(timeout: Duration(seconds: 3));

    test('shows the fingerprint a self-signed server presents', () async {
      final server = await serve(_Answer.tlsAsA);

      final fetched = await probe.fetch('127.0.0.1', server.port);

      expect(fetched, isA<CertificateFetched>());
      expect((fetched as CertificateFetched).certificate.sha256, fixtureASha256);
      // And it sent nothing a password could ride on.
      expect(server.tlsStartups, 0);
      expect(server.plaintextStartups, 0);
    });

    test('says when the server has no TLS at all', () async {
      final server = await serve(_Answer.noTls);

      expect(
        await probe.fetch('127.0.0.1', server.port),
        isA<ServerOffersNoTls>(),
      );
      expect(server.plaintextStartups, 0);
    });

    test('says when nothing answers', () async {
      final unused = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = unused.port;
      await unused.close();

      expect(
        await probe.fetch('127.0.0.1', port),
        isA<CertificateFetchFailed>(),
      );
    });
  });
}

enum _Answer {
  /// `N`: `ssl = off`.
  noTls,

  /// `S`, then the socket is closed before any handshake.
  yesThenHangUp,

  /// `S`, then TLS as fixture A; hangs up after the first packet inside.
  tlsAsA,
}

/// Just enough of PostgreSQL to watch what a client sends before and after
/// it decides about TLS.
class _FakePostgres {
  _FakePostgres._(this._server, this._answer);

  static Future<_FakePostgres> start(_Answer answer) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _FakePostgres._(server, answer);
    server.listen(fake._serve);
    return fake;
  }

  final ServerSocket _server;
  final _Answer _answer;
  final _sockets = <Socket>[];

  int get port => _server.port;

  /// SSLRequests received: the only thing a client may send in the clear.
  int sslRequests = 0;

  /// Anything else received before TLS — a StartupMessage, and with it the
  /// role name and the start of the password exchange.
  int plaintextStartups = 0;

  /// Packets received inside a completed TLS handshake.
  int tlsStartups = 0;

  static const _sslRequestCode = 80877103;

  void _serve(Socket socket) {
    _sockets.add(socket);
    final received = <int>[];
    late final StreamSubscription<Uint8List> subscription;
    subscription = socket.listen(
      (data) {
        received.addAll(data);
        if (received.length < 8) return;
        final bytes = Uint8List.fromList(received);
        received.clear();
        final code = ByteData.sublistView(bytes, 4, 8).getUint32(0);
        if (code != _sslRequestCode) {
          plaintextStartups++;
          socket.destroy();
          return;
        }
        sslRequests++;
        switch (_answer) {
          case _Answer.noTls:
            socket.add(ascii.encode('N'));
          case _Answer.yesThenHangUp:
            socket.add(ascii.encode('S'));
            socket.destroy();
          case _Answer.tlsAsA:
            socket.add(ascii.encode('S'));
            subscription.pause();
            // TLS owns it from here; the plain socket is detached.
            _sockets.remove(socket);
            unawaited(_secure(socket));
        }
      },
      onError: (Object _) {},
    );
  }

  Future<void> _secure(Socket socket) async {
    final context = SecurityContext()
      ..useCertificateChainBytes(utf8.encode(fixtureACertificate))
      ..usePrivateKeyBytes(utf8.encode(fixtureAKey));
    try {
      final secure = await SecureSocket.secureServer(socket, context);
      _sockets.add(secure);
      secure.listen(
        (data) {
          tlsStartups++;
          secure.destroy();
        },
        onError: (Object _) {},
      );
    } on Object {
      // The client refused the certificate — the case under test, not a
      // failure of the fake.
    }
  }

  Future<void> close() async {
    for (final socket in _sockets) {
      try {
        socket.destroy();
      } on Object {
        // Already gone; a fake's teardown is not what is under test.
      }
    }
    await _server.close();
  }
}
