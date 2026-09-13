<?php

namespace App\Http\Controllers\Dashboard;

use App\Http\Controllers\Controller;
use App\Models\StockLevel;
use App\Support\StockCosting;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * CB-09 slice b: what each branch has RECEIVED TO DATE, valued at the
 * moving average.
 *
 * Not "on hand". Tills don't deduct stock when they sell (D4), and slice b
 * writes only receipts, so this is everything booked in, never less. The
 * dashboard labels it that way in both languages.
 *
 * Read-only. A level is a cache of the ledger, written only by
 * ReceivingService in the same transaction as its movement.
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
