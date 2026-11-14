import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart' as pc;

import '../../core/config/lan_tls.dart';

/// The certificate a till presents to its waiter handhelds (waiter-app, WA4).
///
/// **Made here, in pure Dart, once per till.** The LAN certificate the
/// installer makes for PostgreSQL cannot be reused: its private key is
/// readable by the database service only, and a cloud till has no PostgreSQL
/// at all. So the till mints its own on the first start of the link — an
/// ECDSA P-256 key (Ed25519, the licence's algorithm, was tried first; the
/// Dart VM's BoringSSL would not negotiate it in a handshake) in a self-signed
/// X.509 v3 certificate — and keeps the pair in the operating system's secret
/// store under [secretKey], so the fingerprint a waiter confirmed stays the
/// same across restarts and the key never sits in a file.
///
/// Nothing verifies this certificate by chain. A handheld pins its SHA-256
/// (`LanTls.sha256OfDer`), confirmed once against the fingerprint the till
/// shows under Settings › Waiter devices, exactly as a child till pins its
/// database server (ADR-006, slice C). The shape is therefore the minimum a
/// TLS library accepts as a server certificate: subject and issuer the till's
/// name, 825 days (the longest Apple's policy allows, an iPad may be a
/// handheld), `CA:TRUE`, `digitalSignature + keyCertSign`, `serverAuth`.
class WaiterLinkIdentity {
  const WaiterLinkIdentity({required this.certificatePem, required this.privateKeyPem});

  /// Where the till keeps it ([SecretStore]).
  static const secretKey = 'waiter_link.identity';

  final String certificatePem;

  /// PKCS#8, unencrypted — the secret store is the encryption.
  final String privateKeyPem;

  /// Lower-case hex, no separators: what a handheld pins.
  String get sha256 => LanTls.sha256OfPem(certificatePem) ?? '';

  DateTime? get notAfter => LanTls.notAfterOfPem(certificatePem);

  bool get isUsable => sha256.isNotEmpty && privateKeyPem.contains('PRIVATE KEY');

  /// Whether a certificate made now would serve longer than this one with
  /// the margin the installer uses for the database's (its last 60 days).
  bool expiresWithin(Duration margin, {DateTime? now}) {
    final end = notAfter;
    return end == null || !(now ?? DateTime.now()).toUtc().add(margin).isBefore(end);
  }

  String toJson() => jsonEncode({'certificate': certificatePem, 'private_key': privateKeyPem});

