import '../core/config/deployment.dart';

/// Seeding this till's database from a platform bootstrap reply.
///
/// **pos-split-apps, stage 3.** The setup wizard's "Download menu" step
/// fetches `GET /api/pos/bootstrap` and hands the body here. Parsing the
/// bundle and writing it (`BootstrapBundle`, `BootstrapSeeder`) are cloud code
/// in `apps/xorder_pos_cloud`, which binds them to `bootstrapSeedingProvider`;
/// the offline app binds nothing, and never reaches the step that would ask.
abstract interface class BootstrapSeeding {
  /// Parse [body] and seed [config]'s database from it.
  ///
  /// Returns false when the body is not a bundle this build can seed from, so
  /// the wizard can say so; throws for a database failure.
  Future<bool> seed(
    Map<String, Object?> body, {
    required DeploymentConfig config,
    required bool force,
  });
}
