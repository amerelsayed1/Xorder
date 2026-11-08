import 'package:shared_module/core/config/deployment.dart';
import 'package:shared_module/core/security/pin_hash.dart';
import 'package:shared_module/data/postgres/pos_database.dart';

/// A whole business, in one function.
///
/// The end-to-end suite used to lean on `FakeCatalogRepository` for its menu.
/// It cannot any more, and should not: the till now reads everything from the
/// branch database, so a test that skipped that read would be testing a code
/// path no installation runs.
///
/// Small on purpose. Two products priced to make the arithmetic checkable by
/// hand — 25.00 and 55.00, so the subtotal is 80.00 — one modifier group to
/// prove attachments survive the round trip, and one table so a ticket can be
/// seated.
class E2eSeed {
  const E2eSeed._({
    required this.businessId,
    required this.branchId,
    required this.terminalId,
  });

  static const slug = 'e2e-diner';
  static const businessName = 'End To End Diner';
  static const branchName = 'Test Branch';

  /// The invoice prefix, so a sale here reads `TEST-2026-000001`. Deliberately
  /// not a real branch code belonging to anybody.
  static const branchCode = 'TEST';

  static const terminalName = 'Counter 1';
  static const pairingCode = 'TEST-0001';
  static const staffName = 'Test Cashier';
  static const staffUsername = 'cashier';
  static const staffPin = '4321';
  static const tableLabel = 'T1';
  static const tableSeats = 2;

  /// 25.00 — no modifier groups, so it goes straight onto the ticket.
  static const water = 'Still Water';
  static const waterMinor = 2500;

  /// 55.00 — carries a required group, so tapping it opens the sheet.
  static const fries = 'House Fries';
  static const friesMinor = 5500;

  final int businessId;
  final int branchId;
  final String terminalId;

  /// Insert everything, or reuse what a previous run left behind.
  ///
  /// Idempotent because the suite migrates and seeds in `setUp`: only the
  /// ledger is truncated between tests, since re-inserting a menu before each
  /// one would make a fast suite slow for no benefit.
  static Future<E2eSeed> apply(PosDatabase db, DeploymentConfig config) async {
    final business = await db.query(
      config,
      'INSERT INTO pos_businesses (slug, name) VALUES (@slug, @name) '
      'ON CONFLICT (slug) DO UPDATE SET name = EXCLUDED.name RETURNING id',
      parameters: {'slug': slug, 'name': businessName},
    );
    final businessId = business.first[0] as int;

    final branch = await db.query(
      config,
      'INSERT INTO pos_branches (business_id, code, name, supported_order_types) '
      "VALUES (@business, @code, @name, ARRAY['dine_in','takeaway']) "
      'ON CONFLICT (business_id, code) DO UPDATE SET name = EXCLUDED.name RETURNING id',
      parameters: {'business': businessId, 'code': branchCode, 'name': branchName},
    );
    final branchId = branch.first[0] as int;

    final salt = PinHash.newSalt();
    await db.query(
      config,
      'INSERT INTO pos_users (business_id, branch_id, name, username, pin_salt, pin_hash, capabilities) '
      "VALUES (@business, @branch, @name, @username, @salt, @hash, ARRAY['pos.operate']) "
      'ON CONFLICT (business_id, username) '
      'DO UPDATE SET pin_salt = EXCLUDED.pin_salt, pin_hash = EXCLUDED.pin_hash',
      parameters: {
        'business': businessId,
        'branch': branchId,
        'name': staffName,
        'username': staffUsername,
        'salt': salt,
        'hash': await PinHash.hash(staffPin, salt),
      },
    );

    // The pairing code is single-use, and every test in the suite walks setup.
    // Resetting `claimed_at` is what lets the second test claim it again —
    // production has no such reset, which is the point of the column.
    final terminal = await db.query(
      config,
      'INSERT INTO pos_terminals (id, business_id, branch_id, name, pairing_code) '
      'VALUES (gen_random_uuid(), @business, @branch, @name, @code) '
      'ON CONFLICT (business_id, pairing_code) '
      'DO UPDATE SET claimed_at = NULL RETURNING id',
      parameters: {
        'business': businessId,
        'branch': branchId,
        'name': terminalName,
        'code': pairingCode,
      },
    );

    await db.query(
      config,
      'INSERT INTO pos_dining_tables (business_id, branch_id, label, seats) '
      'VALUES (@business, @branch, @label, @seats) '
      'ON CONFLICT (branch_id, label) DO UPDATE SET seats = EXCLUDED.seats',
      parameters: {
        'business': businessId,
        'branch': branchId,
        'label': tableLabel,
        'seats': tableSeats,
      },
    );

    await _menu(db, config, businessId);

    return E2eSeed._(
      businessId: businessId,
      branchId: branchId,
      terminalId: terminal.first[0].toString(),
    );
  }

  static Future<void> _menu(PosDatabase db, DeploymentConfig config, int businessId) async {
    final existing = await db.query(
      config,
      'SELECT count(*) FROM pos_products WHERE business_id = @business',
      parameters: {'business': businessId},
    );
    if ((existing.first[0] as int) > 0) return;

    final category = await db.query(
      config,
      'INSERT INTO pos_categories (business_id, name_en, slug, sort_order) '
      "VALUES (@business, 'Counter', 'counter', 1) RETURNING id",
      parameters: {'business': businessId},
    );
    final categoryId = category.first[0] as int;

    final group = await db.query(
      config,
      'INSERT INTO pos_modifier_groups (business_id, name_en, is_required, max_select) '
      "VALUES (@business, 'Size', true, 1) RETURNING id",
      parameters: {'business': businessId},
    );
    final groupId = group.first[0] as int;

    await db.query(
      config,
      'INSERT INTO pos_modifiers (group_id, name_en, price_delta_minor, sort_order) '
      "VALUES (@group, 'Regular', 0, 1), (@group, 'Large', 1000, 2)",
      parameters: {'group': groupId},
    );

    for (final (name, minor, sku, sort) in [
      (water, waterMinor, 'E2E-001', 1),
      (fries, friesMinor, 'E2E-002', 2),
    ]) {
      final product = await db.query(
        config,
        'INSERT INTO pos_products (business_id, category_id, name_en, price_minor, sku, sort_order) '
        'VALUES (@business, @category, @name, @price, @sku, @sort) RETURNING id',
        parameters: {
          'business': businessId,
          'category': categoryId,
          'name': name,
          'price': minor,
          'sku': sku,
          'sort': sort,
        },
      );

      // Only the chips carry the group. Water with no modifiers is what proves
      // a plain product still goes straight onto the ticket.
      if (name == fries) {
        await db.query(
          config,
          'INSERT INTO pos_product_modifier_groups (product_id, group_id) VALUES (@product, @group)',
          parameters: {'product': product.first[0], 'group': groupId},
        );
      }
    }
  }
}
