/// Sealing a receipt with the taxpayer's e-seal.
///
/// **The key is not here, and should not be.** Egypt issues an e-seal as an
/// X.509 certificate whose private key lives on a hardware token or an HSM and
/// is not exportable — that non-exportability is the entire point of it. A
/// Flutter process cannot hold it, and a design that assumed it could would be
/// a design that only works for a taxpayer who has already broken the rule
/// they are being audited against.
///
/// So signing is an interface with the key on the far side of it, and the
/// deployment decides what that side is:
///
/// * ETA's own integration toolkit, run as a local service beside the branch
///   server, which is what their SDK is for;
/// * a signing service on the branch server holding the token;
/// * a service provider signing on the taxpayer's behalf, which is what
///   `signatureType` `S` exists for.
///
/// What this file guarantees is that a till which has none of those **says
/// so**, loudly and at the right moment, rather than queueing receipts nobody
/// can file.
library;

/// Who sealed the receipt, in ETA's vocabulary.
enum EtaSignatureType {
  /// `I` — the issuer. The taxpayer's own seal.
  issuer('I'),

  /// `S` — a service provider signing on their behalf.
  serviceProvider('S');

  const EtaSignatureType(this.wire);

  final String wire;
}

/// A seal over one document.
class EtaSignature {
  const EtaSignature({
    required this.value,
    this.type = EtaSignatureType.issuer,
  });

  /// The CAdES-BES structure, base64. Opaque here on purpose: this process
  /// does not build it and must not pretend to be able to check it.
  final String value;

  final EtaSignatureType type;
}

/// Why a receipt could not be sealed.
///
/// Separate cases rather than one message, because the answers are different
/// jobs for different people: a till with nothing configured needs an
/// installer, and a token that has been unplugged needs whoever is standing
/// next to it.
sealed class EtaSigningFailure {
  const EtaSigningFailure();
}

/// Nothing has been set up. The normal state of a fresh install, and the state
/// a restaurant is in right up until the day it must not be.
class NoSealConfigured extends EtaSigningFailure {
  const NoSealConfigured();
}

/// Configured, but not reachable — the toolkit is down, the token is out.
class SealUnavailable extends EtaSigningFailure {
  const SealUnavailable(this.detail);

  final String detail;
}

/// It answered, and refused.
class SealRefused extends EtaSigningFailure {
  const SealRefused(this.detail);

  final String detail;
}

/// Signs the canonical text of a receipt.
abstract interface class EtaReceiptSigner {
  /// Whether this till can seal a receipt at all.
  ///
  /// Asked before a sale is queued rather than after, so a restaurant learns
  /// it cannot file from a settings screen instead of from a queue that has
  /// been silently growing for a fortnight.
  Future<bool> get isConfigured;

  /// Seals [canonical] — the exact text that was hashed, never a rebuild.
  ///
  /// Returns the failure rather than throwing: a till that cannot reach its
  /// token must keep selling, and an exception here would have to be caught by
  /// every caller anyway.
  Future<({EtaSignature? signature, EtaSigningFailure? failure})> sign(
    String canonical,
  );
}

/// The binding a till gets when nothing has been configured.
///
/// **It refuses honestly rather than failing late.** The tempting alternative
/// — return an empty signature and let the authority reject it — would turn a
/// setup problem into a compliance one, discovered days later by whoever reads
/// the rejection. This one is discoverable the moment somebody opens the
/// receipt settings.
class UnconfiguredEtaSigner implements EtaReceiptSigner {
  const UnconfiguredEtaSigner();

  @override
  Future<bool> get isConfigured async => false;

  @override
  Future<({EtaSignature? signature, EtaSigningFailure? failure})> sign(
    String canonical,
  ) async => (signature: null, failure: const NoSealConfigured());
}
