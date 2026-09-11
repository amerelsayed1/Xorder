import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every table the till touches is a table the till has a grant on.
///
/// **Written because six of them were not.** Waves M and N added
/// `pos_product_prices`, three combo tables, `pos_order_taxes` and
/// `pos_order_line_items`; the catalogue query joins the first four and a
/// settlement writes the last two. None had a grant. Every database suite runs
/// as the superuser, who needs no grant at all, so nothing failed — an offline
/// till on its own credential would have been unable to load its menu or record
/// a sale, and the first person to find out would have been a restaurant.
///
/// A grant list only ever grows and nobody re-reads it. This reads it, by
/// scanning the source rather than the schema, so it holds with no server —
/// which is the only way it runs on every commit. `theme_test.dart` uses the
/// same trick for raw colours.
void main() {
  final root = Directory.current.path;

  String read(String path) => File('$root/$path').readAsStringSync();

  /// Every table the migrations create.
  Set<String> allTables() => RegExp(r'CREATE TABLE IF NOT EXISTS (\w+)')
      .allMatches(read('lib/data/postgres/migrations.dart'))
      .map((m) => m.group(1)!)
      .toSet();

  /// A grant block, as text. Sliced out rather than executed, because the
  /// statements interpolate a role name and a database name that only exist at
  /// install time.
  String grantSource({required bool admin}) {
    final source = read('lib/data/postgres/local_bootstrap.dart');
    final till = source.indexOf('static List<String> tillGrants');
    final administrative = source.indexOf(
      'static List<String> administrativeGrants',
    );
    expect(till, greaterThan(-1));
    expect(administrative, greaterThan(till));

    // An administrator role is given **both** lists — see
    // `pos_migrate --grant-admin-to` — so the admin block on its own is not
    // the set it holds. Checking it alone would report every table the till
    // list already covers as missing, and hide the ones that matter.
    return admin
        ? source.substring(till)
        : source.substring(till, administrative);
  }

  String tillGrantsSource() => grantSource(admin: false);

  /// The repositories bound on the **till's** credential.
  ///
  /// Named individually rather than globbed. A repository added to
  /// `lib/data/postgres/` is not automatically a till one — the admin
  /// repositories run on the administrator connection and are covered by a
  /// different grant list — so a new file has to be classified here on
  /// purpose. That is the point: the decision is which credential it runs on,
  /// and it should be made by somebody rather than by a glob.
  const tillRepositories = <String>[
    'postgres_catalog_repository.dart',
    'postgres_orders_repository.dart',
    'postgres_directory_repositories.dart',
    'postgres_floor_repository.dart',
    'postgres_shift_repository.dart',
    'postgres_parked_tickets.dart',
    'postgres_reason_repository.dart',
    'postgres_discounts_repository.dart',
    'postgres_refunds_repository.dart',
    'postgres_settings_repository.dart',
    'postgres_business_day_repository.dart',
    'postgres_cash_movements_repository.dart',
    'postgres_order_history_repository.dart',
    'postgres_branch_sales_repository.dart',
    'postgres_eta_queue_repository.dart',
    // Receipts the printer would not take. Written at the counter on the till's
    // own credential, because a printer that is off is a till problem and not a
    // back-office one.
    'postgres_print_queue_repository.dart',
    'postgres_receipt_profile_repository.dart',
    // Read at the till and written in the back office, so they are in both
    // lists. A cashier takes a payment method and charges what the restaurant
    // set; they do not invent either.
    'postgres_tender_types_repository.dart',
    'postgres_service_charges_repository.dart',
    'postgres_order_types_repository.dart',
    'postgres_units_repository.dart',
    'postgres_stock_items_repository.dart',
    // Written by the till at day close and read in the back office. It is on
    // the till's list because the automatic copy is taken by a machine on which
    // nobody has signed into Management — see `PostgresBackupRepository`.
    'postgres_backup_repository.dart',
  ];

  /// The repositories bound on the **administrator's** credential.
  const adminRepositories = <String>[
    'postgres_admin_repositories.dart',
    'postgres_catalog_admin_repository.dart',
    'postgres_receipt_profile_repository.dart',
    'postgres_tender_types_repository.dart',
    'postgres_service_charges_repository.dart',
    'postgres_order_types_repository.dart',
    'postgres_units_repository.dart',
    'postgres_stock_items_repository.dart',
    'postgres_suppliers_repository.dart',
    'postgres_purchase_orders_repository.dart',
    'postgres_receiving_repository.dart',
    'postgres_supplier_invoices_repository.dart',
    // Read only from the back office: the till holds no grant on stock levels.
    'postgres_stock_levels_repository.dart',
  ];

  test('every repository is classified as one or the other', () {
    // **The check that was missing, and the reason nine tables went ungranted.**
    // Both lists above are hand-written, and the version of this test that
    // shipped said so — "a renamed file would silently stop being checked" —
    // and then went on to trust them. Wave D added five repositories that
    // nobody added here, so the tables behind the payment methods, the service
    // charges and the whole purchasing chain were checked against nothing.
    //
    // Enumerating the directory is what makes the omission loud. A new
    // repository still has to be classified by hand, because which credential
    // it runs on is a decision rather than something a glob can know — but now
    // it fails until somebody makes it.
    final files =
        Directory('$root/lib/data/postgres')
            .listSync()
            .whereType<File>()
            .map((f) => f.uri.pathSegments.last)
            .where((n) => n.startsWith('postgres_') && n.endsWith('.dart'))
            // Not a repository: the tenant resolver names no table it reads on
            // either credential.
            .where((n) => n != 'postgres_tenant.dart')
            .toList()
          ..sort();

    final unclassified = [
      for (final name in files)
        if (!tillRepositories.contains(name) &&
            !adminRepositories.contains(name))
          name,
    ];

    expect(
      unclassified,
      isEmpty,
      reason:
          'These repositories are in neither list, so no grant check covers '
          'the tables they use. Add each one to tillRepositories, to '
          'adminRepositories, or to both.',
    );
  });

  test('every repository named here exists', () {
    // The other direction. A renamed file that stayed in the list would pass
    // the classification check above by being absent from the directory.
    for (final name in {...tillRepositories, ...adminRepositories}) {
      expect(
        File('$root/lib/data/postgres/$name').existsSync(),
        isTrue,
        reason: name,
      );
    }
  });

  test('every table a till repository names has a grant', () {
    final tables = allTables();
    final grants = tillGrantsSource();

    final missing = <String, List<String>>{};
    for (final name in tillRepositories) {
      final source = read('lib/data/postgres/$name');
      for (final table in tables) {
        if (!RegExp('\\b$table\\b').hasMatch(source)) continue;
        if (RegExp('\\b$table\\b').hasMatch(grants)) continue;
        missing.putIfAbsent(table, () => []).add(name);
      }
    }

    expect(
      missing,
      isEmpty,
      reason:
          'These tables are used on the till credential and appear in no '
          'grant. Add them to LocalBootstrap.tillGrants — read-only unless '
          'the till genuinely writes them.',
    );
  });

  test('every table an admin repository names has a grant', () {
    // The same question of the back office, which is how the offline
    // catalogue-authoring hole was found: an administrator is given the till
    // list *and* the administrative one, and the till list REVOKEs the
    // catalogue writes on an offline install. Nothing put them back.
    final tables = allTables();
    final grants = grantSource(admin: true);

    final missing = <String, List<String>>{};
    for (final name in adminRepositories) {
      final source = read('lib/data/postgres/$name');
      for (final table in tables) {
        if (!RegExp('\\b$table\\b').hasMatch(source)) continue;
        if (RegExp('\\b$table\\b').hasMatch(grants)) continue;
        missing.putIfAbsent(table, () => []).add(name);
      }
    }

    expect(
      missing,
      isEmpty,
      reason:
          'These tables are used on the administrator credential and appear '
          'in neither grant list.',
    );
  });

  test('the grant list names no sequence that does not exist', () {
    // **The mirror of the test below, and written because the sequence grants
    // were added by hand and one of them was for a table with no sequence.**
    // `pos_stock_levels` is keyed by (restaurant, branch, product), so
    // `pos_stock_levels_id_seq` has never existed — and
    // `GRANT ... ON SEQUENCE` on a missing sequence throws, taking the whole
    // bootstrap down on a machine nobody is watching. Exactly the failure the
    // table version of this test exists to stop, one noun over.
    final source = read('lib/data/postgres/migrations.dart');
    final owning = <String>{
      for (final match in RegExp(
        r'CREATE TABLE IF NOT EXISTS (\w+) \((.*?)\n\s*\)',
        dotAll: true,
      ).allMatches(source))
        if (match.group(2)!.contains('serial')) '${match.group(1)!}_id_seq',
    };

    final named = <String>{};
    for (final admin in [false, true]) {
      final flat = grantSource(admin: admin)
          .replaceAll(RegExp(r"'\s*\n\s*'"), '')
          .replaceAll(RegExp(r'\s+'), ' ');
      named.addAll(
        RegExp(r'\b(\w+_seq)\b').allMatches(flat).map((m) => m.group(1)!),
      );
    }

    expect(
      named.difference(owning),
      isEmpty,
      reason:
          'These sequences are granted and no migration creates them. A GRANT '
          'on a missing sequence throws at install time.',
    );
  });

  test('every table granted INSERT is granted its sequence too', () {
    // The same trap one level down, and it fails at exactly the wrong moment:
    // `GRANT INSERT` without `GRANT USAGE ON SEQUENCE` passes every shape check
    // and then refuses `nextval` on the first row anybody writes. A superuser
    // never sees that either.
    final source = read('lib/data/postgres/migrations.dart');
    final owning = <String>{
      for (final match in RegExp(
        r'CREATE TABLE IF NOT EXISTS (\w+) \((.*?)\n\s*\)',
        dotAll: true,
      ).allMatches(source))
        if (match.group(2)!.contains('serial')) match.group(1)!,
    };

    for (final admin in [false, true]) {
      final grants = grantSource(admin: admin);
      // Dart concatenates adjacent string literals across lines, so a
      // multi-line GRANT is several literals. Strip the seams and the newlines
      // and the block reads as one line of SQL-ish text, which is all this
      // needs.
      final flat = grants
          .replaceAll(RegExp(r"'\s*\n\s*'"), '')
          .replaceAll(RegExp(r'\s+'), ' ');

      final missing = <String>[];
      for (final statement in flat.split('GRANT ').skip(1)) {
        final clause = statement.split(' TO ').first;
        final parts = clause.split(' ON ');
        if (parts.length < 2) continue;
        if (!parts.first.contains('INSERT')) continue;

        for (final table in owning) {
          if (!RegExp('\\b$table\\b').hasMatch(parts[1])) continue;
          if (flat.contains('${table}_id_seq')) continue;
          missing.add(table);
        }
      }

      expect(
        missing,
        isEmpty,
        reason: admin
            ? 'granted INSERT with no sequence, on the administrator list'
            : 'granted INSERT with no sequence, on the till list',
      );
    }
  });

  test('the grant list names no table that does not exist', () {
    // The other direction, and it matters at install time rather than at
    // runtime: `GRANT ... ON a_table_that_was_renamed` throws, and the whole
    // bootstrap fails on a machine nobody is watching.
    final tables = allTables();
    final grants = tillGrantsSource();

    final named = RegExp(r'\bpos_\w+\b')
        .allMatches(grants)
        .map((m) => m.group(0)!)
        // Sequences are named after their table with a suffix, and are
        // granted separately.
        .where((n) => !n.endsWith('_id_seq'))
        .toSet();

    final unknown = named.where((n) => !tables.contains(n)).toSet()
      // The role name itself is interpolated as `pos_till` in the doc comments
      // and in `GRANT ... TO "$role"`, and is not a table.
      ..removeWhere((n) => n == 'pos_till');

    expect(unknown, isEmpty);
  });
}
