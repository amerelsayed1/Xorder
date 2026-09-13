<?php

namespace App\Services;

use App\Enums\StockAdjustmentReason;
use App\Exceptions\PurchasingRefusal;
use App\Models\StockItem;
use App\Models\StockLevel;
use App\Models\StockMovement;
use App\Models\Unit;
use App\Models\User;
use App\Support\StockCosting;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * CB-09 slice d (D12, owner 2026-09-13: "finish all phases"): opening
 * stock, waste, adjustments and counts. Each is ONE new, immutable movement
 * in the same ledger receiving writes. Nothing is ever edited: a mistake is
 * corrected by another movement.
 *
 * The lock pattern is ReceivingService's, for one item:
 *
 *   1. a SHARED lock on the stock item, so a unit change waits;
 *   2. insertOrIgnore the (branch, item) level, then lock it FOR UPDATE, so
 *      a receipt and an adjustment of the same item serialise on that row;
 *   3. read the position under the lock, compute with StockCosting, append
 *      the movement with the resulting balance and average, update the level
 *      to match, audit. All inside one transaction: a refusal writes nothing.
 *
 * Arithmetic, exactly the till's (stock_costing.dart):
 *
 *   in   (opening, adjustment up, count up)    StockCosting::receive at the
 *        entry's unit cost: nothing or a NEGATIVE on hand takes that cost,
 *        otherwise the quantity-weighted average, rounded half-up once.
 *   out  (waste, adjustment down, count down)  StockCosting::issue: the
 *        quantity falls, may go below zero, and the average never moves. The
 *        movement records the average it left at as its unit cost.
 *
 * StockLedger::replay folds exactly this (positive = receive at the row's
 * cost, negative = issue), so a slice-d movement can be checked like a
 * receipt.
 *
 * A movement never converts units. It is refused when the page's unit is not
 * the item's, or when the branch holds a non-zero quantity in another unit.
 *
 * It never touches a purchase order: no order id, no line, no status. A
 * closed-short order stays closed; short-close never touched stock either.
 */
