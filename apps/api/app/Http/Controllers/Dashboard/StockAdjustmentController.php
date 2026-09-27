<?php

namespace App\Http\Controllers\Dashboard;

use App\Http\Controllers\Controller;
use App\Http\Requests\Dashboard\StoreStockAdjustmentRequest;
use App\Models\StockLevel;
use App\Services\StockAdjustmentService;
use Illuminate\Http\JsonResponse;

/**
 * CB-09 slice d: opening stock, waste, adjustments and counts. Create only:
 * a movement is never edited or deleted, so a wrong entry is corrected by
 * another one (an adjustment with reason `entry_error`).
 *
 * Thin on purpose. The position-dependent rules (unit held, one opening per
 * branch, a cost to enter at, the count's difference) are decided by
 * StockAdjustmentService under the level-row lock.
 */
class StockAdjustmentController extends Controller
{
    public function store(StoreStockAdjustmentRequest $request, StockAdjustmentService $adjustments): JsonResponse
    {
        $movement = $adjustments->record($request->entry(), $request->user());
        $movement->load('createdBy:id,name');

        $level = StockLevel::query()
            ->where('branch_id', $movement->branch_id)
            ->where('stock_item_id', $movement->stock_item_id)
            ->firstOrFail();

        return response()->json([
            'data' => array_merge($movement->ledgerRow(), [
                'level' => [
                    'branch_id' => $level->branch_id,
                    'stock_item_id' => $level->stock_item_id,
                    'unit_code' => $level->unit_code,
                    'quantity_milli' => $level->quantity_milli,
                    'average_cost_minor' => $level->average_cost_minor,
                    'value_minor' => $level->valueMinor(),
                ],
            ]),
            'message' => __('xorder.messages.saved'),
        ], 201);
    }
}
