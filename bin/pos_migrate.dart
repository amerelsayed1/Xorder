// Prepares a branch server's PostgreSQL for the tills that will write to it.
//
// This is the missing half of `lib/data/postgres/migrations.dart`. The migrator
// has always been there; nothing outside the tests ever ran it, which left a
// real branch box with no way to get a schema short of someone pasting DDL into
// psql at a restaurant on opening night.
//
// It is a **separate command with an admin credential**, deliberately, rather
// than something the till does at boot. The till connects as `pos_till`, which
// is granted the least it can do its job with and no DDL at all — a role that
// could CREATE TABLE could also DROP one, and that credential sits on a machine
// in a public room. Schema changes are an install-time act by someone with the
// keys, not a side effect of a cashier turning a till on.
//
// Pure Dart: no Flutter engine, so it runs on a headless server.
//
//   dart run bin/pos_migrate.dart --host 192.168.1.20 --user postgres \
//     --create-database --grant-to pos_till
//
// The password comes from POS_PG_PASSWORD unless --password is given, because a
// password passed on the command line is a password in shell history.

import 'dart:io';
import 'dart:math';

import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/core/security/pin_hash.dart';
import 'package:xorder_pos/data/postgres/local_bootstrap.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';
import 'package:xorder_pos/domain/models/permissions.dart';
import 'package:xorder_pos/domain/models/reason_code.dart';

Future<void> main(List<String> arguments) async {
  final Options options;
  try {
    options = Options.parse(arguments);
  } on FormatException catch (error) {
    stderr.writeln('${error.message}\n');
    stderr.writeln(usage);
    exit(64); // EX_USAGE
  }

  if (options.help) {
    stdout.writeln(usage);
    return;
  }

  if (options.password.isEmpty) {
    stderr.writeln(
      'No password. Set POS_PG_PASSWORD, or pass --password if you do not mind '
      'it being in your shell history.',
    );
    exit(64);
  }

  try {
    if (options.createDatabase) await _createDatabase(options);

    final database = PosDatabase(
      credentials: InMemoryPosDbCredentials(options.password),
    );
    try {
      if (options.status) {
        await _reportStatus(database, options);
        return;
      }

      final applied = await PosMigrator(database).migrate(options.config);
      if (applied.isEmpty) {
        stdout.writeln('${options.describe} is already up to date.');
      } else {
        for (final version in applied) {
          final migration = posMigrations.firstWhere(
            (m) => m.version == version,
          );
          stdout.writeln(
            'applied ${migration.version} · ${migration.description}',
          );
        }
      }

      if (options.seed) await _seed(database, options);
      // After --seed, so a single invocation can do both and the catalogue
      // finds the restaurant the same run just created.
      if (options.seedCatalogue) await _seedCatalogue(database, options);

      final till = options.grantTo;
      if (till != null) await _grant(database, options, till, admin: false);

      final admin = options.grantAdminTo;
      if (admin != null) await _grant(database, options, admin, admin: true);
    } finally {
      await database.close();
    }
  } on PosDbException catch (error) {
    // `PosDatabase` has already worked out *which* of the four things went
    // wrong. Saying so is the entire value: an installer sent to open a
    // firewall port when the password is wrong will not fix it.
    stderr.writeln('Could not migrate ${options.describe}.');
    stderr.writeln(_explain(error, options));
    exit(1);
  }
}

