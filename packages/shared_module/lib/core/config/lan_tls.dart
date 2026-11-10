import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// How a till's connection to its PostgreSQL is protected.
///
/// **Encrypted unless somebody decided otherwise** (ADR-006, slice C). The
/// only plaintext a LAN address ever gets is [insecureLan], and that is a
/// technician's audited act in Management, never a fallback: a handshake that
/// fails is a failed connection, not a reason to try again in the clear.
enum LanTransport {
  /// This machine. Traffic to 127.0.0.1 never reaches a network interface, so
  /// there is nothing for TLS to protect — and demanding it would make every
  /// single-till install issue itself a certificate to talk to itself.
  loopback,

  /// A private address a technician turned encryption off for, in
  /// Management › Devices (or an old till that had ticked "trust without
  /// a certificate" before slice C — see `DeploymentConfig.fromJson`). Shown
  /// as a warning on the start screen for as long as it is true.
  insecureLan,

  /// TLS, trusting exactly one certificate: the one the technician confirmed
  /// by fingerprint when this till was paired with its database server.
  pinned,

  /// TLS, verified against the platform's trust store: a server whose
  /// certificate a real authority issued. What a till with no pin gets, and
  /// what a self-signed server fails — which is the moment the wizard offers
  /// the fingerprint to compare.
  verifiedChain;

  bool get encrypted => this == pinned || this == verifiedChain;
}

/// The certificate a till was paired with, as `config.json` keeps it.
///
/// **Both halves are kept, on purpose.** The PEM is what the connection
/// trusts; the fingerprint is what a person compared. Keeping only the PEM
/// would leave nothing to show a technician on the phone; keeping only the
/// fingerprint would need the driver to hand us the server's certificate
/// mid-handshake, which `postgres` 3.5 does not (see `pos_tls.dart`). Each is
/// checked against the other before every pool opens, so a hand-edited file
/// that changed one fails loudly rather than trusting whichever half is wrong.
class PinnedCertificate {
  const PinnedCertificate({required this.sha256, required this.pem});

  /// Lower-case hex, 64 characters, no separators.
  final String sha256;
  final String pem;

  bool get isConsistent => LanTls.sha256OfPem(pem) == sha256;
}

/// What a server answered with on its first handshake — offered to the
/// technician for comparison, never trusted until they confirm it.
class PresentedCertificate {
  const PresentedCertificate({required this.pem, required this.sha256});

  /// From the DER bytes a TLS handshake delivered.
  factory PresentedCertificate.fromDer(List<int> der) => PresentedCertificate(
    pem: LanTls.pemFromDer(der),
    sha256: LanTls.sha256OfDer(der),
  );

  /// Null when [pem] holds no certificate at all.
  static PresentedCertificate? fromPem(String pem) {
    final sha = LanTls.sha256OfPem(pem);
    return sha == null ? null : PresentedCertificate(pem: pem, sha256: sha);
  }

  final String pem;
  final String sha256;

  DateTime? get notAfter => LanTls.notAfterOfPem(pem);

  @override
  bool operator ==(Object other) =>
      other is PresentedCertificate && other.sha256 == sha256;

  @override
  int get hashCode => sha256.hashCode;
}

/// The transport [LanTls.decide] chose, and the pin it chose it with.
class LanTlsDecision {
  const LanTlsDecision(this.transport, {this.pin});

  final LanTransport transport;

  /// Set exactly when [transport] is [LanTransport.pinned].
  final PinnedCertificate? pin;

  @override
  String toString() => 'LanTlsDecision(${transport.name}, ${pin?.sha256})';
}

/// What fetching the server's certificate found. See [ServerCertificateProbe].
sealed class CertificateFetch {
  const CertificateFetch();
}

/// The server spoke TLS and handed over this certificate.
final class CertificateFetched extends CertificateFetch {
  const CertificateFetched(this.certificate);

  final PresentedCertificate certificate;
}

/// PostgreSQL answered the SSLRequest with `N`: `ssl = off`. Every install the
/// slice-C installer made has it on, so this is an older or hand-made server.
final class ServerOffersNoTls extends CertificateFetch {
  const ServerOffersNoTls();
}

/// Nothing usable came back: no route, no listener, a timeout, a handshake
/// that died before any certificate was seen.
final class CertificateFetchFailed extends CertificateFetch {
  const CertificateFetchFailed(this.error);

  final Object error;
}

/// Asks a database server which certificate it presents, trusting nothing.
///
/// The pairing half of TLS: what the wizard calls when the real connection
/// was refused for a certificate, so the technician has a fingerprint to
/// compare. Behind an interface because the implementation opens a socket,
/// and a widget test has no server to open one to.
abstract interface class ServerCertificateProbe {
  Future<CertificateFetch> fetch(String host, int port);
}

/// Why a TLS connection to the database server was refused, in terms of what
/// the technician should do next. See [LanTls.diagnose].
enum LanTlsDiagnosis {
  /// The server does not do TLS. Run the installer on it again.
  notOffered,

