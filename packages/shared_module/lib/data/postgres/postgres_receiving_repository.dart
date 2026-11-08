import '../sql/sql.dart';

import '../../core/config/deployment.dart';
import '../../core/money/money.dart';
import '../../core/money/quantity.dart';
import '../../domain/services/authorization.dart';
import '../../domain/models/permissions.dart';
import '../../domain/models/purchase_order.dart';
import '../../domain/repositories/admin_repositories.dart';
import '../../domain/repositories/repositories.dart';
import '../../domain/services/stock_costing.dart';

/// Booking goods in against a purchase order.
///
/// **The one write in this product that has to do four things atomically**: the
/// received quantity on the line, a movement in the ledger, the new position in
/// the cache, and the order's status. Any of those landing without the others
/// leaves a stock figure that disagrees with its own history — so all of it is
/// one transaction, and the position is read `FOR UPDATE` because two people
/// booking in two deliveries of the same product at once is a Tuesday in a
/// business with a back door.
class PostgresReceivingRepository implements ReceivingRepository {
  const PostgresReceivingRepository({
    required SqlDatabase database,
    required this.config,
    required this.adminAvailable,
    required this.businessId,
    required this.branchId,
  }) : _db = database;

  final SqlDatabase _db;
  final DeploymentConfig config;
  final bool adminAvailable;
  final int businessId;
  final int branchId;

