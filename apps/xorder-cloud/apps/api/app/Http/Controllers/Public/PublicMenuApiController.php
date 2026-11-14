<?php

namespace App\Http\Controllers\Public;

use App\Http\Controllers\Controller;
use App\Http\Resources\Public\BranchPublicResource;
use App\Http\Resources\Public\CategoryPublicResource;
use App\Http\Resources\Public\ComboPublicResource;
use App\Http\Resources\Public\MenuItemPublicResource;
use App\Http\Resources\Public\RestaurantPublicResource;
use App\Models\MenuViewDaily;
use App\Services\PublicMenuService;
use App\Support\MenuViewGate;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class PublicMenuApiController extends Controller
{
    public function __construct(private readonly PublicMenuService $menu) {}

    public function show(Request $request, string $slug): JsonResponse
    {
        $restaurant = $this->menu->findBySlug($slug);

        if ($restaurant === null) {
            return response()->json(['message' => __('xorder.messages.restaurant_not_found')], 404);
        }

        if (! $this->menu->isVisible($restaurant)) {
            return response()->json([
                'available' => false,
                'message' => __('xorder.messages.menu_unavailable'),
            ], 200);
        }

        $data = $this->menu->loadMenu($restaurant);

        // First-party view counter for the owner's dashboard analytics. Only
        // genuine diner views count — owner previews (?preview=1) and crawlers /
        // link-preview bots are excluded so a new menu is not inflated.
        if (MenuViewGate::shouldCount($request)) {
            MenuViewDaily::record($restaurant->id);
        }

        return response()->json([
            'available' => true,
            'data' => [
                'restaurant' => RestaurantPublicResource::make($restaurant),
                'featured' => MenuItemPublicResource::collection($data['featured']),
                'categories' => CategoryPublicResource::collection($data['categories']),
                'branches' => BranchPublicResource::collection($data['branches']),
                'combos' => ComboPublicResource::collection($data['combos']),
            ],
        ]);
    }
}
