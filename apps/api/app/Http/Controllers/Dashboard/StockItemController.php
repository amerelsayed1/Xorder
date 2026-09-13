<?php

namespace App\Http\Controllers\Dashboard;

use App\Enums\PurchaseStatus;
use App\Http\Controllers\Controller;
use App\Http\Requests\Dashboard\StoreStockItemRequest;
use App\Http\Requests\Dashboard\UpdateStockItemRequest;
use App\Models\StockItem;
use App\Models\StockMovement;
use App\Services\StockItemService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * CB-09 slice b: stock items (D3), and one item's ledger.
 *
 * RestaurantScope isolates (a foreign id is a 404) and the Auditable trait
 * records create and update. No destroy: movements point at an item, so it
 * is retired with is_active = false. Stock items never count against
 * max_items; they are not menu items.
 *
 * `unit_locked` tells the page whether the unit may still change. The rule
 * itself is StockItemService's, under a lock.
 */
class StockItemController extends Controller
{
    public function index(): JsonResponse
    {
        return response()->json(['data' => $this->query()->orderBy('id')->get()]);
    }

    public function show(StockItem $stockItem): JsonResponse
    {
        return response()->json(['data' => $this->query()->findOrFail($stockItem->id)]);
    }

    public function store(StoreStockItemRequest $request, StockItemService $items): JsonResponse
    {
        $item = $items->create($request->validated(), $request->user());

        return response()->json(['data' => $this->query()->findOrFail($item->id), 'message' => __('xorder.messages.saved')], 201);
    }

    public function update(UpdateStockItemRequest $request, StockItem $stockItem, StockItemService $items): JsonResponse
    {
        $items->update($stockItem, $request->validated(), $request->user());

        return response()->json(['data' => $this->query()->findOrFail($stockItem->id), 'message' => __('xorder.messages.saved')]);
    }

    /** The ledger for one item, newest first, optionally one branch. Append-only rows. */
    public function movements(Request $request, StockItem $stockItem): JsonResponse
    {
        $request->validate(['branch_id' => ['nullable', 'integer']]);

        $page = StockMovement::query()
            ->where('stock_item_id', $stockItem->id)
            ->when($request->filled('branch_id'), fn ($q) => $q->where('branch_id', $request->integer('branch_id')))
            ->with(['purchaseOrder:id,reference', 'createdBy:id,name'])
            ->orderByDesc('id')
            ->paginate(50);

        $page->getCollection()->transform(fn (StockMovement $m) => [
            'id' => $m->id,
            'branch_id' => $m->branch_id,
            'kind' => $m->kind,
            'quantity_milli' => $m->quantity_milli,
            'unit_code' => $m->unit_code,
            'unit_cost_minor' => $m->unit_cost_minor,
            'balance_milli' => $m->balance_milli,
            'average_cost_minor' => $m->average_cost_minor,
            'purchase_order_id' => $m->purchase_order_id,
            'purchase_order_reference' => $m->purchaseOrder?->reference,
            'note' => $m->note,
            'occurred_at' => $m->occurred_at?->toIso8601String(),
            'created_by' => $m->createdBy?->name,
        ]);

        return response()->json($page);
    }

    private function query()
    {
        $open = [PurchaseStatus::DRAFT->value, PurchaseStatus::SENT->value, PurchaseStatus::PARTIALLY_RECEIVED->value];

        return StockItem::query()
            ->with('menuItem:id,name_en,name_ar,deleted_at')
            ->withExists([
                'levels as holds_stock' => fn ($q) => $q->where('quantity_milli', '!=', 0),
                'purchaseOrderLines as on_open_order' => fn ($q) => $q->whereHas('purchaseOrder', fn ($q) => $q->whereIn('status', $open)),
            ]);
    }
}