  /// No certificate could be read at all; the network is the problem.
  unreachable,

  /// A certificate nobody here has confirmed yet: compare and pair.
  untrusted,

  /// Not the certificate this till was paired with. Either the server was set
  /// up again (compare and re-pair) or somebody is in the middle.
  changed,

  /// The paired certificate, presented for an address it was not issued for.
  nameMismatch,
}

/// The rules, as pure functions — no socket, no driver, no Flutter.
abstract final class LanTls {
  /// Which transport a connection to [host] gets.
  ///
  /// In order, and the order is the policy:
  ///
  ///  1. Loopback is plaintext. A fact about the route, not a decision.
  ///  2. A pin wins over everything else, including [allowInsecureLan]. The
  ///     two are never set together by this build — turning encryption off
  ///     clears the pin and pairing clears the flag — so this only decides a
  ///     hand-edited file, and it decides it towards encryption.
  ///  3. [allowInsecureLan] is honoured for a private address only. A
  ///     mistyped public hostname must never inherit a LAN concession.
  ///  4. Everything else verifies against the platform's trust store.
  ///
  /// The rejected alternative was `SslMode.require` as the default for a LAN
  /// host: it encrypts, but the `postgres` package then accepts *every*
  /// certificate, so anybody on the switch can sit in the middle and read the
  /// till's password on its way past. That is encryption without
  /// authentication, and it is the thing pinning exists to replace.
  static LanTlsDecision decide({
    required String host,
    required bool allowInsecureLan,
    String? pinnedSha256,
    String? pinnedPem,
  }) {
    final address = host.trim();
    if (isLoopbackHost(address)) {
      return const LanTlsDecision(LanTransport.loopback);
    }
    final sha = normaliseFingerprint(pinnedSha256);
    final pem = pinnedPem?.trim() ?? '';
    if (address.isNotEmpty && sha != null && pem.isNotEmpty) {
      return LanTlsDecision(
        LanTransport.pinned,
        pin: PinnedCertificate(sha256: sha, pem: pem),
      );
    }
    if (allowInsecureLan && isPrivateHost(address)) {
      return const LanTlsDecision(LanTransport.insecureLan);
    }
    return const LanTlsDecision(LanTransport.verifiedChain);
  }

  /// What a refused TLS connection means, from what the server presented and
  /// what this till was paired with.
  static LanTlsDiagnosis diagnose({
    required PinnedCertificate? pin,
    required CertificateFetch fetch,
  }) => switch (fetch) {
    ServerOffersNoTls() => LanTlsDiagnosis.notOffered,
    CertificateFetchFailed() => LanTlsDiagnosis.unreachable,
    CertificateFetched(:final certificate) => switch (pin) {
      null => LanTlsDiagnosis.untrusted,
      // The very certificate this till trusts, and the connection was still
      // refused: the only check left that can fail is the name.
      PinnedCertificate(sha256: final trusted)
          when trusted == certificate.sha256 =>
        LanTlsDiagnosis.nameMismatch,
      PinnedCertificate() => LanTlsDiagnosis.changed,
    },
  };

  /// This machine, by the only three spellings that mean it.
  static bool isLoopbackHost(String host) {
    final value = host.trim();
    return value == 'localhost' || value == '127.0.0.1' || value == '::1';
  }

  /// This machine or a box on the same LAN: `localhost`, `*.local`, RFC 1918
  /// and 127/8. The only addresses [LanTransport.insecureLan] may apply to.
  static bool isPrivateHost(String host) {
    final value = host.trim().toLowerCase();
    if (value.isEmpty) return false;
    if (value == 'localhost' || value.endsWith('.local')) return true;

    final octets = value.split('.');
    if (octets.length != 4) return false;
    final first = int.tryParse(octets[0]);
    final second = int.tryParse(octets[1]);
    if (first == null || second == null) return false;

    return first == 10 ||
        first == 127 ||
        (first == 192 && second == 168) ||
        (first == 172 && second >= 16 && second <= 31);
  }

  /// `AB:CD:…`, `ab cd …` or `abcd…` → `abcd…`; null unless it is 32 bytes of
  /// hex. Lenient on purpose: a fingerprint read aloud over the phone and
  /// typed back arrives in any of these shapes.
  static String? normaliseFingerprint(String? value) {
    if (value == null) return null;
    final hex = value.replaceAll(RegExp(r'[\s:]'), '').toLowerCase();
    return RegExp(r'^[0-9a-f]{64}$').hasMatch(hex) ? hex : null;
  }

  /// `AB:CD:EF:…` — the shape `openssl x509 -fingerprint` and Windows print,
  /// so a technician comparing against either reads the same characters.
  static String formatFingerprint(String sha256) {
    final hex = normaliseFingerprint(sha256);
    if (hex == null) return sha256;
    return [
      for (var i = 0; i < hex.length; i += 2) hex.substring(i, i + 2),
    ].join(':').toUpperCase();
  }