  @override
  Future<AdminResult<void>> receive({
    required int purchaseOrderId,
    required Map<int, Quantity> byLine,
    required PosStaff by,
    DateTime? at,
    String? note,
  }) async {
    if (!adminAvailable) {
      return const AdminResult.refused(AdministratorCredentialRequired());
    }
    // `Authorization.check` and not `by.capabilities`: that field holds the
    // direct grants alone, so a manager whose permission comes from their
    // role would have been refused. It also asks whether they are still
    // employed, which membership of a set does not.
    if (!Authorization.check(by, PosCapability.purchaseManage).isAllowed) {
      return const AdminResult.refused(
        NotPermitted(PosCapability.purchaseManage),
      );
    }
    if (byLine.values.every((q) => q.milli <= 0)) {
      return const AdminResult.refused(
        CatalogInvalid('Nothing was booked in.'),
      );
    }

    return _db.runTx(config, (tx) async {
      final order = await tx.execute(
        Sql.named(
          'SELECT status FROM pos_purchase_orders '
          'WHERE id = @id AND business_id = @r AND branch_id = @b FOR UPDATE',
        ),
        parameters: {'id': purchaseOrderId, 'r': businessId, 'b': branchId},
      );
      if (order.isEmpty) {
        return const AdminResult<void>.refused(EditedElsewhere(0));
      }

      final status = PurchaseStatus.fromWire(order.first[0]! as String);
      if (!status.isOpen) {
        return AdminResult<void>.refused(
          CatalogInvalid(
            status == PurchaseStatus.draft
                ? 'That order has not been sent yet, so nothing can arrive '
                      'against it.'
                : 'That order is closed.',
          ),
        );
      }

      final occurredAt = (at ?? DateTime.now()).toUtc();

      for (final entry in byLine.entries) {
        if (entry.value.milli <= 0) continue;

        final lines = await tx.execute(
          Sql.named(
            'SELECT product_id, description, unit, unit_cost_minor, '
            '       received_milli '
            'FROM pos_purchase_order_lines '
            'WHERE id = @id AND purchase_order_id = @order FOR UPDATE',
          ),
          parameters: {'id': entry.key, 'order': purchaseOrderId},
        );
        if (lines.isEmpty) {
          return const AdminResult<void>.refused(EditedElsewhere(0));
        }

        final row = lines.first;
        final productId = row[0] as int?;
        final unit = QuantityUnit.fromWire(row[2] as String?);
        final unitCost = Money(row[3]! as int);
        final arrived = Quantity(entry.value.milli, unit: unit);

        // The position before anything is written, and in the unit it is
        // STORED in. This used to read the quantity and label it with the
        // line's unit, then overwrite the stored unit with the line's — so
        // 5 kg arriving on 10 boxes was saved as 15 kg, and the assert meant to
        // catch it compared the line's unit with itself.
        StockPosition? before;
        if (productId != null) {
          // FOR SHARE on the item, so a unit change from the Items or Menu
          // pane waits for this receipt instead of both reading "nothing held"
          // and both committing. It also names the item for the refusal.
          final product = await tx.execute(
            Sql.named(
              'SELECT name_en FROM pos_products WHERE id = @p FOR SHARE',
            ),
            parameters: {'p': productId},
          );
          final held = await tx.execute(
            Sql.named(
              'SELECT quantity_milli, average_cost_minor, unit '
              'FROM pos_stock_levels '
              'WHERE branch_id = @b AND product_id = @p FOR UPDATE',
            ),
            parameters: {'b': branchId, 'p': productId},
          );

          if (held.isEmpty) {
            before = StockPosition(
              onHand: Quantity(0, unit: unit),
              unitCost: unitCost,
            );
          } else {
            final onHand = Quantity(
              held.first[0]! as int,
              unit: QuantityUnit.fromWire(held.first[2] as String?),
            );
            // Refused, never converted: nothing here knows how many kilos are
            // in a box. Negative stock counts as held — a debt in boxes is not
            // settled in kilos.
            if (!onHand.isZero && onHand.unit != unit) {
              // Rolled back, not only returned. An earlier line of this same
              // receipt may already be written, and `runTx` commits whatever
              // the callback returns — so a plain return would keep half a
              // delivery that the screen says was refused.
              await tx.rollback();
              return AdminResult<void>.refused(
                StockHeldInAnotherUnit(
                  item: product.isEmpty
                      ? row[1]! as String
                      : product.first[0]! as String,
                  held: onHand,
                  asked: unit,
                ),
              );
            }
            before = StockPosition(
              onHand: onHand,
              unitCost: Money(held.first[1]! as int),
            );
          }
        }

        await tx.execute(
          Sql.named(
            'UPDATE pos_purchase_order_lines '
            '   SET received_milli = received_milli + @arrived '
            ' WHERE id = @id',
          ),
          parameters: {'id': entry.key, 'arrived': arrived.milli},
        );

        // A line that stocks nothing — packaging, gas, a service — moves the
        // order along and touches no ledger. Most of a purchase order by line
        // count is this, and inventing a stock record for it would fill the
        // ledger with movements nobody counts.
        if (productId == null) continue;

        final after = StockCosting.receive(
          before!,
          received: arrived,
          unitCost: unitCost,
        );

        await tx.execute(
          Sql.named('''
          INSERT INTO pos_stock_movements
            (business_id, branch_id, product_id, kind, quantity_milli, unit,
             unit_cost_minor, balance_milli, average_cost_minor,
             purchase_order_id, note, occurred_at, created_by)
          VALUES (@r, @b, @p, 'receipt', @qty, @unit, @cost, @balance,
                  @average, @order, @note, @at, @by)
          '''),
          parameters: {
            'r': businessId,
            'b': branchId,
            'p': productId,
            'qty': arrived.milli,
            'unit': unit.wire,
            'cost': unitCost.minor,
            'balance': after.onHand.milli,
            'average': after.unitCost.minor,
            'order': purchaseOrderId,
            'note': note,
            'at': occurredAt,
            'by': by.id == 0 ? null : by.id,
          },
        );

        await tx.execute(
          Sql.named('''
          INSERT INTO pos_stock_levels
            (business_id, branch_id, product_id, quantity_milli, unit,
             average_cost_minor, updated_at)
          VALUES (@r, @b, @p, @qty, @unit, @average, now())
          ON CONFLICT (branch_id, product_id) DO UPDATE SET
            quantity_milli = excluded.quantity_milli,
            average_cost_minor = excluded.average_cost_minor,
            -- Only ever a real change when nothing was held: the check above
            -- refuses any other, and migration 44's trigger refuses it again.
            unit = excluded.unit,
            updated_at = now()
          '''),
          parameters: {
            'r': businessId,
            'b': branchId,
            'p': productId,
            'qty': after.onHand.milli,
            'unit': unit.wire,
            'average': after.unitCost.minor,
          },
        );
      }

      // The status follows the lines rather than being set by the caller, so a
      // receipt cannot leave the order saying something its own lines
      // contradict.
      final remaining = await tx.execute(
        Sql.named(
          'SELECT count(*) FILTER (WHERE received_milli < ordered_milli), '
          '       count(*) FILTER (WHERE received_milli > 0) '
          'FROM pos_purchase_order_lines WHERE purchase_order_id = @id',
        ),
        parameters: {'id': purchaseOrderId},
      );
      final short = remaining.first[0]! as int;
      final touched = remaining.first[1]! as int;
      final next = short == 0
          ? PurchaseStatus.received
          : (touched > 0
                ? PurchaseStatus.partiallyReceived
                : PurchaseStatus.sent);

      await tx.execute(
        Sql.named(
          'UPDATE pos_purchase_orders SET status = @status, updated_at = now(), '
          '  updated_by = @by WHERE id = @id',
        ),
        parameters: {
          'id': purchaseOrderId,
          'status': next.wire,
          'by': by.id == 0 ? null : by.id,
        },
      );

      await tx.execute(
        Sql.named('''
        INSERT INTO pos_audit_events
          (business_id, branch_id, actor_user_id, actor_name, action,
           entity_type, entity_id, after_value)
        VALUES (@business, @branch, @by, @actor, @action, @type, @entity,
                @after::jsonb)
        '''),
        parameters: {
          'business': businessId,
          'branch': branchId,
          'by': by.id == 0 ? null : by.id,
          'actor': by.name,
          'action': AuditAction.stockReceived,
          'type': AuditAction.entityPurchaseOrder,
          'entity': '$purchaseOrderId',
          'after': '{"status": "${next.wire}", "lines": ${byLine.length}}',
        },
      );

      return const AdminResult<void>.done(null);
    });
  }

