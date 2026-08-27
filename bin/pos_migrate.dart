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

import 'package:postgres/postgres.dart';
import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/core/security/pin_hash.dart';
import 'package:xorder_pos/data/postgres/migrations.dart';
import 'package:xorder_pos/data/postgres/pos_database.dart';

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

    final database = PosDatabase(credentials: InMemoryPosDbCredentials(options.password));
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
          final migration = posMigrations.firstWhere((m) => m.version == version);
          stdout.writeln('applied ${migration.version} · ${migration.description}');
        }
      }

      if (options.seed) await _seed(database, options);

      final role = options.grantTo;
      if (role != null) await _grant(database, options, role);
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
String _explain(PosDbException error, Options options) => switch (error.failure) {
      PosDbFailure.dns => 'The name "${options.host}" does not resolve. Use its IP address, or '
          'give the box a fixed address on the router.',
      PosDbFailure.tcp => 'Nothing answered on port ${options.port}. Check PostgreSQL is running, '
          "that listen_addresses includes this network, and the host's firewall "
          'allows the connection.',
      PosDbFailure.auth => 'PostgreSQL rejected the username or password. Check the '
          '"${options.user}" role exists and the password is right.',
      PosDbFailure.tls => 'PostgreSQL rejected the secure connection. Check its certificate, or '
          'pass --no-verify-tls if this really is a box on this network.',
      PosDbFailure.query || PosDbFailure.unknown =>
        'Connected, but the database did not answer as expected. Check that '
            '"${options.database}" is the right database and that "${options.user}" '
            'may create tables in it.\n${error.raw}',
    };