  static String sha256OfDer(List<int> der) => sha256.convert(der).toString();

  /// The SHA-256 of the first certificate in [pem], over its DER bytes — the
  /// same bytes `provision.ps1` hashes, so the main device and the child
  /// agree to the character. Null when [pem] holds no certificate.
  static String? sha256OfPem(String pem) {
    final der = derFromPem(pem);
    return der == null ? null : sha256OfDer(der);
  }

  static const _begin = '-----BEGIN CERTIFICATE-----';
  static const _end = '-----END CERTIFICATE-----';

  /// The first certificate in [pem]. A chain file holds the server's own
  /// certificate first, and that is the one a fingerprint is about.
  static Uint8List? derFromPem(String pem) {
    final start = pem.indexOf(_begin);
    if (start < 0) return null;
    final end = pem.indexOf(_end, start);
    if (end < 0) return null;
    final body = pem
        .substring(start + _begin.length, end)
        .replaceAll(RegExp(r'\s'), '');
    if (body.isEmpty) return null;
    try {
      return base64.decode(body);
    } on FormatException {
      return null;
    }
  }

  /// 64-character lines, the width OpenSSL writes and PostgreSQL reads.
  static String pemFromDer(List<int> der) {
    final body = base64.encode(der);
    final lines = [
      for (var i = 0; i < body.length; i += 64)
        body.substring(i, i + 64 > body.length ? body.length : i + 64),
    ];
    return '$_begin\n${lines.join('\n')}\n$_end\n';
  }

  /// When the first certificate in [pem] stops being valid; null when it
  /// cannot be read.
  ///
  /// Read here rather than trusted from a side file because the installer's
  /// certificate lives 825 days — the longest Apple's TLS policy accepts, and
  /// a tablet child may be an iPad — so the date is something a technician
  /// needs to see coming, on the screen they already look at.
  static DateTime? notAfterOfPem(String pem) {
    final der = derFromPem(pem);
    return der == null ? null : notAfterOfDer(der);
  }

  /// Walks `Certificate → tbsCertificate → validity → notAfter` (RFC 5280
  /// §4.1) and nothing else. Not a certificate parser, and not trusted for
  /// anything but a date on a screen.
  static DateTime? notAfterOfDer(Uint8List der) {
    try {
      final certificate = _Tlv.at(der, 0);
      final tbs = _Tlv.at(der, certificate.valueStart);
      var field = _Tlv.at(der, tbs.valueStart);
      // [0] EXPLICIT version, present on every v3 certificate.
      if (field.tag == 0xA0) field = _Tlv.at(der, field.end);
      // field is serialNumber; then signature, issuer, validity.
      final signature = _Tlv.at(der, field.end);
      final issuer = _Tlv.at(der, signature.end);
      final validity = _Tlv.at(der, issuer.end);
      final notBefore = _Tlv.at(der, validity.valueStart);
      final notAfter = _Tlv.at(der, notBefore.end);
      return _time(
        notAfter.tag,
        ascii.decode(der.sublist(notAfter.valueStart, notAfter.end)),
      );
    } on RangeError {
      return null;
    } on FormatException {
      return null;
    }
  }

  /// UTCTime `YYMMDDHHMMSSZ` or GeneralizedTime `YYYYMMDDHHMMSSZ`.
  static DateTime? _time(int tag, String text) {
    if (!text.endsWith('Z')) return null;
    final digits = text.substring(0, text.length - 1);
    final int year;
    final String rest;
    if (tag == 0x17 && digits.length == 12) {
      final yy = int.parse(digits.substring(0, 2));
      // RFC 5280 §4.1.2.5.1: 50 and above is the 1900s.
      year = yy >= 50 ? 1900 + yy : 2000 + yy;
      rest = digits.substring(2);
    } else if (tag == 0x18 && digits.length == 14) {
      year = int.parse(digits.substring(0, 4));
      rest = digits.substring(4);
    } else {
      return null;
    }
    int part(int at) => int.parse(rest.substring(at, at + 2));
    return DateTime.utc(year, part(0), part(2), part(4), part(6), part(8));
  }
}

/// One DER tag-length-value header.
class _Tlv {
  const _Tlv(this.tag, this.valueStart, this.end);

  final int tag;
  final int valueStart;
  final int end;

  static _Tlv at(Uint8List der, int offset) {
    final tag = der[offset];
    final first = der[offset + 1];
    var length = 0;
    var header = 2;
    if (first < 0x80) {
      length = first;
    } else {
      final count = first & 0x7f;
      if (count == 0 || count > 4) {
        throw const FormatException('unsupported DER length');
      }
      for (var i = 0; i < count; i++) {
        length = (length << 8) | der[offset + 2 + i];
      }
      header += count;
    }
    final end = offset + header + length;
    if (end > der.length) throw RangeError('DER value runs past the end');
    return _Tlv(tag, offset + header, end);
  }
}