  @override
  Future<AdminResult<StockPosition>> setOpeningCost({
    required int productId,
    required Money unitCost,
    required PosStaff by,
    String? note,
  }) async {
    if (!adminAvailable) {
      return const AdminResult.refused(AdministratorCredentialRequired());
    }
    if (!Authorization.check(by, PosCapability.purchaseManage).isAllowed) {
      return const AdminResult.refused(
        NotPermitted(PosCapability.purchaseManage),
      );
    }

    return _db.runTx(config, (tx) async {
      AdminResult<StockPosition> refuse(OpeningCostProblem problem) =>
          AdminResult.refused(OpeningCostRefused(problem));

      // The item, locked: two people setting a first cost at once must not both
      // succeed, and the second has to find it costed.
      final product = await tx.execute(
        Sql.named(
          'SELECT stock_unit, is_stocked FROM pos_products '
          'WHERE id = @p AND business_id = @r FOR UPDATE',
        ),
        parameters: {'p': productId, 'r': businessId},
      );
      if (product.isEmpty) return refuse(OpeningCostProblem.itemUnknown);

      final held = await tx.execute(
        Sql.named(
          'SELECT quantity_milli, unit, average_cost_minor '
          'FROM pos_stock_levels '
          'WHERE branch_id = @b AND product_id = @p FOR UPDATE',
        ),
        parameters: {'b': branchId, 'p': productId},
      );
      // Not counted at all — neither stocked nor holding a position — means
      // there is no stock here to give a cost to.
      if (held.isEmpty && product.first[1] != true) {
        return refuse(OpeningCostProblem.itemUnknown);
      }

      final unit = held.isEmpty
          ? QuantityUnit.fromWire(product.first[0] as String?)
          : QuantityUnit.fromWire(held.first[1] as String?);
      final before = StockPosition(
        onHand: Quantity(held.isEmpty ? 0 : held.first[0]! as int, unit: unit),
        unitCost: Money(held.isEmpty ? 0 : held.first[2]! as int),
      );

      final problem = OpeningCost.refusal(before, unitCost);
      if (problem != null) return refuse(problem);
      final after = OpeningCost.apply(before, unitCost);

      // A movement of nothing: how much is on the shelf has not changed, only
      // what it cost. It carries the cost and the resulting position like every
      // other row, so a replay of the ledger arrives at the same average.
      await tx.execute(
        Sql.named('''
        INSERT INTO pos_stock_movements
          (business_id, branch_id, product_id, kind, quantity_milli, unit,
           unit_cost_minor, balance_milli, average_cost_minor, note,
           occurred_at, created_by)
        VALUES (@r, @b, @p, 'opening', 0, @unit, @cost, @balance, @cost, @note,
                now(), @by)
        '''),
        parameters: {
          'r': businessId,
          'b': branchId,
          'p': productId,
          'unit': unit.wire,
          'cost': unitCost.minor,
          'balance': before.onHand.milli,
          'note': note,
          'by': by.id == 0 ? null : by.id,
        },
      );

      await tx.execute(
        Sql.named('''
        INSERT INTO pos_stock_levels
          (business_id, branch_id, product_id, quantity_milli, unit,
           average_cost_minor, updated_at)
        VALUES (@r, @b, @p, @qty, @unit, @cost, now())
        ON CONFLICT (branch_id, product_id) DO UPDATE SET
          average_cost_minor = excluded.average_cost_minor,
          updated_at = now()
        '''),
        parameters: {
          'r': businessId,
          'b': branchId,
          'p': productId,
          'qty': before.onHand.milli,
          'unit': unit.wire,
          'cost': unitCost.minor,
        },
      );

      await tx.execute(
        Sql.named('''
        INSERT INTO pos_audit_events
          (business_id, branch_id, actor_user_id, actor_name, action,
           entity_type, entity_id, before_value, after_value)
        VALUES (@business, @branch, @by, @actor, @action, @type, @entity,
                @before::jsonb, @after::jsonb)
        '''),
        parameters: {
          'business': businessId,
          'branch': branchId,
          'by': by.id == 0 ? null : by.id,
          'actor': by.name,
          'action': AuditAction.stockCostSet,
          'type': AuditAction.entityProduct,
          'entity': '$productId',
          'before': '{"average_cost_minor": 0}',
          'after':
              '{"average_cost_minor": ${unitCost.minor}, '
              '"on_hand_milli": ${before.onHand.milli}}',
        },
      );

      return AdminResult.done(after);
    });
  }

