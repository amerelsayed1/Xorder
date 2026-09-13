<?php

namespace App\Services;

use App\Models\StockLevel;
use App\Models\StockMovement;
use App\Support\StockCosting;

/**
 * CB-09 slice b: the level checked against the ledger.
 *
 * The level is a cache; the movements are the truth. replay() folds a
 * branch's movements for one item through StockCosting, in id order, and
 * reports every movement whose recorded balance or average disagrees with
 * the fold, plus whether the level matches the end of it. A drift found
 * here means something wrote stock outside ReceivingService.
 *
 * Positive quantities are arrivals at their own cost; negative ones are
 * issues, which never move the average. Slice b writes only receipts.
 */
class StockLedger
{
    /**
     * @return array{milli:int, cost:int, movements:int, drift:list<int>, level_matches:bool}
     */
    public function replay(int $branchId, int $stockItemId): array
    {
        $milli = 0;
        $cost = 0;
        $drift = [];
        $count = 0;

        StockMovement::withoutGlobalScopes()
            ->where('branch_id', $branchId)
            ->where('stock_item_id', $stockItemId)
            ->orderBy('id')
            ->each(function (StockMovement $m) use (&$milli, &$cost, &$drift, &$count) {
                $next = $m->quantity_milli > 0
                    ? StockCosting::receive($milli, $cost, $m->quantity_milli, $m->unit_cost_minor)
                    : StockCosting::issue($milli, $cost, -$m->quantity_milli);
                [$milli, $cost] = [$next['milli'], $next['cost']];
                $count++;

                if ($m->balance_milli !== $milli || $m->average_cost_minor !== $cost) {
                    $drift[] = $m->id;
                }
            });

        $level = StockLevel::withoutGlobalScopes()
            ->where('branch_id', $branchId)
            ->where('stock_item_id', $stockItemId)
            ->first();

        $levelMatches = $level === null
            ? $count === 0
            : ($level->quantity_milli === $milli && ($milli === 0 && $count === 0 || $level->average_cost_minor === $cost));

        return ['milli' => $milli, 'cost' => $cost, 'movements' => $count, 'drift' => $drift, 'level_matches' => $levelMatches];
    }
}
