// Issues the signed licence files the till verifies.
//
// The verifier in `lib/features/licensing/domain/license_verifier.dart` has
// always done real Ed25519. What did not exist was anything to sign with, so the
// app was wired to `FakeLicenceService`, which accepted **any non-empty key** —
// `HELLO` licensed a terminal for a year. That is the half of the licence system
// this file supplies.
//
// Two jobs:
//
//   # Once, per release channel. The public half is embedded in the app; the
//   # private half never leaves whoever issues licences.
//   dart run bin/pos_licence.dart keygen
//
//   # Per customer.
//   POS_LICENCE_KEY=<private-key-b64> dart run bin/pos_licence.dart issue \
//     --tenant amer --name "Amer's Kitchen" --days 365 --out amer.xlic
//
// **What this is not.** The verification key ships inside the binary, so anyone
// willing to patch the binary defeats every check. This is commercial hygiene,
// not security — the same as every offline licence system ever built. Real
// enforcement stays server-side.

import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/features/licensing/domain/license.dart';
import 'package:xorder_pos/features/licensing/domain/license_verifier.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty || arguments.first == '--help' || arguments.first == 'help') {
    stdout.writeln(usage);
    return;
  }

  final command = arguments.first;
  final options = _parse(arguments.skip(1).toList());

  switch (command) {
    case 'keygen':
      await _keygen();
    case 'issue':
      await _issue(options);
    case 'inspect':
      await _inspect(options);
    default:
      stderr.writeln('Unknown command "$command".\n');
      stderr.writeln(usage);
      exit(64);
  }
}

/// Mint a signing key pair.
///
/// Printed rather than written to disk: a private key that lands in the repo
/// directory is a private key that gets committed. Whoever runs this puts it
/// somewhere deliberate.
Future<void> _keygen() async {
  final pair = await Ed25519().newKeyPair();
  final publicKey = await pair.extractPublicKey();
  final privateBytes = await pair.extractPrivateKeyBytes();

  stdout
    ..writeln('Public key — embed this in lib/features/licensing/data/license_keys.dart:')
    ..writeln()
    ..writeln('  ${base64.encode(publicKey.bytes)}')
    ..writeln()
    ..writeln('Private key — keep it out of the repository and off shared drives:')
    ..writeln()
    ..writeln('  ${base64.encode(privateBytes)}')
    ..writeln()
    ..writeln('Issue with it via POS_LICENCE_KEY, not --private-key, so it stays')
    ..writeln('out of your shell history.');
}

Future<void> _issue(Map<String, String> options) async {
  final privateB64 = options['private-key'] ?? Platform.environment['POS_LICENCE_KEY'] ?? '';
  final tenant = options['tenant'];
  final name = options['name'];

  if (privateB64.isEmpty || tenant == null || name == null) {
    stderr.writeln(
      'issue needs --tenant, --name, and a private key in POS_LICENCE_KEY '
      '(or --private-key).',
    );
    exit(64);
  }

  final days = int.tryParse(options['days'] ?? '365');
  if (days == null || days <= 0) {
    stderr.writeln('--days must be a positive number of days.');
    exit(64);
  }

  // Dated from the issuing machine's clock. The verifier refuses a licence that
  // starts in the future and says to check the terminal's date, so a wrong
  // clock here produces a confusing failure at a restaurant rather than a
  // security problem.
  final now = DateTime.now().toUtc();
  final claims = LicenseClaims(
    licenseId: options['id'] ?? 'lic-${now.millisecondsSinceEpoch}',
    tenantSlug: tenant.trim().toLowerCase(),
    tenantName: name,
    issuedAt: now.subtract(const Duration(minutes: 5)),
    expiresAt: now.add(Duration(days: days)),
    graceDays: int.tryParse(options['grace-days'] ?? '') ?? 14,
    warnDays: int.tryParse(options['warn-days'] ?? '') ?? 30,
    maxTerminals: int.tryParse(options['max-terminals'] ?? '') ?? 1,
    features: _set(options['features']) ?? const {'pos'},
    modes: _modes(options['modes']),
    fingerprints: _set(options['fingerprints']) ?? const {},
    plan: options['plan'],
  );

  final payload = base64Url.encode(utf8.encode(jsonEncode(claims.toJson())));

  final pair = await Ed25519().newKeyPairFromSeed(base64.decode(privateB64));
  final signature = await Ed25519().sign(
    base64Url.decode(_pad(payload)),
    keyPair: pair,
  );

  final file = LicenseFile(
    payloadB64: payload,
    signatureB64: base64Url.encode(signature.bytes),
    keyId: options['key-id'] ?? 'v1',
  );

  final out = options['out'];
  if (out == null) {
    stdout.writeln(file.serialize());
  } else {
    await File(out).writeAsString(file.serialize());
    stdout
      ..writeln('Wrote $out')
      ..writeln('  ${claims.tenantName} (${claims.tenantSlug})')
      ..writeln('  expires ${claims.expiresAt.toIso8601String()}, '
          'then ${claims.graceDays} days grace')
      ..writeln('  covers ${claims.modes.map((m) => m.wire).join(', ')}');
  }
}

