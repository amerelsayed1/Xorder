import '../../core/config/deployment.dart';
import '../../domain/models/customer.dart';
import '../../domain/models/permissions.dart';
import '../../domain/services/authorization.dart';
import '../../domain/repositories/repositories.dart';
import 'pos_database.dart';

/// Reads and writes `pos_customers` (migration 51, POS-BE-014).
///
/// **Matching happens in SQL, not in Dart.** The obvious implementation — read
/// the directory and filter it with [PosCustomer.matches] — is fine for the
/// hundred customers a new restaurant has and wrong for the twenty thousand an
/// old one has, on a machine that is also running a sale. The model's rule
/// still exists and is still tested; it is what the payment screen filters an
/// already-loaded page with as somebody types, so the two agree on what a
/// match is and only this one is asked to do it over the whole table.
class PostgresCustomersRepository implements CustomersRepository {
  const PostgresCustomersRepository({
    required PosDatabase database,
    required this.config,
    required this.restaurantId,
    this.branchId,
    this.syncsToPlatform = false,
    this.onQueued,
  }) : _db = database;

  /// Told after a customer is queued — see `PostgresOrdersRepository.onQueued`.
  final void Function()? onQueued;

  final PosDatabase _db;
  final DeploymentConfig config;
  final int restaurantId;

  /// The branch an outbox row is stamped with. Null on a till that is not
  /// configured to sync.
  final int? branchId;

  /// Whether a customer created here should be queued for the platform.
  ///
  /// False on an offline install, where there is nobody to tell — and where
  /// queueing would build a backlog that is never drained and shows in the
  /// sync pill forever.
  final bool syncsToPlatform;

  @override
  Future<List<PosCustomer>> search(String query, {int limit = 30}) async {
    final trimmed = query.trim();
    final digits = PosCustomer.normalisePhone(trimmed);

    // An empty box answers the most recently seen rather than nothing: the
    // person the cashier wants is very often the last one served.
    final rows = await _db.query(
      config,
      'SELECT id, platform_id, name, phone, email, address, note '
      'FROM pos_customers WHERE restaurant_id = @r '
      '${trimmed.isEmpty ? '' : 'AND (lower(name) LIKE @name '
          '${digits.isEmpty ? '' : 'OR phone LIKE @phone'}) '}'
      'ORDER BY updated_at DESC, id DESC LIMIT @limit',
      parameters: {
        'r': restaurantId,
        'limit': limit,
        if (trimmed.isNotEmpty) 'name': '%${trimmed.toLowerCase()}%',
        if (trimmed.isNotEmpty && digits.isNotEmpty) 'phone': '%$digits%',
      },
    );

    return [for (final row in rows) _read(row.toList())];
  }

  @override
  Future<PosCustomer> upsert({
    required PosStaff? by,
    required String name,
    required String phone,
    String? email,
    String? address,
    String? note,
  }) async {
    // Re-checked where the write happens, as every repository does: a button
    // that is wrong can only ever show less than is allowed (XORD-001).
    if (Authorization.check(by, PosCapability.customersCreate) is! Allowed) {
      throw const CustomerNotPermitted();
    }

    final normalised = PosCustomer.normalisePhone(phone);
    if (normalised.isEmpty) {
      throw ArgumentError.value(
        phone,
        'phone',
        'A customer with no number cannot be found again.',
      );
    }

    // ON CONFLICT on the phone, which is the identity — so a regular
    // re-entered at the counter has their details corrected rather than
    // becoming a second row the platform would then have to merge.
    //
    // COALESCE on the optional columns: a cashier who types a name and a
    // number for somebody whose address is already known must not blank it.
    final rows = await _db.query(
      config,
      '''
      INSERT INTO pos_customers (restaurant_id, client_transaction_id, name,
                                 phone, email, address, note)
      VALUES (@r, gen_random_uuid(), @name, @phone, @email, @address, @note)
      ON CONFLICT (restaurant_id, phone) DO UPDATE SET
        name       = EXCLUDED.name,
        email      = COALESCE(EXCLUDED.email, pos_customers.email),
        address    = COALESCE(EXCLUDED.address, pos_customers.address),
        note       = COALESCE(EXCLUDED.note, pos_customers.note),
        updated_at = now()
      RETURNING id, platform_id, name, phone, email, address, note
      ''',
      parameters: {
        'r': restaurantId,
        'name': name.trim(),
        'phone': normalised,
        'email': _orNull(email),
        'address': _orNull(address),
        'note': _orNull(note),
      },
    );

    final customer = _read(rows.first.toList());

    // Queued only when this till has somewhere to send it AND the platform
    // does not already know them. A customer who arrived in a bundle has a
    // `platform_id` already; posting them back would be a write the platform
    // has to resolve for no reason.
    if (syncsToPlatform && branchId != null && customer.platformId == null) {
      await _enqueue(customer.id);
      onQueued?.call();
    }

    return customer;
  }

  /// One outbox row per customer, keyed on the row's own uuid.
  ///
  /// `DO NOTHING` on conflict, so a regular corrected twice before the next
  /// drain is queued once — the drain sends the row as it stands when it runs,
  /// not as it stood when it was first touched.
  Future<void> _enqueue(int customerId) async {
    await _db.query(
      config,
      '''
      INSERT INTO pos_sync_outbox
        (restaurant_id, branch_id, event_type, source_id, client_transaction_id)
      SELECT @restaurant, @branch, 'customer', id, client_transaction_id
        FROM pos_customers WHERE id = @id
      ON CONFLICT (restaurant_id, client_transaction_id) DO NOTHING
      ''',
      parameters: {
        'restaurant': restaurantId,
        'branch': branchId,
        'id': customerId,
      },
    );
  }

  static String? _orNull(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  static PosCustomer _read(List<Object?> row) => PosCustomer(
    id: row[0]! as int,
    platformId: row[1] as int?,
    name: row[2]! as String,
    phone: row[3]! as String,
    email: row[4] as String?,
    address: row[5] as String?,
    note: row[6] as String?,
  );
}

/// A till that has not been set up yet: no directory, and nothing to write to.
///
/// Answers empty rather than throwing, so the payment screen renders its
/// search box on an unconfigured machine (the widget tests run here) instead
/// of failing to build. [upsert] refuses, because silently dropping a customer
/// a cashier typed would be worse than the error.
class UnconfiguredCustomersRepository implements CustomersRepository {
  const UnconfiguredCustomersRepository();

  @override
  Future<List<PosCustomer>> search(String query, {int limit = 30}) async =>
      const [];

  @override
  Future<PosCustomer> upsert({
    required PosStaff? by,
    required String name,
    required String phone,
    String? email,
    String? address,
    String? note,
  }) async => throw StateError('This terminal has no database yet.');
}
