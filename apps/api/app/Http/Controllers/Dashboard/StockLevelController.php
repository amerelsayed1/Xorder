<?php

namespace App\Http\Controllers\Dashboard;

use App\Http\Controllers\Controller;
use App\Models\StockLevel;
use App\Support\StockCosting;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * CB-09: each branch's RECORDED stock, valued at the moving average.
 *
 * Slice b called it "received to date". Since slice d it is receipts plus
 * opening stock plus adjustments and counts, less waste, and the dashboard
 * heads it "Recorded stock". It is still not "on hand": tills don't deduct
 * stock when they sell (D4), and the dashboard says so in both languages.
 *
 * `quantity_milli` is the figure. `received_milli` is the same number under
 * its slice-b name, kept so nothing that read it breaks.
 *
 * Read-only. A level is a cache of the ledger, written only by
 * ReceivingService and StockAdjustmentService, in the same transaction as
 * the movement, under a lock on the level row.
 */
class StockLevelController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $request->validate(['branch_id' => ['nullable', 'integer']]);

        $levels = StockLevel::query()
            ->with('stockItem:id,name_en,name_ar,sku,unit_code,is_active')
            ->when($request->filled('branch_id'), fn ($q) => $q->where('branch_id', $request->integer('branch_id')))
            ->orderBy('stock_item_id')
            ->orderBy('branch_id')
            ->get();

        $rows = $levels->map(fn (StockLevel $l) => [
            'id' => $l->id,
            'branch_id' => $l->branch_id,
            'stock_item_id' => $l->stock_item_id,
            'stock_item' => $l->stockItem ? [
                'id' => $l->stockItem->id, 'name_en' => $l->stockItem->name_en, 'name_ar' => $l->stockItem->name_ar,
                'sku' => $l->stockItem->sku, 'is_active' => $l->stockItem->is_active,
            ] : null,
            'unit_code' => $l->unit_code,
            'quantity_milli' => $l->quantity_milli,
            'received_milli' => $l->quantity_milli,
            'average_cost_minor' => $l->average_cost_minor,
            'value_minor' => $l->valueMinor(),
            'updated_at' => $l->updated_at?->toIso8601String(),
        ])->values();

        $restaurant = $request->user()->restaurant;

        return response()->json([
            'data' => $rows,
            'meta' => [
                'currency' => $restaurant->currency?->value,
                'exponent' => $restaurant->currency?->exponent() ?? 2,
                'value_minor' => $rows->sum('value_minor'),
            ],
        ]);
    }
}
