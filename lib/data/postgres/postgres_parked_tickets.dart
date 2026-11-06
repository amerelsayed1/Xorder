import 'dart:convert';

import '../../core/config/deployment.dart';
import '../../domain/models/catalog.dart';
import '../../domain/models/ticket.dart';
import 'parked_ticket_codec.dart';
import 'pos_database.dart';

/// What one till has put down, on disk.
///
/// Write-through storage for parked tickets — seated ones on their table, and
/// since migration 32 the ones with no table at all: park upserts, settlement
/// and voiding delete — the one legitimate DELETE in the till's grant set,
/// because the durable record of the money lives in `pos_orders` from the
/// moment it settles. Reads happen at boot, to put the till back the way the
/// restart found it, and every few seconds after, so a till sees what the
/// others on the branch have seated (XORD-044).
///
/// Writes deliberately surface failure to the caller.  A parked ticket is a
/// promise that a cashier may clear the screen and recover the sale after a
/// restart; pretending that promise succeeded loses orders on the first
/// database outage.
class PostgresParkedTickets {
  const PostgresParkedTickets({
    required PosDatabase database,
    required this.config,
    required this.restaurantId,
    required this.branchId,
  }) : _db = database;

  final PosDatabase _db;
  final DeploymentConfig config;
  final int restaurantId;

  /// The shop this till stands in.
  ///
  /// Written onto every row, and not only for tidiness: a ticket with no table
  /// has nothing else that can say which branch it belongs to, and both the
  /// hydration below and the day-close check read it. A seated row carries it
  /// too, so neither of those has to care which kind of row it is looking at.
  final int branchId;

  /// Everything this branch has parked, split the way the till holds it.
  ///
  /// Never throws: a boot that cannot read the floor starts with an empty one
  /// rather than a broken one. [refresh] is the same read, failing loudly.
  Future<ParkedFloor> load(Catalog catalog) async {
    try {
      return await refresh(catalog);
    } on Object {
      return const ParkedFloor();
    }
  }

  /// The read behind [load], without the safety net.
  ///
  /// For the periodic floor refresh (XORD-044): an outage there must leave the
  /// floor the till already shows, not swap it for an empty one.
  Future<ParkedFloor> refresh(Catalog catalog) async {
    final rows = await _db.query(
      config,
      // Branch-scoped, which it was not before: on a branch server serving
      // two shops, one till used to hydrate the other shop's parked tables.
      // A row that cannot name its branch — a table deleted before migration
      // 25 backfilled from it — is shown to every till rather than to none,
      // because a parked ticket nobody can reach is money nobody can collect.
      'SELECT table_id, payload, version FROM pos_parked_tickets '
      'WHERE pos_parked_tickets.restaurant_id = @restaurant '
      '  AND (branch_id = @branch OR branch_id IS NULL) '
      // A sale can commit before a transient delete of its parked row.  Do
      // not ever hydrate that stale work as an unpaid ticket on the next
      // boot; the committed order is the authoritative fact.
      '  AND NOT EXISTS (SELECT 1 FROM pos_orders o '
      '                  WHERE o.restaurant_id = pos_parked_tickets.restaurant_id '
      '                    AND o.client_transaction_id = pos_parked_tickets.client_transaction_id) '
      'ORDER BY parked_at',
      parameters: {'restaurant': restaurantId, 'branch': branchId},
    );

    final onTables = <int, Ticket>{};
    final versions = <int, int>{};
    final held = <Ticket>[];
    final heldVersions = <String, int>{};
    for (final row in rows) {
      final ticket = _decode(row[1], catalog);
      if (ticket == null) continue;
      final tableId = row[0];
      if (tableId is int) {
        onTables[tableId] = ticket;
        versions[tableId] = row[2]! as int;
      } else {
        held.add(ticket);
        heldVersions[ticket.id] = row[2]! as int;
      }
    }
    return ParkedFloor(
      onTables: onTables,
      held: held,
      versions: versions,
      heldVersions: heldVersions,
    );
  }

