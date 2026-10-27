import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/core/security/pin_hash.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';

/// A whole restaurant, in one function.
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
    required this.restaurantId,
    required this.branchId,
    required this.terminalId,
  });

  static const slug = 'e2e-diner';
  static const restaurantName = 'End To End Diner';
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

  final int restaurantId;
  final int branchId;
  final String terminalId;

  /// Insert everything, or reuse what a previous run left behind.
  ///
  /// Idempotent because the suite migrates and seeds in `setUp`: only the
  /// ledger is truncated between tests, since re-inserting a menu before each
  /// one would make a fast suite slow for no benefit.
  static Future<E2eSeed> apply(PosDatabase db, DeploymentConfig config) async {
    final restaurant = await db.query(
      config,
      'INSERT INTO pos_restaurants (slug, name) VALUES (@slug, @name) '
      'ON CONFLICT (slug) DO UPDATE SET name = EXCLUDED.name RETURNING id',
      parameters: {'slug': slug, 'name': restaurantName},
    );
    final restaurantId = restaurant.first[0] as int;

    final branch = await db.query(
      config,
      'INSERT INTO pos_branches (restaurant_id, code, name, supported_order_types) '
      "VALUES (@restaurant, @code, @name, ARRAY['dine_in','takeaway']) "
      'ON CONFLICT (restaurant_id, code) DO UPDATE SET name = EXCLUDED.name RETURNING id',
      parameters: {'restaurant': restaurantId, 'code': branchCode, 'name': branchName},
    );
    final branchId = branch.first[0] as int;

    final salt = PinHash.newSalt();
    await db.query(
      config,
      'INSERT INTO pos_users (restaurant_id, branch_id, name, username, pin_salt, pin_hash, capabilities) '
      "VALUES (@restaurant, @branch, @name, @username, @salt, @hash, ARRAY['pos.operate']) "
      'ON CONFLICT (restaurant_id, username) '
      'DO UPDATE SET pin_salt = EXCLUDED.pin_salt, pin_hash = EXCLUDED.pin_hash',
      parameters: {
        'restaurant': restaurantId,
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
      'INSERT INTO pos_terminals (id, restaurant_id, branch_id, name, pairing_code) '
      'VALUES (gen_random_uuid(), @restaurant, @branch, @name, @code) '
      'ON CONFLICT (restaurant_id, pairing_code) '
      'DO UPDATE SET claimed_at = NULL RETURNING id',
      parameters: {
        'restaurant': restaurantId,
        'branch': branchId,
        'name': terminalName,
        'code': pairingCode,
      },
    );

    await db.query(
      config,
      'INSERT INTO pos_dining_tables (restaurant_id, branch_id, label, seats) '
      'VALUES (@restaurant, @branch, @label, @seats) '
      'ON CONFLICT (branch_id, label) DO UPDATE SET seats = EXCLUDED.seats',
      parameters: {
        'restaurant': restaurantId,
        'branch': branchId,
        'label': tableLabel,
        'seats': tableSeats,
      },
    );

    await _menu(db, config, restaurantId);

    return E2eSeed._(
      restaurantId: restaurantId,
      branchId: branchId,
      terminalId: terminal.first[0].toString(),
    );
  }

  static Future<void> _menu(PosDatabase db, DeploymentConfig config, int restaurantId) async {
    final existing = await db.query(
      config,
      'SELECT count(*) FROM pos_products WHERE restaurant_id = @restaurant',
      parameters: {'restaurant': restaurantId},
    );
    if ((existing.first[0] as int) > 0) return;

    final category = await db.query(
      config,
      'INSERT INTO pos_categories (restaurant_id, name_en, slug, sort_order) '
      "VALUES (@restaurant, 'Counter', 'counter', 1) RETURNING id",
      parameters: {'restaurant': restaurantId},
    );
    final categoryId = category.first[0] as int;

    final group = await db.query(
      config,
      'INSERT INTO pos_modifier_groups (restaurant_id, name_en, is_required, max_select) '
      "VALUES (@restaurant, 'Size', true, 1) RETURNING id",
      parameters: {'restaurant': restaurantId},
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
        'INSERT INTO pos_products (restaurant_id, category_id, name_en, price_minor, sku, sort_order) '
        'VALUES (@restaurant, @category, @name, @price, @sku, @sort) RETURNING id',
        parameters: {
          'restaurant': restaurantId,
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
