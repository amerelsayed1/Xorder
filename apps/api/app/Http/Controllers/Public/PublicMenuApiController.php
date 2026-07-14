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
use Illuminate\Http\JsonResponse;

class PublicMenuApiController extends Controller
{
    public function __construct(private readonly PublicMenuService $menu) {}

    public function show(string $slug, PublicMenuService $menu): JsonResponse
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

        // First-party view counter for the owner's dashboard analytics.
        MenuViewDaily::record($restaurant->id);

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
