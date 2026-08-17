<?php

namespace App\Http\Controllers\Dashboard;

use App\Enums\OrderStatus;
use App\Http\Controllers\Controller;
use App\Models\Category;
use App\Models\MenuItem;
use App\Models\MenuViewDaily;
use App\Models\Order;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class StatsController extends Controller
{
    /** Dashboard-home counters. Queries are tenant-scoped automatically. */
    public function index(Request $request): JsonResponse
    {
        $restaurant = $request->user()->restaurant;

        $totalItems = MenuItem::count();

        // "Available" means available to a diner, which an item in a switched-off
        // category is not — the public menu only loads active categories, so
        // counting those items here reported stock the menu never shows. The
        // difference lands in unavailable_items below, where it belongs: they
        // are items the owner still has, just not ones anyone can order.
        $availableItems = MenuItem::where('is_available', true)
            ->whereHas('category', fn ($q) => $q->where('is_active', true))
            ->count();

        return response()->json([
            'data' => [
                'public_url' => $restaurant->publicUrl(),
                'total_categories' => Category::count(),
                'active_categories' => Category::where('is_active', true)->count(),
                'total_items' => $totalItems,
                'available_items' => $availableItems,
                'unavailable_items' => $totalItems - $availableItems,
                'featured_items' => MenuItem::where('is_featured', true)->count(),
                'new_orders' => Order::where('status', OrderStatus::NEW)->count(),
                'views_today' => (int) MenuViewDaily::whereDate('date', now()->toDateString())->sum('views'),
            ],
        ]);
    }
}