/// Turn a connection failure into the next thing to try.
///
/// Deliberately parallel to what the setup wizard tells an operator, because
/// the person running this command and the person running that wizard are
/// usually the same person on the same afternoon.
String _explain(
  PosDbException error,
  Options options,
) => switch (error.failure) {
  PosDbFailure.dns =>
    'The name "${options.host}" does not resolve. Use its IP address, or '
        'give the box a fixed address on the router.',
  PosDbFailure.tcp =>
    'Nothing answered on port ${options.port}. Check PostgreSQL is running, '
        "that listen_addresses includes this network, and the host's firewall "
        'allows the connection.',
  PosDbFailure.auth =>
    'PostgreSQL rejected the username or password. Check the '
        '"${options.user}" role exists and the password is right.',
  PosDbFailure.tls =>
    'PostgreSQL rejected the secure connection. Check its certificate, or '
        'pass --no-verify-tls if this really is a box on this network.',
  // The first-install case, and this CLI is the tool that fixes it — so it
  // names its own flag rather than the wizard's button.
  PosDbFailure.missingDatabase =>
    'PostgreSQL is running and accepted the login, but there is no database '
        'called "${options.database}" yet. Re-run with --create-database to '
        'create it before migrating.',
  PosDbFailure.permissionDenied =>
    'PostgreSQL signed "${options.user}" in, then refused the work: it may not '
        'create objects in "${options.database}". From PostgreSQL 15 the public '
        'schema no longer grants that to everyone, so a role that did not '
        'create the database has to be given it:\n'
        '  ALTER DATABASE "${options.database}" OWNER TO "${options.user}";\n'
        '  ALTER SCHEMA public OWNER TO "${options.user}";',
  PosDbFailure.query || PosDbFailure.unknown =>
    'Connected, but the database did not answer as expected. Check that '
        '"${options.database}" is the right database and that "${options.user}" '
        'may create tables in it.\n${error.raw}',
};

/// `CREATE DATABASE` cannot run inside a transaction and has no `IF NOT
/// EXISTS`, so it needs its own connection to the maintenance database and a
/// look before it leaps.
Future<void> _createDatabase(Options options) async {
  final created = await LocalBootstrap.createDatabase(
    options.config,
    options.password,
    options.database,
  );
  stdout.writeln(
    created
        ? 'created ${options.database}.'
        : '${options.database} already exists.',
  );
}

Future<void> _reportStatus(PosDatabase database, Options options) async {
  // Two statements rather than one guarded by `to_regclass`: PostgreSQL plans
  // the whole query before running it, so selecting from a table that is not
  // there yet fails outright however the WHERE clause is written. A database
  // with nothing applied is the normal first case, not an error.
  final existing = await database.query(
    options.config,
    "SELECT to_regclass('public.schema_migrations') IS NOT NULL",
  );

  final applied = <int>{};
  if (existing.first[0] == true) {
    final rows = await database.query(
      options.config,
      'SELECT version FROM schema_migrations ORDER BY version',
    );
    applied.addAll(rows.map((row) => row[0] as int));
  }

  stdout.writeln('${options.describe}:');
  for (final migration in posMigrations) {
    final mark = applied.contains(migration.version) ? 'applied' : 'PENDING';
    stdout.writeln('  ${migration.version}  $mark  ${migration.description}');
  }
}