  /// Write [ticket] down, and return its row's new version.
  ///
  /// **Every save is a compare-and-swap (XORD-044, XORD-046).**
  /// [expectedVersion] is the version of the row this till last read or wrote,
  /// or null when it believes there is none yet. The save lands only if the
  /// row is still exactly that; one another till has created, changed or
  /// cleared since throws [ParkedTicketChanged] instead of being overwritten.
  /// Before this, a second till whose floor still showed the table free
  /// replaced the first till's check — food already sent to the kitchen
  /// included — and nobody was told; and two tills that resumed the same held
  /// takeaway each saved over the other. Every replacement moves the version
  /// (migration 63) on by one.
  ///
  /// A seated row is found by its table, a held one by its transaction id.
  Future<int> save(Ticket ticket, {int? expectedVersion}) async {
    final tableId = ticket.tableId;
    final parameters = {
      'restaurant': restaurantId,
      'branch': branchId,
      'table': ?tableId,
      'txn': ticket.id,
      'payload': jsonEncode(ParkedTicketCodec.encode(ticket)),
      'expected': ?expectedVersion,
    };
    if (tableId == null) {
      final rows = await _db.query(
        config,
        expectedVersion == null
            ? '''
              INSERT INTO pos_parked_tickets
                (restaurant_id, branch_id, table_id, client_transaction_id,
                 payload, parked_at)
              VALUES (@restaurant, @branch, NULL, @txn, @payload, now())
              ON CONFLICT (restaurant_id, client_transaction_id)
                WHERE table_id IS NULL
              DO NOTHING
              RETURNING version
              '''
            : '''
              UPDATE pos_parked_tickets
                 SET payload = @payload,
                     parked_at = now(),
                     version = version + 1
               WHERE restaurant_id = @restaurant
                 AND client_transaction_id = @txn
                 AND table_id IS NULL
                 AND version = @expected
              RETURNING version
              ''',
        // The branch is not rewritten on a held row: it is what locates it.
        parameters: expectedVersion == null
            ? parameters
            : ({...parameters}..remove('branch')),
      );
      if (rows.isEmpty) throw const ParkedTicketChanged(null);
      return rows.first[0]! as int;
    }

    final rows = await _db.query(
      config,
      // Two statements rather than one upsert, because the two cases refuse
      // differently: a till that thinks the table is free may only create its
      // row, and one that holds a version may only replace that exact row —
      // never re-create a row another till has since cleared. Both still
      // conflict on the one-ticket-per-table index, which stays the backstop.
      expectedVersion == null
          ? '''
            INSERT INTO pos_parked_tickets
              (restaurant_id, branch_id, table_id, client_transaction_id,
               payload, parked_at)
            VALUES (@restaurant, @branch, @table, @txn, @payload, now())
            ON CONFLICT (restaurant_id, table_id) DO NOTHING
            RETURNING version
            '''
          : '''
            UPDATE pos_parked_tickets
               SET branch_id = @branch,
                   client_transaction_id = @txn,
                   payload = @payload,
                   parked_at = now(),
                   version = version + 1
             WHERE restaurant_id = @restaurant
               AND table_id = @table
               AND version = @expected
            RETURNING version
            ''',
      parameters: parameters,
    );
    if (rows.isEmpty) throw ParkedTicketChanged(tableId);
    return rows.first[0]! as int;
  }

  /// Let go of a parked ticket, by whichever of its two identities is real.
  ///
  /// Both are matched in one statement rather than one of them, because a
  /// ticket that was parked on a table and then switched to takeaway — which
  /// clears the table — would otherwise leave its old row behind, and that row
  /// comes back on the floor at the next boot as a bill nobody owes.
  ///
  /// The table is matched only at the [expectedVersion] this till holds
  /// (XORD-044): a row on that table under another transaction is another
  /// till's ticket, and clearing a table must never delete somebody else's
  /// check. Without a version only the transaction is matched.
  Future<void> remove({
    int? tableId,
    required String transactionId,
    int? expectedVersion,
  }) async {
    await _db.query(
      config,
        'DELETE FROM pos_parked_tickets '
        'WHERE restaurant_id = @restaurant '
        '  AND (client_transaction_id = @txn '
        '       OR (@table::bigint IS NOT NULL AND table_id = @table '
        '           AND version = @expected::int))',
        parameters: {
          'restaurant': restaurantId,
          'txn': transactionId,
          'table': tableId,
          'expected': expectedVersion,
      },
    );
  }

  static Ticket? _decode(Object? payload, Catalog catalog) {
    final map = switch (payload) {
      final Map<String, Object?> m => m,
      final Map m => m.cast<String, Object?>(),
      final String s => switch (jsonDecode(s)) {
        final Map m => m.cast<String, Object?>(),
        _ => null,
      },
      _ => null,
    };
    return map == null ? null : ParkedTicketCodec.decode(map, catalog);
  }
}

/// What [PostgresParkedTickets.load] reads back: the floor, the counter, and
/// the version of each table's row for the next compare-and-swap.
class ParkedFloor {
  const ParkedFloor({
    this.onTables = const {},
    this.held = const [],
    this.versions = const {},
    this.heldVersions = const {},
  });

  final Map<int, Ticket> onTables;
  final List<Ticket> held;

  /// Table id → `pos_parked_tickets.version` of its row.
  final Map<int, int> versions;

  /// Held ticket's transaction id → the version of its row.
  final Map<String, int> heldVersions;
}

/// A save refused because the parked row is no longer the one this till last
/// saw: another till seated, changed or cleared it (XORD-044, XORD-046).
class ParkedTicketChanged implements Exception {
  const ParkedTicketChanged(this.tableId);

  /// The table, or null for a held ticket.
  final int? tableId;

  @override
  String toString() => 'ParkedTicketChanged(table $tableId)';
}
