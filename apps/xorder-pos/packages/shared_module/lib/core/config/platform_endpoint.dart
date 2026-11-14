import 'package:flutter/foundation.dart' show kDebugMode;

/// The hosted XOrder platform, as a fixed fact about the build.
///
/// Deliberately **not** [DeploymentConfig.baseUrl]. Two things need the platform
/// before a terminal has been configured at all:
///
///   * licence activation, which now runs as the *first* wizard step, before
///     any address has been typed; and
///   * licence renewal on an offline terminal, which has no `baseUrl` ever.
///
/// Reading it from device config would mean an operator could point licence
/// activation at their own machine, which is the one check in the system that
/// must not be operator-configurable. That rule is about RELEASE builds, and it
/// is why [devDefault] below applies only in debug — see [base].
class PlatformEndpoint {
  const PlatformEndpoint._();

  /// The production platform. What a shipped till asks, always.
  static const production = 'https://xorder.io';

  /// The local stack from `docker-compose.yml` (`web` on :8080), which is where
  /// a licence issued from a developer's own Super Admin actually lives.
  static const devDefault = 'http://localhost:8080';

  /// Set at build time to point anywhere else:
  /// `flutter run --dart-define=XORDER_PLATFORM=https://staging.xorder.app`.
  static const _override = String.fromEnvironment('XORDER_PLATFORM');

  /// Where activation and renewal go.
  ///
  /// **A debug build defaults to the local stack, not to production.** A
  /// developer who issues a licence from their own Super Admin and types the
  /// key into a till they just launched is not asking to talk to xorder.io —
  /// but that is what a single production constant did, and production answered
  /// truthfully that it had never heard of the key. The message read as a bad
  /// key, and the key was perfect.
  ///
  /// The safety property is unchanged, because it was always about shipped
  /// software: a release build ignores [devDefault] entirely and an operator
  /// still cannot repoint licence checking at a machine they control. An
  /// explicit `--dart-define` wins over both, so staging needs no code change.
  static String get base {
    if (_override.isNotEmpty) return _override;
    return kDebugMode ? devDefault : production;
  }

  /// Exchanges a typed key for a signed licence file (POS-BE-015).
  static Uri get licenceActivation =>
      Uri.parse('$base/api/pos/licence/activate');
}