class StockAdjustmentService
{
    /**
     * @param  array{branch_id:int, stock_item_id:int, kind:string, quantity_milli?:int, counted_milli?:int,
     *               unit_cost_minor?:?int, unit_code?:?string, reason:StockAdjustmentReason, note?:?string,
     *               occurred_at?:?string}  $entry  validated by StoreStockAdjustmentRequest
     */
    public function record(array $entry, User $by): StockMovement
    {
        return DB::transaction(function () use ($entry, $by) {
            $tenant = $by->restaurant_id;
            $kind = $entry['kind'];
            $reason = $entry['reason'];
            $branchId = (int) $entry['branch_id'];

            $item = StockItem::withoutGlobalScopes()
                ->where('restaurant_id', $tenant)
                ->whereKey($entry['stock_item_id'])
                ->sharedLock()
                ->firstOrFail();

            $unitCode = $item->unit_code;
            $label = $item->displayName();

            if (! empty($entry['unit_code']) && $entry['unit_code'] !== $unitCode) {
                throw PurchasingRefusal::conflict('ADJUSTMENT_UNIT_DIFFERS', 'adjustment_unit_differs', [
                    'item' => $label, 'asked' => $entry['unit_code'], 'item_unit' => $unitCode,
                ], 'unit_code');
            }

            $unit = Unit::withoutGlobalScopes()->where('restaurant_id', $tenant)->where('code', $unitCode)->first();
            $typed = $kind === 'count' ? (int) $entry['counted_milli'] : (int) $entry['quantity_milli'];
            if ($unit !== null && ! $unit->allows_fraction && $typed % 1000 !== 0) {
                throw PurchasingRefusal::invalid('FRACTION_NOT_ALLOWED', 'fraction_not_allowed', ['unit' => $unitCode],
                    $kind === 'count' ? 'counted_milli' : 'quantity_milli');
            }

            StockLevel::query()->insertOrIgnore([
                'restaurant_id' => $tenant,
                'branch_id' => $branchId,
                'stock_item_id' => $item->id,
                'quantity_milli' => 0,
                'unit_code' => $unitCode,
                'average_cost_minor' => 0,
                'updated_at' => now(),
            ]);

            $level = StockLevel::withoutGlobalScopes()
                ->where('branch_id', $branchId)
                ->where('stock_item_id', $item->id)
                ->lockForUpdate()
                ->firstOrFail();

            if ($level->quantity_milli !== 0 && $level->unit_code !== $unitCode) {
                throw PurchasingRefusal::conflict('STOCK_HELD_IN_ANOTHER_UNIT', 'held_in_another_unit', [
                    'item' => $label, 'held' => $level->unit_code, 'asked' => $unitCode,
                ]);
            }

            $held = $level->quantity_milli;
            $average = $level->average_cost_minor;
            $history = StockMovement::withoutGlobalScopes()
                ->where('branch_id', $branchId)->where('stock_item_id', $item->id);

            if ($kind === 'opening' && (clone $history)->where('kind', 'opening')->exists()) {
                throw PurchasingRefusal::conflict('OPENING_ALREADY_RECORDED', 'opening_already_recorded', ['item' => $label]);
            }

            $delta = match ($kind) {
                'opening' => (int) $entry['quantity_milli'],
                'waste' => -(int) $entry['quantity_milli'],
                'adjustment' => (int) $entry['quantity_milli'],
                'count' => (int) $entry['counted_milli'] - $held,
            };

            if ($delta === 0) {
                // Only a count can get here: the request refuses a zero otherwise.
                throw PurchasingRefusal::invalid('COUNT_MATCHES', 'count_matches', [], 'counted_milli');
            }
            if ($reason->direction() > 0 && $delta < 0) {
                throw PurchasingRefusal::invalid('REASON_NEEDS_INCREASE', 'reason_needs_increase', [], 'reason');
            }
            if ($reason->direction() < 0 && $delta > 0) {
                throw PurchasingRefusal::invalid('REASON_NEEDS_DECREASE', 'reason_needs_decrease', [], 'reason');
            }

            if ($delta > 0) {
                // In: at the entry's cost, or the average held when none was
                // typed. With no history there is no average to fall back on.
                $cost = $entry['unit_cost_minor'] ?? null;
                if ($cost === null) {
                    if (! (clone $history)->exists()) {
                        throw PurchasingRefusal::invalid('UNIT_COST_REQUIRED', 'unit_cost_required', ['item' => $label], 'unit_cost_minor');
                    }
                    $cost = $average;
                }
                $cost = (int) $cost;
                $after = StockCosting::receive($held, $average, $delta, $cost);
            } else {
                // Out: at the average it was carried at, which does not move.
                $cost = $average;
                $after = StockCosting::issue($held, $average, -$delta);
            }

            $movement = new StockMovement;
            $movement->forceFill([
                'restaurant_id' => $tenant,
                'branch_id' => $branchId,
                'stock_item_id' => $item->id,
                'kind' => $kind === 'count' ? 'adjustment' : $kind,
                'quantity_milli' => $delta,
                'unit_code' => $unitCode,
                'unit_cost_minor' => $cost,
                'balance_milli' => $after['milli'],
                'average_cost_minor' => $after['cost'],
                'reason' => $reason->value,
                'note' => $entry['note'] ?? null,
                'occurred_at' => ! empty($entry['occurred_at']) ? Carbon::parse($entry['occurred_at']) : now(),
                'created_by' => $by->id,
            ])->save();

            $level->forceFill([
                'quantity_milli' => $after['milli'],
                'average_cost_minor' => $after['cost'],
                // Only ever a real change when nothing was held: the check
                // above refuses any other.
                'unit_code' => $unitCode,
                'updated_at' => now(),
            ])->save();

            AuditLogger::record('stock_movement.'.$kind, [
                'auditable' => $movement,
                'description' => sprintf('Stock %s recorded for %s', $kind, $label),
                'properties' => array_filter([
                    'branch_id' => $branchId,
                    'stock_item_id' => $item->id,
                    'kind' => $movement->kind,
                    'reason' => $reason->value,
                    'note' => $entry['note'] ?? null,
                    'quantity_milli' => $delta,
                    'counted_milli' => $kind === 'count' ? (int) $entry['counted_milli'] : null,
                    'unit_code' => $unitCode,
                    'unit_cost_minor' => $cost,
                    // What left or arrived, at the cost it moved at (for an
                    // issue: the till's costOfGoods, the average before it).
                    'value_minor' => StockCosting::costAt(abs($delta), $cost),
                    'before' => ['milli' => $held, 'average_cost_minor' => $average],
                    'after' => ['milli' => $after['milli'], 'average_cost_minor' => $after['cost']],
                ], fn ($v) => $v !== null),
            ]);

            return $movement;
        });
    }
}