  @override
  Future<StockPosition?> positionFor(int productId) async {
    if (!adminAvailable) return null;

    final rows = await _db.query(
      config,
      'SELECT quantity_milli, unit, average_cost_minor FROM pos_stock_levels '
      'WHERE branch_id = @b AND product_id = @p',
      parameters: {'b': branchId, 'p': productId},
    );
    if (rows.isEmpty) return null;

    return StockPosition(
      onHand: Quantity(
        rows.first[0]! as int,
        unit: QuantityUnit.fromWire(rows.first[1] as String?),
      ),
      unitCost: Money(rows.first[2]! as int),
    );
  }
}

/// What a terminal binds before it has an administrator credential.
class UnconfiguredReceivingRepository implements ReceivingRepository {
  const UnconfiguredReceivingRepository();

  @override
  Future<AdminResult<void>> receive({
    required int purchaseOrderId,
    required Map<int, Quantity> byLine,
    required PosStaff by,
    DateTime? at,
    String? note,
  }) async => const AdminResult.refused(NoDatabaseConfigured());

  @override
  Future<StockPosition?> positionFor(int productId) async => null;

  @override
  Future<AdminResult<StockPosition>> setOpeningCost({
    required int productId,
    required Money unitCost,
    required PosStaff by,
    String? note,
  }) async => const AdminResult.refused(NoDatabaseConfigured());
}