  static WaiterLinkIdentity? fromJson(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map) return null;
      final cert = decoded['certificate'], key = decoded['private_key'];
      if (cert is! String || key is! String) return null;
      final identity = WaiterLinkIdentity(certificatePem: cert, privateKeyPem: key);
      return identity.isUsable ? identity : null;
    } on FormatException {
      return null;
    }
  }

  /// A fresh identity for [name] ("Main till — Maadi").
  static Future<WaiterLinkIdentity> generate({
    required String name,
    DateTime? now,
    Duration lifetime = const Duration(days: 825),
    Random? random,
  }) async {
    final rng = random ?? Random.secure();
    final secureRandom = pc.FortunaRandom()
      ..seed(pc.KeyParameter(Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)))));
    final curve = pc.ECCurve_secp256r1();
    final generator = pc.ECKeyGenerator()
      ..init(pc.ParametersWithRandom(pc.ECKeyGeneratorParameters(curve), secureRandom));
    final pair = generator.generateKeyPair();
    final privateKey = pair.privateKey;
    final publicKey = pair.publicKey;
    final point = publicKey.Q!;
    // Uncompressed SEC 1 point: 04 || X || Y, each 32 bytes.
    final publicPoint = Uint8List.fromList([
      0x04,
      ..._fixed(point.x!.toBigInteger()!, 32),
      ..._fixed(point.y!.toBigInteger()!, 32),
    ]);
    final notBefore = (now ?? DateTime.now()).toUtc();
    final notAfter = notBefore.add(lifetime);

    // A positive serial: the top bit clear so DER's INTEGER needs no padding.
    final serial = Uint8List.fromList(List.generate(16, (_) => rng.nextInt(256)));
    serial[0] &= 0x7f;
    if (serial[0] == 0) serial[0] = 1;

    final tbs = _Der.sequence([
      _Der.explicit(0, _Der.integer([2])), // v3
      _Der.integer(serial),
      _ecdsaSha256,
      _name(name),
      _Der.sequence([_Der.utcTime(notBefore), _Der.utcTime(notAfter)]),
      _name(name),
      _Der.sequence([_ecPublicKeyP256, _Der.bitString(publicPoint)]),
      _Der.explicit(3, _Der.sequence([
        _extension(_oidBasicConstraints, critical: true, value: _Der.sequence([_Der.boolean(true)])),
        // digitalSignature (bit 0) and keyCertSign (bit 5): 1000 0100, two unused bits.
        _extension(_oidKeyUsage, critical: true, value: _Der.bitString([0x84], unusedBits: 2)),
        _extension(_oidExtendedKeyUsage, value: _Der.sequence([_Der.oid(_oidServerAuth)])),
      ])),
    ]);
    // Deterministic nonces (RFC 6979): a bad random can never leak the key
    // through a repeated k.
    final signer = pc.ECDSASigner(pc.SHA256Digest(), pc.HMac(pc.SHA256Digest(), 64))
      ..init(true, pc.PrivateKeyParameter<pc.ECPrivateKey>(privateKey));
    final signature = signer.generateSignature(tbs) as pc.ECSignature;
    final signatureDer = _Der.sequence([_Der.bigInteger(signature.r), _Der.bigInteger(signature.s)]);
    final certificate = _Der.sequence([tbs, _ecdsaSha256, _Der.bitString(signatureDer)]);

    // PKCS#8 PrivateKeyInfo around an RFC 5915 ECPrivateKey.
    final ecPrivateKey = _Der.sequence([
      _Der.integer([1]),
      _Der.octetString(_fixed(privateKey.d!, 32)),
      _Der.explicit(1, _Der.bitString(publicPoint)),
    ]);
    final privateKeyInfo = _Der.sequence([
      _Der.integer([0]),
      _ecPublicKeyP256,
      _Der.octetString(ecPrivateKey),
    ]);

    return WaiterLinkIdentity(
      certificatePem: LanTls.pemFromDer(certificate),
      privateKeyPem: _pem('PRIVATE KEY', privateKeyInfo),
    );
  }

  /// [value] as exactly [length] big-endian bytes.
  static Uint8List _fixed(BigInt value, int length) {
    final bytes = Uint8List(length);
    var v = value;
    for (var i = length - 1; i >= 0; i--) {
      bytes[i] = (v & BigInt.from(0xff)).toInt();
      v >>= 8;
    }
    return bytes;
  }

  /// ecdsa-with-SHA256, no parameters (RFC 5758 §3.2).
  static final _ecdsaSha256 = _Der.sequence([_Der.oid(_oidEcdsaSha256)]);

  /// id-ecPublicKey with the named curve prime256v1 (RFC 5480 §2.1.1).
  static final _ecPublicKeyP256 = _Der.sequence([_Der.oid(_oidEcPublicKey), _Der.oid(_oidPrime256v1)]);

  static Uint8List _name(String commonName) => _Der.sequence([
    _Der.set([_Der.sequence([_Der.oid(_oidCommonName), _Der.utf8String(commonName)])]),
    _Der.set([_Der.sequence([_Der.oid(_oidOrganisation), _Der.utf8String('XOrder POS')])]),
  ]);

  static Uint8List _extension(List<int> oid, {bool critical = false, required Uint8List value}) => _Der.sequence([
    _Der.oid(oid),
    if (critical) _Der.boolean(true),
    _Der.octetString(value),
  ]);

  static String _pem(String label, List<int> der) {
    final body = base64.encode(der);
    final lines = [for (var i = 0; i < body.length; i += 64) body.substring(i, min(i + 64, body.length))];
    return '-----BEGIN $label-----\n${lines.join('\n')}\n-----END $label-----\n';
  }

  // OIDs, pre-encoded.
  static const _oidEcdsaSha256 = [0x2a, 0x86, 0x48, 0xce, 0x3d, 0x04, 0x03, 0x02]; // 1.2.840.10045.4.3.2
  static const _oidEcPublicKey = [0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01]; // 1.2.840.10045.2.1
  static const _oidPrime256v1 = [0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07]; // 1.2.840.10045.3.1.7
  static const _oidCommonName = [0x55, 0x04, 0x03]; // 2.5.4.3
  static const _oidOrganisation = [0x55, 0x04, 0x0a]; // 2.5.4.10
  static const _oidBasicConstraints = [0x55, 0x1d, 0x13]; // 2.5.29.19
  static const _oidKeyUsage = [0x55, 0x1d, 0x0f]; // 2.5.29.15
  static const _oidExtendedKeyUsage = [0x55, 0x1d, 0x25]; // 2.5.29.37
  static const _oidServerAuth = [0x2b, 0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x01]; // 1.3.6.1.5.5.7.3.1
}

