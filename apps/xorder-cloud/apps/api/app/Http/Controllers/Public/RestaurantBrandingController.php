<?php

namespace App\Http\Controllers\Public;

use App\Http\Controllers\Controller;
use App\Models\Restaurant;
use Illuminate\Http\JsonResponse;

class RestaurantBrandingController extends Controller
{
    /**
     * Minimal public branding for a restaurant subdomain — used to brand the
     * restaurant admin login screen ({slug}.host/admin/login) before auth.
     * Available for any existing restaurant (even suspended) so its admin can
     * still reach the branded login.
     */
    public function show(string $slug): JsonResponse
    {
        $restaurant = Restaurant::query()
            ->where('slug', $slug)
            ->first(['name_en', 'name_ar', 'slug', 'logo_url', 'brand_color', 'secondary_color']);

        if ($restaurant === null) {
            return response()->json(['message' => __('xorder.messages.restaurant_not_found')], 404);
        }

        return response()->json([
            'data' => [
                'name_en' => $restaurant->name_en,
                'name_ar' => $restaurant->name_ar,
                'slug' => $restaurant->slug,
                'logo_url' => $restaurant->logo_url,
                'brand_color' => $restaurant->brand_color,
                'secondary_color' => $restaurant->secondary_color,
            ],
        ]);
    }
}