/// Create the restaurant, one branch, one terminal and one member of staff.
///
/// **It seeds no menu.** A starter menu would be somebody else's food — which
/// is the entire problem this work exists to fix — so what goes in here is only
/// what the till cannot boot without, under names the operator supplied. The
/// categories and products are then inserted by hand; the README has the SQL.
///
/// Safe to re-run: it matches on the restaurant slug, the branch code and the
/// staff username, and leaves anything already there alone.
Future<void> _seed(PosDatabase database, Options options) async {
  final restaurant = options.restaurantName;
  final slug = options.slug;
  if (restaurant == null || slug == null || options.pin == null) {
    stderr.writeln(
      '--seed needs --restaurant, --slug and --pin. The till has to know what '
      'the restaurant is called, how to look it up, and how to unlock.',
    );
    exit(64);
  }

  final restaurantRows = await database.query(
    options.config,
    'INSERT INTO pos_restaurants (slug, name) VALUES (@slug, @name) '
    'ON CONFLICT (slug) DO UPDATE SET slug = EXCLUDED.slug '
    'RETURNING id, (xmax = 0) AS inserted',
    parameters: {'slug': slug, 'name': restaurant},
  );
  final restaurantId = restaurantRows.first[0] as int;
  stdout.writeln(
    restaurantRows.first[1] == true
        ? 'created restaurant $restaurant ($slug).'
        : 'restaurant $slug already exists — reusing it.',
  );

  final branchRows = await database.query(
    options.config,
    'INSERT INTO pos_branches (restaurant_id, code, name, supported_order_types) '
    "VALUES (@restaurant, @code, @name, ARRAY['dine_in','takeaway','delivery']) "
    'ON CONFLICT (restaurant_id, code) DO UPDATE SET code = EXCLUDED.code '
    'RETURNING id, (xmax = 0) AS inserted',
    parameters: {
      'restaurant': restaurantId,
      'code': options.branchCode,
      'name': options.branchName,
    },
  );
  final branchId = branchRows.first[0] as int;
  stdout.writeln(
    branchRows.first[1] == true
        ? 'created branch ${options.branchName} (${options.branchCode}) — '
              'invoices will read ${options.branchCode}-<year>-000001.'
        : 'branch ${options.branchCode} already exists — reusing it.',
  );

  // PBKDF2 at the same work factor the till verifies with, so the hash this
  // writes is the hash the lock screen checks.
  final salt = PinHash.newSalt();
  final hash = await PinHash.hash(options.pin!, salt);

  final roles = await _seedRoles(database, options, restaurantId);

  // On the owner role, with no direct grants of their own.
  //
  // This account is the restaurant's only credential until somebody uses it to
  // create more, so it has to be able to reach the Management screen and hand
  // out permissions — and it is the *role* that carries them, because the whole
  // point of the model is that a person's permissions are legible as a job
  // title rather than as an array somebody typed once at install time.
  final staffRows = await database.query(
    options.config,
    'INSERT INTO pos_staff (restaurant_id, branch_id, name, username, pin_salt, pin_hash, role_id) '
    'VALUES (@restaurant, @branch, @name, @username, @salt, @hash, @role) '
    'ON CONFLICT (restaurant_id, username) DO NOTHING '
    'RETURNING id',
    parameters: {
      'restaurant': restaurantId,
      'branch': branchId,
      'name': options.staffName,
      'username': options.staffUsername,
      'salt': salt,
      'hash': hash,
      'role': roles[SystemRoles.ownerCode],
    },
  );
  stdout.writeln(
    staffRows.isNotEmpty
        ? 'created ${options.staffName} (${options.staffUsername}) with the PIN you gave.'
        : 'staff ${options.staffUsername} already exists — PIN left unchanged.',
  );

  // The terminal row before the machine: the till claims this code at setup,
  // which is what makes an offline terminal trackable at all.
  final existing = await database.query(
    options.config,
    'SELECT id, pairing_code, claimed_at FROM pos_terminals '
    'WHERE restaurant_id = @restaurant AND branch_id = @branch AND name = @name',
    parameters: {
      'restaurant': restaurantId,
      'branch': branchId,
      'name': options.terminalName,
    },
  );

  if (existing.isNotEmpty) {
    final claimed = existing.first[2] != null;
    stdout.writeln(
      'terminal ${options.terminalName} already exists — '
      '${claimed ? 'already claimed by a till' : 'setup code ${existing.first[1]}'}.',
    );
    return;
  }

  final code = _pairingCode(options.branchCode);
  await database.query(
    options.config,
    'INSERT INTO pos_terminals (id, restaurant_id, branch_id, name, pairing_code) '
    'VALUES (gen_random_uuid(), @restaurant, @branch, @name, @code)',
    parameters: {
      'restaurant': restaurantId,
      'branch': branchId,
      'name': options.terminalName,
      'code': code,
    },
  );

  stdout
    ..writeln('created terminal ${options.terminalName}.')
    ..writeln()
    ..writeln('  Setup code for this till:  $code')
    ..writeln()
    ..writeln('Type it at the wizard\'s Sign in step. It is single-use — run')
    ..writeln('--seed again with a different --terminal for the next till.');
}

/// `MAIN-7Q42`. Short enough to read off a screen and type at a counter, from
/// an alphabet with no 0/O or 1/I to mishear.
String _pairingCode(String branchCode) {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final random = Random.secure();
  final suffix = List.generate(
    4,
    (_) => alphabet[random.nextInt(alphabet.length)],
  ).join();
  return '${branchCode.toUpperCase()}-$suffix';
}

