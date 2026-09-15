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
/// moment it settles. Reads happen once, at boot, to put the till back the way
/// the restart found it.
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
  Future<({Map<int, Ticket> onTables, List<Ticket> held})> load(
    Catalog catalog,
  ) async {
    try {
      final rows = await _db.query(
        config,
        // Branch-scoped, which it was not before: on a branch server serving
        // two shops, one till used to hydrate the other shop's parked tables.
        // A row that cannot name its branch — a table deleted before migration
        // 25 backfilled from it — is shown to every till rather than to none,
        // because a parked ticket nobody can reach is money nobody can collect.
        'SELECT table_id, payload FROM pos_parked_tickets '
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
      final held = <Ticket>[];
      for (final row in rows) {
        final ticket = _decode(row[1], catalog);
        if (ticket == null) continue;
        final tableId = row[0];
        if (tableId is int) {
          onTables[tableId] = ticket;
        } else {
          held.add(ticket);
        }
      }
      return (onTables: onTables, held: held);
    } on Object {
      return (onTables: const <int, Ticket>{}, held: const <Ticket>[]);
    }
  }

  Future<void> save(Ticket ticket) async {
    final tableId = ticket.tableId;
    await _db.query(
      config,
        // Two upserts, one per identity, because a parked ticket is identified
        // by its table when it has one and by its transaction when it does not.
        // A single statement conflicting on the transaction id would have let a
        // table hold two tickets at once — the invariant the floor rests on —
        // and one conflicting on the table cannot be written at all for a row
        // whose table is null.
        tableId != null
            ? '''
              INSERT INTO pos_parked_tickets
                (restaurant_id, branch_id, table_id, client_transaction_id,
                 payload, parked_at)
              VALUES (@restaurant, @branch, @table, @txn, @payload, now())
              ON CONFLICT (restaurant_id, table_id) DO UPDATE
                SET branch_id = @branch,
                    client_transaction_id = @txn,
                    payload = @payload,
                    parked_at = now()
              '''
            : '''
              INSERT INTO pos_parked_tickets
                (restaurant_id, branch_id, table_id, client_transaction_id,
                 payload, parked_at)
              VALUES (@restaurant, @branch, NULL, @txn, @payload, now())
              ON CONFLICT (restaurant_id, client_transaction_id)
                WHERE table_id IS NULL
              DO UPDATE SET payload = @payload, parked_at = now()
              ''',
        parameters: {
          'restaurant': restaurantId,
          'branch': branchId,
          'table': ?tableId,
          'txn': ticket.id,
          'payload': jsonEncode(ParkedTicketCodec.encode(ticket)),
      },
    );
  }

  /// Let go of a parked ticket, by whichever of its two identities is real.
  ///
  /// Both are matched in one statement rather than one of them, because a
  /// ticket that was parked on a table and then switched to takeaway — which
  /// clears the table — would otherwise leave its old row behind, and that row
  /// comes back on the floor at the next boot as a bill nobody owes.
  Future<void> remove({int? tableId, required String transactionId}) async {
    await _db.query(
      config,
        'DELETE FROM pos_parked_tickets '
        'WHERE restaurant_id = @restaurant '
        '  AND (client_transaction_id = @txn '
        '       OR (@table::bigint IS NOT NULL AND table_id = @table))',
        parameters: {
          'restaurant': restaurantId,
          'txn': transactionId,
          'table': tableId,
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
