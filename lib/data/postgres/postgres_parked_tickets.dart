import 'dart:convert';

import '../../core/config/deployment.dart';
import '../../domain/models/catalog.dart';
import '../../domain/models/ticket.dart';
import 'parked_ticket_codec.dart';
import 'pos_database.dart';

/// The open floor, on disk.
///
/// Write-through storage for parked table tickets: park upserts, settlement
/// deletes — the one legitimate DELETE in the till's grant set, because the
/// durable record of the money lives in `pos_orders` from the moment it
/// settles. Reads happen once, at boot, to put the floor back the way the
/// restart found it.
///
/// Every failure is swallowed into a best-effort result rather than thrown:
/// parking a table must never crash a sale over a database hiccup — the
/// in-memory floor keeps working and the next write tries again.
class PostgresParkedTickets {
  const PostgresParkedTickets({
    required PosDatabase database,
    required this.config,
    required this.restaurantId,
  }) : _db = database;

  final PosDatabase _db;
  final DeploymentConfig config;
  final int restaurantId;

  Future<Map<int, Ticket>> load(Catalog catalog) async {
    try {
      final rows = await _db.query(
        config,
        'SELECT table_id, payload FROM pos_parked_tickets '
        'WHERE restaurant_id = @restaurant',
        parameters: {'restaurant': restaurantId},
      );
      return {for (final row in rows) row[0] as int: ?_decode(row[1], catalog)};
    } on Object {
      return const {};
    }
  }

  Future<void> save(Ticket ticket) async {
    final tableId = ticket.tableId;
    if (tableId == null) return;
    try {
      await _db.query(
        config,
        '''
        INSERT INTO pos_parked_tickets
          (restaurant_id, table_id, client_transaction_id, payload, parked_at)
        VALUES (@restaurant, @table, @txn, @payload, now())
        ON CONFLICT (restaurant_id, table_id) DO UPDATE
          SET client_transaction_id = @txn, payload = @payload, parked_at = now()
        ''',
        parameters: {
          'restaurant': restaurantId,
          'table': tableId,
          'txn': ticket.id,
          'payload': jsonEncode(ParkedTicketCodec.encode(ticket)),
        },
      );
    } on Object {
      // Best effort — see the class comment.
    }
  }

  Future<void> remove(int tableId) async {
    try {
      await _db.query(
        config,
        'DELETE FROM pos_parked_tickets '
        'WHERE restaurant_id = @restaurant AND table_id = @table',
        parameters: {'restaurant': restaurantId, 'table': tableId},
      );
    } on Object {
      // Best effort — a row that outlives its settlement is re-deleted on the
      // next settle of that table, and hydration tolerates it meanwhile.
    }
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