/// Put a small demo menu on a freshly migrated database.
///
/// **Deliberately its own flag, not part of `--seed`.** `--seed` creates the
/// records a real site genuinely needs — the restaurant, its branch, a role set
/// and one person who can unlock the till. A menu is not one of those: a real
/// restaurant's menu is authored in the dashboard and pulled down, and a
/// production install that quietly acquired fictional products would put made-up
/// prices in front of a customer.
///
/// It exists because until the catalogue endpoints land (POS-BE-012,
/// POS-BE-023) there is **no** way to get a menu onto a till, so a bring-up
/// install reaches the wizard's catalogue step, is told it cached nothing, and
/// cannot sell. Demonstrating the till needs something on the screen.
///
/// Idempotent by the same guard the end-to-end suite uses: a restaurant that
/// already has products is left exactly as it is. Re-running is safe and is not
/// a way to top up a menu.
Future<void> _seedCatalogue(PosDatabase database, Options options) async {
  final slug = options.slug;
  if (slug == null) {
    stderr.writeln(
      '--seed-catalogue needs --slug, so it knows which restaurant to put the '
      'menu on. It will not guess.',
    );
    exit(64);
  }

  final restaurantRows = await database.query(
    options.config,
    'SELECT id, name FROM pos_restaurants WHERE slug = @slug',
    parameters: {'slug': slug},
  );
  if (restaurantRows.isEmpty) {
    stderr.writeln(
      'No restaurant with the short name "$slug". Run --seed first, or check '
      'the spelling.',
    );
    exit(1);
  }
  final restaurantId = restaurantRows.first[0] as int;
  final restaurantName = restaurantRows.first[1] as String;

  final existing = await database.query(
    options.config,
    'SELECT count(*) FROM pos_products WHERE restaurant_id = @restaurant',
    parameters: {'restaurant': restaurantId},
  );
  // Guards the *menu* only. Tables are guarded by their own unique key below,
  // so a restaurant that got its products but not its floor — which is exactly
  // what a half-finished run leaves behind — can still be completed.
  final hasMenu = (existing.first[0] as int) > 0;
  if (hasMenu) {
    stdout.writeln(
      '$restaurantName already has a menu — leaving it alone. Delete its '
      'products first if you meant to replace it.',
    );
  }

  if (!hasMenu) {
    // Categories carry no unique key of their own, so the guard above is what
    // makes this safe to re-run rather than an ON CONFLICT clause.
    final categories = <String, int>{};
    for (final (nameEn, nameAr, categorySlug, sort) in const [
      ('Hot Drinks', 'مشروبات ساخنة', 'hot-drinks', 1),
      ('Cold Drinks', 'مشروبات باردة', 'cold-drinks', 2),
      ('Food', 'مأكولات', 'food', 3),
    ]) {
      final row = await database.query(
        options.config,
        'INSERT INTO pos_categories (restaurant_id, name_en, name_ar, slug, sort_order) '
        'VALUES (@restaurant, @en, @ar, @slug, @sort) RETURNING id',
        parameters: {
          'restaurant': restaurantId,
          'en': nameEn,
          'ar': nameAr,
          'slug': categorySlug,
          'sort': sort,
        },
      );
      categories[categorySlug] = row.first[0] as int;
    }

    // One required group and one optional, because those are the two shapes the
    // ticket engine has to get right and a menu with only one proves half of it.
    final sizeRows = await database.query(
      options.config,
      'INSERT INTO pos_modifier_groups (restaurant_id, name_en, name_ar, is_required, max_select, is_variant) '
      "VALUES (@restaurant, 'Size', 'الحجم', true, 1, true) RETURNING id",
      parameters: {'restaurant': restaurantId},
    );
    final sizeId = sizeRows.first[0] as int;
    await database.query(
      options.config,
      'INSERT INTO pos_modifiers (group_id, name_en, name_ar, price_delta_minor, sort_order) '
      "VALUES (@group, 'Regular', 'عادي', 0, 1), (@group, 'Large', 'كبير', 1000, 2)",
      parameters: {'group': sizeId},
    );

    final extrasRows = await database.query(
      options.config,
      'INSERT INTO pos_modifier_groups (restaurant_id, name_en, name_ar, is_required, max_select, is_variant) '
      "VALUES (@restaurant, 'Extras', 'إضافات', false, 3, false) RETURNING id",
      parameters: {'restaurant': restaurantId},
    );
    final extrasId = extrasRows.first[0] as int;
    await database.query(
      options.config,
      'INSERT INTO pos_modifiers (group_id, name_en, name_ar, price_delta_minor, sort_order) '
      "VALUES (@group, 'Extra shot', 'جرعة إضافية', 1500, 1), "
      "       (@group, 'Oat milk', 'حليب شوفان', 1000, 2)",
      parameters: {'group': extrasId},
    );

    // Minor units, as everywhere: 4500 is 45.00. Never a decimal, never a float.
    const menu = [
      ('hot-drinks', 'Espresso', 'إسبريسو', 3500, 'DEMO-001', 1, true),
      ('hot-drinks', 'Latte', 'لاتيه', 5500, 'DEMO-002', 2, true),
      ('hot-drinks', 'Tea', 'شاي', 2500, 'DEMO-003', 3, false),
      ('cold-drinks', 'Iced Latte', 'لاتيه مثلج', 6000, 'DEMO-004', 1, true),
      (
        'cold-drinks',
        'Fresh Orange',
        'عصير برتقال',
        5000,
        'DEMO-005',
        2,
        false,
      ),
      ('cold-drinks', 'Water', 'مياه', 1500, 'DEMO-006', 3, false),
      ('food', 'Club Sandwich', 'كلوب ساندويتش', 12000, 'DEMO-007', 1, false),
      ('food', 'Chicken Caesar', 'سيزر بالدجاج', 14000, 'DEMO-008', 2, false),
      ('food', 'Fries', 'بطاطس', 4500, 'DEMO-009', 3, false),
      ('food', 'Cheesecake', 'تشيز كيك', 7500, 'DEMO-010', 4, false),
    ];

    for (final (categorySlug, nameEn, nameAr, minor, sku, sort, sized)
        in menu) {
      final product = await database.query(
        options.config,
        'INSERT INTO pos_products (restaurant_id, category_id, name_en, name_ar, price_minor, sku, sort_order) '
        'VALUES (@restaurant, @category, @en, @ar, @price, @sku, @sort) '
        'ON CONFLICT (restaurant_id, sku) DO NOTHING '
        'RETURNING id',
        parameters: {
          'restaurant': restaurantId,
          'category': categories[categorySlug],
          'en': nameEn,
          'ar': nameAr,
          'price': minor,
          'sku': sku,
          'sort': sort,
        },
      );
      if (product.isEmpty) continue;

      // Drinks get both groups; food gets neither. A product with no modifiers
      // is what proves one still goes straight onto the ticket.
      if (sized) {
        await database.query(
          options.config,
          'INSERT INTO pos_product_modifier_groups (product_id, group_id, sort_order) '
          'VALUES (@product, @size, 1), (@product, @extras, 2)',
          parameters: {
            'product': product.first[0],
            'size': sizeId,
            'extras': extrasId,
          },
        );
      }
    }

    stdout.writeln(
      'created a ${menu.length}-item demo menu for $restaurantName.',
    );
  }

  // Without tables the floor screen is an empty room, and dine-in cannot be
  // demonstrated at all.
  final branches = await database.query(
    options.config,
    'SELECT id, name FROM pos_branches WHERE restaurant_id = @restaurant ORDER BY id',
    parameters: {'restaurant': restaurantId},
  );
  for (final branch in branches) {
    final branchId = branch[0] as int;
    var created = 0;
    for (var seat = 1; seat <= 8; seat++) {
      final row = await database.query(
        options.config,
        'INSERT INTO pos_dining_tables (restaurant_id, branch_id, label, seats, area_name, sort_order) '
        "VALUES (@restaurant, @branch, @label, @seats, 'Main', @sort) "
        'ON CONFLICT (branch_id, label) DO NOTHING RETURNING id',
        parameters: {
          'restaurant': restaurantId,
          'branch': branchId,
          'label': 'T$seat',
          'seats': seat <= 4 ? 2 : 4,
          'sort': seat,
        },
      );
      if (row.isNotEmpty) created++;
    }
    if (created > 0) {
      stdout.writeln('created $created tables on ${branch[1]}.');
    }
  }
}

