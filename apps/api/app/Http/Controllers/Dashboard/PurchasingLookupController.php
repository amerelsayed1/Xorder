<?php

namespace App\Http\Controllers\Dashboard;

use App\Http\Controllers\Controller;
use App\Models\Branch;
use App\Models\MenuItem;
use App\Models\StockItem;
use App\Models\Supplier;
use App\Models\Unit;
use App\Services\UnitCatalog;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * CB-09 slice b: the pickers the purchasing pages need, in one read, under
 * purchase.manage alone.
 *
 * Why not reuse /branches and /items: those sit behind branches.list and
 * menu.view. A buyer whose role holds only purchase.manage still has to pick
 * a branch for an order and link a stock item to a menu item, and granting
 * them the menu or branch capabilities just to fill two dropdowns would
 * leak those whole screens into their sidebar. So this returns ids and
 * names only, nothing else about either.
 *
 * Retired suppliers, units and items ARE included, flagged: old orders must
 * still display them, even though new ones may not pick them.
 */
class PurchasingLookupController extends Controller
{
    public function index(Request $request, UnitCatalog $catalog): JsonResponse
    {
        $catalog->ensureDefaults($request->user()->restaurant_id);
        $restaurant = $request->user()->restaurant;

        return response()->json(['data' => [
            'currency' => $restaurant->currency?->value,
            'exponent' => $restaurant->currency?->exponent() ?? 2,
            'branches' => Branch::orderBy('sort_order')->orderBy('id')->get(['id', 'name_en', 'name_ar', 'is_active']),
            'suppliers' => Supplier::orderBy('id')->get(['id', 'name_en', 'name_ar', 'is_active']),
            'units' => Unit::orderBy('sort_order')->orderBy('id')->get(['id', 'code', 'name_en', 'name_ar', 'allows_fraction', 'is_active']),
            'stock_items' => StockItem::orderBy('id')->get(['id', 'name_en', 'name_ar', 'sku', 'unit_code', 'menu_item_id', 'is_active']),
            'menu_items' => MenuItem::orderBy('id')->get(['id', 'name_en', 'name_ar']),
        ]]);
    }
}
