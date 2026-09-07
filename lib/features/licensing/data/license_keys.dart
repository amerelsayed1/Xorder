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
  /// Ed25519 public key, base64.
  /// The **development** channel key — the platform's own pair.
  ///
  /// Deliberately the public half of `LICENCE_SIGNING_KEY` in `apps/api`, not a
  /// key minted on this side. The platform is the issuer: `LicenceIssuer::mint`
  /// signs every licence the dashboard hands out, and a till that verified
  /// against anything else would reject them all. There is one pair, and the
  /// POS holds the half that cannot sign.
  ///
  /// A release build must not ship this. Run `php artisan licence:keygen` for
  /// the release channel, embed that public half **before** anything is signed
  /// with it — see the rotation rule in `config/licence.php` — and keep the
  /// secret with the issuer.
  static const currentB64 = 'ZRdC6SonAA+7/63bGBT5z2JauylXU0iYZe79hU78vE0=';

  /// Which key signed a given file. Files carry `key_id` so a rotation can be
  /// rolled out before the old key stops being honoured.
  static const currentId = 'v1';

  static List<int> get current => base64.decode(currentB64);
}