/// Give the till role exactly what the write path uses, and nothing more.
///
/// Worth reading closely, because "SELECT and INSERT" — which is how the till
/// role is described elsewhere — is **not enough** and a till granted only that
/// would fail on its first sale:
///
/// * `pos_invoice_sequences` needs UPDATE. Invoice numbering bumps `next_value`
///   under `SELECT … FOR UPDATE`, and row locking is itself an UPDATE right.
/// * The `bigserial` primary keys need USAGE on their sequences, or every
///   INSERT fails on `nextval`.
///
/// Still no DELETE and no DDL anywhere: a recovered till credential can add to
/// history and read it back, but never rewrite it.
/// The four roles a new restaurant starts with.
///
/// `SystemRoles` is the living definition; migration 5 carries a frozen copy for
/// restaurants that already existed when roles landed. Re-running `--seed` never
/// resets them — a restaurant that has edited what a supervisor may do keeps its
/// edit, because the alternative is an upgrade that quietly reinstates a
/// permission somebody deliberately removed.
Future<Map<String, int>> _seedRoles(
  PosDatabase database,
  Options options,
  int restaurantId,
) async {
  final bootstrap = LocalBootstrap(database);
  final seeded = await bootstrap.seedSystemRoles(options.config, restaurantId);

  stdout.writeln(
    seeded.created == 0
        ? 'roles already exist — left as the restaurant has them.'
        : 'created ${seeded.created} of ${SystemRoles.seeded.length} system roles.',
  );

  // The reason lists, for the same reason and on the same terms: migration 9
  // seeded the restaurants that already existed, and a restaurant this command
  // is creating right now was not one of them.
  final reasons = await bootstrap.seedReasonCodes(options.config, restaurantId);
  stdout.writeln(
    reasons == 0
        ? 'reason codes already exist — left as the restaurant has them.'
        : 'created $reasons reason codes across '
              '${SystemReasons.seededScopes.length} lists.',
  );

  return seeded.ids;
}

