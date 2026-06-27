<?php

namespace App\Http\Controllers\Public;

use App\Http\Controllers\Controller;
use App\Http\Resources\Public\CategoryPublicResource;
use App\Http\Resources\Public\MenuItemPublicResource;
use App\Http\Resources\Public\RestaurantPublicResource;
use App\Services\PublicMenuService;
use Illuminate\Http\JsonResponse;

class PublicMenuApiController extends Controller
{
    public function __construct(private readonly PublicMenuService $menu)
    {
    }

    public function show(string $slug, PublicMenuService $menu): JsonResponse
    {
        $restaurant = $this->menu->findBySlug($slug);

        if ($restaurant === null) {
            return response()->json(['message' => 'Restaurant not found.'], 404);
        }

        if (! $this->menu->isVisible($restaurant)) {
            return response()->json([
                'available' => false,
                'message' => 'This menu is currently unavailable.',
            ], 200);
        }

        $data = $this->menu->loadMenu($restaurant);

        return response()->json([
            'available' => true,
            'data' => [
                'restaurant' => RestaurantPublicResource::make($restaurant),
                'featured' => MenuItemPublicResource::collection($data['featured']),
                'categories' => CategoryPublicResource::collection($data['categories']),
            ],
        ]);
    }
}