/// `CREATE DATABASE` cannot run inside a transaction and has no `IF NOT
/// EXISTS`, so it needs its own connection to the maintenance database and a
/// look before it leaps.
Future<void> _createDatabase(Options options) async {
  final admin = await Connection.open(
    Endpoint(
      host: options.host,
      port: options.port,
      database: 'postgres',
      username: options.user,
      password: options.password,
    ),
    settings: ConnectionSettings(
      sslMode: options.config.allowsInsecureTransport ? SslMode.disable : SslMode.require,
    ),
  );

  try {
    final existing = await admin.execute(
      Sql.named('SELECT 1 FROM pg_database WHERE datname = @name'),
      parameters: {'name': options.database},
    );
    if (existing.isNotEmpty) {
      stdout.writeln('${options.database} already exists.');
      return;
    }
    // An identifier, so it cannot be a bind parameter. Quoted, and the name is
    // rejected earlier if it is not a plain identifier.
    await admin.execute('CREATE DATABASE "${options.database}"');
    stdout.writeln('created ${options.database}.');
  } finally {
    await admin.close();
  }
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
  stdout.writeln(restaurantRows.first[1] == true
      ? 'created restaurant $restaurant ($slug).'
      : 'restaurant $slug already exists — reusing it.');

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
  stdout.writeln(branchRows.first[1] == true
      ? 'created branch ${options.branchName} (${options.branchCode}) — '
          'invoices will read ${options.branchCode}-<year>-000001.'
      : 'branch ${options.branchCode} already exists — reusing it.');

  // PBKDF2 at the same work factor the till verifies with, so the hash this
  // writes is the hash the lock screen checks.
  final salt = PinHash.newSalt();
  final hash = await PinHash.hash(options.pin!, salt);

  final staffRows = await database.query(
    options.config,
    'INSERT INTO pos_staff (restaurant_id, branch_id, name, username, pin_salt, pin_hash, capabilities) '
    "VALUES (@restaurant, @branch, @name, @username, @salt, @hash, "
    "        ARRAY['pos.operate','pos.discount','pos.shift_open','pos.shift_close',"
    "              'pos.cash_movement','pos.reprint']) "
    'ON CONFLICT (restaurant_id, username) DO NOTHING '
    'RETURNING id',
    parameters: {
      'restaurant': restaurantId,
      'branch': branchId,
      'name': options.staffName,
      'username': options.staffUsername,
      'salt': salt,
      'hash': hash,
    },
  );
  stdout.writeln(staffRows.isNotEmpty
      ? 'created ${options.staffName} (${options.staffUsername}) with the PIN you gave.'
      : 'staff ${options.staffUsername} already exists — PIN left unchanged.');

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
  final suffix = List.generate(4, (_) => alphabet[random.nextInt(alphabet.length)]).join();
  return '${branchCode.toUpperCase()}-$suffix';
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
Future<void> _grant(PosDatabase database, Options options, String role) async {
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

  for (final statement in [
    'GRANT CONNECT ON DATABASE "${options.database}" TO "$role"',
    'GRANT USAGE ON SCHEMA public TO "$role"',
    // The sale itself.
    'GRANT SELECT, INSERT ON pos_orders, pos_order_lines, pos_order_payments TO "$role"',
    'GRANT SELECT, INSERT, UPDATE ON pos_invoice_sequences TO "$role"',
    'GRANT USAGE, SELECT ON SEQUENCE pos_orders_id_seq, pos_order_lines_id_seq, '
        'pos_order_payments_id_seq TO "$role"',
    // The restaurant's own data. Read-only: a till displays the menu, it does
    // not edit it. Changing what the restaurant sells is a back-office act, and
    // a credential sitting on a machine in a public room should not be able to
    // reprice the food.
    'GRANT SELECT ON pos_restaurants, pos_branches, pos_staff, pos_categories, '
        'pos_products, pos_modifier_groups, pos_modifiers, '
        'pos_product_modifier_groups, pos_dining_tables TO "$role"',
    // Two exceptions. Claiming a pairing code stamps `claimed_at`, and an
    // installer with no dashboard registers the terminal from the wizard.
    'GRANT SELECT, INSERT, UPDATE ON pos_terminals TO "$role"',
    // Shifts are opened and closed at the till by definition. No DELETE: a
    // cash-up somebody wants to disappear is exactly the row that must not.
    'GRANT SELECT, INSERT, UPDATE ON pos_shifts TO "$role"',
    'GRANT USAGE, SELECT ON SEQUENCE pos_shifts_id_seq TO "$role"',
  ]) {
    await database.query(options.config, statement);
  }

  stdout.writeln('granted the till privileges to $role.');
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
    required this.verifyTls,
    required this.status,
    required this.seed,
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
  final bool verifyTls;
  final bool status;
  final bool seed;
  final bool help;

  /// Everything `--seed` needs. Held as raw values rather than a dozen more
  /// constructor parameters, because they matter to exactly one function.
  final Map<String, String> _values;

  String? get restaurantName => _values['restaurant']?.trim();
  String? get slug => _values['slug']?.trim().toLowerCase();
  String? get pin => _values['pin']?.trim();
  String get branchName => _values['branch']?.trim() ?? 'Main';
  String get branchCode => (_values['branch-code']?.trim() ?? branchName).toUpperCase();
  String get terminalName => _values['terminal']?.trim() ?? 'Counter 1';
  String get staffName => _values['staff']?.trim() ?? 'Manager';
  String get staffUsername => _values['staff-username']?.trim() ?? 'manager';

  /// `PosDatabase` takes its host from the deployment's `baseUrl`, since in the
  /// app that address and the database are the same branch box. Here there is no
  /// API to talk to, so the URL exists only to carry the host.
  DeploymentConfig get config => DeploymentConfig(
        mode: DeploymentMode.branchServer,
        baseUrl: 'http://$host',
        upstreamUrl: 'https://xorder.io',
        verifyTls: verifyTls,
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

      if (const {'create-database', 'no-verify-tls', 'status', 'seed', 'help'}.contains(name)) {
        flags.add(name);
        continue;
      }
      if (!const {
        'host', 'port', 'database', 'user', 'password', 'grant-to', //
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

    final slug = values['slug'];
    if (slug != null && !RegExp(r'^[a-z0-9][a-z0-9-]*$').hasMatch(slug.toLowerCase())) {
      throw FormatException(
        'Restaurant short name "$slug" should be lowercase letters, digits and '
        'hyphens — it is the mahsoub in mahsoub.xorder.io.',
      );
    }

    // The invoice prefix ends up on every receipt a tax authority may read, so
    // it has to stay legible and stable: letters and digits only.
    final branchCode = values['branch-code'];
    if (branchCode != null && !RegExp(r'^[A-Za-z0-9]{1,12}$').hasMatch(branchCode)) {
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
      password: values['password'] ?? Platform.environment['POS_PG_PASSWORD'] ?? '',
      createDatabase: flags.contains('create-database'),
      grantTo: role,
      // Matches the wizard: skipping certificate checks is only ever honoured
      // for a private address, so a typo in a public hostname cannot quietly
      // downgrade the connection.
      verifyTls: !flags.contains('no-verify-tls'),
      status: flags.contains('status'),
      seed: flags.contains('seed'),
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