/// Grant a database role exactly what its job needs.
///
/// **Two roles, not one.** The till connects as [Options.grantTo] from a machine
/// standing in a public room, often with the password in a config file beside
/// it; the Management section connects as [Options.grantAdminTo]. Both
/// credentials end up on the same disk, so this is not a wall — but it is the
/// difference between "the till's password rewrites the menu and resets PINs"
/// and "it does not", and it costs nothing here while costing a re-grant on
/// every deployed branch server later.
///
/// The capability check in the app is the control that decides *who* may do
/// these things. This is the control that decides what is reachable at all if
/// that check is ever bypassed.
Future<void> _grant(
  PosDatabase database,
  Options options,
  String role, {
  required bool admin,
}) async {
  final present = await database.query(
    options.config,
    'SELECT 1 FROM pg_roles WHERE rolname = @role',
    parameters: {'role': role},
  );
  if (present.isEmpty) {
    stderr.writeln(
      'No role "$role" on this server. Create it first — '
      'CREATE ROLE $role LOGIN PASSWORD \'…\'; — then run this again.',
    );
    exit(1);
  }

  // Both lists live in `LocalBootstrap` so this tool and the setup wizard
  // cannot answer "what does a till need" two different ways.
  final shared = LocalBootstrap.tillGrants(
    database: options.database,
    role: role,
  );
  final administrative = LocalBootstrap.administrativeGrants(role: role);

  for (final statement in [...shared, if (admin) ...administrative]) {
    await database.query(options.config, statement);
  }

  stdout.writeln(
    admin
        ? 'granted the Management privileges to $role.'
        : 'granted the till privileges to $role.',
  );
}

class Options {
  Options({
    required this.host,
    required this.port,
    required this.database,
    required this.user,
    required this.password,
    required this.createDatabase,
    required this.grantTo,
    required this.grantAdminTo,
    required this.verifyTls,
    required this.status,
    required this.seed,
    required this.seedCatalogue,
    required this.help,
    required this._values,
  });

  final String host;
  final int port;
  final String database;
  final String user;
  final String password;
  final bool createDatabase;
  final String? grantTo;

  /// The role the Management section connects as. Separate from [grantTo] on
  /// purpose — see [_grant].
  final String? grantAdminTo;
  final bool verifyTls;
  final bool status;
  final bool seed;

  /// A demo menu, kept apart from [seed] on purpose — see `_seedCatalogue`.
  final bool seedCatalogue;
  final bool help;

