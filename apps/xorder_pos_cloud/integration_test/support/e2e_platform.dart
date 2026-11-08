import 'dart:io';

/// The platform half of the end-to-end suite.
///
/// The till under test needs a real server to sign in to: the tenant, and the
/// owner account the wizard signs in with (pos-cloud-sign-in-setup). That
/// account must be the business owner's (`RESTAURANT_ADMIN`), and the tenant
/// must hold a live cloud licence, which arrives in the bootstrap bundle.
///
/// Skips the whole suite when `POS_PLATFORM_URL` is unset, the same bargain
/// `POS_PG_HOST` already makes: a machine with no local API running should say
/// so rather than fail.
abstract final class E2ePlatform {
  static String? get baseUrl => Platform.environment['POS_PLATFORM_URL'];
  static String get slug => Platform.environment['POS_TENANT_SLUG'] ?? 'demo';
  static String get username => Platform.environment['POS_TENANT_USER'] ?? 'admin';
  static String get password =>
      Platform.environment['POS_TENANT_PASSWORD'] ?? 'Demo1234!';

  /// The till PIN of the platform user this suite signs shifts in with.
  ///
  /// On the cloud path the bootstrap bundle REPLACES the till's staff table
  /// with the platform's — so a PIN seeded locally by the test is gone the
  /// moment registration succeeds, and the shift must be opened with the
  /// credential the platform actually sent down. That replacement is the
  /// feature working, not a bug: head office owns who may open a drawer.
  static String get staffPin => Platform.environment['POS_STAFF_PIN'] ?? '4829';
}
