<?php

namespace App\Services;

use App\Enums\PurchaseStatus;
use App\Exceptions\PurchasingRefusal;
use App\Models\PurchaseOrder;
use App\Models\PurchaseOrderLine;
use App\Models\StockItem;
use App\Models\StockLevel;
use App\Models\StockMovement;
use App\Models\Unit;
use App\Models\User;
use App\Support\StockCosting;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * CB-09 slice b: booking goods in against a purchase order. The platform's
 * PostgresReceivingRepository.receive, as one transaction:
 *
 *   1. lock the order and RE-READ its status: only sent or part-received
 *      orders take goods;
 *   2. lock the lines named, in ascending id order;
 *   3. take a SHARED lock on each stock item, so a unit change waits;
 *   4. lock each (branch, item) level row, in ascending item id order, so
 *      two receipts can't deadlock;
 *   5. per line: add to received_milli, append a movement carrying the
 *      resulting balance and moving average (StockCosting, the till's
 *      arithmetic), and update the level to match;
 *   6. set the status FROM THE LINES (all full → received, anything arrived
 *      → partially_received, else sent), and audit.
 *
 * Any refusal throws inside the transaction, so a receipt is all or nothing:
 * a refused third line never leaves the first two booked.
 *
 * The cost is the PO line's unit_cost_minor, the ordered price, as on the
 * till. Over-delivery is accepted (suppliers round up to a crate). A line
 * with no stock item moves the order along and touches no ledger.
 *
 * A receipt NEVER converts units. It is refused when the line's unit is not
 * the item's unit, or when the branch already holds a non-zero quantity of
 * the item in another unit (a debt in boxes is not settled in kilos). The
 * till's version of this check was a stripped assert (design §10 C3).
 */