/// Read a licence back without installing it.
///
/// The one thing a support call needs: is this file signed by us, and what does
/// it actually say?
Future<void> _inspect(Map<String, String> options) async {
  final path = options['file'];
  if (path == null) {
    stderr.writeln('inspect needs --file <licence.xlic>.');
    exit(64);
  }

  final file = LicenseFile.tryParse(await File(path).readAsString());
  if (file == null) {
    stderr.writeln('$path is not a licence file.');
    exit(1);
  }

  final claims = LicenseVerifier.claimsOf(file);
  if (claims == null) {
    stderr.writeln('$path is damaged — the claims could not be read.');
    exit(1);
  }

  final publicB64 = options['public-key'] ?? Platform.environment['POS_LICENCE_PUBLIC_KEY'];
  final signed = publicB64 == null
      ? null
      : await LicenseVerifier(publicKeyBytes: base64.decode(publicB64)).verifySignature(file);

  stdout
    ..writeln(path)
    ..writeln('  tenant     ${claims.tenantName} (${claims.tenantSlug})')
    ..writeln('  issued     ${claims.issuedAt.toIso8601String()}')
    ..writeln('  expires    ${claims.expiresAt.toIso8601String()}')
    ..writeln('  grace      ${claims.graceDays} days')
    ..writeln('  modes      ${claims.modes.map((m) => m.wire).join(', ')}')
    ..writeln('  terminals  ${claims.maxTerminals}')
    ..writeln('  signature  ${switch (signed) {
      null => 'not checked — pass --public-key to verify',
      true => 'valid',
      false => 'DOES NOT VERIFY against that key',
    }}');
}

Set<String>? _set(String? value) =>
    value?.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();

Set<DeploymentMode> _modes(String? value) {
  final names = _set(value);
  if (names == null || names.isEmpty) return DeploymentMode.values.toSet();
  return names.map(DeploymentMode.fromWire).whereType<DeploymentMode>().toSet();
}

Map<String, String> _parse(List<String> arguments) {
  final values = <String, String>{};
  for (var i = 0; i < arguments.length; i++) {
    final argument = arguments[i];
    if (!argument.startsWith('--')) {
      stderr.writeln('Unexpected argument "$argument".');
      exit(64);
    }
    if (i + 1 >= arguments.length) {
      stderr.writeln('"$argument" needs a value.');
      exit(64);
    }
    values[argument.substring(2)] = arguments[++i];
  }
  return values;
}

String _pad(String value) =>
    value.padRight(value.length + ((4 - value.length % 4) % 4), '=');

const usage = '''
Issue and inspect XOrder POS licence files.

  dart run bin/pos_licence.dart keygen
  dart run bin/pos_licence.dart issue  [options]
  dart run bin/pos_licence.dart inspect --file <licence.xlic> [--public-key <b64>]

keygen prints a fresh Ed25519 pair. The public half goes into
lib/features/licensing/data/license_keys.dart and ships in the binary; the
private half issues licences and must never be committed.

issue options:
  --tenant <slug>      Restaurant short name. Must match the terminal's. Required
  --name <name>        Shown when a licence is refused for the wrong tenant. Required
  --days <n>           Term length. Default 365
  --grace-days <n>     Trading allowed after expiry. Default 14
  --warn-days <n>      When the renewal banner appears. Default 30
  --max-terminals <n>  Advisory offline — only a server can really count. Default 1
  --modes <list>       cloud,branch_server,standalone. Default all three
  --features <list>    Default "pos"
  --fingerprints <ls>  Pin to specific machines. Default unpinned
  --plan <name>        Shown on the licence screen
  --id <id>            Licence id. Default derived from the clock
  --key-id <id>        Which signing key this is. Default v1
  --out <path>         Write here rather than to stdout
  --private-key <b64>  Prefer the POS_LICENCE_KEY environment variable

Example:

  POS_LICENCE_KEY=… dart run bin/pos_licence.dart issue \\
    --tenant amer --name "Amer's Kitchen" --days 365 \\
    --modes branch_server --out amer.xlic
''';