/// The handful of DER encodings an X.509 certificate needs. Encoders only —
/// the till never parses a certificate beyond `LanTls.notAfterOfDer`.
abstract final class _Der {
  static Uint8List tlv(int tag, List<int> value) {
    final length = value.length;
    final header = <int>[tag];
    if (length < 0x80) {
      header.add(length);
    } else {
      final bytes = <int>[];
      var n = length;
      while (n > 0) {
        bytes.insert(0, n & 0xff);
        n >>= 8;
      }
      header
        ..add(0x80 | bytes.length)
        ..addAll(bytes);
    }
    return Uint8List.fromList([...header, ...value]);
  }

  static Uint8List sequence(List<List<int>> items) => tlv(0x30, [for (final i in items) ...i]);
  static Uint8List set(List<List<int>> items) => tlv(0x31, [for (final i in items) ...i]);
  static Uint8List explicit(int index, List<int> inner) => tlv(0xa0 | index, inner);

  /// A non-negative INTEGER from big-endian bytes.
  static Uint8List integer(List<int> bytes) => tlv(0x02, bytes.isNotEmpty && bytes[0] & 0x80 != 0 ? [0, ...bytes] : bytes);

  /// A positive INTEGER from a [BigInt]: minimal bytes, sign bit padded.
  static Uint8List bigInteger(BigInt value) {
    var hex = value.toRadixString(16);
    if (hex.length.isOdd) hex = '0$hex';
    final bytes = [for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)];
    return integer(bytes);
  }

  static Uint8List boolean(bool value) => tlv(0x01, [value ? 0xff : 0x00]);
  static Uint8List oid(List<int> encoded) => tlv(0x06, encoded);
  static Uint8List octetString(List<int> bytes) => tlv(0x04, bytes);
  static Uint8List bitString(List<int> bytes, {int unusedBits = 0}) => tlv(0x03, [unusedBits, ...bytes]);
  static Uint8List utf8String(String text) => tlv(0x0c, utf8.encode(text));

  /// `YYMMDDHHMMSSZ` (RFC 5280 §4.1.2.5.1: UTCTime through 2049).
  static Uint8List utcTime(DateTime utc) {
    String two(int n) => n.toString().padLeft(2, '0');
    final text = '${two(utc.year % 100)}${two(utc.month)}${two(utc.day)}${two(utc.hour)}${two(utc.minute)}${two(utc.second)}Z';
    return tlv(0x17, ascii.encode(text));
  }
}