  /// Everything `--seed` needs. Held as raw values rather than a dozen more
  /// constructor parameters, because they matter to exactly one function.
  final Map<String, String> _values;

  String? get restaurantName => _values['restaurant']?.trim();
  String? get slug => _values['slug']?.trim().toLowerCase();
  String? get pin => _values['pin']?.trim();
  String get branchName => _values['branch']?.trim() ?? 'Main';
  String get branchCode =>
      (_values['branch-code']?.trim() ?? branchName).toUpperCase();
  String get terminalName => _values['terminal']?.trim() ?? 'Counter 1';
  String get staffName => _values['staff']?.trim() ?? 'Manager';
  String get staffUsername => _values['staff-username']?.trim() ?? 'manager';

  /// Offline, because this script only ever talks to PostgreSQL — there is no
  /// API to reach from here, and `databaseHost` now carries the address on its
  /// own rather than being read back out of a URL that existed to hold it.
  DeploymentConfig get config => DeploymentConfig(
    mode: DeploymentMode.offline,
    verifyTls: verifyTls,
    databaseHost: host,
    databaseName: database,
    databaseUser: user,
    databasePort: port,
  );

  String get describe => '$database on $host:$port';

  /// Hyphens allowed — `xorder-pos` is a name a person will reasonably pick,
  /// and every use below is double-quoted so PostgreSQL takes it literally.
  /// What is refused is anything that could end the quoting: no `"`, no
  /// backslash, no whitespace.
  static final _identifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_$-]*$');

  static Options parse(List<String> arguments) {
    final values = <String, String>{};
    final flags = <String>{};

    for (var i = 0; i < arguments.length; i++) {
      final argument = arguments[i];
      if (!argument.startsWith('--')) {
        throw FormatException('Unexpected argument "$argument".');
      }
      final name = argument.substring(2);

      if (const {
        'create-database', 'no-verify-tls', 'status', 'seed', //
        'seed-catalogue', 'help', //
      }.contains(name)) {
        flags.add(name);
        continue;
      }
      if (!const {
        'host', 'port', 'database', 'user', 'password', 'grant-to', //
        'grant-admin-to', //
        'restaurant', 'slug', 'branch', 'branch-code', 'terminal', //
        'staff', 'staff-username', 'pin',
      }.contains(name)) {
        throw FormatException('Unknown option "$argument".');
      }
      if (i + 1 >= arguments.length) {
        throw FormatException('"$argument" needs a value.');
      }
      values[name] = arguments[++i];
    }

    final port = int.tryParse(values['port'] ?? '5432');
    if (port == null || port <= 0 || port > 65535) {
      throw FormatException('"${values['port']}" is not a port.');
    }

    final database = values['database'] ?? 'xorder_pos';
    // Interpolated into DDL further down, where a bind parameter is not
    // allowed. Refuse anything that is not a plain identifier rather than try
    // to escape it.
    if (!_identifier.hasMatch(database)) {
      throw FormatException(
        'Database name "$database" is not a plain identifier. Use letters, '
        'digits and underscores.',
      );
    }

    final role = values['grant-to'];
    if (role != null && !_identifier.hasMatch(role)) {
      throw FormatException('Role name "$role" is not a plain identifier.');
    }

    final adminRole = values['grant-admin-to'];
    if (adminRole != null && !_identifier.hasMatch(adminRole)) {
      throw FormatException(
        'Role name "$adminRole" is not a plain identifier.',
      );
    }
    if (adminRole != null && adminRole == role) {
      throw FormatException(
        'The till role and the administrator role must be different. Granting '
        'both to "$role" would give a credential that sits on a machine in a '
        'public room the ability to rewrite the menu and reset PINs, which is '
        'the whole thing the split exists to prevent.',
      );
    }

    final slug = values['slug'];
    if (slug != null &&
        !RegExp(r'^[a-z0-9][a-z0-9-]*$').hasMatch(slug.toLowerCase())) {
      throw FormatException(
        'Restaurant short name "$slug" should be lowercase letters, digits and '
        'hyphens — it is the mahsoub in mahsoub.xorder.io.',
      );
    }

    // The invoice prefix ends up on every receipt a tax authority may read, so
    // it has to stay legible and stable: letters and digits only.
    final branchCode = values['branch-code'];
    if (branchCode != null &&
        !RegExp(r'^[A-Za-z0-9]{1,12}$').hasMatch(branchCode)) {
      throw FormatException(
        'Branch code "$branchCode" should be 1–12 letters or digits. It is the '
        'invoice prefix — MAADI in MAADI-2026-000042.',
      );
    }

    final pin = values['pin'];
    if (pin != null && !RegExp(r'^\d{4,12}$').hasMatch(pin)) {
      throw FormatException('A PIN should be 4 to 12 digits.');
    }

    return Options(
      values: values,
      host: values['host'] ?? '127.0.0.1',
      port: port,
      database: database,
      user: values['user'] ?? 'postgres',
      password:
          values['password'] ?? Platform.environment['POS_PG_PASSWORD'] ?? '',
      createDatabase: flags.contains('create-database'),
      grantTo: role,
      grantAdminTo: adminRole,
      // Matches the wizard: skipping certificate checks is only ever honoured
      // for a private address, so a typo in a public hostname cannot quietly
      // downgrade the connection.
      verifyTls: !flags.contains('no-verify-tls'),
      status: flags.contains('status'),
      seed: flags.contains('seed'),
      seedCatalogue: flags.contains('seed-catalogue'),
      help: flags.contains('help'),
    );
  }
}

