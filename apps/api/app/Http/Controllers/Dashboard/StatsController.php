<?php

namespace App\Http\Controllers\Dashboard;

use App\Http\Controllers\Controller;
use App\Models\Category;
use App\Models\MenuItem;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class StatsController extends Controller
{
    /** Dashboard-home counters. Queries are tenant-scoped automatically. */
    public function index(Request $request): JsonResponse
    {
        $restaurant = $request->user()->restaurant;

        $totalItems = MenuItem::count();
        $availableItems = MenuItem::where('is_available', true)->count();

        return response()->json([
            'data' => [
                'public_url' => $restaurant->publicUrl(),
                'total_categories' => Category::count(),
                'active_categories' => Category::where('is_active', true)->count(),
                'total_items' => $totalItems,
                'available_items' => $availableItems,
                'unavailable_items' => $totalItems - $availableItems,
                'featured_items' => MenuItem::where('is_featured', true)->count(),
            ],
        ]);
    }
}
