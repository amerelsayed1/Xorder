import '../../core/config/deployment.dart';
import 'pos_database.dart';

/// The restaurant a till is working for.
///
/// Every read repository needs this before it can ask anything, because every
/// table under migration 2 is scoped to a restaurant. It is resolved from the
/// tenant slug the operator typed at setup — `mahsoub` in `mahsoub.xorder.io` —
/// which is also the only tenant identifier available *during* setup, before a
/// terminal has been claimed and a numeric id is known.
class PosTenant {
  const PosTenant({required this.id, required this.name, this.nameAr, this.taxNumber});

  final int id;
  final String name;
  final String? nameAr;
  final String? taxNumber;
}

/// Thrown when the configured tenant slug matches no restaurant.
///
/// A distinct type because it is an ordinary operator mistake — a typo in the
/// wizard, or a database that was never seeded — and the UI should say which,
/// rather than showing a driver error.
class PosTenantMissing implements Exception {
  const PosTenantMissing(this.slug);

  final String? slug;

  @override
  String toString() {
    final name = slug;
    return name == null || name.isEmpty
        ? 'No restaurant is configured for this terminal. Set the restaurant '
            'short name in Settings.'
        : 'No restaurant named "$name" exists in this database. Check the short '
            'name, or seed it with bin/pos_migrate.dart --seed.';
  }
}

/// Resolves and caches the tenant for the life of a repository.
///
/// Cached because it never changes for a given till and is needed by every
/// query: re-reading it on each catalogue refresh would be a round trip to
/// learn something already known.
class PosTenantResolver {
  PosTenantResolver(this._db, this._config);

  final PosDatabase _db;
  final DeploymentConfig _config;
  PosTenant? _cached;

  Future<PosTenant> resolve() async {
    final cached = _cached;
    if (cached != null) return cached;

    final slug = _config.tenantSlug;
    if (slug == null || slug.isEmpty) throw PosTenantMissing(slug);

    final rows = await _db.query(
      _config,
      'SELECT id, name, name_ar, tax_number FROM pos_restaurants '
      'WHERE slug = @slug AND is_active',
      parameters: {'slug': slug},
    );
    if (rows.isEmpty) throw PosTenantMissing(slug);

    return _cached = PosTenant(
      id: rows.first[0] as int,
      name: rows.first[1] as String,
      nameAr: rows.first[2] as String?,
      taxNumber: rows.first[3] as String?,
    );
  }
}
