import 'dart:convert';

/// The licence-signing public key that ships in the binary.
///
/// The private half lives with whoever issues licences and is never in this
/// repository. Replace both per release channel: a build signed by a key you
/// cannot rotate is a build you cannot stop issuing licences for.
///
/// Generate a pair with:
///
/// ```
/// dart run bin/pos_licence.dart keygen
/// ```
///
/// **This is commercial hygiene, not security.** The key below is public by
/// definition — it ships to every customer — so anyone willing to patch the
/// binary defeats every check that uses it. That is true of every offline
/// licence system and is not a reason to skip it; it is a reason not to rely on
/// it for anything that actually matters. Real enforcement stays server-side.
abstract final class LicenseKeys {
  /// The public key and key id are injected for every production build.
  ///
  /// They are build-time values rather than a checked-in release constant so a
  /// compromised/retired issuer can be rotated without giving the development
  /// issuer authority over restaurant binaries.  A release build that omits
  /// either value fails closed when the verifier is constructed.
  static const _releaseB64 = String.fromEnvironment(
    'XORDER_LICENSE_PUBLIC_KEY_B64',
  );
  static const _releaseId = String.fromEnvironment('XORDER_LICENSE_KEY_ID');

  /// Ed25519 public key, base64, used only by debug/profile builds.
  ///
  /// The **development** channel key — the platform's own pair.
  ///
  /// Deliberately the public half of `LICENCE_SIGNING_KEY` in `apps/api`, not a
  /// key minted on this side. The platform is the issuer: `LicenceIssuer::mint`
  /// signs every licence the dashboard hands out, and a till that verified
  /// against anything else would reject them all. There is one pair, and the
  /// POS holds the half that cannot sign.
  ///
  /// A release build must not use this. Run `php artisan licence:keygen` for
  /// the release channel and supply its public half through
  /// `XORDER_LICENSE_PUBLIC_KEY_B64` before signing the installer.
  static const _developmentB64 = 'ZRdC6SonAA+7/63bGBT5z2JauylXU0iYZe79hU78vE0=';

  /// Which key signed a given file. Files carry `key_id` so a rotation can be
  /// rolled out before the old key stops being honoured.
  static String get currentB64 {
    if (_releaseB64.isNotEmpty) return _releaseB64;
    if (const bool.fromEnvironment('dart.vm.product')) {
      throw StateError(
        'A release build requires XORDER_LICENSE_PUBLIC_KEY_B64.',
      );
    }
    return _developmentB64;
  }

  static String get currentId {
    if (_releaseId.isNotEmpty) return _releaseId;
    if (const bool.fromEnvironment('dart.vm.product')) {
      throw StateError('A release build requires XORDER_LICENSE_KEY_ID.');
    }
    return 'development-v1';
  }

  static List<int> get current {
    final key = base64.decode(currentB64);
    if (key.length != 32) {
      throw StateError('The configured licence public key is not an Ed25519 key.');
    }
    return key;
  }
}