const usage = '''
Prepare a branch server's database for the tills that write to it.

  dart run bin/pos_migrate.dart [options]

  --host <address>     Branch server. Default 127.0.0.1
  --port <number>      Default 5432
  --database <name>    Default xorder_pos
  --user <role>        Connect as this role. Needs DDL rights, so an admin —
                       not the till's own role. Default postgres
  --password <secret>  Prefer the POS_PG_PASSWORD environment variable
  --create-database    Create the database first if it is not there yet
  --grant-to <role>    Grant that role what a till needs, and nothing else
  --grant-admin-to <r> Grant that role what the Management section needs on top
                       of the till's grants: staff, roles and the audit ledger
  --no-verify-tls      Skip certificate checks. Honoured for private addresses
                       only, exactly as the setup wizard treats it
  --status             Say which migrations are applied, and change nothing
  --help

Seeding — creates the restaurant, one branch, one terminal and one member of
staff, then prints the setup code the till claims. It seeds NO menu: the
categories and products are yours to insert, and a starter menu would just be
somebody else's food.

  --seed               Create the records below
  --restaurant <name>  Shown on the receipt and the start screen. Required
  --slug <name>        Short name, as in mahsoub.xorder.io. Required
  --pin <digits>       PIN for the member of staff created. Required, 4-12
  --branch <name>      Default "Main"
  --branch-code <code> Invoice prefix, letters and digits. Default the branch
                       name uppercased — MAIN-2026-000042
  --terminal <name>    Default "Counter 1". Re-run with a new one per till
  --staff <name>       Default "Manager"
  --staff-username <u> Default "manager"

  --seed-catalogue     Put a small demo menu on the restaurant named by
                       --slug: ten products, two modifier groups and eight
                       tables per branch. Separate from --seed because a
                       real menu is authored in the dashboard and pulled
                       down — this exists so a bring-up till has something
                       to sell before those endpoints are built. Refuses to
                       touch a restaurant that already has products.

Examples:

  # First install of a branch box, all in one go.
  POS_PG_PASSWORD=… dart run bin/pos_migrate.dart --host 192.168.1.20 \\
    --user postgres --create-database --grant-to pos_till \\
    --seed --restaurant "Amer's Kitchen" --slug amer --pin 1234

  # A second till at the same branch: a new terminal and a new setup code.
  POS_PG_PASSWORD=… dart run bin/pos_migrate.dart --host 192.168.1.20 \\
    --user postgres --seed --restaurant "Amer's Kitchen" --slug amer \\
    --pin 1234 --terminal "Counter 2"

  # After an update, on a box that already has a database.
  POS_PG_PASSWORD=… dart run bin/pos_migrate.dart --host 192.168.1.20 --user postgres

  # Check before touching anything.
  POS_PG_PASSWORD=… dart run bin/pos_migrate.dart --host 192.168.1.20 \\
    --user postgres --status
''';