class ReceivingService
{
    /**
     * @param  array<int,int>  $quantities  line id => quantity_milli arriving
     */
    public function receive(PurchaseOrder $order, array $quantities, ?Carbon $occurredAt, ?string $note, User $by): PurchaseOrder
    {
        return DB::transaction(function () use ($order, $quantities, $occurredAt, $note, $by) {
            $locked = PurchaseOrder::withoutGlobalScopes()
                ->where('restaurant_id', $order->restaurant_id)
                ->whereKey($order->id)
                ->lockForUpdate()
                ->firstOrFail();

            if (! $locked->status->isOpen()) {
                throw PurchasingRefusal::conflict('PO_NOT_OPEN', $locked->status === PurchaseStatus::DRAFT ? 'receive_draft' : 'receive_closed');
            }

            $quantities = array_filter($quantities, fn ($q) => $q > 0);
            ksort($quantities);
            if ($quantities === []) {
                throw PurchasingRefusal::invalid('NOTHING_RECEIVED', 'nothing_received', [], 'lines');
            }

            $lines = PurchaseOrderLine::withoutGlobalScopes()
                ->where('purchase_order_id', $locked->id)
                ->whereIn('id', array_keys($quantities))
                ->orderBy('id')
                ->lockForUpdate()
                ->get()
                ->keyBy('id');

            if ($lines->count() !== count($quantities)) {
                throw PurchasingRefusal::invalid('LINE_NOT_ON_ORDER', 'line_not_on_order', [], 'lines');
            }

            $itemIds = $lines->pluck('stock_item_id')->filter()->unique()->sort()->values()->all();

            $items = StockItem::withoutGlobalScopes()
                ->where('restaurant_id', $locked->restaurant_id)
                ->whereIn('id', $itemIds)
                ->orderBy('id')
                ->sharedLock()
                ->get()
                ->keyBy('id');

            // A level row exists before it is locked, so two first receipts
            // of the same item serialise on the row instead of racing to
            // insert it. insertOrIgnore is the grammar's portable form.
            foreach ($itemIds as $itemId) {
                StockLevel::query()->insertOrIgnore([
                    'restaurant_id' => $locked->restaurant_id,
                    'branch_id' => $locked->branch_id,
                    'stock_item_id' => $itemId,
                    'quantity_milli' => 0,
                    'unit_code' => $items->get($itemId)?->unit_code ?? 'ea',
                    'average_cost_minor' => 0,
                    'updated_at' => now(),
                ]);
            }

            $levels = StockLevel::withoutGlobalScopes()
                ->where('branch_id', $locked->branch_id)
                ->whereIn('stock_item_id', $itemIds)
                ->orderBy('stock_item_id')
                ->lockForUpdate()
                ->get()
                ->keyBy('stock_item_id');

            $units = Unit::withoutGlobalScopes()
                ->where('restaurant_id', $locked->restaurant_id)
                ->whereIn('code', $lines->pluck('unit_code')->unique()->all())
                ->get()
                ->keyBy('code');

            $at = $occurredAt ?? now();
            $movements = 0;

            foreach ($quantities as $lineId => $milli) {
                $line = $lines->get($lineId);
                $unit = $units->get($line->unit_code);

                if ($unit !== null && ! $unit->allows_fraction && $milli % 1000 !== 0) {
                    throw PurchasingRefusal::invalid('FRACTION_NOT_ALLOWED', 'fraction_not_allowed', ['unit' => $line->unit_code], 'lines');
                }

                $line->forceFill(['received_milli' => $line->received_milli + $milli])->save();

                if ($line->stock_item_id === null) {
                    continue;
                }

                $item = $items->get($line->stock_item_id);
                $level = $levels->get($line->stock_item_id);

                if ($item === null || $level === null) {
                    // The item belongs to this business (it was validated when
                    // the line was written) and stock items are never
                    // deleted, so this is corruption, not a user error.
                    throw new \LogicException("Stock item {$line->stock_item_id} is missing.");
                }

                if ($line->unit_code !== $item->unit_code) {
                    throw PurchasingRefusal::conflict('LINE_UNIT_DIFFERS', 'line_unit_differs', [
                        'item' => $line->description, 'line_unit' => $line->unit_code, 'item_unit' => $item->unit_code,
                    ]);
                }

                if ($level->quantity_milli !== 0 && $level->unit_code !== $line->unit_code) {
                    throw PurchasingRefusal::conflict('STOCK_HELD_IN_ANOTHER_UNIT', 'held_in_another_unit', [
                        'item' => $line->description, 'held' => $level->unit_code, 'asked' => $line->unit_code,
                    ]);
                }

                $after = StockCosting::receive($level->quantity_milli, $level->average_cost_minor, $milli, $line->unit_cost_minor);

                $movement = new StockMovement;
                $movement->forceFill([
                    'restaurant_id' => $locked->restaurant_id,
                    'branch_id' => $locked->branch_id,
                    'stock_item_id' => $item->id,
                    'kind' => 'receipt',
                    'quantity_milli' => $milli,
                    'unit_code' => $line->unit_code,
                    'unit_cost_minor' => $line->unit_cost_minor,
                    'balance_milli' => $after['milli'],
                    'average_cost_minor' => $after['cost'],
                    'purchase_order_id' => $locked->id,
                    'purchase_order_line_id' => $line->id,
                    'note' => $note,
                    'occurred_at' => $at,
                    'created_by' => $by->id,
                ])->save();
                $movements++;

                $level->forceFill([
                    'quantity_milli' => $after['milli'],
                    'average_cost_minor' => $after['cost'],
                    // Only ever a real change when nothing was held: the
                    // check above refuses any other.
                    'unit_code' => $line->unit_code,
                    'updated_at' => now(),
                ])->save();
            }

            $all = PurchaseOrderLine::withoutGlobalScopes()
                ->where('purchase_order_id', $locked->id)
                ->get(['ordered_milli', 'received_milli']);
            $short = $all->filter(fn ($l) => $l->received_milli < $l->ordered_milli)->count();
            $touched = $all->filter(fn ($l) => $l->received_milli > 0)->count();

            $next = $short === 0
                ? PurchaseStatus::RECEIVED
                : ($touched > 0 ? PurchaseStatus::PARTIALLY_RECEIVED : PurchaseStatus::SENT);

            $from = $locked->status;
            $locked->forceFill(['status' => $next, 'updated_by' => $by->id])->save();

            AuditLogger::record('purchase_order.received', [
                'auditable' => $locked,
                'description' => sprintf('Goods received against purchase order %s', $locked->reference),
                'properties' => [
                    'from' => $from->value,
                    'status' => $next->value,
                    'lines' => collect($quantities)->map(fn ($q, $id) => ['line_id' => $id, 'quantity_milli' => $q])->values()->all(),
                    'movements' => $movements,
                ],
            ]);

            return $locked;
        });
    }
}
