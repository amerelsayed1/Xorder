<?php

namespace App\Http\Controllers\Dashboard;

use App\Http\Controllers\Controller;
use App\Http\Requests\Dashboard\UpdateRestaurantProfileRequest;
use App\Http\Resources\RestaurantResource;
use App\Services\PosConfigVersion;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class RestaurantProfileController extends Controller
{
    public function show(Request $request): JsonResponse
    {
        return response()->json([
            'data' => RestaurantResource::make($request->user()->restaurant->loadMissing('features')),
        ]);
    }

    public function update(UpdateRestaurantProfileRequest $request): JsonResponse
    {
        $restaurant = $request->user()->restaurant;
        $data = $request->validated();

        // A3: the tax registration number rides the POS bootstrap bundle, both
        // as `restaurant.tax_registration_number` and as every receipt
        // profile's `registration_number`. Changing it must therefore tell the
        // tills — bumped explicitly rather than by hooking Restaurant, because
        // a new cover image is not a bundle change (PosConfigVersion).
        $trnChanged = array_key_exists('tax_registration_number', $data)
            && (string) $data['tax_registration_number'] !== (string) $restaurant->tax_registration_number;
        // The brand colour rides the bundle too, as the till's accent_hex — and
        // is bumped by PosConfigVersion's Restaurant::updated hook (XORD-021),
        // which watches brand_color and logo_url. Not bumped here as well, or a
        // colour change would move the version twice.

        // The content languages ride the bundle too, but the owner cannot change
        // them here (Super Admin only, owner decision 2026-11-07), so nothing
        // on this form moves them.

        $restaurant->update($data);

        if ($trnChanged) {
            PosConfigVersion::bump($restaurant);
        }

        return response()->json([
            'data' => RestaurantResource::make($restaurant->fresh()),
            'message' => __('xorder.messages.profile_updated'),
        ]);
    }
}
