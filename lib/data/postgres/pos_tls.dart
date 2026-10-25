import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:postgres/postgres.dart';

import '../../core/config/lan_tls.dart';

/// Every call this app makes into the `postgres` driver's TLS, in one place.
///
/// **What was read, and what is assumed.** Read in the `postgres` 3.5.12
/// source (`lib/src/v3/connection.dart`, `lib/postgres.dart`): the driver
/// sends PostgreSQL's SSLRequest, and on `S` calls
/// `SecureSocket.secure(socket, context: settings.securityContext,
/// onBadCertificate: …)`, where `onBadCertificate` accepts everything under
/// [SslMode.require] and throws `BadCertificateException(cert)` under
/// [SslMode.verifyFull]. On `N` it throws rather than continuing in the
/// clear. It offers **no certificate callback of its own** and does not
/// expose the peer certificate after connecting.
///
/// So a pin cannot be "compare the fingerprint in a callback". It is done the
/// way the driver's own doc comment on [SslMode.require] suggests: verifyFull,
/// with a [SecurityContext] whose only trust anchor is the paired certificate.
/// That rests on three `dart:io` behaviours that were NOT verified by running
/// anything here, and are listed in the slice-C report to check on a real
/// Windows and macOS till:
///
///  1. `SecurityContext(withTrustedRoots: false)` plus
///     `setTrustedCertificatesBytes(pem)` makes that certificate the *only*
///     anchor, on Windows (BoringSSL) and on macOS (SecTrust anchors-only).
///  2. A self-signed certificate that is its own anchor verifies — it carries
///     `CA:TRUE` and `keyCertSign` for exactly this, the shape PostgreSQL's
///     own docs generate for `verify-full`.
///  3. With no `host:` passed, `SecureSocket.secure` checks the certificate
///     against the address the socket was opened to, IP SAN included.
///
/// The rejected alternative was [SslMode.require] plus a fingerprint check
/// after connecting. The driver gives no way to read the certificate
/// afterwards, and a second connection made just to look at it proves
/// nothing about the first.
abstract final class PosTlsSettings {
  static SslMode sslModeFor(LanTlsDecision decision) =>
      switch (decision.transport) {
        LanTransport.loopback || LanTransport.insecureLan => SslMode.disable,
        LanTransport.pinned || LanTransport.verifiedChain => SslMode.verifyFull,
      };

  /// Null means the driver's default: the platform's trusted roots.
  static SecurityContext? securityContextFor(LanTlsDecision decision) {
    final pin = decision.pin;
    if (decision.transport != LanTransport.pinned || pin == null) return null;
    return SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificatesBytes(utf8.encode(pin.pem));
  }

  /// The certificate a refused handshake was refused over, when the driver
  /// said which. Null for every other error.
  static PresentedCertificate? presentedBy(Object error) =>
      error is BadCertificateException
      ? PresentedCertificate.fromDer(error.certificate.der)
      : null;
}

/// Reads the certificate a PostgreSQL server presents, trusting nothing and
/// sending nothing past the TLS handshake.
///
/// PostgreSQL does not start TLS on connect: the client first sends an
/// 8-byte SSLRequest and the server answers one byte, `S` or `N`. This does
/// exactly that, then a TLS handshake whose `onBadCertificate` *records* the
/// certificate and refuses it — so a server nobody has paired with yet still
/// shows its fingerprint, and no password, startup packet or query ever
/// travels on this socket.
///
/// The same sequence the driver runs (listen, pause, `SecureSocket.secure`),
/// copied rather than invented, because it is the one known to work against
/// a real PostgreSQL. `dart:io` only: no driver API is assumed here.
class PostgresCertificateProbe implements ServerCertificateProbe {
  const PostgresCertificateProbe({this.timeout = const Duration(seconds: 5)});

  final Duration timeout;

  /// Length 8, then the SSLRequest code 80877103 (`04 D2 16 2F`).
  static final sslRequest = Uint8List.fromList([0, 0, 0, 8, 4, 210, 22, 47]);

  @override
  Future<CertificateFetch> fetch(String host, int port) async {
    Socket? socket;
    // Once `SecureSocket.secure` has the socket it owns it: the plain socket
    // is detached, and destroying it afterwards is not ours to do.
    var handedOver = false;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      final answer = Completer<int>();
      final subscription = socket.listen(
        (data) {
          if (!answer.isCompleted && data.isNotEmpty) answer.complete(data[0]);
        },
        onError: (Object error) {
          if (!answer.isCompleted) answer.completeError(error);
        },
        onDone: () {
          if (!answer.isCompleted) {
            answer.completeError(
              const SocketException('closed before answering the SSLRequest'),
            );
          }
        },
      );
      socket.add(sslRequest);
      final byte = await answer.future.timeout(timeout);
      if (byte != 0x53) {
        await subscription.cancel();
        return const ServerOffersNoTls();
      }
      subscription.pause();
      handedOver = true;
      return await _handshake(socket);
    } on Object catch (error) {
      return CertificateFetchFailed(error);
    } finally {
      if (!handedOver) socket?.destroy();
    }
  }

  Future<CertificateFetch> _handshake(Socket socket) async {
    X509Certificate? refused;
    try {
      final secure = await SecureSocket.secure(
        socket,
        onBadCertificate: (certificate) {
          refused = certificate;
          return false;
        },
      ).timeout(timeout);
      try {
        // Trusted by the platform already — a certificate a real authority
        // issued. Still returned, so the technician sees what was accepted.
        final peer = secure.peerCertificate;
        return peer == null
            ? const CertificateFetchFailed('no certificate presented')
            : CertificateFetched(PresentedCertificate.fromDer(peer.der));
      } finally {
        secure.destroy();
      }
    } on Object catch (error) {
      final seen = refused;
      return seen == null
          ? CertificateFetchFailed(error)
          : CertificateFetched(PresentedCertificate.fromDer(seen.der));
    }
  }
}

/// The certificate this machine's PostgreSQL presents to the LAN, as the
/// installer published it for the Management pane to read.
///
/// `provision.ps1` writes `server.crt` into the data directory, which only
/// Administrators, SYSTEM and the service account can read — so it also
/// writes a copy, public by nature, beside `install-credentials.json`. Read
/// here and hashed here, by the same [LanTls.sha256OfPem] a child hashes
/// with, so the two screens a technician compares cannot disagree about how
/// a fingerprint is computed.
abstract interface class PublishedServerCertificateSource {
  Future<PresentedCertificate?> read();
}

class FilePublishedServerCertificate
    implements PublishedServerCertificateSource {
  const FilePublishedServerCertificate();

  /// Kept in step with `installer/provision.ps1` by hand.
  static const fileName = 'server-certificate.pem';

  /// Same folder as `install-credentials.json` (`FileInstallerCredentials`).
  static const directoryName = 'XOrder POS';

  @override
  Future<PresentedCertificate?> read() async {
    final root = Platform.environment['ProgramData'];
    if (root == null || root.isEmpty) return null;
    final file = File(
      '$root${Platform.pathSeparator}$directoryName'
      '${Platform.pathSeparator}$fileName',
    );
    try {
      if (!await file.exists()) return null;
      return PresentedCertificate.fromPem(await file.readAsString());
    } on FileSystemException {
      return null;
    }
  }
}
